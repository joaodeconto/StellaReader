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
  const OpenLibraryDownload({
    required this.url,
    required this.extension,
    required this.sizeBytes,
  });

  final String url;
  final String extension;
  final int sizeBytes;
}

class OpenLibraryService {
  OpenLibraryService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 25),
                followRedirects: true,
                headers: const {'User-Agent': 'StellaReader/0.3.1'},
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
    for (final archiveId in book.archiveIds.take(6)) {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://archive.org/metadata/$archiveId',
      );
      final files = response.data?['files'];
      if (files is! List) continue;

      final candidates = files
          .whereType<Map<String, dynamic>>()
          .map(_DownloadCandidate.fromJson)
          .whereType<_DownloadCandidate>()
          .where((file) => file.isUsable)
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      if (candidates.isEmpty) continue;
      final selected = candidates.first;
      final encodedName = selected.name
          .split('/')
          .map(Uri.encodeComponent)
          .join('/');

      return OpenLibraryDownload(
        url: 'https://archive.org/download/$archiveId/$encodedName',
        extension: selected.extension,
        sizeBytes: selected.sizeBytes,
      );
    }
    return null;
  }
}

class _DownloadCandidate {
  const _DownloadCandidate({
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.format,
  });

  static _DownloadCandidate? fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString();
    if (name == null || name.isEmpty) return null;
    final lower = name.toLowerCase();
    final extension = lower.endsWith('.pdf')
        ? '.pdf'
        : lower.endsWith('.epub')
            ? '.epub'
            : null;
    if (extension == null) return null;

    final rawSize = json['size'];
    final size = rawSize is int
        ? rawSize
        : int.tryParse(rawSize?.toString() ?? '') ?? 0;

    return _DownloadCandidate(
      name: name,
      extension: extension,
      sizeBytes: size,
      format: json['format']?.toString().toLowerCase() ?? '',
    );
  }

  final String name;
  final String extension;
  final int sizeBytes;
  final String format;

  bool get isUsable {
    final lower = name.toLowerCase();
    const rejectedTokens = [
      'meta',
      'metadata',
      'readme',
      'notice',
      'disclaimer',
      'restricted',
      'encrypted',
      'preview',
      'sample',
      'placeholder',
    ];
    if (rejectedTokens.any(lower.contains)) return false;
    if (extension == '.epub' && sizeBytes < 80 * 1024) return false;
    if (extension == '.pdf' && sizeBytes < 120 * 1024) return false;
    return true;
  }

  int get score {
    var value = extension == '.epub' ? 200 : 160;
    if (format.contains('epub')) value += 30;
    if (format.contains('pdf')) value += 20;
    if (name.toLowerCase().contains('text')) value += 10;
    if (sizeBytes > 0) value += (sizeBytes ~/ (1024 * 1024)).clamp(0, 80);
    return value;
  }
}
