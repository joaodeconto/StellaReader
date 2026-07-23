import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

class CatalogBook {
  const CatalogBook({
    required this.title,
    required this.author,
    required this.downloadUrl,
    required this.source,
  });

  final String title;
  final String author;
  final String downloadUrl;
  final String source;
}

class OpdsService {
  OpdsService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
                headers: const {
                  'Accept':
                      'application/atom+xml, application/xml;q=0.9, text/xml;q=0.8',
                  'User-Agent': 'StellaReader/0.2.1',
                },
              ),
            );

  final Dio _dio;

  static const standardEbooksUrl = 'https://standardebooks.org/opds/all';
  static const gutenbergUrl =
      'https://www.gutenberg.org/ebooks/search.opds/?sort_order=downloads';

  Future<List<CatalogBook>> standardEbooks() =>
      _load(standardEbooksUrl, 'Standard Ebooks');

  Future<List<CatalogBook>> projectGutenberg() =>
      _load(gutenbergUrl, 'Project Gutenberg');

  Future<List<CatalogBook>> _load(String url, String source) async {
    final response = await _dio.get<String>(url);
    final body = response.data;
    if (body == null || body.trim().isEmpty) return const [];

    final baseUri = Uri.parse(url);
    final document = XmlDocument.parse(body);
    final entries = document.findAllElements('entry');

    return entries.map((entry) {
      final title = entry.findElements('title').firstOrNull?.innerText.trim() ??
          'Untitled';
      final author = entry
              .findElements('author')
              .expand((node) => node.findElements('name'))
              .firstOrNull
              ?.innerText
              .trim() ??
          'Unknown author';

      final links = entry.findElements('link');
      final acquisition = links.firstWhere(
        (link) {
          final type = (link.getAttribute('type') ?? '').toLowerCase();
          final rel = (link.getAttribute('rel') ?? '').toLowerCase();
          final href = link.getAttribute('href') ?? '';
          return href.isNotEmpty &&
              (type.contains('epub') ||
                  type.contains('pdf') ||
                  rel.contains('acquisition'));
        },
        orElse: () => XmlElement(XmlName('link')),
      );

      final href = acquisition.getAttribute('href') ?? '';
      final resolvedUrl = href.isEmpty ? '' : baseUri.resolve(href).toString();

      return CatalogBook(
        title: title,
        author: author,
        downloadUrl: resolvedUrl,
        source: source,
      );
    }).where((book) => book.downloadUrl.isNotEmpty).toList();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
