import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
    final books = ref.watch(booksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Biblioteca')),
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
