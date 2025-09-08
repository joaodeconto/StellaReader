import 'dart:async';

import 'package:epub_view/epub_view.dart' hide Image;
import 'package:universal_file/universal_file.dart' as uni;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/book.dart';
import '../data/book_repository.dart';
import '../domain/bookmark.dart';
import '../data/bookmark_repository.dart';
import '../utils/epub_helpers.dart';

/// Screen responsible for rendering an EPUB book and managing reader state.
class EpubReaderScreen extends ConsumerStatefulWidget {
  /// Book to open.
  final Book book;
  const EpubReaderScreen({super.key, required this.book});

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen>
    with WidgetsBindingObserver {
  /// Controller from `epub_view` that handles rendering and navigation.
  late EpubController _controller;

  /// Ensures we only jump to the stored CFI once.
  bool _didInitialCfiJump = false;

  /// Listener reference so we can clean it up on dispose.
  late VoidCallback _loadingListener;

  /// Debouncer to avoid writing to the database on every tiny scroll.
  Timer? _saveDebounce;

  /// Last non-empty chapter label we've seen, used to avoid showing noisy
  /// sections like the Gutenberg license.
  String _lastNonEmptyChapterLabel = '';
  bool _didBackfillIndices = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize controller pointing to the book file.
    _controller = EpubController(
      document: EpubDocument.openFile(uni.File(widget.book.path)),
      epubCfi: widget.book.lastCfi,
    );
    debugPrint('EpubReaderScreen init for book id: ${widget.book.id}');

    // When the document finishes loading, jump to last known location if any.
    _loadingListener = () {
      debugPrint('Loading state: ${_controller.loadingState.value}');
      if (_controller.loadingState.value == EpubViewLoadingState.success) {
        if (!_didInitialCfiJump &&
            (widget.book.lastCfi != null && widget.book.lastCfi!.isNotEmpty)) {
          _didInitialCfiJump = true;
          debugPrint('Jumping to stored CFI: ${widget.book.lastCfi}');
          _controller.gotoEpubCfi(widget.book.lastCfi!);
          // Also align to stored paragraph index if present (more robust for some books)
          if (widget.book.lastPage > 0) {
            Future.delayed(const Duration(milliseconds: 120), () {
              debugPrint('Aligning to stored index: ${widget.book.lastPage}');
              _controller.jumpTo(index: widget.book.lastPage, alignment: 0.05);
            });
          }
        }
        // Kick off a one-time bookmark index backfill in the background.
        _backfillBookmarkIndicesIfNeeded();
      }
    };
    _controller.loadingState.addListener(_loadingListener);

    // Debounced saving of the current location.
    _controller.currentValueListenable.addListener(_onLocationChanged);
  }

  /// Called whenever the reader's location changes.
  /// Starts a debounce timer to persist the position shortly after.
  void _onLocationChanged() {
    debugPrint('Location changed');
    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      const Duration(milliseconds: 2000),
      _saveLastLocation,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      debugPrint('App paused; saving last location');
      _saveLastLocation();
    }
  }

  Future<void> _saveLastLocation() async {
    if (widget.book.id == null) return;
    final cfi = _controller.generateEpubCfi();
    if (cfi == null || cfi.isEmpty) return;
    debugPrint('Saving CFI: $cfi for book id: ${widget.book.id}');
    await BookRepository().updateLastCfi(widget.book.id!, cfi);
    final idx = _controller.currentValueListenable.value?.position.index;
    if (idx != null) {
      await BookRepository().updateLastPage(widget.book.id!, idx);
    }
  }

  Future<void> _addBookmark() async {
    if (widget.book.id == null) return;
    final cfi = _controller.generateEpubCfi();
    if (cfi == null || cfi.isEmpty) return;

    // Avoid duplicate bookmarks for the same location.
    final repo = BookmarkRepository();
    final exists = await repo.existsByCfi(widget.book.id!, cfi);
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Este marcador já existe')));
      return;
    }

    final label = _displayChapterLabel() ?? 'Localização atual';
    final absIndex =
        _controller.currentValueListenable.value?.position.index ?? 0;
    debugPrint('Adding bookmark: label="$label" cfi=$cfi');
    await repo.insert(
      Bookmark(
        bookId: widget.book.id!,
        page: absIndex, // Use absolute paragraph index for reliable jumps
        cfi: cfi,
        // Prefer current chapter label; if fallback text, use date
        label:
            _displayChapterLabel() ??
            (label.contains('Localiza') ? _formatNowLabel() : label),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Marcador adicionado')));
  }

  Future<void> _showBookmarks() async {
    if (widget.book.id == null) return;
    final repo = BookmarkRepository();
    var items = await repo.byBook(widget.book.id!);
    debugPrint('Loaded ${items.length} bookmarks');
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        Future<void> renameBookmark(Bookmark bm) async {
          final controller = TextEditingController(
            text: bm.label ?? _displayChapterLabel() ?? '',
          );
          final newLabel = await showDialog<String>(
            context: ctx,
            builder: (dctx) => AlertDialog(
              title: const Text('Renomear marcador'),
              content: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Título do marcador',
                ),
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dctx, controller.text.trim()),
                  child: const Text('Salvar'),
                ),
              ],
            ),
          );
          if (newLabel != null && newLabel.isNotEmpty) {
            await repo.updateLabel(bm.id!, newLabel);
            final idx = items.indexWhere((e) => e.id == bm.id);
            if (idx >= 0) {
              items[idx] = Bookmark(
                id: bm.id,
                bookId: bm.bookId,
                page: bm.page,
                cfi: bm.cfi,
                label: newLabel,
                createdAt: bm.createdAt,
              );
            }
          }
        }

        Future<void> deleteBookmark(Bookmark bm) async {
          await repo.delete(bm.id!);
          items = items.where((e) => e.id != bm.id).toList();
        }

        if (items.isEmpty) {
          return const ListTile(title: Text('Sem marcadores'));
        }

        return ListView(
          children: items
              .map(
                (bm) => ListTile(
                  leading: const Icon(Icons.bookmark),
                  title: Text(bm.label ?? _formatDate(bm.createdAt)),
                  onTap: () {
                    final cfi = bm.cfi;
                    Navigator.pop(context);
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      if (bm.page > 0) {
                        debugPrint('Jumping by index: ${bm.page}');
                        _controller.jumpTo(index: bm.page, alignment: 0.05);
                        await Future.delayed(const Duration(milliseconds: 120));
                      }
                      if (cfi != null && cfi.isNotEmpty) {
                        debugPrint('Refining with CFI: $cfi');
                        _controller.gotoEpubCfi(
                          cfi,
                          alignment: 0.0,
                          duration: Duration.zero,
                        );
                        await Future.delayed(const Duration(milliseconds: 140));
                        final idx = _controller
                            .currentValueListenable
                            .value
                            ?.position
                            .index;
                        if (idx != null && bm.page != idx && bm.id != null) {
                          await repo.updatePage(bm.id!, idx);
                        }
                      }
                    });
                  },
                ),
              )
              .toList(),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.currentValueListenable.removeListener(_onLocationChanged);
    _saveDebounce?.cancel();
    _controller.loadingState.removeListener(_loadingListener);
    _saveLastLocation();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Ensure we save the last position when leaving the screen.
      onPopInvokedWithResult: (didPop, result) {
        _saveLastLocation();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.book.title),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: _showBookmarks,
            ),
          ],
        ),
        body: Stack(
          children: [
            // Actual EPUB rendering widget.
            EpubView(
              controller: _controller,
              builders: const EpubViewBuilders<DefaultBuilderOptions>(
                options: DefaultBuilderOptions(),
              ),
              onExternalLinkPressed: (href) async {
                final uri = Uri.tryParse(href);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: EpubViewActualChapter(
                    controller: _controller,
                    builder: (chapterValue) {
                      final raw = chapterValue?.chapter?.Title
                          ?.replaceAll('\n', '')
                          .trim();
                      final cleaned = raw != null ? cleanTitle(raw) : '';
                      if (cleaned.isNotEmpty) {
                        _lastNonEmptyChapterLabel = cleaned;
                      }
                      final text = cleaned.isNotEmpty
                          ? cleaned
                          : (_lastNonEmptyChapterLabel.isNotEmpty
                                ? _lastNonEmptyChapterLabel
                                : '');
                      return Text(
                        text,
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addBookmark,
          child: const Icon(Icons.star),
        ),
      ),
    );
  }

  // Using the default EpubView builders to ensure CFI navigation works reliably.

  // One-time background backfill of bookmark indices to absolute paragraph index.
  Future<void> _backfillBookmarkIndicesIfNeeded() async {
    if (_didBackfillIndices || widget.book.id == null) return;
    _didBackfillIndices = true;
    final repo = BookmarkRepository();
    final items = await repo.byBook(widget.book.id!);
    final origCfi = _controller.generateEpubCfi();
    final origIdx = _controller.currentValueListenable.value?.position.index;
    for (final bm in items) {
      if (bm.id == null) continue;
      final needsIdx = bm.page <= 1;
      final needsLabel = _isGenericLabel(bm.label);
      if (!needsIdx && !needsLabel) continue;

      try {
        if (bm.cfi != null && bm.cfi!.isNotEmpty) {
          _controller.gotoEpubCfi(
            bm.cfi!,
            alignment: 0.0,
            duration: Duration.zero,
          );
          await Future.delayed(const Duration(milliseconds: 140));
        } else if (bm.page > 0) {
          _controller.jumpTo(index: bm.page, alignment: 0.05);
          await Future.delayed(const Duration(milliseconds: 120));
        }

        final idx = _controller.currentValueListenable.value?.position.index;
        if (needsIdx && idx != null) {
          await repo.updatePage(bm.id!, idx);
        }

        if (needsLabel) {
          final newLabel = _displayChapterLabel() ?? _formatDate(bm.createdAt);
          if (newLabel != bm.label) {
            await repo.updateLabel(bm.id!, newLabel);
          }
        }
      } catch (_) {}
    }
    // Restore reader position
    if (origIdx != null) {
      _controller.jumpTo(index: origIdx, alignment: 0.05);
      await Future.delayed(const Duration(milliseconds: 80));
    }
    if (origCfi != null && origCfi.isNotEmpty) {
      _controller.gotoEpubCfi(origCfi, alignment: 0.0, duration: Duration.zero);
    }
  }

  String _formatNowLabel() =>
      _formatDate(DateTime.now().millisecondsSinceEpoch);
  String _formatDate(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  bool _isGenericLabel(String? s) {
    if (s == null) return true;
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return true;
    if (t == 'marcador' || t == 'bookmark') return true;
    if (t.contains('localiza')) return true;
    return false;
  }

  String? _displayChapterLabel() {
    final v = _controller.currentValueListenable.value;
    final raw = v?.chapter?.Title?.trim();
    final cleaned = raw != null ? cleanTitle(raw) : '';
    if (cleaned.isNotEmpty) {
      _lastNonEmptyChapterLabel = cleaned;
      return cleaned;
    }
    return _lastNonEmptyChapterLabel.isNotEmpty
        ? _lastNonEmptyChapterLabel
        : null;
  }

  // _currentChapterLabel was replaced by EpubViewActualChapter + _displayChapterLabel.
}
