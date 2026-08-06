import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellareader/data/scielo_opds_service.dart';

/// Serves canned bodies so the parser can be exercised without the network.
///
/// Records every URL asked for, which is how the tests check that the crawl
/// stays inside its budget instead of chasing a catalog forever.
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
    final url = options.uri.toString();
    requested.add(url);
    final body = bodies[url] ?? bodies[options.uri.path];
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

/// Serves one body for every request, whatever the URL.
class _AlwaysAdapter extends _CannedAdapter {
  _AlwaysAdapter(this.only) : super(const {});

  final String only;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri.toString());
    return ResponseBody.fromString(only, 200);
  }
}

ScieloOpdsService _serviceServing(String body) =>
    _serviceWith(_AlwaysAdapter(body));

ScieloOpdsService _serviceWith(_CannedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ScieloOpdsService(dio: dio);
}

/// An acquisition feed in the shape OPDS servers actually emit: Atom as the
/// default namespace, Dublin Core for the publisher.
const _acquisitionFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:dcterms="http://purl.org/dc/terms/">
  <id>https://opds.livros.scielo.org/opds/</id>
  <title>SciELO Livros</title>
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

/// The same feed, but with Atom bound to a prefix instead of being the
/// default namespace. Both forms are valid XML and mean the same thing.
const _prefixedAcquisitionFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<atom:feed xmlns:atom="http://www.w3.org/2005/Atom">
  <atom:entry>
    <atom:id>urn:uuid:book-1</atom:id>
    <atom:title>Cidadania no Brasil</atom:title>
    <atom:author><atom:name>Carvalho, José Murilo de</atom:name></atom:author>
    <atom:link rel="http://opds-spec.org/acquisition"
               href="/opds/book-1.epub" type="application/epub+zip"/>
  </atom:entry>
</atom:feed>
''';

/// What the root of an OPDS server usually is: entries that point at other
/// feeds, with no book to download anywhere in sight.
const _navigationFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>https://opds.livros.scielo.org/opds/</id>
  <title>SciELO Livros</title>
  <entry>
    <id>urn:uuid:nav-new</id>
    <title>Novidades</title>
    <link rel="http://opds-spec.org/sort/new" href="/opds/new"
          type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  </entry>
  <entry>
    <id>urn:uuid:nav-publishers</id>
    <title>Editoras</title>
    <link rel="subsection" href="/opds/publishers"
          type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  </entry>
</feed>
''';

/// A navigation root whose "Novidades" section holds the actual books.
const _navigationRoot = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>SciELO Livros</title>
  <entry>
    <id>urn:uuid:nav-new</id>
    <title>Novidades</title>
    <link rel="http://opds-spec.org/sort/new" href="/opds/new"
          type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  </entry>
</feed>
''';

String _bookFeed(String id, String title, {String? next}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Novidades</title>
  ${next == null ? '' : '<link rel="next" href="$next"/>'}
  <entry>
    <id>$id</id>
    <title>$title</title>
    <link rel="http://opds-spec.org/acquisition"
          href="/opds/$id.epub" type="application/epub+zip"/>
  </entry>
</feed>
''';

/// Two navigation feeds that point at each other.
String _loopFeed(String target) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Loop</title>
  <entry>
    <id>urn:uuid:$target</id>
    <title>Continua</title>
    <link rel="subsection" href="$target"
          type="application/atom+xml;profile=opds-catalog"/>
  </entry>
</feed>
''';

void main() {
  group('ScieloOpdsService.loadEpubs', () {
    test('reads a default-namespace acquisition feed', () async {
      final books = await _serviceServing(_acquisitionFeed).loadEpubs();

      expect(books, hasLength(1));
      final book = books.single;
      expect(book.title, 'Cidadania no Brasil');
      expect(book.author, 'Carvalho, José Murilo de');
      expect(
        book.epubUrl.toString(),
        'https://opds.livros.scielo.org/opds/book-1.epub',
      );
      expect(book.pageUrl.toString(), 'https://books.scielo.org/id/abc');
    });

    test('reads an acquisition feed that binds Atom to a prefix', () async {
      final books = await _serviceServing(_prefixedAcquisitionFeed).loadEpubs();

      expect(books, hasLength(1));
      expect(books.single.title, 'Cidadania no Brasil');
    });

    test('gives up on a catalog that is all navigation, no books', () async {
      final books = await _serviceServing(_navigationFeed).loadEpubs();

      expect(books, isEmpty);
    });

    test('keeps the books it found when a section is broken', () async {
      final adapter = _CannedAdapter({
        '/opds/': '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>nav-ok</id><title>Funciona</title>
    <link href="/opds/ok" type="application/atom+xml;kind=acquisition"/>
  </entry>
  <entry>
    <id>nav-gone</id><title>Sumiu</title>
    <link href="/opds/gone" type="application/atom+xml;kind=acquisition"/>
  </entry>
</feed>
''',
        '/opds/ok': _bookFeed('book-1', 'Cidadania no Brasil'),
        // '/opds/gone' is unmapped, so the adapter answers 404.
      });

      final books = await _serviceWith(adapter).loadEpubs();

      expect(books.map((book) => book.title), ['Cidadania no Brasil']);
    });

    test('reports a failure to reach the catalog root', () async {
      final adapter = _CannedAdapter(const {});

      await expectLater(
        _serviceWith(adapter).loadEpubs(),
        throwsA(isA<DioException>()),
      );
    });

    test('rejects an empty body', () async {
      expect(
        () => _serviceServing('   ').loadEpubs(),
        throwsA(isA<FormatException>()),
      );
    });

    test('follows a navigation root down to the books', () async {
      final adapter = _CannedAdapter({
        '/opds/': _navigationRoot,
        '/opds/new': _bookFeed('book-1', 'Cidadania no Brasil'),
      });

      final books = await _serviceWith(adapter).loadEpubs();

      expect(books.map((book) => book.title), ['Cidadania no Brasil']);
      expect(adapter.requested, hasLength(2));
    });

    test('follows pagination within an acquisition feed', () async {
      final adapter = _CannedAdapter({
        '/opds/': _bookFeed('book-1', 'Primeiro', next: '/opds/page-2'),
        '/opds/page-2': _bookFeed('book-2', 'Segundo'),
      });

      final books = await _serviceWith(adapter).loadEpubs();

      expect(books.map((book) => book.title), ['Primeiro', 'Segundo']);
    });

    test('stops instead of looping when feeds point at each other', () async {
      final adapter = _CannedAdapter({
        '/opds/': _loopFeed('/opds/b'),
        '/opds/b': _loopFeed('/opds/'),
      });

      final books = await _serviceWith(adapter).loadEpubs();

      expect(books, isEmpty);
      expect(adapter.requested, hasLength(2));
    });

    test('keeps one copy of a book listed in two sections', () async {
      final adapter = _CannedAdapter({
        '/opds/': '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>nav-a</id><title>A</title>
    <link href="/opds/a" type="application/atom+xml;kind=acquisition"/>
  </entry>
  <entry>
    <id>nav-b</id><title>B</title>
    <link href="/opds/b" type="application/atom+xml;kind=acquisition"/>
  </entry>
</feed>
''',
        '/opds/a': _bookFeed('book-1', 'Cidadania no Brasil'),
        '/opds/b': _bookFeed('book-1', 'Cidadania no Brasil'),
      });

      final books = await _serviceWith(adapter).loadEpubs();

      expect(books, hasLength(1));
    });
  });
}
