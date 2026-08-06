import 'catalog_book.dart';

/// A branch of the catalog: a feed that holds other feeds or books.
class CatalogSection {
  const CatalogSection({required this.title, required this.uri});

  final String title;
  final Uri uri;
}

/// One OPDS feed, read exactly as served.
///
/// A feed can hold books, links to other feeds, or both. Nothing is followed
/// on the reader's behalf — opening a section is the reader's choice, which is
/// what keeps the catalog browsable without guessing how much of somebody
/// else's server to download up front.
class OpdsFeed {
  const OpdsFeed({
    required this.title,
    required this.books,
    required this.sections,
    required this.next,
  });

  final String title;
  final List<CatalogBook> books;
  final List<CatalogSection> sections;

  /// The next page of this same feed, when it is paginated.
  final Uri? next;

  bool get isEmpty => books.isEmpty && sections.isEmpty;
}
