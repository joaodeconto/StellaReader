class Bookmark {
  final int? id;
  final int bookId;
  final int page;
  final String? label;
  final int createdAt;

  Bookmark({
    this.id,
    required this.bookId,
    required this.page,
    this.label,
    required this.createdAt,
  });

  factory Bookmark.fromMap(Map<String, dynamic> m) => Bookmark(
        id: m['id'] as int?,
        bookId: m['bookId'] as int,
        page: m['page'] as int,
        label: m['label'] as String?,
        createdAt: m['createdAt'] as int,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'bookId': bookId,
        'page': page,
        'label': label,
        'createdAt': createdAt,
      };
}

