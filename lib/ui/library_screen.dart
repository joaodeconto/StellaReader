import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/book_repository.dart';
import '../data/import_service.dart';
import '../domain/book.dart';
import '../settings/app_settings.dart';
import 'discover_screen.dart';

final booksProvider = FutureProvider.autoDispose<List<Book>>((ref) async {
  return BookRepository().all();
});

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _tab = 0;

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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Appearance', style: Theme.of(context).textTheme.titleSmall),
              RadioListTile<ThemeMode>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use device setting'),
                value: ThemeMode.system,
                groupValue: selectedMode,
                onChanged: (mode) {
                  if (mode != null) AppSettings.setThemeMode(mode);
                },
              ),
              RadioListTile<ThemeMode>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Light'),
                value: ThemeMode.light,
                groupValue: selectedMode,
                onChanged: (mode) {
                  if (mode != null) AppSettings.setThemeMode(mode);
                },
              ),
              RadioListTile<ThemeMode>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dark'),
                value: ThemeMode.dark,
                groupValue: selectedMode,
                onChanged: (mode) {
                  if (mode != null) AppSettings.setThemeMode(mode);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
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
        Text('A focused Android reader for local PDF and EPUB books, with public-domain catalog discovery.'),
      ],
    );
  }

  Future<void> _handleMenu(String value) async {
    switch (value) {
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
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'StellaReader is currently optimized for Android.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final books = ref.watch(booksProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Library' : 'Discover'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'App menu',
            onSelected: _handleMenu,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('About'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          books.when(
            data: (items) => items.isEmpty
                ? const Center(
                    child: Text('No books yet. Tap + to import PDF or EPUB.'),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final book = items[index];
                      final epub = ImportService.isEpub(book);
                      return ListTile(
                        leading: Icon(epub ? Icons.auto_stories : Icons.picture_as_pdf),
                        title: Text(book.title),
                        subtitle: Text(
                          epub
                              ? 'EPUB · reading position saved'
                              : 'PDF · last page ${book.lastPage}',
                        ),
                        onTap: () => context.push('/reader', extra: book),
                      );
                    },
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
          ),
          DiscoverScreen(
            onImported: (book) {
              ref.invalidate(booksProvider);
              context.push('/reader', extra: book);
            },
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              onPressed: _import,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
        ],
      ),
    );
  }
}
