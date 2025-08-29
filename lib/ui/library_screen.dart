import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;
import 'package:pdfx/pdfx.dart';
import '../data/share_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/book_repository.dart';
import '../domain/book.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

final booksProvider = FutureProvider.autoDispose<List<Book>>((ref) async {
  final repo = BookRepository();
  return repo.all();
});

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Biblioteca')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Preview Web: armazenamento e importação estão desativados neste MVP.\n\n'
              'Execute no Android para testar importar PDFs, salvar última página e marcadores.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    // Initialize Android share-to-open once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) ShareHandler.init(context);
    });

    final books = ref.watch(booksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biblioteca'),
        actions: [
          IconButton(
            tooltip: 'Baixar por URL',
            icon: const Icon(Icons.download),
            onPressed: () => _promptDownload(context, ref),
          ),
        ],
      ),
      body: books.when(
        data: (items) => items.isEmpty
            ? const Center(child: Text('Nenhum livro. Toque em + para importar.'))
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final b = items[i];
                  return ListTile(
                    title: Text(b.title),
                    subtitle: Text('Última página: ${b.lastPage}'),
                    onTap: () => context.push('/reader', extra: b),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final res = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['pdf'],
          );
          if (res != null && res.files.single.path != null) {
            final path = res.files.single.path!;
            final title = p.basenameWithoutExtension(path);
            final id = await BookRepository().insert(Book(title: title, path: path));
            // Recarrega lista
            ref.invalidate(booksProvider);
            // Abre direto
            final book = Book(id: id, title: title, path: path);
            // ignore: use_build_context_synchronously
            context.push('/reader', extra: book);
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

Future<void> _promptDownload(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final url = await showDialog<String?>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Baixar PDF por URL'),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(hintText: 'https://.../arquivo.pdf'),
        keyboardType: TextInputType.url,
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Baixar')),
      ],
    ),
  );
  if (url == null || url.isEmpty) return;
  // ignore: use_build_context_synchronously
  await _startDownload(context, ref, url);
}

Future<void> _startDownload(BuildContext context, WidgetRef ref, String url) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final filename = _suggestFileName(url);
    final savePath = _uniquePath(io.File(p.join(dir.path, filename)));

    double progress = 0;
    bool canceled = false;
    final cancelToken = CancelToken();
    // ignore: use_build_context_synchronously
    await showDialog(
      barrierDismissible: false,
      // ignore: use_build_context_synchronously
      context: context,
      builder: (c) {
        () async {
          try {
            await Dio().download(
              url,
              savePath,
              cancelToken: cancelToken,
              onReceiveProgress: (r, t) {
                if (t > 0) {
                  progress = r / t;
                  // ignore: invalid_use_of_protected_member
                  (c as Element).markNeedsBuild();
                }
              },
            );
            // Validate PDF
            final doc = await PdfDocument.openFile(savePath);
            await doc.close();
            final title = p.basenameWithoutExtension(savePath);
            final id = await BookRepository().insert(Book(title: title, path: savePath));
            if (c.mounted) {
              Navigator.pop(c); // close progress
              // Navigate to reader
              // ignore: use_build_context_synchronously
              GoRouter.of(context).push('/reader', extra: Book(id: id, title: title, path: savePath));
              // Refresh list
              ref.invalidate(booksProvider);
            }
          } catch (e) {
            if (!c.mounted) return;
            Navigator.pop(c);
            if (!canceled) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Falha no download: $e')),
              );
              try { await io.File(savePath).delete(); } catch (_) {}
            }
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
              onPressed: () {
                canceled = true;
                cancelToken.cancel('cancelado');
              },
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erro: $e')),
    );
  }
}

String _suggestFileName(String url) {
  try {
    final uri = Uri.parse(url);
    var name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'arquivo.pdf';
    if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
    return name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  } catch (_) {
    return 'arquivo.pdf';
  }
}

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

