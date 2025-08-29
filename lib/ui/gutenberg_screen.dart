import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/gutendex_service.dart';
import '../domain/gutenberg_book.dart';
import 'package:go_router/go_router.dart';
import '../domain/book.dart';
import '../data/book_repository.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io' as io;
import 'package:pdfx/pdfx.dart';
import 'package:epub_view/epub_view.dart';
import 'package:universal_file/universal_file.dart' as uni;
import 'library_screen.dart' as lib;

final _queryProvider = StateProvider<String>((_) => '');
final _pageProvider = StateProvider<int>((_) => 1);
final _resultsProvider = FutureProvider.autoDispose<List<GutenbergBook>>((ref) async {
  final q = ref.watch(_queryProvider);
  final page = ref.watch(_pageProvider);
  final svc = GutendexService();
  return svc.search(query: q.isEmpty ? null : q, page: page);
});

class GutenbergScreen extends ConsumerStatefulWidget {
  const GutenbergScreen({super.key});
  @override
  ConsumerState<GutenbergScreen> createState() => _GutenbergScreenState();
}

class _GutenbergScreenState extends ConsumerState<GutenbergScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(_resultsProvider);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            hintText: 'Buscar em Gutenberg...',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            ref.read(_queryProvider.notifier).state = v.trim();
            ref.read(_pageProvider.notifier).state = 1;
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              ref.read(_queryProvider.notifier).state = _searchCtrl.text.trim();
              ref.read(_pageProvider.notifier).state = 1;
            },
          )
        ],
      ),
      body: results.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('Nenhum resultado'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final b = items[i];
              final hasPdf = b.pdfUrl != null && b.pdfUrl!.isNotEmpty;
              final hasEpub = b.epubUrl != null && b.epubUrl!.isNotEmpty;
              return ListTile(
                leading: b.coverUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: m.Image.network(b.coverUrl!, width: 48, height: 48, fit: BoxFit.cover),
                      )
                    : const Icon(Icons.menu_book_outlined),
                title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(b.author ?? 'Autor desconhecido', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Wrap(spacing: 8, children: [
                  IconButton(
                    tooltip: hasPdf ? 'Baixar PDF' : 'PDF indisponível',
                    onPressed: hasPdf ? () => _downloadFormat(context, ref, b, 'pdf') : null,
                    icon: const Icon(Icons.picture_as_pdf),
                  ),
                  IconButton(
                    tooltip: hasEpub ? 'Baixar EPUB' : 'EPUB indisponível',
                    onPressed: hasEpub ? () => _downloadFormat(context, ref, b, 'epub') : null,
                    icon: const Icon(Icons.book_outlined),
                  ),
                ]),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: () {
                final p = ref.read(_pageProvider);
                if (p > 1) ref.read(_pageProvider.notifier).state = p - 1;
              },
              icon: const Icon(Icons.chevron_left),
              label: const Text('Anterior'),
            ),
            Text('Página ${ref.watch(_pageProvider)}'),
            TextButton.icon(
              onPressed: () {
                final p = ref.read(_pageProvider);
                ref.read(_pageProvider.notifier).state = p + 1;
              },
              icon: const Icon(Icons.chevron_right),
              label: const Text('Próxima'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadFormat(BuildContext context, WidgetRef ref, GutenbergBook g, String format) async {
    final url = format == 'pdf' ? g.pdfUrl! : g.epubUrl!;
    final dir = await getApplicationDocumentsDirectory();
    final filename = _sanitizeFileName('${g.title}.${format == 'pdf' ? 'pdf' : 'epub'}');
    final savePath = _uniquePath(io.File(p.join(dir.path, filename)));
    final cancelToken = CancelToken();
    int received = 0;
    int total = -1;
    bool started = false;
    // ignore: use_build_context_synchronously
    await showDialog(
      barrierDismissible: false,
      // ignore: use_build_context_synchronously
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (c, setState) {
          if (!started) {
            started = true;
            () async {
              try {
                await Dio().download(url, savePath, cancelToken: cancelToken, onReceiveProgress: (r, t) {
                  setState(() {
                    received = r;
                    total = t;
                  });
                });
                if (format == 'pdf') {
                  final doc = await PdfDocument.openFile(savePath);
                  await doc.close();
                } else {
                  await EpubDocument.openFile(uni.File(savePath));
                }
                final id = await BookRepository().insert(Book(title: g.title, path: savePath, format: format));
                if (!c.mounted) return;
                Navigator.pop(c);
                if (!context.mounted) return;
                final nav = GoRouter.of(context).push('/reader', extra: Book(id: id, title: g.title, path: savePath, format: format));
                // Refresh library once back
                await nav;
                ref.invalidate(lib.booksProvider);
              } catch (e) {
                if (!c.mounted) return;
                Navigator.pop(c);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha no download: $e')));
                try { await io.File(savePath).delete(); } catch (_) {}
              }
            }();
          }
          final value = (total > 0) ? (received / total) : null;
          final percent = (value == null) ? '—' : '${(value * 100).toStringAsFixed(0)}%';
          return AlertDialog(
            title: const Text('Baixando...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: value),
                const SizedBox(height: 8),
                Text(percent),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => cancelToken.cancel('cancelado'),
                child: const Text('Cancelar'),
              ),
            ],
          );
        });
      },
    );
  }

  String _sanitizeFileName(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  String _uniquePath(io.File target) {
    var path = target.path;
    if (!target.existsSync()) return path;
    final dir = target.parent.path;
    final base = p.basenameWithoutExtension(path);
    final ext = p.extension(path);
    var i = 1;
    while (io.File(p.join(dir, '$base($i)$ext')).existsSync()) {
      i++;
    }
    return p.join(dir, '$base($i)$ext');
  }
}
