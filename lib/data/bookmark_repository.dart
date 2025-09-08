import '../domain/bookmark.dart';
import 'app_db.dart';

class BookmarkRepository {
  Future<int> insert(Bookmark b) async {
    final db = await AppDb.instance;
    return db.insert('bookmarks', b.toMap()..remove('id'));
  }

  Future<bool> existsByCfi(int bookId, String cfi) async {
    final db = await AppDb.instance;
    final rows = await db.query(
      'bookmarks',
      columns: const ['id'],
      where: 'bookId=? AND cfi=?',
      whereArgs: [bookId, cfi],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> updatePage(int id, int page) async {
    final db = await AppDb.instance;
    await db.update('bookmarks', {'page': page}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> updateLabel(int id, String label) async {
    final db = await AppDb.instance;
    await db.update('bookmarks', {'label': label}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> delete(int id) async {
    final db = await AppDb.instance;
    await db.delete('bookmarks', where: 'id=?', whereArgs: [id]);
  }

  Future<List<Bookmark>> byBook(int bookId) async {
    final db = await AppDb.instance;
    final rows = await db.query('bookmarks', where: 'bookId=?', whereArgs: [bookId], orderBy: 'page ASC');
    return rows.map(Bookmark.fromMap).toList();
  }
}

