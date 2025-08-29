import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import '../domain/book.dart';
import '../data/book_repository.dart';
import '../domain/bookmark.dart';
import '../data/bookmark_repository.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  PdfControllerPinch? _controller;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openFile(widget.book.path),
      initialPage: widget.book.lastPage,
    );
    _currentPage = widget.book.lastPage;
  }

  Future<void> _saveLastPage() async {
    if (widget.book.id != null) {
      await BookRepository().updateLastPage(widget.book.id!, _currentPage);
    }
  }

  Future<void> _addBookmark() async {
    if (widget.book.id == null) return;
    await BookmarkRepository().insert(Bookmark(
      bookId: widget.book.id!,
      page: _currentPage,
      label: null,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Página $_currentPage marcada')),
      );
    }
  }

  Future<void> _showBookmarks() async {
    if (widget.book.id == null) return;
    final items = await BookmarkRepository().byBook(widget.book.id!);
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        children: items.isEmpty
            ? [const ListTile(title: Text('Sem marcadores'))]
            : items
                .map((bm) => ListTile(
                      leading: const Icon(Icons.bookmark),
                      title: Text('Página ${bm.page}'),
                      onTap: () {
                        _controller?.jumpToPage(bm.page);
                        Navigator.pop(context);
                      },
                    ))
                .toList(),
      ),
    );
  }

  @override
  void dispose() {
    _saveLastPage();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) => _saveLastPage(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.book.title),
          actions: [
            IconButton(
                icon: const Icon(Icons.bookmarks_outlined),
                onPressed: _showBookmarks),
          ],
        ),
        body: PdfViewPinch(
          controller: _controller!,
          onPageChanged: (page) => setState(() => _currentPage = page),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addBookmark,
          child: const Icon(Icons.star),
        ),
      ),
    );
  }
}
