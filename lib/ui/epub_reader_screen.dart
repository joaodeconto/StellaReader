import 'package:epub_view/epub_view.dart';
import 'package:universal_file/universal_file.dart' as uni;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/book.dart';
import '../data/book_repository.dart';
import '../domain/bookmark.dart';
import '../data/bookmark_repository.dart';

class EpubReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  const EpubReaderScreen({super.key, required this.book});

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> {
  late EpubController _controller;
  bool _didInitialCfiJump = false;

  @override
  void initState() {
    super.initState();
    _controller = EpubController(
      document: EpubDocument.openFile(uni.File(widget.book.path)),
      epubCfi: widget.book.lastCfi,
    );

    // Ensure we jump to saved CFI when document finishes loading
    _controller.loadingState.addListener(() {
      if (_controller.loadingState.value == EpubViewLoadingState.success &&
          !_didInitialCfiJump &&
          (widget.book.lastCfi != null && widget.book.lastCfi!.isNotEmpty)) {
        _didInitialCfiJump = true;
        _controller.gotoEpubCfi(widget.book.lastCfi!);
      }
    });
  }

  Future<void> _saveLastLocation() async {
    if (widget.book.id != null) {
      final cfi = _controller.generateEpubCfi();
      if (cfi != null) {
        await BookRepository().updateLastCfi(widget.book.id!, cfi);
      }
    }
  }

  Future<void> _addBookmark() async {
    if (widget.book.id == null) return;
    final cfi = _controller.generateEpubCfi();
    if (cfi == null) return;
    final label = _currentChapterLabel();
    await BookmarkRepository().insert(Bookmark(
      bookId: widget.book.id!,
      page: 1,
      cfi: cfi,
      label: label,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marcador adicionado')),
    );
  }

  Future<void> _showBookmarks() async {
    if (widget.book.id == null) return;
    final items = await BookmarkRepository().byBook(widget.book.id!);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        children: items.isEmpty
            ? [const ListTile(title: Text('Sem marcadores'))]
            : items
                .map(
                  (bm) => ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text(bm.label ?? 'Localização'),
                    onTap: () {
                      final cfi = bm.cfi;
                      Navigator.pop(context);
                      if (cfi != null) {
                        // jump after sheet closes
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _controller.gotoEpubCfi(cfi);
                        });
                      }
                    },
                  ),
                )
                .toList(),
      ),
    );
  }

  @override
  void dispose() {
    _saveLastLocation();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) => _saveLastLocation(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.book.title),
          actions: [
            IconButton(icon: const Icon(Icons.bookmarks_outlined), onPressed: _showBookmarks),
          ],
        ),
        body: Stack(
          children: [
            EpubView(
              controller: _controller,
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ValueListenableBuilder(
                    valueListenable: _controller.currentValueListenable,
                    builder: (context, value, _) => Text(
                      _currentChapterLabel() ?? '…',
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addBookmark,
          child: const Icon(Icons.star),
        ),
      ),
    );
  }

  String? _currentChapterLabel() {
    final v = _controller.currentValueListenable.value;
    final raw = (v?.chapter?.Title)?.trim();
    if (raw == null || raw.isEmpty) return null;
    final cleaned = _cleanTitle(raw);
    // Try to compute a chapter number from ToC
    String prefix = '';
    try {
      final toc = _controller.tableOfContents();
      final idx = toc.indexWhere((c) => (c.title ?? '').trim().toLowerCase() == raw.toLowerCase());
      if (idx >= 0) prefix = 'Capítulo ${idx + 1} — ';
    } catch (_) {}
    final text = cleaned.isEmpty ? (prefix.isNotEmpty ? prefix.replaceAll(RegExp(r'\s—\s?$'), '') : null) : '$prefix$cleaned';
    return text?.trim();
  }

  String _cleanTitle(String s) {
    final lowered = s.toLowerCase();
    // Filter common Gutenberg headings
    if (lowered.contains('project gutenberg')) {
      // Return empty so we can fall back to prefix only
      return '';
    }
    // Remove excessive whitespace
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
