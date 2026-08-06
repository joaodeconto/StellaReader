import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../app_info.dart';
import '../domain/catalog_book.dart';
import '../domain/catalog_feed.dart';

/// Reads the SciELO Books OPDS catalog, one feed at a time.
///
/// OPDS feeds come in two kinds. An *acquisition* feed lists books you can
/// download; a *navigation* feed lists other feeds. The root of a server is
/// conventionally a navigation feed, and SciELO's is: New Releases,
/// Publishers, Alphabetical.
///
/// This reads whichever feed it is asked for and reports what is in it. It
/// deliberately does not crawl. The catalog runs to thousands of titles, so
/// any bounded walk of it returns an arbitrary slice while looking like the
/// whole thing — which branch to open is the reader's call, not ours.
class ScieloOpdsService {
  ScieloOpdsService({Dio? dio}) : _dio = dio ?? Dio();

  /// The catalog root.
  ///
  /// Not `opds.livros.scielo.org`, which the app pointed at for a long time:
  /// that host serves an expired certificate and is not where SciELO
  /// publishes OPDS. The feed identifies itself as `books.scielo.org/opds/`.
  static final Uri catalogUri = Uri.parse('https://books.scielo.org/opds/');

  final Dio _dio;

  /// Reads [uri], defaulting to the catalog root.
  Future<OpdsFeed> loadFeed([Uri? uri]) async {
    final target = uri ?? catalogUri;
    return _parseFeed(await _fetch(target), target);
  }

  Future<String> _fetch(Uri uri) async {
    final response = await _dio.getUri<String>(
      uri,
      options: Options(
        responseType: ResponseType.plain,
        headers: const {
          'Accept': 'application/atom+xml, application/xml;q=0.9',
          'User-Agent': userAgent,
        },
      ),
    );

    final body = response.data;
    if (body == null || body.trim().isEmpty) {
      throw const FormatException(
        'O catálogo SciELO retornou uma resposta vazia.',
      );
    }
    return body;
  }

  OpdsFeed _parseFeed(String body, Uri base) {
    final document = XmlDocument.parse(body);
    final books = <CatalogBook>[];
    final sections = <CatalogSection>[];

    // Atom is matched in any namespace: SciELO binds it to a prefix
    // (`<atom:entry>`) rather than making it the default, and matching the
    // bare name would silently find nothing.
    for (final entry in document.findAllElements('entry', namespace: '*')) {
      final parsed = _parseEntry(entry, base);
      if (parsed == null) continue;
      if (parsed.book != null) {
        books.add(parsed.book!);
      } else if (parsed.section != null) {
        sections.add(parsed.section!);
      }
    }

    return OpdsFeed(
      title: _feedTitle(document),
      books: books,
      sections: sections,
      next: _nextPage(document, base),
    );
  }

  /// The feed's own title, ignoring the titles inside its entries.
  String _feedTitle(XmlDocument document) {
    for (final child in document.rootElement.childElements) {
      if (child.name.local == 'title') return child.innerText.trim();
    }
    return '';
  }

  /// The feed-level `rel="next"` link, ignoring the ones inside entries.
  Uri? _nextPage(XmlDocument document, Uri base) {
    for (final link in document.rootElement.childElements) {
      if (link.name.local != 'link') continue;
      if (link.getAttribute('rel') != 'next') continue;
      final href = link.getAttribute('href');
      if (href != null && href.isNotEmpty) return base.resolve(href);
    }
    return null;
  }

  _Entry? _parseEntry(XmlElement entry, Uri base) {
    String text(String name) => entry.descendants
        .whereType<XmlElement>()
        .firstWhere(
          (element) => element.name.local == name,
          orElse: () => XmlElement(XmlName(name)),
        )
        .innerText
        .trim();

    final title = text('title');
    if (title.isEmpty) return null;

    final authors = entry
        .findAllElements('author', namespace: '*')
        .map(
          (author) => author.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'name')
              .map((element) => element.innerText.trim())
              .where((value) => value.isNotEmpty)
              .join(),
        )
        .where((value) => value.isNotEmpty)
        .join('; ');

    Uri? epubUrl;
    Uri? pageUrl;
    Uri? coverUrl;
    Uri? feedUrl;

    for (final link in entry.findAllElements('link', namespace: '*')) {
      final href = link.getAttribute('href');
      if (href == null || href.isEmpty) continue;
      final uri = base.resolve(href);
      final type = (link.getAttribute('type') ?? '').toLowerCase();
      final rel = (link.getAttribute('rel') ?? '').toLowerCase();

      if (type.contains('application/epub+zip')) {
        epubUrl = uri;
      } else if (type.contains('application/atom+xml')) {
        // A link to another feed: this entry is a section, not a book.
        feedUrl ??= uri;
      } else if (rel.contains('image') || type.startsWith('image/')) {
        coverUrl ??= uri;
      } else if (rel == 'alternate' || type.contains('text/html')) {
        pageUrl ??= uri;
      }
    }

    if (epubUrl == null) {
      return feedUrl == null
          ? null
          : _Entry.section(CatalogSection(title: title, uri: feedUrl));
    }

    return _Entry.book(
      CatalogBook(
        id: text('id').isEmpty ? title : text('id'),
        title: title,
        author: authors.isEmpty ? 'Autoria não informada' : authors,
        summary: text('summary'),
        publisher: text('publisher'),
        license: text('rights').isEmpty
            ? 'Acesso conforme SciELO Livros'
            : text('rights'),
        source: 'SciELO Livros',
        epubUrl: epubUrl,
        pageUrl: pageUrl,
        coverUrl: coverUrl,
      ),
    );
  }

  void close() => _dio.close(force: true);
}

/// An entry is either a book to download or a pointer to another feed.
class _Entry {
  const _Entry.book(CatalogBook this.book) : section = null;
  const _Entry.section(CatalogSection this.section) : book = null;

  final CatalogBook? book;
  final CatalogSection? section;
}
