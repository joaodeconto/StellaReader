import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellareader/data/scielo_opds_service.dart';

/// Serves canned bodies so the parser can be exercised without the network.
///
/// Records every URL asked for, which is how the tests check that reading one
/// feed reads exactly one feed.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.bodies);

  /// Path (or full URL) to the feed served for it.
  final Map<String, String> bodies;

  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri.toString());
    final body = bodies[options.uri.toString()] ?? bodies[options.uri.path];
    if (body == null) {
      throw DioException(
        requestOptions: options,
        response: Response<void>(requestOptions: options, statusCode: 404),
        type: DioExceptionType.badResponse,
      );
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/atom+xml;charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ScieloOpdsService _serviceWith(_CannedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ScieloOpdsService(dio: dio);
}

ScieloOpdsService _serviceServing(String body) =>
    _serviceWith(_CannedAdapter({'/opds/': body}));

/// The real SciELO Books catalog root, as served by books.scielo.org.
///
/// Worth keeping verbatim: it binds Atom to a prefix instead of using the
/// default namespace, and it is pure navigation with no book in it. Matching
/// bare element names finds nothing here at all.
const _scieloRoot = '''
<atom:feed xmlns:atom="http://www.w3.org/2005/Atom">
  <atom:id>http://books.scielo.org/opds/</atom:id>
  <atom:title>SciELO Books</atom:title>
  <atom:updated>2026-08-06T12:59:34Z</atom:updated>
  <atom:author>
    <atom:name>SciELO Books</atom:name>
    <atom:uri>http://books.scielo.org</atom:uri>
  </atom:author>
  <atom:link href="/opds/"
    type="application/atom+xml;profile=opds-catalog;kind=navigation"
    rel="start"/>
  <atom:entry>
    <atom:title>New Releases</atom:title>
    <atom:id>http://books.scielo.org/opds/new</atom:id>
    <atom:link href="/opds/new"
      type="application/atom+xml;profile=opds-catalog;kind=acquisition"
      rel="http://opds-spec.org/sort/new"/>
  </atom:entry>
  <atom:entry>
    <atom:title>Publishers</atom:title>
    <atom:id>http://books.scielo.org/opds/publisher</atom:id>
    <atom:link href="/opds/publisher"
      type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  </atom:entry>
  <atom:entry>
    <atom:title>Alphabetical</atom:title>
    <atom:id>http://books.scielo.org/opds/alpha</atom:id>
    <atom:link href="/opds/alpha"
      type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  </atom:entry>
</atom:feed>
''';

/// An acquisition feed with Atom as the default namespace and Dublin Core for
/// the publisher — the other shape OPDS servers commonly emit.
const _acquisitionFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:dcterms="http://purl.org/dc/terms/">
  <title>Novidades</title>
  <entry>
    <id>urn:uuid:book-1</id>
    <title>Cidadania no Brasil</title>
    <author><name>Carvalho, José Murilo de</name></author>
    <summary>Um ensaio sobre cidadania.</summary>
    <dcterms:publisher>EDUFBA</dcterms:publisher>
    <rights>CC-BY-NC-SA</rights>
    <link rel="http://opds-spec.org/acquisition"
          href="/opds/book-1.epub" type="application/epub+zip"/>
    <link rel="http://opds-spec.org/image"
          href="/opds/book-1.jpg" type="image/jpeg"/>
    <link rel="alternate" href="https://books.scielo.org/id/abc"
          type="text/html"/>
  </entry>
</feed>
''';

void main() {
  group('the real SciELO Books catalog root', () {
    test('reads its three sections and no books', () async {
      final feed = await _serviceServing(_scieloRoot).loadFeed();

      expect(feed.title, 'SciELO Books');
      expect(feed.books, isEmpty);
      expect(feed.sections.map((section) => section.title), [
        'New Releases',
        'Publishers',
        'Alphabetical',
      ]);
    });

    test('resolves section links against the catalog host', () async {
      final feed = await _serviceServing(_scieloRoot).loadFeed();

      expect(
        feed.sections.first.uri.toString(),
        'https://books.scielo.org/opds/new',
      );
    });

    test('reads one feed and nothing else', () async {
      final adapter = _CannedAdapter({'/opds/': _scieloRoot});

      await _serviceWith(adapter).loadFeed();

      // The sections are the reader's to open. Following them here is what
      // made the old crawl return an arbitrary slice of a large catalog while
      // looking like the whole thing.
      expect(adapter.requested, ['https://books.scielo.org/opds/']);
    });
  });

  group('ScieloOpdsService.loadFeed', () {
    test('reads a default-namespace acquisition feed', () async {
      final feed = await _serviceServing(_acquisitionFeed).loadFeed();

      expect(feed.title, 'Novidades');
      expect(feed.sections, isEmpty);
      final book = feed.books.single;
      expect(book.title, 'Cidadania no Brasil');
      expect(book.author, 'Carvalho, José Murilo de');
      expect(book.publisher, 'EDUFBA');
      expect(
        book.epubUrl.toString(),
        'https://books.scielo.org/opds/book-1.epub',
      );
      expect(book.pageUrl.toString(), 'https://books.scielo.org/id/abc');
      expect(
        book.coverUrl.toString(),
        'https://books.scielo.org/opds/book-1.jpg',
      );
    });

    test('reads an acquisition feed that binds Atom to a prefix', () async {
      final feed = await _serviceServing('''
<atom:feed xmlns:atom="http://www.w3.org/2005/Atom">
  <atom:title>Novidades</atom:title>
  <atom:entry>
    <atom:id>urn:uuid:book-1</atom:id>
    <atom:title>Cidadania no Brasil</atom:title>
    <atom:author><atom:name>Carvalho, José Murilo de</atom:name></atom:author>
    <atom:link rel="http://opds-spec.org/acquisition"
               href="/opds/book-1.epub" type="application/epub+zip"/>
  </atom:entry>
</atom:feed>
''').loadFeed();

      expect(feed.books.single.title, 'Cidadania no Brasil');
      expect(feed.books.single.author, 'Carvalho, José Murilo de');
    });

    test('exposes the next page without fetching it', () async {
      final adapter = _CannedAdapter({
        '/opds/new': '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Novidades</title>
  <link rel="next" href="/opds/new?page=2"/>
  <entry>
    <id>book-1</id><title>Primeiro</title>
    <link rel="http://opds-spec.org/acquisition"
          href="/opds/book-1.epub" type="application/epub+zip"/>
  </entry>
</feed>
''',
      });

      final feed = await _serviceWith(
        adapter,
      ).loadFeed(Uri.parse('https://books.scielo.org/opds/new'));

      expect(feed.next.toString(), 'https://books.scielo.org/opds/new?page=2');
      expect(adapter.requested, hasLength(1));
    });

    test('reports no next page on the last one', () async {
      final feed = await _serviceServing(_acquisitionFeed).loadFeed();

      expect(feed.next, isNull);
    });

    test('reads a feed holding both sections and books', () async {
      final feed = await _serviceServing('''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Misto</title>
  <entry>
    <id>nav</id><title>Mais uma seção</title>
    <link href="/opds/more" type="application/atom+xml;kind=navigation"/>
  </entry>
  <entry>
    <id>book-1</id><title>Um livro</title>
    <link rel="http://opds-spec.org/acquisition"
          href="/opds/book-1.epub" type="application/epub+zip"/>
  </entry>
</feed>
''').loadFeed();

      expect(feed.sections.single.title, 'Mais uma seção');
      expect(feed.books.single.title, 'Um livro');
      expect(feed.isEmpty, isFalse);
    });

    test('reports an empty feed as empty', () async {
      final feed = await _serviceServing('''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>Vazio</title></feed>
''').loadFeed();

      expect(feed.isEmpty, isTrue);
    });

    test('rejects an empty body', () async {
      expect(
        () => _serviceServing('   ').loadFeed(),
        throwsA(isA<FormatException>()),
      );
    });

    test('reports a failure to reach the feed', () async {
      await expectLater(
        _serviceWith(_CannedAdapter(const {})).loadFeed(),
        throwsA(isA<DioException>()),
      );
    });
  });
}
