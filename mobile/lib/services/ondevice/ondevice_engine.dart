import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import '../../core/audio/pcm.dart';
import '../../core/engine/listener.dart';
import '../../core/engine/matcher.dart';
import '../../core/engine/quran_index.dart';
import '../../core/engine/segmenter.dart';
import '../../core/engine/tracker.dart';
import '../../core/engine/word_follower.dart';
import '../../core/recognition/models.dart';
import '../../core/recognition/recognition_engine.dart';
import '../../data/quran.dart';
import 'model_store.dart' show ModelMissing;

/// A loaded speech model, inside the worker isolate.
typedef LoadedTranscriber = ({Transcribe transcribe, void Function() dispose, String device});

/// Loads the speech model; called inside the worker isolate (it must not
/// capture anything that cannot be sent there).
typedef TranscriberLoader = LoadedTranscriber Function();

/// Recognition on the phone itself: no server, no network.
///
/// The microphone's audio goes to a background isolate that runs the whole
/// pipeline (the Dart port of the engine): segmenter -> speech model ->
/// tracker. The UI isolate only batches audio and turns results into
/// [RecognitionEvent]s, so following never makes the reader stutter.
///
/// If transcription falls behind, the worker merges all the audio waiting
/// and transcribes only *now*; past [maxBacklog] the oldest is dropped. A slow
/// phone updates less often, but never shows the imam where he was a minute
/// ago.
class OnDeviceRecognitionEngine implements RecognitionEngine {
  OnDeviceRecognitionEngine({
    required this.quran,
    required this.prepare,
    this.listenerConfig = const ListenerConfig(),
    this.maxBacklog = const Duration(seconds: 15),
    this.readyTimeout = const Duration(seconds: 90),
    this.finishTimeout = const Duration(seconds: 20),
    this.maxBufferedSeconds = 2,
    this.wordTracking = false,
  });

  final Quran quran;

  /// Also follow the imam word by word (developer setting, off by default).
  /// Off, the worker creates no word tracker at all.
  final bool wordTracking;

  /// Makes the model ready (copies it out of the bundle the first time) and
  /// returns its loader. Throws if there is no model to load.
  final Future<TranscriberLoader> Function() prepare;
  final ListenerConfig listenerConfig;
  final Duration maxBacklog;
  final Duration readyTimeout;
  final Duration finishTimeout;
  final int maxBufferedSeconds;

  final _events = StreamController<RecognitionEvent>.broadcast();
  final _batcher = FrameBatcher();
  ReceivePort? _inbox;
  SendPort? _worker;
  Timer? _readyTimer;
  Completer<void>? _done;
  Hint? _lock;
  int? _pendingPosition;
  bool _active = false;
  bool _finishing = false;
  bool _ready = false;

  @override
  Stream<RecognitionEvent> get events => _events.stream;

  @override
  Future<void> start({Hint? hint}) async {
    if (_active) return;
    _active = true;
    final TranscriberLoader loader;
    try {
      loader = await prepare();
    } on ModelMissing catch (e) {
      _fail('$e', FailureKind.missingModel);
      return;
    } catch (e) {
      _fail('$e', FailureKind.model);
      return;
    }
    if (!_active) return;
    final inbox = ReceivePort();
    _inbox = inbox;
    inbox.listen(_onMessage);
    _readyTimer = Timer(readyTimeout, () {
      if (!_ready && _active) _fail('The speech model did not load in time.', FailureKind.model);
    });
    try {
      await Isolate.spawn(
        _workerMain,
        _WorkerSetup(
          reply: inbox.sendPort,
          verses: [for (final v in quran.verses) v.text],
          hint: _range(hint),
          lock: _range(_lock),
          load: loader,
          config: listenerConfig,
          maxBacklogSamples: maxBacklog.inMilliseconds * sampleRate ~/ 1000,
          basmalaVerses: wordTracking
              ? [
                  for (final s in quran.surahs)
                    if (s.hasBasmala) s.firstVerseId
                ]
              : null,
        ),
        debugName: 'recognition',
      );
    } catch (e) {
      _fail('$e', FailureKind.model);
    }
  }

  /// A hint's verse range (first, last).
  (int, int)? _range(Hint? scope) => switch (scope) {
        SurahHint(:final surah) => (quran.surah(surah).firstVerseId, quran.surah(surah).lastVerseId),
        SurahRange(:final first, :final last) => (quran.surah(first).firstVerseId, quran.surah(last).lastVerseId),
        JuzHint(:final juz) => (quran.juzs.start(juz), quran.juzs.end(juz)),
        null => null,
      };

  @override
  void addAudio(Float32List samples) {
    if (!_active || _finishing) return;
    _batcher.add(samples);
    if (_ready) {
      final frame = _batcher.takeFrame();
      if (frame != null) _worker!.send(frame);
    } else {
      _batcher.trimTo(maxBufferedSeconds * sampleRate);
    }
  }

  @override
  void lock(Hint? scope) {
    _lock = scope;
    if (_ready) _worker!.send(_Control.lock(_range(scope)));
  }

  @override
  void setPosition(int verseId) {
    if (_ready) {
      _worker!.send(_Control.position(verseId));
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
      if (rest.isNotEmpty) _worker!.send(rest);
      _done = Completer<void>();
      _worker!.send(const _Control.end());
      await _done!.future.timeout(finishTimeout, onTimeout: () {});
    } else {
      _emit(const EngineDone());
    }
    await cancel();
  }

  @override
  Future<void> cancel() async {
    _active = false;
    _ready = false;
    _readyTimer?.cancel();
    // The worker frees the model and exits after what it is doing now.
    _worker?.send(const _Control.stop());
    _worker = null;
    _inbox?.close();
    _inbox = null;
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _events.close();
  }

  void _onMessage(Object? message) {
    if (!_active && message is! _Done) return;
    switch (message) {
      case final SendPort port:
        _worker = port;
      case _Ready(:final device):
        _readyTimer?.cancel();
        _ready = true;
        _emit(EngineReady(device: device));
        if (_lock != null) _worker!.send(_Control.lock(_range(_lock)));
        if (_pendingPosition != null) {
          _worker!.send(_Control.position(_pendingPosition!));
          _pendingPosition = null;
        }
        final frame = _batcher.takeAll(); // audio captured while loading
        if (frame.isNotEmpty) _worker!.send(frame);
      case final _Heard heard:
        _emit(Heard(
          text: heard.text,
          start: heard.start,
          end: heard.end,
          asrMs: heard.asrMs,
          state: _state(heard),
          isFinal: heard.isFinal,
          word: heard.wordVerse == null ? null : HeardWord(verseId: heard.wordVerse!, index: heard.wordIndex!),
        ));
      case _Skipped(:final seconds):
        _emit(EngineWarning.fellBehind(seconds));
      case _Failed(:final message):
        _fail(message, FailureKind.model);
      case _Done():
        _emit(const EngineDone());
        _done?.complete();
    }
  }

  Position? _position(int? verseId) {
    if (verseId == null) return null;
    final v = quran.verse(verseId);
    return Position(verseId: verseId, surah: v.surah, ayah: v.ayah);
  }

  TrackState _state(_Heard h) => TrackState(
        position: _position(h.verseId),
        status: TrackStatus.values[h.status],
        confidence: h.confidence.clamp(0, 1).toDouble(),
        pending: _position(h.pending),
        alternatives: [for (final a in h.alternatives) _position(a)!],
        upcoming: _position(h.upcoming),
        evidence: h.evidence,
      );

  void _fail(String message, FailureKind kind) {
    _emit(EngineFailure(message, kind: kind));
    unawaited(cancel());
  }

  void _emit(RecognitionEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

// -- messages between the UI isolate and the worker ---------------------------

class _WorkerSetup {
  const _WorkerSetup({
    required this.reply,
    required this.verses,
    required this.hint,
    required this.lock,
    required this.load,
    required this.config,
    required this.maxBacklogSamples,
    this.basmalaVerses,
  });

  final SendPort reply;
  final List<String> verses;
  final (int, int)? hint;
  final (int, int)? lock;
  final TranscriberLoader load;
  final ListenerConfig config;
  final int maxBacklogSamples;

  /// Set only when word tracking is on: the ayahs a basmala is recited before.
  final List<int>? basmalaVerses;
}

class _Control {
  const _Control.lock(this.range)
      : kind = 'lock',
        verseId = null;
  const _Control.position(int this.verseId)
      : kind = 'position',
        range = null;
  const _Control.end()
      : kind = 'end',
        range = null,
        verseId = null;
  const _Control.stop()
      : kind = 'stop',
        range = null,
        verseId = null;

  final String kind;
  final (int, int)? range;
  final int? verseId;
}

class _Ready {
  const _Ready(this.device);
  final String device;
}

class _Heard {
  const _Heard({
    required this.text,
    required this.start,
    required this.end,
    required this.asrMs,
    required this.isFinal,
    required this.verseId,
    required this.status,
    required this.confidence,
    required this.pending,
    required this.alternatives,
    required this.upcoming,
    required this.evidence,
    this.wordVerse,
    this.wordIndex,
  });

  factory _Heard.of(HeardChunk h, [FollowedWord? word]) => _Heard(
        wordVerse: word?.verseId,
        wordIndex: word?.index,
        text: h.text,
        start: h.start,
        end: h.end,
        asrMs: h.asrMs,
        isFinal: h.isFinal,
        verseId: h.state.verseId,
        status: h.state.status.index,
        confidence: h.state.confidence,
        pending: h.state.pendingVerse,
        alternatives: h.state.alternatives,
        upcoming: h.state.upcomingVerse,
        evidence: h.state.evidence,
      );

  final String text;
  final double start;
  final double end;
  final int asrMs;
  final bool isFinal;
  final int? verseId;
  final int status; // TrackerStatus and TrackStatus share their order
  final double confidence;
  final int? pending;
  final List<int> alternatives;
  final int? upcoming;
  final bool evidence;
  final int? wordVerse;
  final int? wordIndex;
}

class _Skipped {
  const _Skipped(this.seconds);
  final double seconds;
}

class _Failed {
  const _Failed(this.message);
  final String message;
}

class _Done {
  const _Done();
}

// -- the worker isolate ---------------------------------------------------

Future<void> _workerMain(_WorkerSetup setup) async {
  final reply = setup.reply;
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  final queue = Queue<Object?>();
  Completer<void>? wake;
  inbox.listen((message) {
    queue.add(message);
    wake?.complete();
    wake = null;
  });

  LoadedTranscriber? model;
  try {
    model = setup.load();
    model.transcribe(Float32List(engineSampleRate)); // the first decode allocates its buffers
  } catch (e) {
    reply.send(_Failed('$e'));
    model?.dispose();
    inbox.close();
    return;
  }
  final index = QuranIndex(setup.verses);
  final tracker = Tracker(QuranMatcher(index));
  if (setup.hint case final (int, int) h) tracker.hint(h.$1, h.$2);
  if (setup.lock case final (int, int) l) tracker.lock(l.$1, l.$2);
  final listener = Listener(Segmenter(EnergyVad()), model.transcribe, tracker, config: setup.config);
  // Word tracking (developer setting): next to the ayah tracker, never in its
  // way. It costs well under a millisecond a transcript; if it ever fails,
  // it is switched off for the session and the ayahs carry on alone.
  var words = setup.basmalaVerses == null ? null : WordFollower(index, basmalaVerses: setup.basmalaVerses!);
  FollowedWord? follow(HeardChunk h) {
    final w = words;
    if (w == null) return null;
    try {
      return w.onChunk(text: h.text, isFinal: h.isFinal, start: h.start, end: h.end, ayah: h.state);
    } catch (_) {
      words = null;
      return null;
    }
  }

  reply.send(_Ready(model.device));

  try {
    while (true) {
      if (queue.isEmpty) {
        final waiting = wake = Completer<void>();
        await waiting.future;
      }
      final item = queue.removeFirst();
      switch (item) {
        case final Float32List audio:
          // Everything that arrived while the last transcription ran, as one
          // block: the next result is about now.
          final blocks = [audio];
          var length = audio.length;
          while (queue.isNotEmpty && queue.first is Float32List) {
            final next = queue.removeFirst()! as Float32List;
            blocks.add(next);
            length += next.length;
          }
          var merged = Float32List(length);
          var offset = 0;
          for (final b in blocks) {
            merged.setAll(offset, b);
            offset += b.length;
          }
          if (merged.length > setup.maxBacklogSamples) {
            final dropped = merged.length - setup.maxBacklogSamples;
            merged = Float32List.sublistView(merged, dropped);
            listener.skip(dropped);
            words?.skipped();
            reply.send(_Skipped(dropped / engineSampleRate));
          }
          for (final h in listener.feed(merged)) {
            reply.send(_Heard.of(h, follow(h)));
          }
        case _Control(kind: 'lock', :final range):
          tracker.lock(range?.$1, range?.$2);
        case _Control(kind: 'position', :final verseId):
          final state = tracker.setPosition(verseId!);
          try {
            words?.setPosition(verseId);
          } catch (_) {
            words = null;
          }
          reply.send(_Heard.of(HeardChunk(text: '', start: 0, end: 0, asrMs: 0, state: state, isFinal: true)));
        case _Control(kind: 'end'):
          for (final h in listener.flush()) {
            reply.send(_Heard.of(h, follow(h)));
          }
          reply.send(const _Done());
        case _Control(kind: 'stop'):
          return;
      }
      // Let the messages that arrived meanwhile reach the queue.
      await Future<void>.delayed(Duration.zero);
    }
  } catch (e) {
    reply.send(_Failed('$e'));
  } finally {
    model.dispose();
    inbox.close();
  }
}
