import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'ui/library_screen.dart';
import 'ui/reader_screen.dart';
import 'domain/book.dart';
import 'ui/gutenberg_screen.dart';

void main() => runApp(const ProviderScope(child: App()));

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
                return ReaderScreen(book: book);
              },
            ),
            GoRoute(
              path: 'gutenberg',
              builder: (_, __) => const GutenbergScreen(),
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Lê-Livros',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
