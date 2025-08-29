**Minimal Layout Guidelines**

Principles
- Prioritize readability and one-tap actions (import, bookmark).
- Keep hierarchy shallow; defer advanced controls to later.

Library
- Grid (2 columns) with card tiles.
- Tile contents: cover placeholder (or first-page thumbnail later), title, last page.
- Empty state with CTA buttons: “Import PDF”, “Download by URL”.
- Long press: optional delete in MVP+.

Reader
- AppBar: title, bookmarks list action.
- FAB: ⭐ quickly adds a bookmark on current page.
- Bottom overlay: page indicator (current/total) using `PdfPageNumber`.
- Gesture: pinch zoom (PdfViewPinch), vertical scroll.

Theme
- Material 3, seed color teal.
- Spacing 8, radius 12, medium elevation for tiles.
- Support dark mode (system default).

