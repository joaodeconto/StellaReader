import 'package:flutter_test/flutter_test.dart';
import 'package:stellareader/utils/epub_helpers.dart';

void main() {
  group('epub helpers', () {
    test('cleanTitle removes noise', () {
      expect(cleanTitle('Chapter 1 - Introduction'), 'Introduction');
      expect(cleanTitle('Capítulo 2: O Início'), 'O Início');
      expect(cleanTitle('Project Gutenberg'), '');
    });

    test('normTitle collapses whitespace and lowercases', () {
      expect(normTitle('  Hello   World '), 'hello world');
    });
  });
}

