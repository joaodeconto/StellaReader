import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';

import '../data/book_repository.dart';
import '../data/bookmark_repository.dart';
import '../domain/book.dart';
import '../domain/bookmark.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  late final PdfControllerPinch _controller;
  int _currentPage = 1;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.book.lastPage;
    _controller = PdfControllerPinch(
      document: PdfDocument.openFile(widget.book.path),
      initialPage: widget.book.lastPage,
    );
  }

  Future<void> _saveLastPage() async {
    final id = widget.book.id;
    if (id != null) {
      await BookRepository().updateLastPage(id, _currentPage);
    }
  }

  Future<void> _addBookmark() async {
    final id = widget.book.id;
    if (id == null) return;
    await BookmarkRepository().insert(
      Bookmark(
        bookId: id,
        page: _currentPage,
        label: null,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Page $_currentPage bookmarked')),
    );
  }

  Future<void> _showBookmarks() async {
    final id = widget.book.id;
    if (id == null) return;
    final items = await BookmarkRepository().byBook(id);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ListView(
        children: items.isEmpty
            ? const [ListTile(title: Text('No bookmarks'))]
            : items
                .map(
                  (bookmark) => ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text('Page ${bookmark.page}'),
                    onTap: () {
                      _controller.jumpToPage(bookmark.page);
                      Navigator.pop(sheetContext);
                    },
                  ),
                )
                .toList(),
      ),
    );
  }

  Future<void> _jumpToPage() async {
    final input = TextEditingController(text: '$_currentPage');
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: _pageCount > 0 ? '1–$_pageCount' : 'Page number',
          ),
          onSubmitted: (value) {
            Navigator.pop(dialogContext, int.tryParse(value));
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(input.text),
            ),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    input.dispose();
    if (selected == null) return;
    final page = _pageCount > 0 ? selected.clamp(1, _pageCount) : selected;
    if (page >= 1) _controller.jumpToPage(page);
  }

  void _previousPage() {
    if (_currentPage > 1) _controller.previousPage(duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  void _nextPage() {
    if (_pageCount == 0 || _currentPage < _pageCount) {
      _controller.nextPage(duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _saveLastPage();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, __) => _saveLastPage(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.book.title),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: _showBookmarks,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: PdfViewPinch(
                controller: _controller,
                onDocumentLoaded: (document) {
                  if (mounted) setState(() => _pageCount = document.pagesCount);
                },
                onPageChanged: (page) {
                  if (mounted) setState(() => _currentPage = page);
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Material(
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: _currentPage > 1 ? _previousPage : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: _jumpToPage,
                          child: Text(
                            _pageCount > 0
                                ? 'Page $_currentPage of $_pageCount'
                                : 'Page $_currentPage',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: _pageCount == 0 || _currentPage < _pageCount
                            ? _nextPage
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                      IconButton(
                        tooltip: 'Bookmark page',
                        onPressed: _addBookmark,
                        icon: const Icon(Icons.star_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
