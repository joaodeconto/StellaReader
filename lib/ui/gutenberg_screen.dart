import 'package:flutter/material.dart';
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
              return ListTile(
                leading: b.coverUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(b.coverUrl!, width: 48, height: 48, fit: BoxFit.cover),
                      )
                    : const Icon(Icons.menu_book_outlined),
                title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(b.author ?? 'Autor desconhecido', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: hasPdf ? 'Baixar PDF' : 'PDF indisponível',
                  onPressed: hasPdf ? () => _downloadPdf(context, ref, b) : null,
                  icon: const Icon(Icons.download),
                ),
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

  Future<void> _downloadPdf(BuildContext context, WidgetRef ref, GutenbergBook g) async {
    final url = g.pdfUrl!;
    final dir = await getApplicationDocumentsDirectory();
    final filename = _sanitizeFileName('${g.title}.pdf');
    final savePath = _uniquePath(io.File(p.join(dir.path, filename)));
    double progress = 0;
    final cancelToken = CancelToken();
    // ignore: use_build_context_synchronously
    await showDialog(
      barrierDismissible: false,
      // ignore: use_build_context_synchronously
      context: context,
      builder: (c) {
        () async {
          try {
            await Dio().download(url, savePath, cancelToken: cancelToken, onReceiveProgress: (r, t) {
              if (t > 0) {
                progress = r / t;
                // ignore: invalid_use_of_protected_member
                (c as Element).markNeedsBuild();
              }
            });
            final doc = await PdfDocument.openFile(savePath);
            await doc.close();
            final id = await BookRepository().insert(Book(title: g.title, path: savePath));
            if (!c.mounted) return;
            Navigator.pop(c);
            // ignore: use_build_context_synchronously
            GoRouter.of(context).push('/reader', extra: Book(id: id, title: g.title, path: savePath));
          } catch (e) {
            if (!c.mounted) return;
            Navigator.pop(c);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha no download: $e')));
            try { await io.File(savePath).delete(); } catch (_) {}
          }
        }();
        return AlertDialog(
          title: const Text('Baixando...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: progress == 0 ? null : progress),
              const SizedBox(height: 8),
              Text('${(progress * 100).toStringAsFixed(0)}%'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => cancelToken.cancel('cancelado'),
              child: const Text('Cancelar'),
            ),
          ],
        );
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
