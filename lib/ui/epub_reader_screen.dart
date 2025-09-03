import 'dart:async';
import 'dart:typed_data';

import 'package:epub_view/epub_view.dart';
import 'package:universal_file/universal_file.dart' as uni;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';

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

  /// Last known valid chapter number to fall back on when the reader
  /// lands on sections that don't map to a chapter in the TOC.
  int _lastChapterNumber = 0;

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
      if (_controller.loadingState.value == EpubViewLoadingState.success &&
          !_didInitialCfiJump &&
          (widget.book.lastCfi != null && widget.book.lastCfi!.isNotEmpty)) {
        _didInitialCfiJump = true;
        debugPrint('Jumping to stored CFI: ${widget.book.lastCfi}');
        _controller.gotoEpubCfi(widget.book.lastCfi!);
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
    _saveDebounce = Timer(const Duration(milliseconds: 600), _saveLastLocation);
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
  }

  Future<void> _addBookmark() async {
    if (widget.book.id == null) return;
    final cfi = _controller.generateEpubCfi();
    if (cfi == null) return;

    final label = _currentChapterLabel() ?? 'Localização';
    debugPrint('Adding bookmark: label="$label" cfi=$cfi');
    await BookmarkRepository().insert(
      Bookmark(
        bookId: widget.book.id!,
        page: 0,
        cfi: cfi,
        label: label,
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
    final items = await BookmarkRepository().byBook(widget.book.id!);
    debugPrint('Loaded ${items.length} bookmarks');
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        children: items.isEmpty
            ? [const ListTile(title: Text('Sem marcadores'))]
            : items
                  .map(
                    (bm) => ListTile(
                      leading: const Icon(Icons.bookmark),
                      title: Text(bm.label ?? 'Localização'),
                      onTap: () {
                        final cfi = bm.cfi;
                        Navigator.pop(context);
                        if (cfi != null) {
                          debugPrint('Jumping to bookmark CFI: $cfi');
                          // jump after sheet closes
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _controller.gotoEpubCfi(cfi);
                          });
                        }
                      },
                    ),
                  )
                  .toList(),
      ),
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
              builders: EpubViewBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                chapterBuilder: _chapterBuilderWithImages,
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
                  child: ValueListenableBuilder(
                    valueListenable: _controller.currentValueListenable,
                    builder: (context, value, _) => Text(
                      _currentChapterLabel() ?? '…',
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
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

  /// Custom chapter builder that forces images to decode into a safe RGBA8888
  /// format and lowers the filter quality to avoid GPU texture issues on
  /// some devices.
  static Widget _chapterBuilderWithImages(
    BuildContext context,
    EpubViewBuilders builders,
    EpubBook document,
    List<EpubChapter> chapters,
    List paragraphs,
    int index,
    int chapterIndex,
    int paragraphIndex,
    ExternalLinkPressed onExternalLinkPressed,
  ) {
    if (paragraphs.isEmpty) {
      return Container();
    }

    final defaultBuilder = builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    return Column(
      children: <Widget>[
        if (chapterIndex >= 0 && paragraphIndex == 0)
          builders.chapterDividerBuilder(chapters[chapterIndex]),
        Html(
          data: paragraphs[index].element.outerHtml,
          onLinkTap: (href, _, __) => onExternalLinkPressed(href!),
          style: {
            'html': Style(
              padding: HtmlPaddings.only(
                top: (options.paragraphPadding as EdgeInsets?)?.top,
                right: (options.paragraphPadding as EdgeInsets?)?.right,
                bottom: (options.paragraphPadding as EdgeInsets?)?.bottom,
                left: (options.paragraphPadding as EdgeInsets?)?.left,
              ),
            ).merge(Style.fromTextStyle(options.textStyle)),
          },
          extensions: [
            TagExtension(
              tagsToExtend: {"img"},
              builder: (imageContext) {
                final url =
                    imageContext.attributes['src']!.replaceAll('../', '');
                final content = Uint8List.fromList(
                    document.Content!.Images![url]!.Content!);
                return Image.memory(
                  content,
                  filterQuality: FilterQuality.low,
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  String? _currentChapterLabel() {
    final v = _controller.currentValueListenable.value;
    final raw = v?.chapter?.Title?.trim();

    final number = v?.chapterNumber ?? 0;
    if (number > 0) _lastChapterNumber = number;
    final idx = number > 0 ? number : _lastChapterNumber;
    final cleaned = raw != null ? cleanTitle(raw) : '';
    debugPrint('Current chapter: raw="$raw" cleaned="$cleaned" index=$idx');
    final prefix = idx > 0 ? 'Capítulo $idx — ' : '';
    final text = cleaned.isEmpty
        ? (prefix.isNotEmpty ? prefix.substring(0, prefix.length - 3) : null)
        : '$prefix$cleaned';
    return text?.trim();
  }
}
