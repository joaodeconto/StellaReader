import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../domain/book.dart';
import 'import_service.dart';

/// What came of handing a batch of shared files to [ShareIntake].
class ShareImport {
  const ShareImport({required this.books, required this.skipped});

  /// The books now in the library, in the order they were shared.
  final List<Book> books;

  /// How many shared files StellaReader could not take in.
  final int skipped;
}

/// Takes in books that another app handed over through the Android share
/// sheet.
///
/// The plugin copies the shared content into a cache directory and gives us a
/// real file path. That cache is not ours to keep, so every file goes through
/// [ImportService.importFile], which copies it into the library and registers
/// it in the database exactly like a file-picker import.
class ShareIntake {
  ShareIntake({ImportService? importService})
    : _importService = importService ?? ImportService();

  final ImportService _importService;

  /// The plugin only implements Android and iOS; calling it anywhere else
  /// throws `MissingPluginException`.
  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Imports every readable file in [shared].
  ///
  /// One bad file does not sink the batch: sharing five books and getting none
  /// of them because the sender slipped in a stray file would be worse than a
  /// partial import, so failures are counted and reported rather than thrown.
  Future<ShareImport> receive(List<SharedMediaFile> shared) async {
    final books = <Book>[];
    var skipped = 0;

    for (final file in shared) {
      if (!_isSupported(file.path)) {
        skipped++;
        continue;
      }
      try {
        books.add(await _importService.importFile(File(file.path)));
      } on Exception {
        skipped++;
      }
    }

    return ShareImport(books: books, skipped: skipped);
  }

  /// The share sheet filters by MIME type, but a sending app is free to
  /// mislabel a file, so the extension is what decides.
  bool _isSupported(String path) {
    final extension = p.extension(path).toLowerCase();
    return extension == '.pdf' || extension == '.epub';
  }
}
