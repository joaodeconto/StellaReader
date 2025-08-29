import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/gutenberg_book.dart';

class GutendexService {
  final Dio _dio;
  GutendexService([Dio? dio]) : _dio = dio ?? Dio();

  Future<List<GutenbergBook>> search({String? query, int page = 1}) async {
    final params = <String, dynamic>{'page': page.toString()};
    if (query != null && query.trim().isNotEmpty) params['search'] = query.trim();
    final resp = await _dio.get(
      'https://gutendex.com/books/',
      queryParameters: params,
      options: Options(responseType: ResponseType.json),
    );
    final data = resp.data is Map ? resp.data as Map<String, dynamic> : jsonDecode(resp.data as String) as Map<String, dynamic>;
    final results = (data['results'] as List).cast<Map>().cast<Map<String, dynamic>>();
    return results.map(GutenbergBook.fromJson).toList();
  }
}

