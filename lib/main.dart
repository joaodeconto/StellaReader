import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'data/import_service.dart';
import 'data/share_intake.dart';
import 'domain/book.dart';
import 'domain/catalog_feed.dart';
import 'settings/app_settings.dart';
import 'ui/discover_brazil_screen.dart';
import 'ui/epub_reader_screen.dart';
import 'ui/library_screen.dart';
import 'ui/reader_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.load();
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  static const _shareFailed = 'Não foi possível abrir o arquivo compartilhado.';

  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _shareIntake = ShareIntake();
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;

  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const LibraryScreen(),
        routes: [
          GoRoute(
            path: 'discover-brasil',
            // The catalog is a tree, so this route is pushed once per level:
            // no section is the root, and each section carries the feed to
            // open next.
            builder: (_, state) =>
                DiscoverBrazilScreen(section: state.extra as CatalogSection?),
          ),
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

  @override
  void initState() {
    super.initState();
    // A shared book is pushed onto the router, so the first read waits until
    // the router has built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenForShares());
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    super.dispose();
  }

  /// Picks up books handed over by another app's share sheet.
  ///
  /// Two paths matter: the stream carries shares that arrive while
  /// StellaReader is already running, and `getInitialMedia` carries the one
  /// that launched it.
  Future<void> _listenForShares() async {
    if (!ShareIntake.isSupportedPlatform) return;

    _shareSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _receiveShared,
      onError: (_) => _report(_shareFailed),
    );

    try {
      await _receiveShared(
        await ReceiveSharingIntent.instance.getInitialMedia(),
      );
      // Without this Android hands the same files back on every later start.
      await ReceiveSharingIntent.instance.reset();
    } on Exception {
      _report(_shareFailed);
    }
  }

  Future<void> _receiveShared(List<SharedMediaFile> shared) async {
    if (shared.isEmpty) return;

    final result = await _shareIntake.receive(shared);
    if (!mounted) return;

    if (result.books.isNotEmpty) {
      ref.invalidate(booksProvider);
      // A share of several books opens the first one; the rest are waiting in
      // the library.
      _router.push('/reader', extra: result.books.first);
    }

    final message = _shareMessage(result);
    if (message != null) _report(message);
  }

  /// What to tell the user after a share, or null when opening the book says
  /// it all.
  String? _shareMessage(ShareImport result) {
    if (result.books.isEmpty) {
      return 'O StellaReader abre apenas arquivos PDF e EPUB.';
    }
    if (result.skipped > 0) {
      return 'Alguns arquivos foram ignorados: o StellaReader abre apenas '
          'PDF e EPUB.';
    }
    if (result.books.length > 1) {
      return '${result.books.length} livros adicionados à biblioteca.';
    }
    return null;
  }

  void _report(String message) {
    _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (context, themeMode, _) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'StellaReader',
          scaffoldMessengerKey: _messengerKey,
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
          routerConfig: _router,
        );
      },
    );
  }
}
