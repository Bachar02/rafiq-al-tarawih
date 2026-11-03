/// ServerRecognitionEngine against a real WebSocket server in the test process:
/// real sockets, real framing, real disconnects. No mocks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/services/server_recognition_engine.dart';

const heardJson = '{"type":"heard","text":"والضحى","start":0,"end":1.5,"asr_ms":120,'
    '"state":{"position":{"verse_id":6092,"surah":93,"ayah":2},"status":"tracking","confidence":0.9}}';

/// A scriptable stand-in for the Rafiq server.
class FakeServer {
  FakeServer._(this._http);

  final HttpServer _http;
  final connections = <WebSocket>[];
  final requests = <Uri>[];
  final receivedSamples = <int>[]; // samples per binary frame
  final textMessages = <String>[];

  /// Called for each new connection; default: say ready.
  void Function(WebSocket ws, int index) onConnect = (ws, _) => ws.add('{"type":"ready","device":"cpu"}');

  /// Called for each "end" message; default: done + close.
  void Function(WebSocket ws) onEnd = (ws) {
    ws.add('{"type":"done"}');
    ws.close();
  };

  String get address => '127.0.0.1:${_http.port}';

  static Future<FakeServer> start() async {
    final server = FakeServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    server._http.listen((req) async {
      server.requests.add(req.uri);
      final ws = await WebSocketTransformer.upgrade(req);
      server.connections.add(ws);
      ws.listen((data) {
        if (data is List<int>) {
          server.receivedSamples.add(data.length ~/ 4);
        } else if (data is String) {
          server.textMessages.add(data);
          if ((jsonDecode(data) as Map<String, dynamic>)['type'] == 'end') server.onEnd(ws);
        }
      });
      server.onConnect(ws, server.connections.length - 1);
    });
    return server;
  }

  Future<void> dropAll() async {
    for (final ws in connections) {
      await ws.close(WebSocketStatus.goingAway);
    }
  }

  Future<void> close() => _http.close(force: true);
}

ServerRecognitionEngine engineFor(String address) => ServerRecognitionEngine(
      address,
      backoff: (_) => const Duration(milliseconds: 20),
      connectTimeout: const Duration(seconds: 2),
      finishTimeout: const Duration(seconds: 2),
    );

Future<T> next<T extends RecognitionEvent>(Stream<RecognitionEvent> events) =>
    events.firstWhere((e) => e is T).then((e) => e as T).timeout(const Duration(seconds: 5));

void main() {
  late FakeServer server;
  setUp(() async => server = await FakeServer.start());
  tearDown(() => server.close());

  test('handshake, audio in ~250 ms frames, results out', () async {
    server.onConnect = (ws, _) => ws.add('{"type":"ready","device":"cuda"}');
    final engine = engineFor(server.address);
    final events = engine.events.asBroadcastStream();
    final ready = next<EngineReady>(events);
    await engine.start(hint: const SurahHint(93));
    expect((await ready).device, 'cuda');
    expect(server.requests.single.path, '/ws/listen');
    expect(server.requests.single.queryParameters, {'surah': '93'});

    for (var i = 0; i < 10; i++) {
      engine.addAudio(Float32List(1600)); // 100 ms blocks, like a microphone
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.receivedSamples, isNotEmpty);
    expect(server.receivedSamples.every((n) => n >= 4000), isTrue); // batched, not 100 ms dribbles

    final heard = next<Heard>(events);
    server.connections.single.add(heardJson);
    expect((await heard).state.position!.ref, '93:2');
    await engine.dispose();
  });

  test('finish flushes the tail, sends end, waits for done', () async {
    final engine = engineFor(server.address);
    final events = engine.events.asBroadcastStream();
    final ready = next<EngineReady>(events);
    await engine.start();
    await ready;
    engine.addAudio(Float32List(1000)); // less than a frame: held back...
    final done = next<EngineDone>(events);
    await engine.finish(); // ...and flushed here
    await done;
    expect(server.receivedSamples.last, 1000);
    expect(server.textMessages, ['{"type":"end"}']);
    await engine.dispose();
  });

  test('a dropped connection reconnects and keeps only recent audio', () async {
    final engine = engineFor(server.address);
    final events = engine.events.asBroadcastStream();
    final ready = next<EngineReady>(events);
    await engine.start();
    await ready;

    final reconnecting = next<EngineReconnecting>(events);
    await server.dropAll();
    expect((await reconnecting).attempt, 1);

    // While down: 5 s of audio arrives, only the newest 2 s may be kept.
    server.onConnect = (ws, _) {}; // hold "ready" back for a moment
    for (var i = 0; i < 50; i++) {
      engine.addAudio(Float32List(1600));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.connections, hasLength(2));
    final readyAgain = next<EngineReady>(events);
    server.connections.last.add('{"type":"ready"}');
    await readyAgain;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.receivedSamples.single, lessThanOrEqualTo(2 * 16000));
    await engine.dispose();
  });

  test('an unreachable server fails clearly after a few attempts', () async {
    final address = server.address;
    await server.close();
    // Windows takes ~2 s to refuse a closed localhost port (phones refuse instantly).
    final engine = ServerRecognitionEngine(
      address,
      backoff: (_) => const Duration(milliseconds: 20),
      connectTimeout: const Duration(milliseconds: 400),
    );
    final failure = next<EngineFailure>(engine.events);
    await engine.start();
    final f = await failure;
    expect(f.kind, FailureKind.unreachable);
    expect(f.message, contains(address));
    await engine.dispose();
  });

  test('a server error is final: no reconnect loop', () async {
    server.onConnect = (ws, _) => ws
      ..add('{"type":"error","message":"could not load the speech model"}')
      ..close();
    final engine = engineFor(server.address);
    final failure = next<EngineFailure>(engine.events);
    await engine.start();
    expect((await failure).kind, FailureKind.server);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.connections, hasLength(1));
    await engine.dispose();
  });

  test('a server that never gets ready times out with a clear message', () async {
    server.onConnect = (ws, _) {}; // connected, but silent
    final engine = ServerRecognitionEngine(server.address, readyTimeout: const Duration(milliseconds: 200));
    final failure = next<EngineFailure>(engine.events);
    await engine.start();
    expect((await failure).message, contains('did not get ready'));
    await engine.dispose();
  });

  test('cancel stops everything immediately', () async {
    final engine = engineFor(server.address);
    final events = engine.events.asBroadcastStream();
    final ready = next<EngineReady>(events);
    await engine.start();
    await ready;
    await engine.cancel();
    engine.addAudio(Float32List(8000)); // ignored after cancel
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.receivedSamples, isEmpty);
    await engine.dispose();
  });

  test('the lock is re-sent after a reconnect; a position made offline is delivered', () async {
    final engine = engineFor(server.address);
    final events = engine.events.asBroadcastStream();
    final ready = next<EngineReady>(events);
    engine.lock(const SurahHint(55)); // before connecting: remembered
    await engine.start();
    await ready;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.textMessages, ['{"type":"lock","surah":55}']);

    final reconnecting = next<EngineReconnecting>(events);
    await server.dropAll();
    await reconnecting;
    engine.setPosition(4927); // while disconnected
    final readyAgain = next<EngineReady>(events);
    await readyAgain;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.textMessages.skip(1), ['{"type":"lock","surah":55}', '{"type":"position","verse_id":4927}']);

    engine.lock(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.textMessages.last, '{"type":"unlock"}');
    await engine.dispose();
  });
}
