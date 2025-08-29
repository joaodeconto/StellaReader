import '../domain/bookmark.dart';
import 'app_db.dart';

class BookmarkRepository {
  Future<int> insert(Bookmark b) async {
    final db = await AppDb.instance;
    return db.insert('bookmarks', b.toMap()..remove('id'));
  }

  Future<List<Bookmark>> byBook(int bookId) async {
    final db = await AppDb.instance;
    final rows = await db.query('bookmarks', where: 'bookId=?', whereArgs: [bookId], orderBy: 'page ASC');
    return rows.map(Bookmark.fromMap).toList();
  }
}

