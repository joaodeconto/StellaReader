**In-app PDF Download**

Goal
- Paste a PDF URL, download to app storage, validate as PDF, add to library, and open.

Packages
- `dio`, `path_provider`, `pdfx`

Flow
1) Prompt user for URL
2) Resolve filename; sanitize
3) Download via `dio` with progress
4) Save to `getApplicationDocumentsDirectory()`
5) Validate via `PdfDocument.openFile` (catch errors)
6) Insert `Book` and navigate to Reader

Sample code (logic only)
```dart
final dir = await getApplicationDocumentsDirectory();
final fileName = sanitizeFileNameFromUrl(url) ?? 'downloaded.pdf';
final savePath = p.join(dir.path, fileName);

final dio = Dio();
await dio.download(
  url,
  savePath,
  options: Options(receiveTimeout: const Duration(seconds: 30)),
  onReceiveProgress: (received, total) {
    if (total > 0) {
      // update progress: received / total
    }
  },
);

// Validate PDF
try {
  final doc = await PdfDocument.openFile(savePath);
  final pages = doc.pagesCount;
  await doc.close();
  final id = await BookRepository().insert(Book(title: p.basenameWithoutExtension(savePath), path: savePath));
  // navigate to Reader with the new Book
} catch (e) {
  // Not a valid PDF or corrupted; delete file and show error
}
```

Edge cases
- Non-PDF URLs or unexpected content-type
- Redirects; large files; timeouts
- Duplicate filenames → append a counter or UUID

