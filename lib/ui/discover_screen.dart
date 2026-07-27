import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/curated_catalog.dart';
import '../data/import_service.dart';
import '../domain/book.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.onImported});

  final ValueChanged<Book> onImported;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _controller = TextEditingController();
  final _dio = Dio();
  final Map<String, double?> _downloadProgress = <String, double?>{};

  String _category = 'All';
  String _query = '';

  static const _categories = <String>[
    'All',
    'Growing up',
    'Adventure',
    'Fantasy',
    'Mystery',
    'Science fiction',
    'Horror',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  List<CuratedBook> get _visibleBooks {
    final query = _query.toLowerCase().trim();
    return curatedCatalog.where((book) {
      final categoryMatches = _category == 'All' || book.category == _category;
      final queryMatches = query.isEmpty ||
          book.title.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query) ||
          book.description.toLowerCase().contains(query);
      return categoryMatches && queryMatches;
    }).toList();
  }

  Future<void> _download(CuratedBook item) async {
    if (_downloadProgress.containsKey(item.id)) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloadProgress[item.id] = null);

    File? tempFile;
    try {
      final temp = await getTemporaryDirectory();
      final safeTitle = item.title.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
      tempFile = File(p.join(temp.path, '$safeTitle.epub'));

      await _dio.download(
        item.downloadUrl,
        tempFile.path,
        options: Options(
          receiveTimeout: const Duration(minutes: 3),
          headers: const {'User-Agent': 'StellaReader/0.3.3'},
          followRedirects: true,
        ),
        onReceiveProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _downloadProgress[item.id] = received / total);
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
      _showMessage(
        status == 404
            ? 'This curated download has moved. The catalog needs an update.'
            : 'Download failed. Check your connection and try again.',
      );
    } catch (_) {
      _showMessage('This ebook could not be added to the Library.');
    } finally {
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _downloadProgress.remove(item.id));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showDetails(CuratedBook book) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: _BookMark(title: book.title, size: 72),
        title: Text(book.title, textAlign: TextAlign.center),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(book.author, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(book.category, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(book.description, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              const Text(
                'Curated EPUB edition from Standard Ebooks.',
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
            onPressed: () {
              Navigator.pop(dialogContext);
              _download(book);
            },
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download EPUB'),
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
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A small shelf of books worth reading',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Every title is a tested, public-domain EPUB selected for readability.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  SearchBar(
                    controller: _controller,
                    hintText: 'Filter title or author',
                    leading: const Icon(Icons.search),
                    trailing: _query.isEmpty
                        ? null
                        : [
                            IconButton(
                              tooltip: 'Clear',
                              onPressed: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _categories
                          .map(
                            (category) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(category),
                                selected: _category == category,
                                onSelected: (_) => setState(() => _category = category),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${books.length} curated books'),
                ],
              ),
            ),
          ),
          if (books.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No curated books match this filter.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
              sliver: SliverList.separated(
                itemCount: books.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final book = books[index];
                  final downloading = _downloadProgress.containsKey(book.id);
                  final progress = _downloadProgress[book.id];

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: downloading ? null : () => _showDetails(book),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _BookMark(title: book.title),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    book.title,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(book.author),
                                  const SizedBox(height: 8),
                                  Text(
                                    book.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(book.category),
                                  ),
                                  if (downloading) ...[
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(value: progress),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            downloading
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      progress == null
                                          ? 'Preparing'
                                          : '${(progress * 100).round()}%',
                                    ),
                                  )
                                : IconButton(
                                    tooltip: 'Download EPUB',
                                    onPressed: () => _download(book),
                                    icon: const Icon(Icons.download_outlined),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _BookMark extends StatelessWidget {
  const _BookMark({required this.title, this.size = 64});

  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = title
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0].toUpperCase())
        .join();

    return Container(
      width: size,
      height: size * 1.4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        initials,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
