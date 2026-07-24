import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class OpenLibraryTestScreen extends StatefulWidget {
  const OpenLibraryTestScreen({super.key});

  @override
  State<OpenLibraryTestScreen> createState() => _OpenLibraryTestScreenState();
}

class _OpenLibraryTestScreenState extends State<OpenLibraryTestScreen> {
  final _controller = TextEditingController(text: 'Alice in Wonderland');
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'User-Agent': 'StellaReader/0.2.1'},
    ),
  );

  bool _loading = false;
  List<_OpenLibraryBook> _books = const [];
  String? _status;

  @override
  void dispose() {
    _controller.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _books = const [];
      _status = 'Connecting to openlibrary.org…';
    });

    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://openlibrary.org/search.json',
        queryParameters: {'q': query, 'limit': 15},
      );
      stopwatch.stop();

      final docs = response.data?['docs'];
      final books = docs is List
          ? docs.whereType<Map<String, dynamic>>().map(_OpenLibraryBook.fromJson).toList()
          : <_OpenLibraryBook>[];

      if (!mounted) return;
      setState(() {
        _books = books;
        _status = 'HTTP ${response.statusCode} · ${stopwatch.elapsedMilliseconds} ms · ${books.length} results';
      });
    } on DioException catch (error) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _status = 'Dio ${error.type.name} after ${stopwatch.elapsedMilliseconds} ms\n'
            'Status: ${error.response?.statusCode ?? 'none'}\n'
            'Message: ${error.message}\n'
            'Underlying: ${error.error ?? 'none'}';
      });
    } catch (error) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _status = '${error.runtimeType} after ${stopwatch.elapsedMilliseconds} ms\n$error';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Open Library test')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    labelText: 'Search Open Library',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _search,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.public),
                  label: const Text('Test another website'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(_status!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _books.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'This calls the Open Library JSON API directly. A successful search proves Android, DNS, TLS and Dio are working independently of the OPDS catalogs.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _books.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final book = _books[index];
                      return ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(book.title),
                        subtitle: Text(
                          [book.author, book.firstPublishYear]
                              .whereType<String>()
                              .where((value) => value.isNotEmpty)
                              .join(' · '),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _OpenLibraryBook {
  const _OpenLibraryBook({required this.title, this.author, this.firstPublishYear});

  factory _OpenLibraryBook.fromJson(Map<String, dynamic> json) {
    final authorNames = json['author_name'];
    final firstAuthor = authorNames is List && authorNames.isNotEmpty
        ? authorNames.first.toString()
        : null;
    return _OpenLibraryBook(
      title: json['title']?.toString() ?? 'Untitled',
      author: firstAuthor,
      firstPublishYear: json['first_publish_year']?.toString(),
    );
  }

  final String title;
  final String? author;
  final String? firstPublishYear;
}
