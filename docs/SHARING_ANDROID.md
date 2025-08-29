**Android: Share PDFs to StellaReader**

Packages
- `receive_sharing_intent`

Manifest
- Edit `android/app/src/main/AndroidManifest.xml` and add intent filters to the main activity:

```xml
<application ...>
  <activity
    android:name=".MainActivity"
    android:launchMode="singleTask"
    android:exported="true"
    ...>

    <!-- Receive a single PDF -->
    <intent-filter>
      <action android:name="android.intent.action.SEND" />
      <category android:name="android.intent.category.DEFAULT" />
      <data android:mimeType="application/pdf" />
    </intent-filter>

    <!-- Receive multiple PDFs -->
    <intent-filter>
      <action android:name="android.intent.action.SEND_MULTIPLE" />
      <category android:name="android.intent.category.DEFAULT" />
      <data android:mimeType="application/pdf" />
    </intent-filter>
  </activity>
</application>
```

Dart wiring (example)

```dart
// e.g., in a top-level app controller or init point
final _sub = ReceiveSharingIntent.getMediaStream().listen((items) async {
  if (items.isEmpty) return;
  for (final f in items) {
    final path = f.path; // platform file path
    final title = path.split('/').last.replaceAll('.pdf', '');
    final id = await BookRepository().insert(Book(title: title, path: path));
    // Optionally open last received
  }
  // Navigate to Reader for last inserted
}, onError: (e) {
  // Handle errors
});

// On cold start
final initial = await ReceiveSharingIntent.getInitialMedia();
// Handle similarly and then clear intent if needed.
```

Notes
- Many apps share content URIs; keep the file path accessible or copy to app storage if needed.
- No extra storage permission is required for typical shares/file picker on modern Android.

