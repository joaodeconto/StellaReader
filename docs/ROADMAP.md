**Roadmap**

- Status: MVP complete (import, read, save last page, bookmarks).

**1) Download PDF Inside App**
- User flow: Library → action “Download by URL” → paste URL → download → validate → add to library → open.
- Tech: `dio`, `path_provider`, `pdfx` (validate), Riverpod for progress state.
- Tasks:
  - Add UI dialog to capture URL.
  - Implement `DownloadController` with progress (bytes/total, speed optional).
  - Sanitize filename, write to `getApplicationDocumentsDirectory()`.
  - Validate PDF by opening with `PdfDocument.openFile` (catch errors), optionally get `pagesCount`.
  - Insert `Book` row; navigate to Reader.
  - Errors: invalid URL, non-PDF content, timeouts, insufficient space.
- Acceptance:
  - Shows progress and can cancel.
  - Fails gracefully with a message.
  - Opens the downloaded book at page 1; persists `lastPage` after reading.

**2) Android Share-to-Open**
- User flow: Another app → Share PDF → choose StellaReader → book appears and opens.
- Tech: `receive_sharing_intent`.
- Manifest (snippet):
  - Add to `android/app/src/main/AndroidManifest.xml` under the main Activity:
  - Allow `SEND` and `SEND_MULTIPLE` with `application/pdf`.
- Code:
  - On app start, check `ReceiveSharingIntent.getInitialMedia()`.
  - Subscribe to `ReceiveSharingIntent.getMediaStream()` for runtime shares.
  - Map shared file path to `Book` (insert if new), then navigate to Reader.
- Acceptance:
  - Cold and warm shares work.
  - Multiple PDFs share inserts all; opens the last one or shows a picker.

**3) Minimal Layout Polish**
- Library:
  - Grid layout with 2 columns.
  - Placeholder cover (or first-page thumbnail later).
  - Empty state CTA with “Import PDF” and “Download by URL”.
  - Optional long-press delete (MVP+).
- Reader:
  - Bottom page indicator (current/total) using `PdfPageNumber`.
  - AppBar action for bookmarks; FAB continues for quick add.
- Theme:
  - Keep Material 3; define a small set of tokens (spacing 8, radius 12).
- Acceptance:
  - Works on phones; readable and minimal.

**4) DB Evolution**
- Add columns (future): `author`, `coverPath`, `pageCount`, `addedAt`.
- Migration (v2):
  - `ALTER TABLE books ADD COLUMN author TEXT;`
  - `ALTER TABLE books ADD COLUMN coverPath TEXT;`
  - `ALTER TABLE books ADD COLUMN pageCount INTEGER;`
  - `ALTER TABLE books ADD COLUMN addedAt INTEGER;`

**5) QA & Release Gates**
- Smoke tests: import, read, bookmark, resume.
- Offline mode: open existing books offline.
- Large PDFs: handle 1000+ pages responsive scrolling.

