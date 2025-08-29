class Book {
  final int? id;
  final String title;
  final String path;
  final String format; // 'pdf' | 'epub'
  final int lastPage; // used for PDF
  final String? lastCfi; // used for EPUB

  Book({
    this.id,
    required this.title,
    required this.path,
    this.format = 'pdf',
    this.lastPage = 1,
    this.lastCfi,
  });

  Book copyWith({int? id, String? title, String? path, String? format, int? lastPage, String? lastCfi}) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      path: path ?? this.path,
      format: format ?? this.format,
      lastPage: lastPage ?? this.lastPage,
      lastCfi: lastCfi ?? this.lastCfi,
    );
  }

  factory Book.fromMap(Map<String, dynamic> m) => Book(
        id: m['id'] as int?,
        title: m['title'] as String,
        path: m['path'] as String,
        format: (m['format'] as String?) ?? 'pdf',
        lastPage: m['lastPage'] as int? ?? 1,
        lastCfi: m['lastCfi'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'path': path,
        'format': format,
        'lastPage': lastPage,
        'lastCfi': lastCfi,
      };
}
