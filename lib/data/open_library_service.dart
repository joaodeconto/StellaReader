import 'package:dio/dio.dart';

class OpenLibraryBook {
  const OpenLibraryBook({
    required this.workKey,
    required this.title,
    required this.author,
    required this.firstPublishYear,
    required this.coverId,
    required this.archiveIds,
    required this.hasFullText,
  });

  factory OpenLibraryBook.fromJson(Map<String, dynamic> json) {
    final authors = json['author_name'];
    final archiveIds = json['ia'];
    return OpenLibraryBook(
      workKey: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled',
      author: authors is List && authors.isNotEmpty
          ? authors.first.toString()
          : 'Unknown author',
      firstPublishYear: json['first_publish_year']?.toString(),
      coverId: json['cover_i'] is int ? json['cover_i'] as int : null,
      archiveIds: archiveIds is List
          ? archiveIds.map((value) => value.toString()).toList()
          : const [],
      hasFullText: json['has_fulltext'] == true || json['public_scan_b'] == true,
    );
  }

  final String workKey;
  final String title;
  final String author;
  final String? firstPublishYear;
  final int? coverId;
  final List<String> archiveIds;
  final bool hasFullText;

  String? get coverUrl => coverId == null
      ? null
      : 'https://covers.openlibrary.org/b/id/$coverId-M.jpg';

  bool get mayBeDownloadable => hasFullText && archiveIds.isNotEmpty;
}

class OpenLibraryDownload {
  const OpenLibraryDownload({required this.url, required this.extension});

  final String url;
  final String extension;
}

class OpenLibraryService {
  OpenLibraryService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 25),
                followRedirects: true,
                headers: const {'User-Agent': 'StellaReader/0.3.0'},
              ),
            );

  final Dio _dio;

  Future<List<OpenLibraryBook>> search(
    String query, {
    int limit = 30,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://openlibrary.org/search.json',
      queryParameters: {
        'q': query,
        'limit': limit,
        'fields': 'key,title,author_name,first_publish_year,cover_i,ia,has_fulltext,public_scan_b',
      },
    );

    final docs = response.data?['docs'];
    if (docs is! List) return const [];
    return docs
        .whereType<Map<String, dynamic>>()
        .map(OpenLibraryBook.fromJson)
        .where((book) => book.workKey.isNotEmpty)
        .toList();
  }

  Future<OpenLibraryDownload?> resolveDownload(OpenLibraryBook book) async {
    for (final archiveId in book.archiveIds.take(4)) {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://archive.org/metadata/$archiveId',
      );
      final files = response.data?['files'];
      if (files is! List) continue;

      final candidates = files
          .whereType<Map<String, dynamic>>()
          .map((file) => file['name']?.toString())
          .whereType<String>()
          .where((name) {
            final lower = name.toLowerCase();
            return lower.endsWith('.epub') || lower.endsWith('.pdf');
          })
          .toList();

      String? selected;
      for (final name in candidates) {
        if (name.toLowerCase().endsWith('.epub')) {
          selected = name;
          break;
        }
      }
      selected ??= candidates.cast<String?>().firstOrNull;
      if (selected == null) continue;

      final encodedName = selected
          .split('/')
          .map(Uri.encodeComponent)
          .join('/');
      return OpenLibraryDownload(
        url: 'https://archive.org/download/$archiveId/$encodedName',
        extension: selected.toLowerCase().endsWith('.pdf') ? '.pdf' : '.epub',
      );
    }
    return null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
