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

  @override
  void initState() {
    super.initState();
    _controller = EpubController(
      document: EpubDocument.openFile(uni.File(widget.book.path)),
      epubCfi: widget.book.lastCfi,
    );
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
    await BookmarkRepository().insert(Bookmark(
      bookId: widget.book.id!,
      page: 1,
      cfi: cfi,
      label: null,
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
                    title: Text(bm.cfi != null ? 'Localização' : 'Marcador'),
                    onTap: () {
                      if (bm.cfi != null) {
                        _controller.gotoEpubCfi(bm.cfi!);
                      }
                      Navigator.pop(context);
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
        body: EpubView(
          controller: _controller,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addBookmark,
          child: const Icon(Icons.star),
        ),
      ),
    );
  }
}
