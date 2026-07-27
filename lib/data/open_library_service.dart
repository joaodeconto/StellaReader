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
                headers: const {'User-Agent': 'StellaReader/0.3.3'},
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
    for (final archiveId in book.archiveIds.take(8)) {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://archive.org/metadata/$archiveId',
      );
      final metadata = response.data?['metadata'];
      if (metadata is Map<String, dynamic> && _isRestricted(metadata)) continue;

      final files = response.data?['files'];
      if (files is! List) continue;

      final candidates = files
          .whereType<Map<String, dynamic>>()
          .map(_BookCandidate.fromJson)
          .whereType<_BookCandidate>()
          .where((file) => file.isUsable)
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      for (final candidate in candidates.take(6)) {
        final encodedName = candidate.name
            .split('/')
            .map(Uri.encodeComponent)
            .join('/');
        final url = 'https://archive.org/download/$archiveId/$encodedName';
        if (!await _isPubliclyAccessible(url)) continue;

        return OpenLibraryDownload(
          url: url,
          extension: candidate.extension,
          sizeBytes: candidate.sizeBytes,
        );
      }
    }
    return null;
  }

  bool _isRestricted(Map<String, dynamic> metadata) {
    final access = [
      metadata['access-restricted-item'],
      metadata['accessrestricteditem'],
      metadata['is_dark'],
    ].map((value) => value?.toString().toLowerCase()).toList();
    return access.any((value) => value == 'true' || value == '1');
  }

  Future<bool> _isPubliclyAccessible(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {
            'Range': 'bytes=0-0',
            'User-Agent': 'StellaReader/0.3.3',
          },
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      return response.statusCode == 200 || response.statusCode == 206;
    } on DioException {
      return false;
    }
  }
}

class _BookCandidate {
  const _BookCandidate({
    required this.name,
    required this.sizeBytes,
    required this.format,
    required this.extension,
  });

  static _BookCandidate? fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString();
    if (name == null) return null;
    final lower = name.toLowerCase();
    final extension = lower.endsWith('.epub')
        ? '.epub'
        : lower.endsWith('.pdf')
            ? '.pdf'
            : null;
    if (extension == null) return null;

    final rawSize = json['size'];
    final size = rawSize is int
        ? rawSize
        : int.tryParse(rawSize?.toString() ?? '') ?? 0;

    return _BookCandidate(
      name: name,
      sizeBytes: size,
      format: json['format']?.toString().toLowerCase() ?? '',
      extension: extension,
    );
  }

  final String name;
  final int sizeBytes;
  final String format;
  final String extension;

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
      'single_page',
      'scandata',
    ];
    if (rejectedTokens.any(lower.contains)) return false;
    if (sizeBytes < 100 * 1024) return false;
    return true;
  }

  int get score {
    var value = 100;
    final lower = name.toLowerCase();
    if (extension == '.epub') value += 250;
    if (format.contains('text pdf')) value += 120;
    if (format == 'pdf') value += 50;
    if (lower.contains('text')) value += 30;
    if (lower.contains('bw')) value -= 10;
    if (lower.contains('color')) value += 5;
    if (sizeBytes > 0) {
      value -= (sizeBytes ~/ (20 * 1024 * 1024)).clamp(0, 80);
    }
    return value;
  }
}