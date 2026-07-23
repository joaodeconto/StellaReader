import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/import_service.dart';
import 'domain/book.dart';
import 'settings/app_settings.dart';
import 'ui/epub_reader_screen.dart';
import 'ui/library_screen.dart';
import 'ui/reader_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.load();
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const LibraryScreen(),
          routes: [
            GoRoute(
              path: 'reader',
              builder: (_, state) {
                final book = state.extra as Book;
                return ImportService.isEpub(book)
                    ? EpubReaderScreen(book: book)
                    : ReaderScreen(book: book);
              },
            ),
          ],
        ),
      ],
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (context, themeMode, _) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'StellaReader',
          themeMode: themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          routerConfig: router,
        );
      },
    );
  }
}
