import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/book.dart';
import 'book_repository.dart';

class ImportService {
  ImportService({BookRepository? repository})
      : _repository = repository ?? BookRepository();

  final BookRepository _repository;

  Future<Book?> pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'epub'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final sourcePath = result.files.single.path;
    if (sourcePath == null || sourcePath.isEmpty) return null;
    return importFile(File(sourcePath));
  }

  Future<Book> importFile(File source) async {
    final extension = p.extension(source.path).toLowerCase();
    if (extension != '.pdf' && extension != '.epub') {
      throw const FormatException('Only PDF and EPUB files are supported.');
    }

    final documents = await getApplicationDocumentsDirectory();
    final libraryDir = Directory(p.join(documents.path, 'books'));
    await libraryDir.create(recursive: true);

    final baseName = p.basenameWithoutExtension(source.path);
    final safeName = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    final fileName = '${DateTime.now().microsecondsSinceEpoch}_$safeName$extension';
    final destination = File(p.join(libraryDir.path, fileName));
    await source.copy(destination.path);

    final book = Book(title: baseName, path: destination.path);
    final id = await _repository.insert(book);
    return book.copyWith(id: id);
  }

  static bool isEpub(Book book) =>
      p.extension(book.path).toLowerCase() == '.epub';
}
