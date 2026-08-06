import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../data/import_service.dart';
import '../data/scielo_opds_service.dart';
import '../domain/catalog_book.dart';
import '../domain/catalog_feed.dart';
import 'catalog_error.dart';

/// Browses one OPDS feed: its sections, its books, or both.
///
/// The catalog is a tree, so this screen pushes another copy of itself for
/// each section the reader opens. Nothing is fetched until it is asked for.
class DiscoverBrazilScreen extends StatefulWidget {
  const DiscoverBrazilScreen({super.key, this.section});

  /// The section being browsed, or null for the catalog root.
  final CatalogSection? section;

  @override
  State<DiscoverBrazilScreen> createState() => _DiscoverBrazilScreenState();
}

class _DiscoverBrazilScreenState extends State<DiscoverBrazilScreen> {
  final _service = ScieloOpdsService();
  final _dio = Dio();
  final _search = TextEditingController();
  final Map<String, double?> _downloads = {};

  /// Pages loaded so far, in order. A feed can be paginated, and the reader
  /// asks for the next page rather than the app deciding how much of somebody
  /// else's catalog to pull down.
  final List<OpdsFeed> _pages = [];

  late Future<void> _loading;
  bool _loadingMore = false;
  Object? _error;
  String _query = '';

  /// Bumped on every reload. A pagination request that was in flight when the
  /// reader refreshed belongs to the previous list, and appending its page to
  /// the new one would interleave two different loads.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loading = _loadFirstPage();
  }

  @override
  void dispose() {
    _service.close();
    _dio.close(force: true);
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    _pages.clear();
    _error = null;
    try {
      final feed = await _service.loadFeed(widget.section?.uri);
      if (generation != _generation) return;
      _pages.add(feed);
    } catch (error) {
      if (generation != _generation) return;
      _error = error;
    }
  }

  void _reload() => setState(() => _loading = _loadFirstPage());

  Future<void> _loadMore() async {
    if (_pages.isEmpty || _loadingMore) return;
    final next = _pages.last.next;
    if (next == null) return;

    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.loadFeed(next);
      // A refresh overtook this request, so these pages are no longer the
      // ones on screen.
      if (!mounted || generation != _generation) return;
      setState(() => _pages.add(page));
    } catch (error) {
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeCatalogError(error))));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<CatalogBook> get _books => [
    for (final page in _pages)
      ...page.books.where((book) => book.matches(_query)),
  ];

  List<CatalogSection> get _sections => [
    for (final page in _pages) ...page.sections,
  ];

  bool get _hasMore => _pages.isNotEmpty && _pages.last.next != null;

  String get _title => widget.section?.title ?? 'EPUBs do Brasil';

  Future<void> _download(CatalogBook book) async {
    final url = book.epubUrl;
    if (url == null || _downloads.containsKey(book.id)) return;
    setState(() => _downloads[book.id] = null);
    File? temporaryFile;
    try {
      final dir = await getTemporaryDirectory();
      final safeTitle = book.title.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
      temporaryFile = File(p.join(dir.path, '$safeTitle.epub'));
      await _dio.downloadUri(
        url,
        temporaryFile.path,
        options: Options(
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 4),
          headers: const {
            'Accept': 'application/epub+zip, application/octet-stream;q=0.9',
            'User-Agent': userAgent,
          },
        ),
        onReceiveProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() => _downloads[book.id] = received / total);
          }
        },
      );
      final imported = await ImportService().importFile(temporaryFile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${book.title} adicionado à biblioteca.')),
      );
      context.push('/reader', extra: imported);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível baixar/importar este EPUB.'),
          ),
        );
      }
    } finally {
      if (temporaryFile != null && await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      if (mounted) setState(() => _downloads.remove(book.id));
    }
  }

  Future<void> _openSource(CatalogBook book) async {
    final url = book.pageUrl ?? book.epubUrl;
    if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: FutureBuilder<void>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_error != null) {
            return _CatalogMessage(
              icon: Icons.cloud_off,
              title: 'Catálogo indisponível',
              detail: describeCatalogError(_error!),
              technical: catalogErrorDetail(_error!),
              onRetry: _reload,
            );
          }
          return _buildFeed(context);
        },
      ),
    );
  }

  Widget _buildFeed(BuildContext context) {
    final sections = _sections;
    final books = _books;
    // Searching filters books, not sections, so it only makes sense where
    // there are books to filter.
    final searchable = _pages.any((page) => page.books.isNotEmpty);

    if (sections.isEmpty && books.isEmpty && _query.isEmpty) {
      return _CatalogMessage(
        icon: Icons.menu_book_outlined,
        title: 'Nada por aqui',
        detail: 'Esta parte do catálogo do SciELO está vazia.',
        onRetry: _reload,
      );
    }

    return Column(
      children: [
        if (searchable)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              controller: _search,
              hintText: 'Buscar nesta lista',
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _loading;
            },
            child: books.isEmpty && sections.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 80),
                      const _SearchMissMessage(),
                      // The message tells the reader to load more pages, so
                      // the control that does it has to survive an empty
                      // search — otherwise the only way forward is to clear
                      // the query, page ahead, and search again.
                      if (_hasMore)
                        _LoadMoreTile(
                          loading: _loadingMore,
                          onPressed: _loadMore,
                        ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount:
                        sections.length + books.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index < sections.length) {
                        return _SectionTile(section: sections[index]);
                      }
                      final bookIndex = index - sections.length;
                      if (bookIndex < books.length) {
                        return _bookTile(books[bookIndex]);
                      }
                      return _LoadMoreTile(
                        loading: _loadingMore,
                        onPressed: _loadMore,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _bookTile(CatalogBook book) {
    final downloading = _downloads.containsKey(book.id);
    return ListTile(
      leading: const Icon(Icons.auto_stories),
      title: Text(book.title),
      subtitle: Text(
        '${book.author}\n'
        '${book.publisher.isEmpty ? book.source : book.publisher} · EPUB',
      ),
      isThreeLine: true,
      onTap: downloading ? null : () => _download(book),
      trailing: downloading
          ? SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(value: _downloads[book.id]),
            )
          : PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'download') _download(book);
                if (value == 'source') _openSource(book);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'download', child: Text('Baixar EPUB')),
                PopupMenuItem(value: 'source', child: Text('Abrir fonte')),
              ],
            ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section});

  final CatalogSection section;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(section.title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/discover-brasil', extra: section),
    );
  }
}

class _LoadMoreTile extends StatelessWidget {
  const _LoadMoreTile({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : OutlinedButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.expand_more),
                label: const Text('Carregar mais'),
              ),
      ),
    );
  }
}

/// Shown when a search matches nothing in the pages loaded so far.
///
/// Deliberately not a flat "not found": only the loaded pages were searched,
/// and the catalog is much larger than that.
class _SearchMissMessage extends StatelessWidget {
  const _SearchMissMessage();

  @override
  Widget build(BuildContext context) {
    return const _CatalogMessage(
      icon: Icons.search_off,
      title: 'Nada encontrado',
      detail:
          'Nenhum livro nesta lista corresponde à sua busca. A busca olha '
          'apenas o que já foi carregado, então tente carregar mais ou '
          'procurar em outra seção.',
    );
  }
}

/// Fills the catalog area when there is no list to show, and says why.
class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.technical,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? technical;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      // Scrollable because the retry button is last: on a landscape phone, or
      // with large text scaling, a fixed column would push the one control
      // that recovers from the error off the bottom of the screen.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            if (technical != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                technical!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  fontFamily: 'monospace',
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
