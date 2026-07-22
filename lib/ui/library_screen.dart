import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/book_repository.dart';
import '../data/import_service.dart';
import '../domain/book.dart';
import 'discover_screen.dart';

final booksProvider = FutureProvider.autoDispose<List<Book>>((ref) async {
  return BookRepository().all();
});

enum _LibraryFilter { all, pdf, epub }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _tab = 0;
  String _query = '';
  _LibraryFilter _filter = _LibraryFilter.all;

  Future<void> _import() async {
    try {
      final book = await ImportService().pickAndImport();
      if (book == null || !mounted) return;
      ref.invalidate(booksProvider);
      context.push('/reader', extra: book);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    }
  }

  List<Book> _filteredBooks(List<Book> books) {
    final normalizedQuery = _query.trim().toLowerCase();
    return books.where((book) {
      final isEpub = ImportService.isEpub(book);
      final matchesType = switch (_filter) {
        _LibraryFilter.all => true,
        _LibraryFilter.pdf => !isEpub,
        _LibraryFilter.epub => isEpub,
      };
      final matchesQuery = normalizedQuery.isEmpty ||
          book.title.toLowerCase().contains(normalizedQuery);
      return matchesType && matchesQuery;
    }).toList();
  }

  bool _hasReadingProgress(Book book) {
    if (ImportService.isEpub(book)) {
      return book.lastCfi?.isNotEmpty ?? false;
    }
    return book.lastPage > 1;
  }

  Widget _buildLibrary(List<Book> items) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No books yet. Tap + to import PDF or EPUB.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final visibleBooks = _filteredBooks(items);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SearchBar(
            hintText: 'Search your library',
            leading: const Icon(Icons.search),
            trailing: _query.isEmpty
                ? null
                : [
                    IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.clear),
                    ),
                  ],
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<_LibraryFilter>(
            segments: const [
              ButtonSegment(value: _LibraryFilter.all, label: Text('All')),
              ButtonSegment(value: _LibraryFilter.pdf, label: Text('PDF')),
              ButtonSegment(value: _LibraryFilter.epub, label: Text('EPUB')),
            ],
            selected: {_filter},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              setState(() => _filter = selection.first);
            },
          ),
        ),
        Expanded(
          child: visibleBooks.isEmpty
              ? const Center(child: Text('No matching books.'))
              : ListView.separated(
                  itemCount: visibleBooks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final book = visibleBooks[index];
                    final epub = ImportService.isEpub(book);
                    final hasProgress = _hasReadingProgress(book);
                    return ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          epub ? Icons.auto_stories : Icons.picture_as_pdf,
                        ),
                      ),
                      title: Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        epub
                            ? (hasProgress
                                ? 'EPUB · Continue reading'
                                : 'EPUB · Not started')
                            : (hasProgress
                                ? 'PDF · Continue from page ${book.lastPage}'
                                : 'PDF · Not started'),
                      ),
                      trailing: Icon(
                        hasProgress
                            ? Icons.play_circle_outline
                            : Icons.chevron_right,
                      ),
                      onTap: () => context.push('/reader', extra: book),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'StellaReader is currently optimized for Android.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final books = ref.watch(booksProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_tab == 0 ? 'Library' : 'Discover')),
      body: IndexedStack(
        index: _tab,
        children: [
          books.when(
            data: _buildLibrary,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
          ),
          DiscoverScreen(
            onImported: (book) {
              ref.invalidate(booksProvider);
              context.push('/reader', extra: book);
            },
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              onPressed: _import,
              tooltip: 'Import PDF or EPUB',
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
        ],
      ),
    );
  }
}
