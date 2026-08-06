/// The app's release version.
///
/// Must match `version:` in `pubspec.yaml` — `app_info_test.dart` fails if it
/// drifts, which is the only thing keeping the two honest.
const appVersion = '0.4.2';

/// How StellaReader identifies itself to servers it fetches books from.
const userAgent = 'StellaReader/$appVersion';
