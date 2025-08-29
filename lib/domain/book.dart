class Book {
  final int? id;
  final String title;
  final String path;
  final int lastPage;

  Book({this.id, required this.title, required this.path, this.lastPage = 1});

  Book copyWith({int? id, String? title, String? path, int? lastPage}) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      path: path ?? this.path,
      lastPage: lastPage ?? this.lastPage,
    );
  }

  factory Book.fromMap(Map<String, dynamic> m) => Book(
        id: m['id'] as int?,
        title: m['title'] as String,
        path: m['path'] as String,
        lastPage: m['lastPage'] as int? ?? 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'path': path,
        'lastPage': lastPage,
      };
}

