class CatalogBook {
  const CatalogBook({
    required this.id,
    required this.title,
    required this.author,
    required this.summary,
    required this.publisher,
    required this.license,
    required this.source,
    this.epubUrl,
    this.pageUrl,
    this.coverUrl,
  });

  final String id;
  final String title;
  final String author;
  final String summary;
  final String publisher;
  final String license;
  final String source;
  final Uri? epubUrl;
  final Uri? pageUrl;
  final Uri? coverUrl;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return title.toLowerCase().contains(normalized) ||
        author.toLowerCase().contains(normalized) ||
        publisher.toLowerCase().contains(normalized) ||
        summary.toLowerCase().contains(normalized);
  }
}
