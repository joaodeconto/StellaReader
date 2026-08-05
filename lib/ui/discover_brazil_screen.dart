import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/import_service.dart';
import '../data/scielo_opds_service.dart';
import '../domain/catalog_book.dart';

class DiscoverBrazilScreen extends StatefulWidget {
  const DiscoverBrazilScreen({super.key});

  @override
  State<DiscoverBrazilScreen> createState() => _DiscoverBrazilScreenState();
}

class _DiscoverBrazilScreenState extends State<DiscoverBrazilScreen> {
  final _service = ScieloOpdsService();
  final _dio = Dio();
  final _search = TextEditingController();
  final Map<String, double?> _downloads = {};
  late Future<List<CatalogBook>> _catalog;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _catalog = _service.loadEpubs();
  }

  @override
  void dispose() {
    _service.close();
    _dio.close(force: true);
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _catalog = _service.loadEpubs());

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
            'User-Agent': 'StellaReader/0.4.1',
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
      appBar: AppBar(title: const Text('EPUBs do Brasil')),
      body: FutureBuilder<List<CatalogBook>>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            );
          }
          final books = (snapshot.data ?? const <CatalogBook>[])
              .where((book) => book.matches(_query))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SearchBar(
                  controller: _search,
                  hintText: 'Buscar título, autor ou editora',
                  leading: const Icon(Icons.search),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text('Catálogo EPUB de acesso aberto do SciELO Livros.'),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _catalog;
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: books.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final book = books[index];
                      final downloading = _downloads.containsKey(book.id);
                      return ListTile(
                        leading: const Icon(Icons.auto_stories),
                        title: Text(book.title),
                        subtitle: Text(
                          '${book.author}\n${book.publisher.isEmpty ? book.source : book.publisher} · EPUB',
                        ),
                        isThreeLine: true,
                        onTap: downloading ? null : () => _download(book),
                        trailing: downloading
                            ? SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  value: _downloads[book.id],
                                ),
                              )
                            : PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'download') _download(book);
                                  if (value == 'source') _openSource(book);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'download',
                                    child: Text('Baixar EPUB'),
                                  ),
                                  PopupMenuItem(
                                    value: 'source',
                                    child: Text('Abrir fonte'),
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
