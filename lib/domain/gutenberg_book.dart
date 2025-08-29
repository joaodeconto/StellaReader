class GutenbergBook {
  final int id;
  final String title;
  final String? author;
  final String? coverUrl;
  final String? pdfUrl;

  GutenbergBook({
    required this.id,
    required this.title,
    this.author,
    this.coverUrl,
    this.pdfUrl,
  });

  factory GutenbergBook.fromJson(Map<String, dynamic> j) {
    final authors = (j['authors'] as List?) ?? [];
    final author = authors.isNotEmpty ? (authors.first['name'] as String?) : null;
    final formats = (j['formats'] as Map?)?.cast<String, dynamic>() ?? {};
    String? cover;
    if (formats['image/jpeg'] is String) cover = formats['image/jpeg'] as String;
    // Prefer explicit PDF link if available
    String? pdf;
    if (formats['application/pdf'] is String) pdf = formats['application/pdf'] as String;
    return GutenbergBook(
      id: j['id'] as int,
      title: (j['title'] as String?)?.trim() ?? 'Untitled',
      author: author,
      coverUrl: cover,
      pdfUrl: pdf,
    );
  }
}

