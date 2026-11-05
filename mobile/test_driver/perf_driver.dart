// Host side of integration_test/quran_view_perf_test.dart: writes one
// timeline summary per scenario to build/<scenario>.timeline_summary.json,
// and the raw extra data to build/perf_extra.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      timeout: const Duration(minutes: 20),
      responseDataCallback: (data) async {
        if (data == null) return;
        final extra = <String, dynamic>{};
        for (final entry in data.entries) {
          final value = entry.value;
          if (value is Map<String, dynamic> && value.containsKey('traceEvents')) {
            final summary = driver.TimelineSummary.summarize(driver.Timeline.fromJson(value));
            await summary.writeTimelineToFile(entry.key, pretty: true, includeSummary: true);
          } else {
            extra[entry.key] = value;
          }
        }
        await File('build/perf_extra.json').writeAsString(const JsonEncoder.withIndent('  ').convert(extra));
      },
    );
