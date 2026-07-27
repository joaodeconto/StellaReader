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
  final Map<String, double?> _downloadProgress = <String, double?>{};

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
    } on DioException {
      if (!mounted) return;
      setState(() {
        _books = const [];
        _error = 'Check your connection and try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _books = const [];
        _error = 'The catalog could not be loaded.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<OpenLibraryBook> get _visibleBooks => _readableOnly
      ? _books.where((book) => book.mayBeDownloadable).toList()
      : _books;

  Future<void> _download(OpenLibraryBook item) async {
    if (_downloadProgress.containsKey(item.workKey)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloadProgress[item.workKey] = null);

    File? tempFile;
    try {
      final download = await _service.resolveDownload(item);
      if (download == null) {
        _showMessage(
          'No public EPUB or PDF edition is available for this book.',
          actionLabel: 'Search again',
          onAction: _search,
        );
        return;
      }

      final temp = await getTemporaryDirectory();
      final safeTitle = item.title.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
      tempFile = File(p.join(temp.path, '$safeTitle${download.extension}'));
      await _dio.download(
        download.url,
        tempFile.path,
        options: Options(
          receiveTimeout: const Duration(minutes: 3),
          headers: const {'User-Agent': 'StellaReader/0.3.3'},
        ),
        onReceiveProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _downloadProgress[item.workKey] = received / total);
        },
      );

      final imported = await ImportService().importFile(tempFile);
      widget.onImported(imported);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('${item.title} added to Library')),
        );
      }
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final message = status == 401 || status == 403
          ? 'This edition requires login or borrowing and cannot be downloaded here.'
          : 'The download failed. Try another edition or try again later.';
      _showMessage(message);
    } catch (_) {
      _showMessage('This file could not be added to the Library.');
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete().catchError((_) => tempFile!);
      }
      if (mounted) setState(() => _downloadProgress.remove(item.workKey));
    }
  }

  void _showMessage(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(label: actionLabel, onPressed: onAction),
        ),
      );
  }

  Future<void> _showDetails(OpenLibraryBook book) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: _BookCover(url: book.coverUrl, width: 72, height: 100),
        title: Text(book.title, textAlign: TextAlign.center),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                [book.author, book.firstPublishYear]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' · '),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                book.mayBeDownloadable
                    ? 'StellaReader will look for a public EPUB or PDF edition. Restricted editions are skipped.'
                    : 'No public full-text edition is listed for this result.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: book.mayBeDownloadable
                ? () {
                    Navigator.pop(dialogContext);
                    _download(book);
                  }
                : null,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = _visibleBooks;
    return SafeArea(
      top: false,
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: books.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final book = books[index];
                            final downloading = _downloadProgress.containsKey(book.workKey);
                            final progress = _downloadProgress[book.workKey];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: _BookCover(url: book.coverUrl),
                              title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    [book.author, book.firstPublishYear]
                                        .whereType<String>()
                                        .where((value) => value.isNotEmpty)
                                        .join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (downloading) ...[
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(value: progress),
                                  ],
                                ],
                              ),
                              trailing: downloading
                                  ? Text(progress == null ? 'Preparing' : '${(progress * 100).round()}%')
                                  : Icon(
                                      book.mayBeDownloadable
                                          ? Icons.download_outlined
                                          : Icons.info_outline,
                                    ),
                              onTap: downloading ? null : () => _showDetails(book),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.url, this.width = 48, this.height = 68});

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: height,
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
            Text(message, textAlign: TextAlign.center),
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