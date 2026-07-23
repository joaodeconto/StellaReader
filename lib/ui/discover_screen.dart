import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/import_service.dart';
import '../data/opds_service.dart';
import '../domain/book.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.onImported});

  final ValueChanged<Book> onImported;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _service = OpdsService();
  final _dio = Dio();

  bool _loading = true;
  List<CatalogBook> _books = const [];
  List<String> _warnings = const [];
  final Set<String> _downloading = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _warnings = const [];
    });

    final results = await Future.wait([
      _loadCatalog('Standard Ebooks', _service.standardEbooks),
      _loadCatalog('Project Gutenberg', _service.projectGutenberg),
    ]);

    if (!mounted) return;

    final books = <CatalogBook>[
      ...results[0].books,
      ...results[1].books,
    ];
    final warnings = results
        .where((result) => result.error != null)
        .map((result) => '${result.source} is temporarily unavailable.')
        .toList();

    setState(() {
      _books = books;
      _warnings = warnings;
      _loading = false;
    });
  }

  Future<_CatalogLoadResult> _loadCatalog(
    String source,
    Future<List<CatalogBook>> Function() loader,
  ) async {
    try {
      return _CatalogLoadResult(source: source, books: await loader());
    } catch (error) {
      return _CatalogLoadResult(source: source, books: const [], error: error);
    }
  }

  Future<void> _download(CatalogBook item) async {
    if (_downloading.contains(item.downloadUrl)) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloading.add(item.downloadUrl));

    try {
      final temp = await getTemporaryDirectory();
      final uri = Uri.parse(item.downloadUrl);
      final extension = p.extension(uri.path).toLowerCase() == '.pdf'
          ? '.pdf'
          : '.epub';
      final safeTitle = item.title.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
      final tempFile = File(p.join(temp.path, '$safeTitle$extension'));

      await _dio.download(
        item.downloadUrl,
        tempFile.path,
        options: Options(
          receiveTimeout: const Duration(minutes: 2),
          headers: const {'User-Agent': 'StellaReader/0.2.1'},
        ),
      );

      final imported = await ImportService().importFile(tempFile);
      await tempFile.delete().catchError((_) => tempFile);
      widget.onImported(imported);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('${item.title} added to library')),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Download failed. Check your connection and try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _downloading.remove(item.downloadUrl));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => const _LoadingBookTile(),
      );
    }

    if (_books.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Could not reach the book catalogs.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your internet connection and try again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _books.length + (_warnings.isEmpty ? 0 : 1),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (_warnings.isNotEmpty && index == 0) {
            return MaterialBanner(
              content: Text(_warnings.join(' ')),
              leading: const Icon(Icons.info_outline),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            );
          }

          final bookIndex = index - (_warnings.isEmpty ? 0 : 1);
          final book = _books[bookIndex];
          final downloading = _downloading.contains(book.downloadUrl);

          return ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(book.title),
            subtitle: Text('${book.author} · ${book.source}'),
            trailing: downloading
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Download',
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () => _download(book),
                  ),
          );
        },
      ),
    );
  }
}

class _CatalogLoadResult {
  const _CatalogLoadResult({
    required this.source,
    required this.books,
    this.error,
  });

  final String source;
  final List<CatalogBook> books;
  final Object? error;
}

class _LoadingBookTile extends StatelessWidget {
  const _LoadingBookTile();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Row(
      children: [
        Container(width: 44, height: 56, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 8),
              FractionallySizedBox(
                widthFactor: 0.62,
                child: Container(height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
