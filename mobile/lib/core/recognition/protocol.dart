/// The `/ws/listen` wire protocol (see server/src/rafiq_server/listen.py).
///
/// client -> server: binary float32 little-endian PCM, 16 kHz mono; text {"type": "end"}
/// server -> client: JSON ready / partial / heard / warning / done / error
///
/// Decoding is deliberately lenient: unknown message types and unknown fields
/// are ignored, so a newer server never breaks an older app.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

const endOfStreamMessage = '{"type":"end"}';

/// "The imam is in this surah/juz: never look elsewhere" (null: unlock).
String lockMessage(Hint? scope) => switch (scope) {
      SurahHint(:final surah) => jsonEncode({'type': 'lock', 'surah': surah}),
      JuzHint(:final juz) => jsonEncode({'type': 'lock', 'juz': juz}),
      null => jsonEncode({'type': 'unlock'}),
    };

/// "The imam is here."
String positionMessage(int verseId) => jsonEncode({'type': 'position', 'verse_id': verseId});

/// Query string for an optional hint, e.g. `?surah=55`.
String hintQuery(Hint? hint) => switch (hint) {
      SurahHint(:final surah) => '?surah=$surah',
      JuzHint(:final juz) => '?juz=$juz',
      null => '',
    };

/// Float32 samples -> little-endian bytes, whatever the host byte order.
Uint8List encodeAudioFrame(Float32List samples) {
  final data = ByteData(samples.length * 4);
  for (var i = 0; i < samples.length; i++) {
    data.setFloat32(i * 4, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

/// One server message -> event, or null if it is not one we understand.
RecognitionEvent? decodeServerMessage(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final message = decoded;

  switch (message['type']) {
    case 'ready':
      return EngineReady(device: message['device'] as String?);
    // "position" acknowledges the user's "the imam is here" with the new state.
    case 'heard' || 'partial' || 'position':
      final state = message['state'];
      if (state is! Map<String, dynamic>) return null;
      return Heard(
        text: (message['text'] as String?) ?? '',
        start: _num(message['start']),
        end: _num(message['end']),
        asrMs: _num(message['asr_ms']).round(),
        state: decodeTrackState(state),
        isFinal: message['type'] != 'partial',
      );
    case 'warning':
      return EngineWarning((message['message'] as String?) ?? 'warning');
    case 'error':
      return EngineFailure((message['message'] as String?) ?? 'server error');
    case 'done':
      return const EngineDone();
    default:
      return null;
  }
}

TrackState decodeTrackState(Map<String, dynamic> json) => TrackState(
      position: _position(json['position']),
      status: TrackStatus.parse(json['status'] as String?),
      confidence: _num(json['confidence']).clamp(0, 1).toDouble(),
      pending: _position(json['pending']),
      alternatives: ((json['alternatives'] as List?) ?? const []).map(_position).whereType<Position>().toList(),
      upcoming: _position(json['upcoming']),
      // A server from before the field: every result counted as evidence.
      evidence: json['evidence'] is bool ? json['evidence'] as bool : true,
    );

Position? _position(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final id = json['verse_id'], surah = json['surah'], ayah = json['ayah'];
  if (id is! int || surah is! int || ayah is! int) return null;
  return Position(verseId: id, surah: surah, ayah: ayah);
}

double _num(Object? value) => value is num ? value.toDouble() : 0;
