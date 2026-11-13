import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/core/recognition/protocol.dart';

void main() {
  group('decodeServerMessage', () {
    test('ready, with and without device', () {
      expect((decodeServerMessage('{"type":"ready","device":"cuda"}')! as EngineReady).device, 'cuda');
      expect((decodeServerMessage('{"type":"ready"}')! as EngineReady).device, isNull);
    });

    test('heard carries the full tracker state', () {
      const raw = '''
      {"type":"heard","text":"وَالضُّحَى","start":0.4,"end":2.1,"asr_ms":180,
       "state":{"position":{"verse_id":6092,"surah":93,"ayah":2,"ref":"93:2"},
                "status":"tracking","confidence":0.93,"pending":null,
                "alternatives":[{"verse_id":10,"surah":2,"ayah":3,"ref":"2:3"}],
                "upcoming":{"verse_id":6093,"surah":93,"ayah":3,"ref":"93:3"},
                "candidates":[]}}''';
      final heard = decodeServerMessage(raw)! as Heard;
      expect(heard.isFinal, isTrue);
      expect(heard.text, 'وَالضُّحَى');
      expect(heard.asrMs, 180);
      expect(heard.state.position!.ref, '93:2');
      expect(heard.state.status, TrackStatus.tracking);
      expect(heard.state.confidence, closeTo(0.93, 1e-9));
      expect(heard.state.alternatives.single.ref, '2:3');
      expect(heard.state.showing!.ref, '93:3'); // upcoming wins for the screen
    });

    test('evidence: a miss says so; a server that does not say counts as evidence', () {
      TrackState state(String extra) => (decodeServerMessage(
                  '{"type":"heard","text":"x","start":0,"end":1,"asr_ms":1,"state":{"status":"uncertain"$extra}}')!
              as Heard)
          .state;
      expect(state(',"evidence":false').evidence, isFalse);
      expect(state(',"evidence":true').evidence, isTrue);
      expect(state('').evidence, isTrue);
      expect(state(',"evidence":"no"').evidence, isTrue);
    });

    test('partial is a non-final heard', () {
      const raw =
          '{"type":"partial","text":"x","start":0,"end":1,"asr_ms":1,"state":{"position":null,"status":"idle"}}';
      final heard = decodeServerMessage(raw)! as Heard;
      expect(heard.isFinal, isFalse);
      expect(heard.state.position, isNull);
      expect(heard.state.showing, isNull);
    });

    test('warning, error, done', () {
      expect(
          (decodeServerMessage('{"type":"warning","message":"skipped 2 s"}')! as EngineWarning).message, 'skipped 2 s');
      final failure = decodeServerMessage('{"type":"error","message":"model failed"}')! as EngineFailure;
      expect(failure.message, 'model failed');
      expect(failure.kind, FailureKind.server);
      expect(decodeServerMessage('{"type":"done"}'), isA<EngineDone>());
    });

    test('is lenient: unknown types, junk and malformed fields are ignored', () {
      expect(decodeServerMessage('{"type":"from_the_future"}'), isNull);
      expect(decodeServerMessage('not json'), isNull);
      expect(decodeServerMessage('[1,2]'), isNull);
      expect(decodeServerMessage('{"type":"heard"}'), isNull); // no state
      const odd = '{"type":"heard","state":{"position":{"surah":"93"},"status":"weird","confidence":7}}';
      final heard = decodeServerMessage(odd)! as Heard;
      expect(heard.state.position, isNull);
      expect(heard.state.status, TrackStatus.idle);
      expect(heard.state.confidence, 1.0); // clamped
    });
  });

  test('audio frames are float32 little-endian', () {
    final bytes = encodeAudioFrame(Float32List.fromList([0.5, -1.0]));
    final data = ByteData.sublistView(bytes);
    expect(bytes.length, 8);
    expect(data.getFloat32(0, Endian.little), 0.5);
    expect(data.getFloat32(4, Endian.little), -1.0);
  });

  test('hint query', () {
    expect(hintQuery(null), '');
    expect(hintQuery(const SurahHint(55)), '?surah=55');
    expect(hintQuery(const JuzHint(30)), '?juz=30');
  });

  test('control messages', () {
    expect(lockMessage(const SurahHint(55)), '{"type":"lock","surah":55}');
    expect(lockMessage(const JuzHint(30)), '{"type":"lock","juz":30}');
    expect(lockMessage(null), '{"type":"unlock"}');
    expect(positionMessage(4927), '{"type":"position","verse_id":4927}');
    const ack = '{"type":"position","text":"","start":0,"end":0,"asr_ms":0,'
        '"state":{"position":{"verse_id":4927,"surah":55,"ayah":13},"status":"tracking","confidence":1}}';
    final heard = decodeServerMessage(ack)! as Heard;
    expect(heard.isFinal, isTrue);
    expect(heard.state.position!.ref, '55:13');
  });
}
