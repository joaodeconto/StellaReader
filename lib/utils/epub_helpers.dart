/// Normalizes a string by collapsing whitespace and lowercasing.
String normTitle(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// Cleans common noisy prefixes from chapter titles found in public EPUBs.
///
/// Examples removed: "Chapter 1 -", "Capítulo 2:", "Project Gutenberg" headers.
String cleanTitle(String s) {
  var r = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lowered = r.toLowerCase();
  if (lowered.contains('project gutenberg') ||
      lowered.startsWith('chapter ') ||
      lowered.startsWith('capítulo ')) {
    r = r.replaceFirst(
      RegExp(r'^(chapter|capítulo)\s+\d+\s*[:\-–—]\s*', caseSensitive: false),
      '',
    );
    if (r.toLowerCase().contains('project gutenberg')) return '';
  }
  return r.trim();
}

