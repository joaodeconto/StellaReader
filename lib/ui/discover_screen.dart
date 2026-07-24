import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/import_service.dart';
import '../data/open_library_service.dart';
import '../domain/book.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.onImported});

  final ValueChanged<Book> onImported;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _controller = TextEditingController(text: 'classic literature');
  final _service = OpenLibraryService();
  final _dio = Dio();
  final Set<String> _downloading = <String>{};

  bool _loading = false;
  bool _readableOnly = true;
  List<OpenLibraryBook> _books = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _controller.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final books = await _service.search(query);
      if (!mounted) return;
      setState(() => _books = books);
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _books = const [];
        _error = 'Network ${error.type.name}: ${error.message ?? 'request failed'}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _books = const [];
        _error = '${error.runtimeType}: $error';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<OpenLibraryBook> get _visibleBooks => _readableOnly
      ? _books.where((book) => book.mayBeDownloadable).toList()
      : _books;

  Future<void> _download(OpenLibraryBook item) async {
    if (_downloading.contains(item.workKey)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloading.add(item.workKey));

    try {
      final download = await _service.resolveDownload(item);
      if (download == null) {
        throw StateError('No downloadable EPUB or PDF was found.');
      }

      final temp = await getTemporaryDirectory();
      final safeTitle = item.title.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
      final tempFile = File(p.join(temp.path, '$safeTitle${download.extension}'));
      await _dio.download(
        download.url,
        tempFile.path,
        options: Options(
          receiveTimeout: const Duration(minutes: 3),
          headers: const {'User-Agent': 'StellaReader/0.3.0'},
        ),
      );

      final imported = await ImportService().importFile(tempFile);
      await tempFile.delete().catchError((_) => tempFile);
      widget.onImported(imported);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('${item.title} added to Library')),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Download failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(item.workKey));
    }
  }

  void _showDetails(OpenLibraryBook book) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(book.author),
            if (book.firstPublishYear != null)
              Text('First published ${book.firstPublishYear}'),
            const SizedBox(height: 16),
            Text(
              book.mayBeDownloadable
                  ? 'A public full-text edition may be available through the Internet Archive.'
                  : 'No public EPUB or PDF is currently listed for this result.',
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: book.mayBeDownloadable
                    ? () {
                        Navigator.pop(context);
                        _download(book);
                      }
                    : null,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download to Library'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = _visibleBooks;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              SearchBar(
                controller: _controller,
                hintText: 'Search title or author',
                leading: const Icon(Icons.search),
                trailing: [
                  IconButton(
                    tooltip: 'Search',
                    onPressed: _loading ? null : _search,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilterChip(
                    label: const Text('Downloadable only'),
                    selected: _readableOnly,
                    onSelected: (value) => setState(() => _readableOnly = value),
                  ),
                  const Spacer(),
                  if (!_loading && _books.isNotEmpty)
                    Text('${books.length} shown'),
                ],
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _error != null
              ? _ErrorState(message: _error!, onRetry: _search)
              : books.isEmpty && !_loading
                  ? const _EmptyState()
                  : RefreshIndicator(
                      onRefresh: _search,
                      child: ListView.separated(
                        itemCount: books.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final book = books[index];
                          final downloading = _downloading.contains(book.workKey);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            leading: _BookCover(url: book.coverUrl),
                            title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [book.author, book.firstPublishYear]
                                  .whereType<String>()
                                  .where((value) => value.isNotEmpty)
                                  .join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: downloading
                                ? const SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(
                                    book.mayBeDownloadable
                                        ? Icons.download_outlined
                                        : Icons.info_outline,
                                  ),
                            onTap: () => _showDetails(book),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 44,
        height: 60,
        child: url == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.menu_book_outlined),
              )
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.menu_book_outlined),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No matching downloadable books. Try another title, author, or disable the filter.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Could not load Open Library'),
            const SizedBox(height: 8),
            SelectableText(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
