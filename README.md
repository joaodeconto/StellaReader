**StellaReader**

- **Goal:** Minimal PDF reader MVP for Android focused on two core pains: bookmark pages and resume from last page. Easy import via file picker; optional Android Share and URL download.
- **Tech:** Flutter, Riverpod, go_router, pdfx, sqflite, path_provider, file_picker.

**Status**
- MVP: Done and running on Android.

**Build Requirements**
- Android NDK: 27.0.12077973 (see `android/app/build.gradle.kts:6`)
- JDK: 21 (install via Android Studio or set `org.gradle.java.home` in `android/gradle.properties`)
- Flutter: 3.32.x stable

**Features**
- **Import PDFs:** Adds local files via file picker; shows in library.
- **Resume Reading:** Persists `lastPage` per book and reopens where you left off.
- **Bookmarks:** One-tap bookmark; list in bottom sheet; jump to page.
- **Simple Library:** List with title and last page; tap to read.
- **Optional (MVP+):** Android Share to open PDFs, download by URL, generated covers.

**Architecture**
- **Layers:**
  - `domain/`: data models (`Book`, `Bookmark`).
  - `data/`: SQLite init and repositories.
  - `ui/`: screens (`LibraryScreen`, `ReaderScreen`).
- **State:** Riverpod (simple and testable).
- **Navigation:** go_router (declarative routes).
- **Persistence:** sqflite + path_provider (app documents dir).
- **PDF Viewer:** pdfx (`PdfViewPinch` for pinch-to-zoom).
- **Import:** file_picker.

**Directory Structure**
- `lib/main.dart` — App entry with `GoRouter` and Material theme.
- `lib/domain/book.dart` — `Book` model with `id`, `title`, `path`, `lastPage`.
- `lib/domain/bookmark.dart` — `Bookmark` model with `bookId`, `page`, `label?`, `createdAt`.
- `lib/data/app_db.dart` — SQLite open/init, creates `books` and `bookmarks` tables.
- `lib/data/book_repository.dart` — Insert, list, update `lastPage`.
- `lib/data/bookmark_repository.dart` — Insert and list bookmarks by `bookId`.
- `lib/ui/library_screen.dart` — Library list, “+” to import, tap to open reader.
- `lib/ui/reader_screen.dart` — PDF reader, auto-save last page, bookmark FAB, bookmarks sheet.

**File References**
- `lib/main.dart:1`
- `lib/domain/book.dart:1`
- `lib/domain/bookmark.dart:1`
- `lib/data/app_db.dart:1`
- `lib/data/book_repository.dart:1`
- `lib/data/bookmark_repository.dart:1`
- `lib/ui/library_screen.dart:1`
- `lib/ui/reader_screen.dart:1`

**Packages**
- `flutter_riverpod`: state management
- `go_router`: routing
- `pdfx`: PDF viewer
- `sqflite`: SQLite DB
- `path_provider`: app directories
- `file_picker`: file import
- `receive_sharing_intent` (optional)
- `dio` (optional)

**Database Schema**
- `books`
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `title TEXT NOT NULL`
  - `path TEXT NOT NULL`
  - `lastPage INTEGER NOT NULL DEFAULT 1`
- `bookmarks`
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `bookId INTEGER NOT NULL` (FK → `books.id` ON DELETE CASCADE)
  - `page INTEGER NOT NULL`
  - `label TEXT`
  - `createdAt INTEGER NOT NULL` (epoch ms)

**Routes**
- `/` → Library
- `/reader` → Reader (expects `Book` via `state.extra`)

**Usage**
- **Import a PDF:** Tap “+” on the Library screen and pick a `.pdf` file.
- **Open to Read:** Tap a book item; it opens at the last saved page.
- **Navigate:** Scroll/pinch; the current page is tracked.
- **Auto-Save:** Last page is saved on back or when the screen disposes.
- **Bookmark:** Tap the ⭐ FAB to add a bookmark for the current page.
- **List Bookmarks:** Tap the bookmarks icon in the AppBar to open the sheet and jump to a page.

**Setup**
- **Flutter SDK:** Use stable channel.
- **Windows dev note:** Enable Developer Mode for symlink support. Run `start ms-settings:developers` and toggle on.
- **Install deps:** `flutter pub get`
- **Platform helpers:**
  - Windows: `flutter pub run pdfx:install_windows`
  - Web: `flutter pub run pdfx:install_web`

**Run**
- Start an Android emulator or connect a device.
- Run the app: `flutter run`

**Implementation Notes**
- **Reader:** `PdfControllerPinch` + `PdfViewPinch`, `onPageChanged` updates the in-memory current page.
- **Persistence:** `BookRepository.updateLastPage` is called on back/dispose to persist `lastPage`.
- **Bookmarks:** Inserted with `BookmarkRepository.insert`; bottom sheet lists `byBook` in ascending `page`.
- **Titles:** Derived from filename without extension on import.

**Extending (MVP+)**
- **Android Share to Open:** Configure `receive_sharing_intent` with `intent-filter` for `application/pdf` in `android/app/src/main/AndroidManifest.xml`. On receipt, persist/copy the file path, insert a `Book`, and navigate to Reader.
- **Download by URL:** Add a dialog to paste a URL; use `dio` to save into `getApplicationDocumentsDirectory()`, then insert into `books` and open Reader.
- **Covers:** Render page 1 via `pdfx` renderer and store `coverPath` to show thumbnails in library.
- **DB Migrations:** Bump `version` in `openDatabase` and implement `onUpgrade` for schema changes.

**Troubleshooting**
- **Windows symlink errors:** Enable Developer Mode (`start ms-settings:developers`).
- **PDF path invalid after import:** Ensure the file wasn’t moved or deleted; re-import if needed.
- **Android storage/permissions:** File picker URIs usually work without extra permissions; for legacy storage, consider `permission_handler`.
- **Web/Windows pdfx setup:** Run the platform install commands above.

**Roadmap**
- Sprint 0: Setup project, packages, DB and routes. ✅
- Sprint 1: Library — import PDF, list books, open. ✅
- Sprint 2: Reader — viewer + save `lastPage`. ✅
- Sprint 3: Bookmarks — create/list/jump. ✅
- Sprint 4: QoL (optional) — Android Share, download by URL, covers.

**Contributing**
- Follow the existing modular structure (`domain/`, `data/`, `ui/`).
- Keep changes targeted and consistent with current style.
- Update this README for new features or behaviors.

**Further Docs**
- `docs/ROADMAP.md:1` — detailed next steps and acceptance criteria
- `docs/SHARING_ANDROID.md:1` — Android share-to-open setup
- `docs/DOWNLOADS.md:1` — in-app download plan and sample code
- `docs/DESIGN.md:1` — minimal layout guidelines

**License**
- Specify license or keep private (TBD).


**Next Improvements**
- Download inside the app: Add a dialog to paste a PDF URL, download with `dio` into `getApplicationDocumentsDirectory()`, validate as PDF, insert as `Book`, and open the Reader. Show progress and basic error states.
- Android sharing: Handle “Share → StellaReader” for PDFs via `receive_sharing_intent` and Manifest intent filters; import shared files into the library and open the Reader.
- Minimal layout: Polished Library grid with placeholders/covers, clearer empty state, and a simple page indicator + actions in the Reader.

Implementation sketch (high level):
- Download
  - UI: add action in `LibraryScreen` to open a “Paste URL” dialog.
  - Logic: `dio.download(url, dest)` with progress; save to app docs dir; try `PdfDocument.openFile` to validate; on success, insert `Book` and navigate.
  - Edge cases: non-PDF content type, timeouts, duplicate filenames.
- Sharing (Android)
  - Manifest: add SEND/SEND_MULTIPLE intent filters for `application/pdf` on `MainActivity`.
  - Code: listen to `ReceiveSharingIntent.getInitialMedia()` and stream; map to file path, insert `Book`, open Reader.
- Minimal layout
  - Library: switch to a simple grid; placeholder cover; long-press to delete (MVP+).
  - Reader: add a bottom page indicator and a bookmarks action next to the ⭐.
