import 'dart:io' show sleep;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/core/engine/listener.dart';
import 'package:rafiq/core/engine/matcher.dart';
import 'package:rafiq/core/engine/segmenter.dart';
import 'package:rafiq/core/engine/tracker.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/data/settings.dart';
import 'package:rafiq/services/ondevice/model_store.dart';
import 'package:rafiq/services/ondevice/ondevice_engine.dart';
import 'package:rafiq/services/server_recognition_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// [seconds] of recitation-like sound (a tone loud enough for the VAD).
Float32List tone(double seconds) => Float32List.fromList([
      for (var i = 0; i < (seconds * 16000).round(); i++) 0.3 * math.sin(2 * math.pi * 180 * i / 16000),
    ]);

Float32List silence(double seconds) => Float32List((seconds * 16000).round());

/// Ad-Duha 93:1..5, one breath each, with pauses between.
List<Float32List> duhaBreaths() => [
      for (var i = 0; i < 5; i++) ...[tone(1.6), silence(0.8)],
    ];

/// A stand-in for the speech model that "hears" [texts] in turn, one per
/// transcription (it runs inside the recognition isolate, with its own copy).
TranscriberLoader scripted(List<String> texts, {Duration delay = Duration.zero, bool failToLoad = false}) => () {
      if (failToLoad) throw StateError('out of memory');
      var next = 0;
      return (
        transcribe: (Float32List audio) {
          if (delay > Duration.zero) sleep(delay);
          if (audio.length == 16000 && audio.every((s) => s == 0)) return ''; // the warm-up
          return next < texts.length ? texts[next++] : '';
        },
        dispose: () {},
        device: 'test',
      );
    };

void main() {
  final quran = loadQuran();
  final duha = [for (var a = 1; a <= 5; a++) quran.verse(quran.verseId(93, a)!).text];

  Future<List<RecognitionEvent>> run(
    OnDeviceRecognitionEngine engine,
    List<Float32List> audio, {
    void Function(OnDeviceRecognitionEngine)? before,
    Duration pace = Duration.zero,
  }) async {
    final events = <RecognitionEvent>[];
    final sub = engine.events.listen(events.add);
    await engine.start();
    // Wait for the model: audio sent meanwhile would be trimmed to 2 s.
    for (var i = 0; i < 200 && !events.any((e) => e is EngineReady || e is EngineFailure); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    before?.call(engine);
    for (final block in audio) {
      for (var i = 0; i < block.length; i += 4000) {
        engine.addAudio(Float32List.sublistView(block, i, math.min(i + 4000, block.length)));
        if (pace > Duration.zero) await Future<void>.delayed(pace);
      }
    }
    await engine.finish();
    await sub.cancel();
    await engine.dispose();
    return events;
  }

  OnDeviceRecognitionEngine engine(TranscriberLoader loader, {ListenerConfig? config}) => OnDeviceRecognitionEngine(
        quran: quran,
        prepare: () async => loader,
        listenerConfig: config ?? const ListenerConfig(partialEvery: 0),
      );

  test('word tracking: off sends no words; on sends them, and the ayahs are exactly the same', () async {
    final ayahs = [for (var a = 1; a <= 9; a++) quran.verse(quran.verseId(93, a)!).text];
    final breaths = [
      for (var i = 0; i < ayahs.length; i++) ...[tone(1.6), silence(0.8)],
    ];
    OnDeviceRecognitionEngine make({required bool words}) => OnDeviceRecognitionEngine(
          quran: quran,
          prepare: () async => scripted(ayahs),
          listenerConfig: const ListenerConfig(partialEvery: 0),
          wordTracking: words,
        );
    // Paced, so the 21.6 s never pile up past the 15 s backlog (which would
    // drop audio depending on timing, not on word tracking).
    const pace = Duration(milliseconds: 5);
    final off = (await run(make(words: false), breaths, pace: pace)).whereType<Heard>().toList();
    final on = (await run(make(words: true), breaths, pace: pace)).whereType<Heard>().toList();
    expect(off, hasLength(ayahs.length), reason: 'every breath heard');
    expect(off.every((h) => h.word == null), isTrue, reason: 'off: no word tracker at all');
    expect([
      for (final h in on) (h.text, h.state.position, h.state.status, h.state.upcoming)
    ], [
      for (final h in off) (h.text, h.state.position, h.state.status, h.state.upcoming)
    ], reason: 'the ayah results do not depend on word tracking');
    final words = on.where((h) => h.word != null).toList();
    expect(words, isNotEmpty, reason: 'on: words once the ayah is found');
    for (final h in words) {
      expect(h.word!.verseId, h.state.position!.verseId, reason: 'the word is in the ayah heard');
    }
  });

  test('follows the recitation in a background isolate: ready, each ayah, done', () async {
    final events = await run(engine(scripted(duha)), duhaBreaths());
    expect(events.first, isA<EngineReady>());
    expect((events.first as EngineReady).device, 'test');
    final heard = events.whereType<Heard>().toList();
    expect(heard, hasLength(5), reason: 'one final per breath');
    expect(heard.every((h) => h.isFinal), isTrue);
    expect([for (final h in heard) h.text], duha);
    expect(heard.last.state.position, pos(93, 5));
    expect(heard.last.state.status, TrackStatus.tracking);
    expect(heard[1].start, closeTo(2.4 - 0.1, 0.05), reason: 'seconds since listening began, padded');
    expect(events.last, isA<EngineDone>());
  });

  test('repeated text crosses the isolate as a tie: all the copies, trusted, held through a miss', () async {
    const refrain = 'فبأي آلاء ربكما تكذبان';
    final texts = [refrain, 'آمين', 'يسأله من في السماوات والأرض كل يوم هو في شأن'];
    final heard = (await run(engine(scripted(texts)), [
      for (var i = 0; i < texts.length; i++) ...[tone(1.6), silence(0.8)],
    ]))
        .whereType<Heard>()
        .toList();
    expect(heard[0].state.position, isNull);
    expect(heard[0].state.tied.length, 31);
    expect(heard[0].state.tied.every((p) => p.surah == 55), isTrue);
    expect(heard[0].state.tieTrusted, isTrue);
    expect(heard[1].state.evidence, isFalse);
    expect(heard[1].state.tied, heard[0].state.tied, reason: 'held through the miss');
    expect(heard[2].state.position, pos(55, 29));
    expect(heard[2].state.tied, isEmpty, reason: 'cleared once accepted');
  });

  test('a breath that matched no Quran arrives as a miss: the position held, no evidence', () async {
    // 93:2 and 93:3, then a breath of "āmīn", then 93:4. (93:1 is one word: itself a miss.)
    final texts = [duha[1], duha[2], 'آمين', duha[3]];
    final heard = (await run(engine(scripted(texts)), [
      for (var i = 0; i < texts.length; i++) ...[tone(1.6), silence(0.8)],
    ]))
        .whereType<Heard>()
        .toList();
    expect([for (final h in heard) h.state.evidence], [true, true, false, true]);
    expect(heard[2].state.position, heard[1].state.position);
    expect(heard[2].state.status, TrackStatus.uncertain);
    expect(heard[3].state.status, TrackStatus.tracking);
  });

  test('partials preview the breath under way; only finals commit', () async {
    final texts = <String>[];
    for (final t in duha) {
      final words = t.split(' ');
      texts
        ..add(words.take(2).join(' '))
        ..add(t);
    }
    final events = await run(
      engine(scripted(texts), config: const ListenerConfig(partialEvery: 0.5, minPartial: 0.6)),
      [
        for (var i = 0; i < 5; i++) ...[tone(1.6), silence(0.8)]
      ],
      pace: const Duration(milliseconds: 30), // a microphone delivers audio over time
    );
    final heard = events.whereType<Heard>().toList();
    expect(heard.where((h) => !h.isFinal), isNotEmpty);
    expect(heard.where((h) => h.isFinal), hasLength(5));
    expect(heard.last.state.position?.surah, 93);
  });

  test('the user\'s lock and "the imam is here" reach the tracker, in order', () async {
    final events = await run(
      engine(scripted(['فبأي آلاء ربكما تكذبان', 'فبأي آلاء ربكما تكذبان'])),
      [tone(1.6), silence(0.8), tone(1.6), silence(0.8)],
      before: (e) {
        e.setPosition(quran.verseId(55, 13)!);
        e.lock(const SurahHint(55));
      },
    );
    final heard = events.whereType<Heard>().toList();
    expect(heard.first.state.position, pos(55, 13), reason: 'shown at once, before any audio');
    expect(heard.first.state.confidence, 1);
    expect(heard.skip(1).every((h) => h.state.showing?.surah == 55), isTrue, reason: 'the refrain stays in Ar-Rahman');
  });

  test('a slow phone falls behind: old audio is dropped, and it says so', () async {
    final events = await run(
      engine(
        scripted([...duha, ...duha, ...duha], delay: const Duration(milliseconds: 400)),
        config: const ListenerConfig(partialEvery: 0),
      ),
      [
        for (var i = 0; i < 12; i++) ...[tone(1.6), silence(0.8)]
      ],
    );
    // 29 s of audio sent at once; at most 15 s are kept waiting.
    expect(events.whereType<EngineWarning>().map((w) => w.skippedSeconds), everyElement(greaterThan(0)));
    expect(events.whereType<EngineWarning>(), isNotEmpty);
    expect(events.last, isA<EngineDone>());
  });

  test('no model in this build, a model that cannot be copied, one that cannot load', () async {
    Future<EngineFailure> failure(OnDeviceRecognitionEngine e) async {
      final first = e.events.firstWhere((x) => x is EngineFailure);
      await e.start();
      final f = await first.timeout(const Duration(seconds: 10)) as EngineFailure;
      await e.dispose();
      return f;
    }

    final missing =
        await failure(OnDeviceRecognitionEngine(quran: quran, prepare: () async => throw const ModelMissing()));
    expect(missing.kind, FailureKind.missingModel);
    final full = await failure(OnDeviceRecognitionEngine(
      quran: quran,
      prepare: () async => throw const FileSystemExceptionLike('No space left on device'),
    ));
    expect(full.kind, FailureKind.model);
    final broken = await failure(engine(scripted(const [], failToLoad: true)));
    expect(broken.kind, FailureKind.model);
    expect(broken.message, contains('out of memory'));
  });

  test('cancel stops at once; nothing arrives after it', () async {
    final e = engine(scripted(duha, delay: const Duration(milliseconds: 200)));
    final events = <RecognitionEvent>[];
    e.events.listen(events.add);
    await e.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final block in duhaBreaths()) {
      e.addAudio(block);
    }
    await e.cancel();
    final count = events.length;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(events.length, count);
    await e.dispose();
  });

  group('the listener on a phone', () {
    final index = indexOf(quran);

    test('partials stop while transcription is slow, and come back when it is not', () {
      var clock = 0;
      var cost = 0; // microseconds each transcription takes
      final listener = Listener(
        Segmenter(EnergyVad()),
        (audio) {
          clock += cost;
          return duha.first;
        },
        Tracker(QuranMatcher(index)),
        nowMicros: () => clock,
      );
      // A long breath (no pause yet): partials every half second of audio.
      int partials(double seconds) {
        var n = 0;
        final audio = tone(seconds);
        for (var i = 0; i < audio.length; i += 4000) {
          n += listener.feed(Float32List.sublistView(audio, i, math.min(i + 4000, audio.length))).length;
        }
        return n;
      }

      cost = 100000; // 0.1 s per transcription: plenty of headroom
      expect(partials(4), greaterThan(3));
      listener.feed(silence(1));
      cost = 400000; // 0.4 s: still under half the audio, but each one waits 0.8 s
      expect(partials(4), inInclusiveRange(3, 5), reason: 'at most half the time on partials');
      expect(listener.partialsOn, isTrue);
      listener.feed(silence(1)); // end of the breath (a final)
      cost = 4000000; // 4 s each: slower than the audio itself
      partials(3);
      listener.feed(silence(1));
      expect(listener.load, greaterThan(0.5));
      expect(listener.partialsOn, isFalse);
      expect(partials(3), 0, reason: 'finals only while the phone is slow');
    });
  });

  group('which engine', () {
    Future<ProviderContainer> container(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final p = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        quranProvider.overrideWithValue(quran),
        settingsStoreProvider.overrideWithValue(SettingsStore(p)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('on the phone by default; the server only when the developer setting says so', () async {
      final onPhone = (await container({})).read(engineFactoryProvider)('10.0.2.2:8765');
      expect(onPhone, isA<OnDeviceRecognitionEngine>());
      await onPhone.dispose();
      final server = (await container({'recognition_server': true})).read(engineFactoryProvider)('10.0.2.2:8765');
      expect(server, isA<ServerRecognitionEngine>());
      await server.dispose();
    });
  });
}

class FileSystemExceptionLike implements Exception {
  const FileSystemExceptionLike(this.message);
  final String message;

  @override
  String toString() => message;
}
