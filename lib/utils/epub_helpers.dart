/// Normalizes a string by collapsing whitespace and lowercasing.
String normTitle(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// Cleans common noisy prefixes from chapter titles found in public EPUBs.
///
/// Examples removed: "Chapter 1 -", "Capítulo 2:", "Project Gutenberg" headers.
String cleanTitle(String s) {
  var r = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lowered = r.toLowerCase();

  final startsWithChapter =
      RegExp(r'^chapter\s+\d+\b', caseSensitive: false).hasMatch(lowered);
  final startsWithCapitulo =
      RegExp(r'^cap[ií]tulo\s+\d+\b', caseSensitive: false).hasMatch(lowered);

  if (lowered.contains('project gutenberg') ||
      startsWithChapter ||
      startsWithCapitulo) {
    r = r.replaceFirst(
      RegExp(r'^(chapter|cap[ií]tulo)\s+\d+\s*[:\-–"“”]?\s*',
          caseSensitive: false),
      '',
    );
    if (r.toLowerCase().contains('project gutenberg')) return '';
  }
  return r.trim();
}

/// Finds the index of [rawTitle] inside the given [toc] (table of contents).
///
/// Titles are normalised and cleaned before comparison, so variants like
/// "Chapter 1 - Foo" and "Capítulo 1: Foo" all resolve to the same entry.
/// Returns `-1` when no matching chapter is found or when the cleaned title
/// is empty (e.g. Project Gutenberg licence pages).
int chapterIndex(String rawTitle, List<String> toc) {
  final cleanedRaw = cleanTitle(rawTitle);
  if (cleanedRaw.isEmpty) return -1;
  final target = normTitle(cleanedRaw);

  for (var i = 0; i < toc.length; i++) {
    final ct = cleanTitle(toc[i]);
    if (ct.isEmpty) continue;
    if (normTitle(ct) == target) return i;
  }

  return -1;
}

