import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/audio/pcm.dart';
import '../core/backoff.dart';
import '../core/recognition/endpoint.dart';
import '../core/recognition/models.dart';
import '../core/recognition/protocol.dart';
import '../core/recognition/recognition_engine.dart';

typedef ChannelConnector = WebSocketChannel Function(Uri uri);

/// Recognition on the laptop server, over `/ws/listen`.
///
/// Connection policy:
/// * Before the first successful session, give up after [maxInitialAttempts]
///   and report the server as unreachable (the user probably typed a wrong
///   address or the server is not running).
/// * Once it has worked, reconnect forever while the user is listening,
///   with exponential backoff; the microphone keeps running meanwhile and
///   only the newest [maxBufferedSeconds] of audio is kept.
/// * The first connection may wait up to [readyTimeout] for the server to
///   load its speech model (it downloads it on first use).
class ServerRecognitionEngine implements RecognitionEngine {
  ServerRecognitionEngine(
    this.address, {
    ChannelConnector? connect,
    this.connectTimeout = const Duration(seconds: 5),
    this.readyTimeout = const Duration(seconds: 90),
    this.finishTimeout = const Duration(seconds: 8),
    this.maxInitialAttempts = 3,
    this.maxBufferedSeconds = 2,
    Duration Function(int attempt) backoff = backoffDelay,
  })  : _connect = connect ?? WebSocketChannel.connect,
        _backoff = backoff;

  /// Server address as the user typed it (see endpoint.dart).
  final String address;
  final Duration connectTimeout;
  final Duration readyTimeout;
  final Duration finishTimeout;
  final int maxInitialAttempts;
  final int maxBufferedSeconds;
  final ChannelConnector _connect;
  final Duration Function(int) _backoff;

  final _events = StreamController<RecognitionEvent>.broadcast();
  final _batcher = FrameBatcher();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _readyTimer;
  Completer<void>? _done;
  Hint? _hint;
  Hint? _lock; // re-sent after every (re)connect: each server session starts fresh
  int? _pendingPosition; // a "the imam is here" made while not connected

  bool _active = false; // between start() and finish()/cancel()
  bool _finishing = false;
  bool _ready = false;
  bool _everReady = false;
  int _attempt = 0;

  @override
  Stream<RecognitionEvent> get events => _events.stream;

  @override
  Future<void> start({Hint? hint}) async {
    if (_active) return;
    _active = true;
    _hint = hint;
    await _open();
  }

  @override
  void addAudio(Float32List samples) {
    if (!_active || _finishing) return;
    _batcher.add(samples);
    if (_ready) {
      final frame = _batcher.takeFrame();
      if (frame != null) _send(encodeAudioFrame(frame));
    } else {
      _batcher.trimTo(maxBufferedSeconds * sampleRate);
    }
  }

  @override
  void lock(Hint? scope) {
    _lock = scope;
    if (_ready) _send(lockMessage(scope));
  }

  @override
  void setPosition(int verseId) {
    if (_ready) {
      _send(positionMessage(verseId));
    } else {
      _pendingPosition = verseId;
    }
  }

  @override
  Future<void> finish() async {
    if (!_active || _finishing) return;
    _finishing = true;
    if (_ready) {
      final rest = _batcher.takeAll();
      if (rest.isNotEmpty) _send(encodeAudioFrame(rest));
      _done = Completer<void>();
      _send(endOfStreamMessage);
      await _done!.future.timeout(finishTimeout, onTimeout: () {});
    } else {
      _emit(const EngineDone());
    }
    await cancel();
  }

  @override
  Future<void> cancel() async {
    _active = false;
    _retryTimer?.cancel();
    _readyTimer?.cancel();
    await _closeChannel();
  }

  // -- connection ---------------------------------------------------------

  Future<void> _open() async {
    if (!_active) return;
    final uri = listenUri(address, hint: _hint);
    final channel = _connect(uri);
    try {
      await channel.ready.timeout(connectTimeout);
    } catch (_) {
      unawaited(channel.sink.close().catchError((_) {}));
      _onClosed();
      return;
    }
    if (!_active) {
      unawaited(channel.sink.close());
      return;
    }
    _channel = channel;
    _subscription = channel.stream.listen(
      _onMessage,
      onDone: _onClosed,
      onError: (Object _) => _onClosed(),
      cancelOnError: true,
    );
    _readyTimer = Timer(readyTimeout, () {
      if (!_ready && _active) {
        _fail('The server did not get ready in time (is the speech model installed?)', FailureKind.server);
      }
    });
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    final event = decodeServerMessage(message);
    switch (event) {
      case null:
        return;
      case EngineReady():
        _readyTimer?.cancel();
        _ready = true;
        _everReady = true;
        _attempt = 0;
        _emit(event);
        if (_lock != null) _send(lockMessage(_lock));
        if (_pendingPosition != null) {
          _send(positionMessage(_pendingPosition!));
          _pendingPosition = null;
        }
        final frame = _batcher.takeAll(); // audio captured while connecting
        if (frame.isNotEmpty) _send(encodeAudioFrame(frame));
      case EngineFailure():
        _fail(event.message, event.kind);
      case EngineDone():
        _emit(event);
        _done?.complete();
      default:
        _emit(event);
    }
  }

  void _onClosed() {
    final wasReady = _ready;
    _ready = false;
    _readyTimer?.cancel();
    _channel = null;
    _subscription = null;
    if (!_active) return;
    if (_finishing) {
      if (!(_done?.isCompleted ?? true)) _done!.complete();
      return;
    }
    _attempt += 1;
    if (!_everReady && _attempt >= maxInitialAttempts) {
      _fail('Cannot reach the recognition server at $address', FailureKind.unreachable);
      return;
    }
    final delay = _backoff(_attempt);
    if (wasReady || _everReady) {
      _emit(EngineReconnecting(attempt: _attempt, delay: delay));
    }
    _retryTimer = Timer(delay, _open);
  }

  void _fail(String message, FailureKind kind) {
    _emit(EngineFailure(message, kind: kind));
    _active = false;
    _retryTimer?.cancel();
    _readyTimer?.cancel();
    unawaited(_closeChannel());
  }

  Future<void> _closeChannel() async {
    final subscription = _subscription, channel = _channel;
    _subscription = null;
    _channel = null;
    _ready = false;
    await subscription?.cancel();
    await channel?.sink.close().catchError((_) {});
  }

  void _send(Object data) {
    try {
      _channel?.sink.add(data);
    } catch (_) {
      // The socket is closing; _onClosed will reconnect.
    }
  }

  void _emit(RecognitionEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _events.close();
  }
}
