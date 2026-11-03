import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/text/normalize.dart';

/// The Dart port must reproduce the Python reference exactly
/// (golden file from tools/golden/make_golden.py).
void main() {
  final cases =
      (jsonDecode(File('test/golden/normalize.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

  test('golden file is substantial', () => expect(cases.length, greaterThan(500)));

  test('normalize matches the Python engine on every golden case', () {
    final mismatches = <String>[];
    for (final c in cases) {
      final got = normalize(c['input'] as String);
      if (got != c['normalized']) mismatches.add('${c['input']}\n  python: ${c['normalized']}\n  dart:   $got');
    }
    expect(mismatches, isEmpty, reason: mismatches.take(5).join('\n'));
  });

  test('tokenize splits words and handles empty input', () {
    expect(tokenize('  والضحى   والليل '), ['والضحي', 'والليل']);
    expect(tokenize(''), isEmpty);
    expect(tokenize('123 abc'), isEmpty);
  });
}
