import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDb {
  /// Bump this whenever the schema changes, and extend [migrate] to match.
  static const schemaVersion = 2;

  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'library.db');
    _db = await open(path);
    return _db!;
  }

  /// Opens (and migrates) the library database at [path].
  ///
  /// Exposed so tests can exercise the migration path against a temporary
  /// file without going through `path_provider`.
  static Future<Database> open(String path, {DatabaseFactory? factory}) {
    return (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          // The bookmarks table declares ON DELETE CASCADE, but SQLite ignores
          // foreign keys unless they are switched on for each connection.
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
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
        onUpgrade: migrate,
      ),
    );
  }

  /// Brings an existing database up to [schemaVersion].
  ///
  /// Version 1 is ambiguous: the EPUB reader added `books.lastCfi` and
  /// `bookmarks.cfi` to the v1 `onCreate` block without bumping the version,
  /// so two different shapes both report version 1. Every step therefore
  /// checks the live schema instead of trusting the recorded version.
  static Future<void> migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(db, 'books', 'lastCfi', 'TEXT');
      await _addColumnIfMissing(db, 'bookmarks', 'cfi', 'TEXT');
    }
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final present = columns.any((row) => row['name'] == column);
    if (present) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }
}
