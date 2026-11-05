import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../support/golden.dart';

/// Applies to every test under test/golden/: real fonts, tolerant comparator.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadAppFonts();
  final local = goldenFileComparator as LocalFileComparator;
  goldenFileComparator = RubricGoldenComparator(local.basedir.resolve('golden_test.dart'));
  await testMain();
}
