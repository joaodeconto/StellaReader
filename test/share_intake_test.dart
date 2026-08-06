import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:stellareader/data/import_service.dart';
import 'package:stellareader/data/share_intake.dart';
import 'package:stellareader/domain/book.dart';

/// Stands in for the real import, which needs `path_provider` and a database.
/// Records what it was asked to copy so the tests can assert on the batch.
class _RecordingImportService extends ImportService {
  _RecordingImportService({this.failOn = const {}});

  /// Paths that should blow up the way an unreadable file would.
  final Set<String> failOn;

  final List<String> imported = [];

  @override
  Future<Book> importFile(File source) async {
    if (failOn.contains(source.path)) {
      throw const FileSystemException('unreadable');
    }
    imported.add(source.path);
    return Book(title: source.path, path: source.path);
  }
}

SharedMediaFile _shared(String path) =>
    SharedMediaFile(path: path, type: SharedMediaType.file);

void main() {
  group('ShareIntake', () {
    test('imports shared PDFs and EPUBs in the order they arrived', () async {
      final importService = _RecordingImportService();

      final result = await ShareIntake(
        importService: importService,
      ).receive([_shared('/cache/first.pdf'), _shared('/cache/second.epub')]);

      expect(importService.imported, [
        '/cache/first.pdf',
        '/cache/second.epub',
      ]);
      expect(result.books.map((book) => book.path), [
        '/cache/first.pdf',
        '/cache/second.epub',
      ]);
      expect(result.skipped, 0);
    });

    test('skips files the reader cannot open', () async {
      final importService = _RecordingImportService();

      final result = await ShareIntake(
        importService: importService,
      ).receive([_shared('/cache/notes.txt'), _shared('/cache/cover.jpg')]);

      expect(importService.imported, isEmpty);
      expect(result.books, isEmpty);
      expect(result.skipped, 2);
    });

    test('matches extensions regardless of case', () async {
      final importService = _RecordingImportService();

      final result = await ShareIntake(
        importService: importService,
      ).receive([_shared('/cache/SHOUTING.PDF'), _shared('/cache/Mixed.Epub')]);

      expect(result.books, hasLength(2));
      expect(result.skipped, 0);
    });

    test('keeps the rest of the batch when one file fails to import', () async {
      final importService = _RecordingImportService(
        failOn: {'/cache/broken.pdf'},
      );

      final result = await ShareIntake(importService: importService).receive([
        _shared('/cache/good.pdf'),
        _shared('/cache/broken.pdf'),
        _shared('/cache/also-good.epub'),
      ]);

      expect(result.books.map((book) => book.path), [
        '/cache/good.pdf',
        '/cache/also-good.epub',
      ]);
      expect(result.skipped, 1);
    });

    test('reports nothing for an empty share', () async {
      final result = await ShareIntake(
        importService: _RecordingImportService(),
      ).receive([]);

      expect(result.books, isEmpty);
      expect(result.skipped, 0);
    });
  });
}
