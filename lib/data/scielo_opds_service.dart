import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../domain/catalog_book.dart';

class ScieloOpdsService {
  ScieloOpdsService({Dio? dio}) : _dio = dio ?? Dio();

  static final Uri catalogUri = Uri.parse(
    'https://opds.livros.scielo.org/opds/',
  );

  final Dio _dio;

  Future<List<CatalogBook>> loadEpubs() async {
    final response = await _dio.getUri<String>(
      catalogUri,
      options: Options(
        responseType: ResponseType.plain,
        headers: const {
          'Accept': 'application/atom+xml, application/xml;q=0.9',
          'User-Agent': 'StellaReader/0.4.1',
        },
      ),
    );

    final body = response.data;
    if (body == null || body.trim().isEmpty) {
      throw const FormatException(
        'O catálogo SciELO retornou uma resposta vazia.',
      );
    }

    final document = XmlDocument.parse(body);
    return document
        .findAllElements('entry')
        .map(_parseEntry)
        .whereType<CatalogBook>()
        .where((book) => book.epubUrl != null)
        .toList(growable: false);
  }

  CatalogBook? _parseEntry(XmlElement entry) {
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
        .findAllElements('author')
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

    for (final link in entry.findAllElements('link')) {
      final href = link.getAttribute('href');
      if (href == null || href.isEmpty) continue;
      final uri = catalogUri.resolve(href);
      final type = (link.getAttribute('type') ?? '').toLowerCase();
      final rel = (link.getAttribute('rel') ?? '').toLowerCase();

      if (type.contains('application/epub+zip')) {
        epubUrl = uri;
      } else if (rel.contains('image') || type.startsWith('image/')) {
        coverUrl ??= uri;
      } else if (rel == 'alternate' || type.contains('text/html')) {
        pageUrl ??= uri;
      }
    }

    return CatalogBook(
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
    );
  }

  void close() => _dio.close(force: true);
}
