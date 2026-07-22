import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/import_service.dart';
import '../data/opds_service.dart';
import '../domain/book.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.onImported});

  final ValueChanged<Book> onImported;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _service = OpdsService();
  final _dio = Dio();
  bool _loading = true;
  String? _error;
  List<CatalogBook> _books = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.standardEbooks(),
        _service.projectGutenberg(),
      ]);
      if (!mounted) return;
      setState(() {
        _books = [...results[0], ...results[1]];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _download(CatalogBook item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final temp = await getTemporaryDirectory();
      final uri = Uri.parse(item.downloadUrl);
      final extension = p.extension(uri.path).toLowerCase() == '.pdf'
          ? '.pdf'
          : '.epub';
      final safeTitle = item.title.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
      final tempFile = File(p.join(temp.path, '$safeTitle$extension'));
      await _dio.download(item.downloadUrl, tempFile.path);
      final imported = await ImportService().importFile(tempFile);
      await tempFile.delete().catchError((_) => tempFile);
      widget.onImported(imported);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('${item.title} added to library')),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Download failed: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load catalogs.\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _books.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final book = _books[index];
          return ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(book.title),
            subtitle: Text('${book.author} · ${book.source}'),
            trailing: IconButton(
              icon: const Icon(Icons.download_outlined),
              onPressed: () => _download(book),
            ),
          );
        },
      ),
    );
  }
}
