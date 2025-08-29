import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../data/book_repository.dart';
import '../domain/book.dart';

class ShareHandler {
  static bool _initialized = false;
  static StreamSubscription? _sub;

  static Future<void> init(BuildContext context) async {
    if (_initialized || kIsWeb || !Platform.isAndroid) return;
    _initialized = true;

    // Handle initial share
    try {
      final items = await ReceiveSharingIntent.instance.getInitialMedia();
      if (items.isNotEmpty) {
        if (!context.mounted) return;
        await _handleItems(context, items);
      }
    } catch (_) {}

    // Listen for runtime shares
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (items) async {
        if (!context.mounted) return;
        await _handleItems(context, items);
      },
      onError: (_) {},
    );
  }

  static Future<void> _handleItems(BuildContext context, List<SharedMediaFile> items) async {
    int? lastId;
    String? lastTitle;
    String? lastPath;
    for (final f in items) {
      final path = f.path; // resolved file path
      var title = path.split('/').last;
      if (title.toLowerCase().endsWith('.pdf')) {
        title = title.substring(0, title.length - 4);
      }
      lastId = await BookRepository().insert(Book(title: title, path: path));
      lastTitle = title;
      lastPath = path;
    }
    if (lastId != null && context.mounted) {
      GoRouter.of(context).push('/reader', extra: Book(id: lastId, title: lastTitle!, path: lastPath!));
    }
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
  }
}
