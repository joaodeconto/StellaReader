import 'package:flutter_test/flutter_test.dart';
import 'package:stellareader/domain/book.dart';

void main() {
  group('Book', () {
    test('round-trips persisted PDF progress', () {
      final book = Book(
        id: 7,
        title: 'Stella',
        path: '/books/stella.pdf',
        lastPage: 42,
      );

      final restored = Book.fromMap(book.toMap());

      expect(restored.id, 7);
      expect(restored.title, 'Stella');
      expect(restored.path, '/books/stella.pdf');
      expect(restored.lastPage, 42);
      expect(restored.lastCfi, isNull);
    });

    test('round-trips persisted EPUB progress', () {
      final book = Book(
        title: 'Alice',
        path: '/books/alice.epub',
        lastCfi: 'epubcfi(/6/4!/4/2/1:0)',
      );

      final restored = Book.fromMap(book.toMap());

      expect(restored.lastPage, 1);
      expect(restored.lastCfi, 'epubcfi(/6/4!/4/2/1:0)');
    });

    test('copyWith preserves values not explicitly changed', () {
      final original = Book(
        id: 3,
        title: 'Original',
        path: '/books/original.pdf',
        lastPage: 8,
      );

      final updated = original.copyWith(lastPage: 9);

      expect(updated.id, original.id);
      expect(updated.title, original.title);
      expect(updated.path, original.path);
      expect(updated.lastPage, 9);
    });
  });
}
