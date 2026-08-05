import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stellareader/data/app_db.dart';

/// The schema as it shipped before "Add EPUB reader with CFI bookmarking":
/// no `books.lastCfi`, no `bookmarks.cfi`, recorded as version 1.
const _legacyV1Books = '''
  CREATE TABLE books(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    path TEXT NOT NULL,
    lastPage INTEGER NOT NULL DEFAULT 1
  );
''';

const _legacyV1Bookmarks = '''
  CREATE TABLE bookmarks(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bookId INTEGER NOT NULL,
    page INTEGER NOT NULL,
    label TEXT,
    createdAt INTEGER NOT NULL,
    FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE
  );
''';

Future<Set<String>> _columnsOf(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'] as String).toSet();
}

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stellareader_db_test');
    dbPath = '${tempDir.path}/library.db';
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('upgrades a pre-EPUB v1 database without losing books', () async {
    final legacy = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(_legacyV1Books);
          await db.execute(_legacyV1Bookmarks);
        },
      ),
    );
    await legacy.insert('books', {
      'title': 'O Pequeno Príncipe',
      'path': '/books/pequeno_principe.pdf',
      'lastPage': 42,
    });
    await legacy.insert('bookmarks', {
      'bookId': 1,
      'page': 42,
      'label': 'a raposa',
      'createdAt': 1700000000000,
    });
    await legacy.close();

    final upgraded = await AppDb.open(dbPath, factory: factory);
    addTearDown(upgraded.close);

    expect(await upgraded.getVersion(), AppDb.schemaVersion);
    expect(await _columnsOf(upgraded, 'books'), contains('lastCfi'));
    expect(await _columnsOf(upgraded, 'bookmarks'), contains('cfi'));

    final books = await upgraded.query('books');
    expect(books, hasLength(1));
    expect(books.single['title'], 'O Pequeno Príncipe');
    expect(books.single['lastPage'], 42);
    expect(books.single['lastCfi'], isNull);

    final bookmarks = await upgraded.query('bookmarks');
    expect(bookmarks.single['label'], 'a raposa');

    // The whole point of the migration: this used to throw.
    await upgraded.update(
      'books',
      {'lastCfi': 'epubcfi(/6/4!/2/2)'},
      where: 'id=?',
      whereArgs: [1],
    );
  });

  test('leaves an already-current v1 database intact', () async {
    // The other shape that also reports version 1: CFI columns present,
    // because they were added to onCreate without bumping the version.
    final current = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE books(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              path TEXT NOT NULL,
              lastPage INTEGER NOT NULL DEFAULT 1,
              lastCfi TEXT
            );
          ''');
          await db.execute('''
            CREATE TABLE bookmarks(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              bookId INTEGER NOT NULL,
              page INTEGER NOT NULL,
              cfi TEXT,
              label TEXT,
              createdAt INTEGER NOT NULL,
              FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE
            );
          ''');
        },
      ),
    );
    await current.insert('books', {
      'title': 'Reinações de Narizinho',
      'path': '/books/narizinho.epub',
      'lastPage': 1,
      'lastCfi': 'epubcfi(/6/2!/4)',
    });
    await current.close();

    final upgraded = await AppDb.open(dbPath, factory: factory);
    addTearDown(upgraded.close);

    expect(await upgraded.getVersion(), AppDb.schemaVersion);
    final books = await upgraded.query('books');
    expect(books.single['lastCfi'], 'epubcfi(/6/2!/4)');
  });

  test('creates a fresh database at the current version', () async {
    final db = await AppDb.open(dbPath, factory: factory);
    addTearDown(db.close);

    expect(await db.getVersion(), AppDb.schemaVersion);
    expect(await _columnsOf(db, 'books'), contains('lastCfi'));
    expect(await _columnsOf(db, 'bookmarks'), contains('cfi'));
  });

  test(
    'cascades bookmark deletion so removing a book leaves no orphans',
    () async {
      final db = await AppDb.open(dbPath, factory: factory);
      addTearDown(db.close);

      final bookId = await db.insert('books', {
        'title': 'Memórias da Emília',
        'path': '/books/emilia.epub',
        'lastPage': 1,
      });
      await db.insert('bookmarks', {
        'bookId': bookId,
        'page': 7,
        'label': 'capítulo 2',
        'createdAt': 1700000000000,
      });

      await db.delete('books', where: 'id=?', whereArgs: [bookId]);

      expect(await db.query('bookmarks'), isEmpty);
    },
  );
}
