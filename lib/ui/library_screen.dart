import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/book_repository.dart';
import '../data/import_service.dart';
import '../domain/book.dart';
import '../settings/app_settings.dart';

final booksProvider = FutureProvider.autoDispose<List<Book>>((ref) async {
  return BookRepository().all();
});

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  Future<void> _import() async {
    try {
      final book = await ImportService().pickAndImport();
      if (book == null || !mounted) return;
      ref.invalidate(booksProvider);
      context.push('/reader', extra: book);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    }
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: AppSettings.themeMode,
        builder: (context, selectedMode, _) => AlertDialog(
          title: const Text('Settings'),
          content: RadioGroup<ThemeMode>(
            groupValue: selectedMode,
            onChanged: (mode) {
              if (mode != null) AppSettings.setThemeMode(mode);
            },
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ThemeMode>(title: Text('Use device setting'), value: ThemeMode.system),
                RadioListTile<ThemeMode>(title: Text('Light'), value: ThemeMode.light),
                RadioListTile<ThemeMode>(title: Text('Dark'), value: ThemeMode.dark),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        ),
      ),
    );
  }

  Future<void> _showAbout() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'StellaReader',
      applicationVersion: '${info.version} (build ${info.buildNumber})',
      applicationIcon: const Icon(Icons.auto_stories, size: 48),
      children: const [
        Text('Leitor Android de PDF e EPUB com biblioteca local e catálogo brasileiro EPUB.'),
      ],
    );
  }

  Future<void> _handleMenu(String value) async {
    switch (value) {
      case 'discover':
        context.push('/discover-brasil');
      case 'settings':
        await _showSettings();
      case 'about':
        await _showAbout();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Scaffold(
        body: Center(child: Text('StellaReader is currently optimized for Android.')),
      );
    }

    final books = ref.watch(booksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'EPUBs do Brasil',
            onPressed: () => context.push('/discover-brasil'),
            icon: const Icon(Icons.travel_explore),
          ),
          IconButton(
            tooltip: 'Import PDF or EPUB',
            onPressed: _import,
            icon: const Icon(Icons.file_open_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'discover', child: Text('EPUBs do Brasil')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'about', child: Text('About')),
            ],
          ),
        ],
      ),
      body: books.when(
        data: (items) => items.isEmpty
            ? _EmptyLibrary(
                onImport: _import,
                onDiscover: () => context.push('/discover-brasil'),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.refresh(booksProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final book = items[index];
                    final epub = ImportService.isEpub(book);
                    return ListTile(
                      leading: Icon(epub ? Icons.auto_stories : Icons.picture_as_pdf, size: 32),
                      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(epub ? 'EPUB · tap to continue reading' : 'PDF · last page ${book.lastPage}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/reader', extra: book),
                    );
                  },
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: FilledButton.icon(
            onPressed: () => ref.invalidate(booksProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _import,
        icon: const Icon(Icons.add),
        label: const Text('Add book'),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport, required this.onDiscover});

  final VoidCallback onImport;
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text('Your books belong here', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            const Text('Importe um PDF ou EPUB, ou descubra EPUBs brasileiros gratuitos.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: onImport, icon: const Icon(Icons.file_open_outlined), label: const Text('Choose a book')),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: onDiscover, icon: const Icon(Icons.travel_explore), label: const Text('EPUBs do Brasil')),
          ],
        ),
      ),
    );
  }
}
