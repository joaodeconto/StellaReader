import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../app_info.dart';
import '../domain/catalog_book.dart';

/// Reads the SciELO Livros OPDS catalog.
///
/// OPDS feeds come in two kinds. An *acquisition* feed lists books you can
/// download; a *navigation* feed lists other feeds. The root of a server is
/// conventionally a navigation feed, so finding books usually means following
/// it one level down — a client that only reads the root sees an empty
/// catalog and cannot tell that apart from a server with nothing to offer.
class ScieloOpdsService {
  ScieloOpdsService({Dio? dio}) : _dio = dio ?? Dio();

  /// The catalog root.
  ///
  /// Not `opds.livros.scielo.org`, which the app pointed at for a long time:
  /// that host serves an expired certificate and is not where SciELO
  /// publishes OPDS. The feed identifies itself as `books.scielo.org/opds/`.
  static final Uri catalogUri = Uri.parse('https://books.scielo.org/opds/');

  /// Ceiling on requests per load, so a catalog that links in circles or
  /// paginates forever cannot spin indefinitely.
  static const _requestBudget = 12;

  /// How far to chase navigation feeds. The root plus two levels reaches the
  /// acquisition feeds on every OPDS layout worth supporting.
  static const _maxDepth = 2;

  final Dio _dio;

  Future<List<CatalogBook>> loadEpubs() async {
    final books = <String, CatalogBook>{};
    final visited = <Uri>{};
    var budget = _requestBudget;

    Future<void> walk(Uri uri, int depth, {required bool tolerant}) async {
      if (budget <= 0 || depth > _maxDepth || !visited.add(uri)) return;
      budget--;

      final _Feed feed;
      try {
        feed = _parseFeed(await _fetch(uri), uri);
      } on Exception {
        // One broken section should not take the whole catalog down with it.
        // The root is the exception: if that fails there is nothing to show,
        // and the screen needs to be able to say why.
        if (!tolerant) rethrow;
        return;
      }

      for (final book in feed.books) {
        books.putIfAbsent(book.id, () => book);
      }

      if (feed.books.isEmpty) {
        // Nothing to download here, so this is a navigation feed: the books
        // are one level further in.
        for (final link in feed.navigation) {
          await walk(link, depth + 1, tolerant: true);
        }
      } else if (feed.next != null) {
        // A page of books, with more behind it.
        await walk(feed.next!, depth, tolerant: true);
      }
    }

    await walk(catalogUri, 0, tolerant: false);
    return books.values.toList(growable: false);
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

  _Feed _parseFeed(String body, Uri base) {
    final document = XmlDocument.parse(body);
    final books = <CatalogBook>[];
    final navigation = <Uri>[];

    // Atom is matched in any namespace: a feed is free to bind it to a prefix
    // (`<atom:entry>`) instead of making it the default, and both mean the
    // same thing. Matching the bare name would silently find nothing.
    for (final entry in document.findAllElements('entry', namespace: '*')) {
      final parsed = _parseEntry(entry, base);
      if (parsed == null) continue;
      if (parsed.book != null) {
        books.add(parsed.book!);
      } else if (parsed.feed != null) {
        navigation.add(parsed.feed!);
      }
    }

    return _Feed(
      books: books,
      navigation: navigation,
      next: _nextPage(document, base),
    );
  }

  /// The feed-level `rel="next"` link, ignoring the ones inside entries.
  Uri? _nextPage(XmlDocument document, Uri base) {
    final root = document.rootElement;
    for (final link in root.childElements) {
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
      return feedUrl == null ? null : _Entry.feed(feedUrl);
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

/// One feed's worth of results: the books in it, the feeds it points at, and
/// the page after it.
class _Feed {
  const _Feed({
    required this.books,
    required this.navigation,
    required this.next,
  });

  final List<CatalogBook> books;
  final List<Uri> navigation;
  final Uri? next;
}

/// An entry is either a book to download or a pointer to another feed.
class _Entry {
  const _Entry.book(CatalogBook this.book) : feed = null;
  const _Entry.feed(Uri this.feed) : book = null;

  final CatalogBook? book;
  final Uri? feed;
}
