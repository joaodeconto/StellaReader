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
      var fileName = path.split('/').last;
      final lower = fileName.toLowerCase();
      final isEpub = lower.endsWith('.epub');
      if (lower.endsWith('.pdf') || isEpub) {
        fileName = fileName.substring(0, fileName.lastIndexOf('.'));
      }
      final format = isEpub ? 'epub' : 'pdf';
      lastId = await BookRepository().insert(Book(title: fileName, path: path, format: format));
      lastTitle = fileName;
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
