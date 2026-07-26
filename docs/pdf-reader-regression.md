# PDF reader regression guard

The primary PDF reading mode must use a single-page horizontal pager with page snapping enabled.

## Manual acceptance checks

- A one-finger horizontal drag moves only the current page and settles on exactly one page.
- Page width and aspect ratio remain stable throughout the drag.
- A short, deliberate swipe advances one page without requiring a long pull.
- Previous/next buttons and page jump remain synchronized with the visible page.
- Imported PDFs and downloaded PDFs open through the same reader path.
- The bottom reader controls remain above Android system navigation controls.
- Test both portrait and landscape documents, including a large scanned PDF.

## Release validation

- Version 0.3.3+8: Android APK release triggered after PR #16 passed analysis and tests.
