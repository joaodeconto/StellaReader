**Android: Share books to StellaReader**

Sharing a PDF or EPUB from another app — a browser, a file manager, an email
client — offers StellaReader in the share sheet. Picking it copies the book
into the library and opens it. This works both from a cold start
(StellaReader was not running) and a warm one (it was already open).

Packages
- `receive_sharing_intent`

Manifest
`android/app/src/main/AndroidManifest.xml` advertises the two MIME types the
reader can open, for both a single share and a multi-select: `SEND` and
`SEND_MULTIPLE`, each with `application/pdf` and `application/epub+zip`.

Only those two types are listed on purpose. A catch-all such as
`application/octet-stream` would put StellaReader in the share sheet for every
unrecognised binary.

The activity runs with `android:launchMode="singleTask"` so a share reaches
the running instance through `onNewIntent` rather than starting a second copy
of the reader inside the sending app's task.

Dart wiring
- `lib/data/share_intake.dart` — `ShareIntake` turns a batch of
  `SharedMediaFile`s into library books.
- `lib/main.dart` — subscribes to the stream for warm shares, reads
  `getInitialMedia()` once for the cold-start case, then calls `reset()`.

Behaviour worth knowing
- **The shared path is a cache path.** The plugin copies incoming content into
  a temporary directory, and that copy is not ours to keep. Every file goes
  through `ImportService.importFile`, which copies it into the app's `books`
  directory and inserts the row — the same path a file-picker import takes.
  Storing the cache path directly would leave the library pointing at files
  Android is free to delete.
- **The extension decides, not the MIME type.** The share sheet filters by
  MIME, but a sending app is free to mislabel a file, so `ShareIntake` checks
  the extension before importing.
- **A bad file does not sink the batch.** Files that cannot be imported are
  counted and reported in a snackbar; the rest still land in the library.
- **Several books at once** all get imported. The first one opens and the rest
  wait in the library, with a snackbar saying how many arrived.
- `reset()` matters: without it Android hands the same files back on every
  later start.

Notes
- No extra storage permission is required for typical shares on modern
  Android.

Not covered
- `ACTION_VIEW`, i.e. "Open with → StellaReader" when tapping a file in a file
  manager. The plugin already handles that action, but it needs its own
  `intent-filter` matching the file scheme, which has not been added or
  tested.
