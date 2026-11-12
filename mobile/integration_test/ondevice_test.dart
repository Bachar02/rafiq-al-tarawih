// Taraweeh mode on the phone, end to end: real recitations, replayed in real
// time through the on-device engine with the bundled speech model.
//
//   py eval/phone_streams.py
//   flutter test integration_test/ondevice_test.dart -d <device>
//   # once it says it is waiting (the install empties the app's folder):
//   adb push eval/results/phone_streams/. /sdcard/Android/data/app.rafiq.rafiq/files/streams/
//   adb pull /sdcard/Android/data/app.rafiq.rafiq/files/streams/results.json
//   py eval/word_replay.py results.json     # word tracking on the phone's own output
//
// The test reinstalls the app, which wipes its data on the device (bookmarks,
// khatm, notes): use a test phone or a backup.
//
// Each stream starts a little late and the engine is told nothing, as in a
// mosque. The scores follow eval/audio_bench.py: a final is acceptable when
// the ayah on screen is within one of an ayah heard in it. Debug builds run
// the Dart part (matching, tracking) slower than a release build; the speech
// model is native code and runs at full speed either way.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/data/quran.dart';
import 'package:rafiq/services/ondevice/model_store.dart';
import 'package:rafiq/services/ondevice/ondevice_engine.dart';
import 'package:rafiq/services/ondevice/ondevice_transcriber.dart';

class _Event {
  _Event(this.heard, this.at);
  final Heard heard;
  final double at; // seconds after the stream began playing
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real recitations, followed on the phone with no server', (tester) async {
    final dir = Directory('${(await getExternalStorageDirectory())!.path}/streams');
    final index = File('${dir.path}/streams.json');
    // `flutter test` reinstalls the app, which empties this folder: wait for
    // the recordings to be pushed after the install.
    for (var i = 0; i < 180 && !index.existsSync(); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    expect(index.existsSync(), isTrue, reason: 'push eval/results/phone_streams/ to ${dir.path}');
    final streams = (jsonDecode(index.readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final quran = await compute(Quran.fromJson, await rootBundle.loadString('assets/quran/quran.json'));

    final prepare = Stopwatch()..start();
    final paths = await ModelStore.prepare();
    final prepareMs = prepare.elapsedMilliseconds;

    final results = <Map<String, Object?>>[];
    for (final s in streams) {
      final name = s['name'] as String;
      final join = (s['join'] as num).toDouble();
      final timeline = [
        for (final t in (s['timeline'] as List).cast<List<dynamic>>())
          ((t[0] as num).toDouble(), (t[1] as num).toDouble(), t[2] as int)
      ];
      final audio = Float32List.fromList(decodeWavPcm16(File('${dir.path}/$name.wav').readAsBytesSync()));

      final engine = OnDeviceRecognitionEngine(quran: quran, prepare: () async => whisperLoader(paths));
      final events = <_Event>[];
      final ready = Completer<void>();
      final clock = Stopwatch();
      final sub = engine.events.listen((e) {
        if (e is EngineReady && !ready.isCompleted) ready.complete();
        if (e is EngineFailure && !ready.isCompleted) ready.completeError(e.message);
        if (e is Heard) events.add(_Event(e, clock.elapsedMicroseconds / 1e6));
      });
      final load = Stopwatch()..start();
      await engine.start();
      await ready.future.timeout(const Duration(seconds: 60));
      final loadMs = load.elapsedMilliseconds;

      // The microphone: 250 ms of audio every 250 ms.
      clock.start();
      const block = 4000;
      for (var i = 0; i < audio.length; i += block) {
        final due = Duration(microseconds: (i + block) * 1000000 ~/ 16000);
        final wait = due - clock.elapsed;
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        engine.addAudio(Float32List.sublistView(audio, i, math.min(i + block, audio.length)));
      }
      await engine.finish();
      await sub.cancel();
      await engine.dispose();

      List<int> spoken(double start, double end) => [
            for (final (s0, e0, v) in timeline)
              if (s0 < end + join - 0.15 && e0 > start + join + 0.15) v
          ];
      bool near(int? shown, List<int> heard) => shown != null && heard.any((v) => (shown - v).abs() <= 1);

      final finals = events.where((e) => e.heard.isFinal && e.heard.text.isNotEmpty).toList();
      var acceptable = 0, counted = 0, wrong = 0;
      for (final e in finals) {
        final heard = spoken(e.heard.start, e.heard.end);
        if (heard.isEmpty) continue;
        counted++;
        final shown = e.heard.state.position?.verseId;
        if (near(shown, heard)) {
          acceptable++;
        } else if (shown != null) {
          wrong++;
        }
      }
      double? detect;
      for (final e in events) {
        if (near(e.heard.state.position?.verseId, spoken(e.heard.start, e.heard.end))) {
          detect = e.at;
          break;
        }
      }
      final lags = <double?>[];
      if (detect != null) {
        for (final (start, _, verse) in timeline) {
          final t = start - join;
          if (t < detect) continue;
          final shown = events.where((e) => e.heard.state.showing?.verseId == verse && e.at >= t).firstOrNull;
          lags.add(shown == null ? null : shown.at - t);
        }
      }
      final shownLags = lags.whereType<double>().toList()..sort();
      final asr = [for (final e in events) e.heard.asrMs]..sort();
      final seconds = audio.length / 16000;
      results.add({
        'name': name,
        'seconds': double.parse(seconds.toStringAsFixed(1)),
        'model_load_ms': loadMs,
        'finals': finals.length,
        'partials': events.where((e) => !e.heard.isFinal).length,
        'acceptable': counted == 0 ? null : double.parse((acceptable / counted).toStringAsFixed(3)),
        'wrong_finals': wrong,
        'detect_s': detect == null ? null : double.parse(detect.toStringAsFixed(2)),
        'lag_median_s': shownLags.isEmpty ? null : double.parse(shownLags[shownLags.length ~/ 2].toStringAsFixed(2)),
        'never_shown': lags.where((l) => l == null).length,
        'asr_median_ms': asr.isEmpty ? null : asr[asr.length ~/ 2],
        'asr_load': double.parse((asr.fold<int>(0, (a, b) => a + b) / 1000 / seconds).toStringAsFixed(2)),
        // A recording, as eval/audio_bench.py --record writes them: what the
        // model produced and when, for eval/word_replay.py and tracker_replay.
        'reciter': s['reciter'],
        'room': s['room'],
        'join': join,
        'timeline': s['timeline'],
        'events': [
          for (final e in events)
            {
              'text': e.heard.text,
              'start': e.heard.start,
              'end': e.heard.end,
              'asr_ms': e.heard.asrMs,
              'final': e.heard.isFinal,
              'ready': e.at,
            }
        ],
      });
      debugPrint('ONDEVICE ${jsonEncode(_summary(results.last))}');
    }

    final report = {
      'device': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}, ${Platform.numberOfProcessors} cores',
      'model': paths.name,
      'prepare_ms': prepareMs,
      'streams': results,
    };
    File('${dir.path}/results.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));
    debugPrint('ONDEVICE ${jsonEncode({...report, 'streams': results.map(_summary).toList()})}');
    for (final r in results) {
      expect(r['detect_s'], isNotNull, reason: '${r['name']}: the imam was never found');
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}

/// A stream's numbers without its recording, for the log.
Map<String, Object?> _summary(Map<String, Object?> stream) => {
      for (final e in stream.entries)
        if (e.key != 'events' && e.key != 'timeline') e.key: e.value
    };
