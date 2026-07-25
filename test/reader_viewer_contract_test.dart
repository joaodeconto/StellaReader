import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF reader uses stable horizontal paged viewer', () {
    final source = File('lib/ui/reader_screen.dart').readAsStringSync();

    expect(source, contains('PdfController('));
    expect(source, contains('child: PdfView('));
    expect(source, contains('scrollDirection: Axis.horizontal'));
    expect(source, contains('pageSnapping: true'));
    expect(source, contains('physics: const PageScrollPhysics()'));
    expect(source, isNot(contains('PdfViewPinch(')));
    expect(source, isNot(contains('PdfControllerPinch')));
  });
}
