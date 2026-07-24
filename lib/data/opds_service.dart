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

class CatalogLoadException implements Exception {
  const CatalogLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OpdsService {
  OpdsService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
                followRedirects: true,
                maxRedirects: 5,
                responseType: ResponseType.plain,
                headers: const {
                  'Accept':
                      'application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.1',
                  'User-Agent': 'StellaReader/0.2.2',
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
    try {
      final response = await _dio.get<String>(url);
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        throw CatalogLoadException('$source returned HTTP $statusCode.');
      }

      final body = response.data;
      if (body == null || body.trim().isEmpty) {
        throw CatalogLoadException('$source returned an empty response.');
      }

      final baseUri = Uri.parse(url);
      final document = XmlDocument.parse(body);
      final entries = document.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'entry');

      final books = entries.map((entry) {
        final title = _childElements(entry, 'title').firstOrNull?.innerText.trim() ??
            'Untitled';
        final author = _childElements(entry, 'author')
                .expand((node) => _childElements(node, 'name'))
                .firstOrNull
                ?.innerText
                .trim() ??
            'Unknown author';

        final links = _childElements(entry, 'link');
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

      if (books.isEmpty) {
        throw CatalogLoadException(
          '$source responded, but no downloadable books were found in the OPDS feed.',
        );
      }

      return books;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final detail = switch (error.type) {
        DioExceptionType.connectionTimeout => 'connection timed out',
        DioExceptionType.sendTimeout => 'request timed out',
        DioExceptionType.receiveTimeout => 'response timed out',
        DioExceptionType.badCertificate => 'TLS certificate was rejected',
        DioExceptionType.badResponse => 'returned HTTP ${status ?? 'error'}',
        DioExceptionType.cancel => 'request was cancelled',
        DioExceptionType.connectionError => 'network connection failed',
        DioExceptionType.unknown => error.error?.toString() ?? error.message ?? 'unknown network error',
      };
      throw CatalogLoadException('$source: $detail.');
    } on XmlParserException catch (error) {
      throw CatalogLoadException('$source returned invalid XML: ${error.message}');
    }
  }

  Iterable<XmlElement> _childElements(XmlElement parent, String localName) {
    return parent.children
        .whereType<XmlElement>()
        .where((element) => element.name.local == localName);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
