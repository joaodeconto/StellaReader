import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;
import 'package:pdfx/pdfx.dart';
import 'package:epub_view/epub_view.dart';
import 'package:universal_file/universal_file.dart' as uni;
import '../data/share_handler.dart';
import '../data/app_db.dart';
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
            tooltip: 'Explorar Gutenberg',
            icon: const Icon(Icons.public),
            onPressed: () => context.push('/gutenberg'),
          ),
          IconButton(
            tooltip: 'Baixar por URL',
            icon: const Icon(Icons.download),
            onPressed: () => _promptDownload(context, ref),
          ),
        ],
      ),
      body: books.when(
        data: (items) => items.isEmpty
            ? const Center(
                child: Text('Nenhum livro. Toque em + para importar.'),
              )
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final b = items[i];
                  return ListTile(
                    title: Text(b.title),
                    subtitle: Text(
                      b.format == 'pdf'
                          ? 'Última página: ${b.lastPage}'
                          : 'Formato: EPUB',
                    ),
                    onTap: () => _openBook(context, ref, b),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        switch (v) {
                          case 'relink':
                            _relinkBook(context, ref, b);
                            break;
                          case 'delete':
                            _deleteBook(context, ref, b);
                            break;
                        }
                      },
                      itemBuilder: (c) => const [
                        PopupMenuItem(
                          value: 'relink',
                          child: Text('Corrigir caminho…'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Remover da biblioteca'),
                        ),
                      ],
                    ),
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
            final ext = p.extension(path).toLowerCase();
            final format = ext == '.epub' ? 'epub' : 'pdf';
            final id = await BookRepository().insert(
              Book(title: title, path: path, format: format),
            );
            // Recarrega lista
            ref.invalidate(booksProvider);
            // Abre direto
            final book = Book(id: id, title: title, path: path, format: format);
            // ignore: use_build_context_synchronously
            await context.push('/reader', extra: book);
            // refresh again after returning
            ref.invalidate(booksProvider);
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
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctrl.text.trim()),
          child: const Text('Baixar'),
        ),
      ],
    ),
  );
  if (url == null || url.isEmpty) return;
  // ignore: use_build_context_synchronously
  await _startDownload(context, ref, url);
}

Future<void> _startDownload(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final filename = _suggestFileName(url);
    final savePath = _uniquePath(io.File(p.join(dir.path, filename)));

    int received = 0;
    int total = -1;
    bool started = false;
    final cancelToken = CancelToken();
    // ignore: use_build_context_synchronously
    await showDialog(
      barrierDismissible: false,
      // ignore: use_build_context_synchronously
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (c, setState) {
            if (!started) {
              started = true;
              () async {
                try {
                  await Dio().download(
                    url,
                    savePath,
                    cancelToken: cancelToken,
                    onReceiveProgress: (r, t) {
                      setState(() {
                        received = r;
                        total = t;
                      });
                    },
                  );
                  // Validate and detect format
                  final format = filename.toLowerCase().endsWith('.epub')
                      ? 'epub'
                      : 'pdf';
                  if (format == 'pdf') {
                    final doc = await PdfDocument.openFile(savePath);
                    await doc.close();
                  } else {
                    await EpubDocument.openFile(uni.File(savePath));
                  }
                  final title = p.basenameWithoutExtension(savePath);
                  final id = await BookRepository().insert(
                    Book(title: title, path: savePath, format: format),
                  );
                  if (!c.mounted) return;
                  Navigator.pop(c); // close progress
                  if (!context.mounted) return;
                  final nav = GoRouter.of(context).push(
                    '/reader',
                    extra: Book(
                      id: id,
                      title: title,
                      path: savePath,
                      format: format,
                    ),
                  );
                  // update list while away, and once back
                  ref.invalidate(booksProvider);
                  await nav;
                  ref.invalidate(booksProvider);
                } catch (e) {
                  if (!c.mounted) return;
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Falha no download: $e')),
                  );
                  try {
                    await io.File(savePath).delete();
                  } catch (_) {}
                }
              }();
            }
            final value = (total > 0) ? (received / total) : null;
            final percent = (value == null)
                ? '—'
                : '${(value * 100).toStringAsFixed(0)}%';
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
          },
        );
      },
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Erro: $e')));
  }
}

String _suggestFileName(String url) {
  try {
    final uri = Uri.parse(url);
    var name = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : 'arquivo.pdf';
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

Future<void> _openBook(BuildContext context, WidgetRef ref, Book b) async {
  final exists = io.File(b.path).existsSync();
  if (exists) {
    // ignore: use_build_context_synchronously
    final nav = GoRouter.of(context).push('/reader', extra: b);
    await nav;
    ref.invalidate(booksProvider);
    return;
  }
  final action = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Arquivo não encontrado'),
      content: Text(
        'O arquivo associado a "${b.title}" não foi encontrado. O que deseja fazer?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, 'cancel'),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, 'relink'),
          child: const Text('Corrigir caminho…'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, 'delete'),
          child: const Text('Remover'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'relink':
      _relinkBook(context, ref, b);
      break;
    case 'delete':
      _deleteBook(context, ref, b);
      break;
    default:
  }
}

Future<void> _relinkBook(BuildContext context, WidgetRef ref, Book b) async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'epub'],
  );
  if (res == null || res.files.single.path == null) return;
  final newPath = res.files.single.path!;
  final ext = p.extension(newPath).toLowerCase();
  final format = ext == '.epub' ? 'epub' : 'pdf';
  await BookRepository().updatePath(b.id!, newPath);
  // Also update format if changed
  if (format != b.format) {
    // quick direct update
    final db = await AppDb.instance;
    await db.update(
      'books',
      {'format': format},
      where: 'id=?',
      whereArgs: [b.id],
    );
  }
  ref.invalidate(booksProvider);
  if (!context.mounted) return;
  GoRouter.of(context).push(
    '/reader',
    extra: b.copyWith(path: newPath, format: format),
  );
}

Future<void> _deleteBook(BuildContext context, WidgetRef ref, Book b) async {
  await BookRepository().delete(b.id!);
  ref.invalidate(booksProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${b.title}" removido da biblioteca')),
    );
  }
}
