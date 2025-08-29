import '../domain/book.dart';
import 'app_db.dart';

class BookRepository {
  Future<int> insert(Book b) async {
    final db = await AppDb.instance;
    return db.insert('books', b.toMap()..remove('id'));
  }

  Future<List<Book>> all() async {
    final db = await AppDb.instance;
    final rows = await db.query('books', orderBy: 'id DESC');
    return rows.map(Book.fromMap).toList();
  }

  Future<void> updateLastPage(int bookId, int page) async {
    final db = await AppDb.instance;
    await db.update('books', {'lastPage': page}, where: 'id=?', whereArgs: [bookId]);
  }

  Future<void> updateLastCfi(int bookId, String cfi) async {
    final db = await AppDb.instance;
    await db.update('books', {'lastCfi': cfi}, where: 'id=?', whereArgs: [bookId]);
  }
}
