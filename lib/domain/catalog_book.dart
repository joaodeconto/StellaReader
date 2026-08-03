class CatalogBook {
  const CatalogBook({
    required this.title,
    required this.author,
    required this.category,
    required this.format,
    required this.license,
    required this.pageUrl,
  });

  final String title;
  final String author;
  final String category;
  final String format;
  final String license;
  final Uri pageUrl;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return title.toLowerCase().contains(normalized) ||
        author.toLowerCase().contains(normalized) ||
        category.toLowerCase().contains(normalized);
  }
}
