import 'dart:async';

import 'package:epub_view/epub_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_io/io.dart' as uni;

import '../data/book_repository.dart';
import '../data/bookmark_repository.dart';
import '../domain/book.dart';
import '../domain/bookmark.dart';

class EpubReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  const EpubReaderScreen({super.key, required this.book});

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen>
    with WidgetsBindingObserver {
  late EpubController _controller;
  bool _didInitialCfiJump = false;
  late VoidCallback _loadingListener;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = EpubController(
      document: EpubDocument.openFile(uni.File(widget.book.path)),
      epubCfi: widget.book.lastCfi,
    );

    _loadingListener = () {
      if (_controller.loadingState.value == EpubViewLoadingState.success &&
          !_didInitialCfiJump &&
          (widget.book.lastCfi != null && widget.book.lastCfi!.isNotEmpty)) {
        _didInitialCfiJump = true;
        _controller.gotoEpubCfi(widget.book.lastCfi!);
      }
    };
    _controller.loadingState.addListener(_loadingListener);

    _controller.currentValueListenable.addListener(_onLocationChanged);
  }

  void _onLocationChanged() {
    _saveDebounce?.cancel();
    _saveDebounce =
        Timer(const Duration(milliseconds: 600), _saveLastLocation);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveLastLocation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.currentValueListenable.removeListener(_onLocationChanged);
    _controller.loadingState.removeListener(_loadingListener);
    _saveDebounce?.cancel();
    _saveLastLocation();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveLastLocation() async {
    if (widget.book.id == null) return;
    final cfi = _controller.generateEpubCfi();
    if (cfi == null || cfi.isEmpty) return;
    await BookRepository().updateLastCfi(widget.book.id!, cfi);
  }

  Future<void> _addBookmark() async {
    if (widget.book.id == null) return;
    final cfi = _controller.generateEpubCfi();
    if (cfi == null) return;

    final label = _currentChapterLabel() ?? 'Localização';
    await BookmarkRepository().insert(Bookmark(
      bookId: widget.book.id!,
      page: 0,
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
                .map((bm) => ListTile(
                      leading: const Icon(Icons.bookmark),
                      title: Text(bm.label ?? 'Local'),
                      onTap: () {
                        if (bm.cfi != null) {
                          _controller.gotoEpubCfi(bm.cfi!);
                        }
                        Navigator.pop(context);
                      },
                    ))
                .toList(),
      ),
    );
  }

  String? _currentChapterLabel() {
    final v = _controller.currentValueListenable.value;
    final raw = v?.chapter?.Title?.trim();
    if (raw == null || raw.isEmpty) return null;

    final cleaned = _cleanTitle(raw);
    final toc = _flattenTocSafe();
    final idx = toc.indexWhere((t) => _norm(t.title) == _norm(raw));

    final prefix = idx >= 0 ? 'Capítulo ${idx + 1} — ' : '';
    final text = cleaned.isEmpty
        ? (prefix.isNotEmpty ? prefix.substring(0, prefix.length - 3) : null)
        : '$prefix$cleaned';
    return text?.trim();
  }

  String _norm(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  class _TocItem {
    final String title;
    _TocItem(this.title);
  }

  List<_TocItem> _flattenTocSafe() {
    try {
      final toc = _controller.tableOfContents();
      final out = <_TocItem>[];
      void walk(dynamic node) {
        if (node == null) return;
        final title = (node.title ?? '').toString();
        if (title.trim().isNotEmpty) out.add(_TocItem(title));
        final children = node.subChapters as List<dynamic>?;
        if (children != null) {
          for (final c in children) {
            walk(c);
          }
        }
      }

      for (final n in toc) {
        walk(n);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  String _cleanTitle(String s) {
    var r = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lowered = r.toLowerCase();
    if (lowered.contains('project gutenberg') ||
        lowered.startsWith('chapter ') ||
        lowered.startsWith('capítulo ')) {
      r = r.replaceFirst(
          RegExp(r'^(chapter|capítulo)\s+\d+\s*[:\-–—]\s*',
              caseSensitive: false),
          '');
      if (r.toLowerCase().contains('project gutenberg')) return '';
    }
    return r.trim();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) => _saveLastLocation(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.book.title),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: _showBookmarks,
            )
          ],
        ),
        body: EpubView(
          controller: _controller,
          onExternalLinkPressed: (href) async {
            // use url_launcher here if desired
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addBookmark,
          child: const Icon(Icons.star),
        ),
      ),
    );
  }
}
