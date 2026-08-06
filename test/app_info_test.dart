import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stellareader/app_info.dart';

/// The version is written down twice: once in `pubspec.yaml`, where the build
/// reads it, and once in `app_info.dart`, where the User-Agent reads it. This
/// is what stops the second from quietly falling behind the first.
void main() {
  test('appVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(
      declared,
      isNotNull,
      reason: 'pubspec.yaml needs a "version: x.y.z+build" line',
    );
    expect(declared!.group(1), appVersion);
  });

  test('identifies the app and its version to servers', () {
    expect(userAgent, 'StellaReader/$appVersion');
  });
}
