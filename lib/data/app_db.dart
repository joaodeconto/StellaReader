import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDb {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'library.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE books(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            path TEXT NOT NULL,
            format TEXT NOT NULL DEFAULT 'pdf',
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
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute("ALTER TABLE books ADD COLUMN format TEXT NOT NULL DEFAULT 'pdf'");
          await db.execute("ALTER TABLE books ADD COLUMN lastCfi TEXT");
          await db.execute("ALTER TABLE bookmarks ADD COLUMN cfi TEXT");
        }
      },
    );
    return _db!;
  }
}
