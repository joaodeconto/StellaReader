import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stellareader/data/scielo_opds_service.dart';

/// Serves a canned body so the parser can be exercised without the network.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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

ScieloOpdsService _serviceServing(String body) {
  final dio = Dio()..httpClientAdapter = _CannedAdapter(body);
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

    test('finds no books in a navigation feed', () async {
      final books = await _serviceServing(_navigationFeed).loadEpubs();

      expect(books, isEmpty);
    });

    test('rejects an empty body', () async {
      expect(
        () => _serviceServing('   ').loadEpubs(),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
