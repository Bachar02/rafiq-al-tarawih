import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/text/normalize.dart';
import '../../services/ondevice/model_store.dart';
import '../../services/ondevice/ondevice_transcriber.dart';

/// Phase 6 go/no-go: can this phone run the Quran speech model fast enough?
///
/// Downloads the model and validation clips from the dev server, transcribes
/// them on the phone with 2 and 4 threads, and reports speed and accuracy next
/// to the laptop server's numbers on the very same audio.
class AsrBenchScreen extends ConsumerStatefulWidget {
  const AsrBenchScreen({super.key});

  @override
  ConsumerState<AsrBenchScreen> createState() => _AsrBenchScreenState();
}

class _AsrBenchScreenState extends ConsumerState<AsrBenchScreen> {
  String _status = 'Downloads ~55 MB from your Rafiq server the first time (Wi-Fi recommended).';
  double? _progress;
  bool _busy = false;
  String? _report;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
      _report = null;
    });
    final address = ref.read(settingsProvider).serverAddress;
    final quran = ref.read(quranProvider);
    try {
      final store = await ModelStore.open();
      _set('Checking the server…');
      final manifest = await fetchManifest(address);
      if (!store.isInstalled) {
        await store.install(address, onProgress: (p) => _set('Downloading the speech model…', progress: p));
      }
      final clips = <(String, Float32List)>[];
      for (final (i, c) in manifest.clips.indexed) {
        _set('Downloading test audio ${i + 1}/${manifest.clips.length}…', progress: i / manifest.clips.length);
        clips.add((c.name, Float32List.fromList(await fetchClip(address, c.name))));
      }

      final lines = <String>[
        'Rafiq on-device speech benchmark',
        'Device: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}, ${Platform.numberOfProcessors} cores',
        'Model: ${ModelStore.model} int8 via sherpa-onnx (${(store.installedBytes / 1e6).round()} MB)',
        'Clips: ${clips.length} (6 reciters, clean + mosque echo)',
        '',
      ];
      int? bestShortMs;
      // (threads, trailing silence): fewer threads avoid the slow cores of
      // big.LITTLE phones; shorter padding is faster, slightly less accurate.
      const configs = [(1, 500), (2, 500), (2, 2000)];
      for (final (threads, padMs) in configs) {
        _set('Transcribing on the phone: $threads thread(s), ${padMs / 1000} s padding…', progress: null);
        final run = await runBenchmark(
          encoder: store.path(ModelStore.encoder),
          decoder: store.path(ModelStore.decoder),
          tokens: store.path(ModelStore.tokens),
          threads: threads,
          silencePad: Duration(milliseconds: padMs),
          clips: clips,
        );
        final byName = {for (final c in manifest.clips) c.name: c};
        final accs = <double>[], shortMs = <int>[], perSecond = <double>[];
        for (final r in run.results) {
          final clip = byName[r.name]!;
          accs.add(wordAccuracy(r.text, quran.verse(clip.verseId).text));
          if (clip.seconds <= 6.5) shortMs.add(r.ms);
          perSecond.add(r.ms / clip.seconds);
        }
        final short = median(shortMs.map((e) => e.toDouble()).toList()).round();
        bestShortMs = bestShortMs == null ? short : math.min(bestShortMs, short);
        lines.add('$threads thr, pad ${padMs / 1000}s: word accuracy ${(mean(accs) * 100).toStringAsFixed(1)}% | '
            'typical chunk (≤6.5 s) $short ms | ${median(perSecond).round()} ms per audio second | '
            'model load ${run.loadMs} ms');
      }
      final serverShort =
          median(manifest.clips.where((c) => c.seconds <= 6.5).map((c) => c.serverMs.toDouble()).toList()).round();
      lines
        ..add('Laptop server, same clips: $serverShort ms per chunk (CPU)')
        ..add('')
        ..add('Verdict: ${verdict(bestShortMs!)}');
      setState(() => _report = lines.join('\n'));
      _set('Done.');
    } catch (e) {
      setState(() => _error = '$e');
      _set('Failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _set(String status, {double? progress}) {
    if (mounted) {
      setState(() {
        _status = status;
        _progress = progress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('On-device speech benchmark')),
      body: ListView(
        padding: const EdgeInsets.all(RubricSpace.gutter),
        children: [
          Text(
            'Tests whether this phone can run the Quran speech model itself, without the laptop. '
            'Uses the server address from Settings to download the model and test audio once.',
            style: context.text.bodyMedium?.copyWith(color: context.colors.inkSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.speed_rounded),
            label: Text(_report == null ? 'Run benchmark' : 'Run again'),
          ),
          const SizedBox(height: 16),
          Text(_status, style: context.text.bodyMedium),
          if (_busy) ...[const SizedBox(height: 8), LinearProgressIndicator(value: _progress)],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: context.text.bodySmall?.copyWith(color: context.colors.signal)),
          ],
          if (_report != null) ...[
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(RubricRadius.md),
                side: BorderSide(color: context.colors.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.all(RubricSpace.s4),
                child: SelectableText(_report!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _report!));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Results copied')));
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy results'),
            ),
          ],
          const SizedBox(height: 24),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await ModelStore.deleteAll();
                    _set('Downloaded models deleted from the phone.');
                  },
            child: const Text('Delete downloaded model'),
          ),
        ],
      ),
    );
  }
}

/// How a typical live chunk's processing time translates into the product.
String verdict(int typicalChunkMs) {
  if (typicalChunkMs <= 1500) {
    return 'GOOD: on-device recognition is fast enough for live following on this phone.';
  }
  if (typicalChunkMs <= 3000) {
    return 'BORDERLINE: usable with fewer live previews; the vocabulary-trim optimization should make it comfortable.';
  }
  return 'TOO SLOW for live following: needs a smaller model (or the cloud fallback) on phones like this.';
}

/// 1 - word edit distance / reference length, on normalized words.
double wordAccuracy(String hypothesis, String reference) {
  final h = tokenize(hypothesis), r = tokenize(reference);
  if (r.isEmpty) return h.isEmpty ? 1 : 0;
  var prev = List<int>.generate(h.length + 1, (i) => i);
  for (var i = 1; i <= r.length; i++) {
    final cur = List<int>.filled(h.length + 1, 0)..[0] = i;
    for (var j = 1; j <= h.length; j++) {
      final cost = r[i - 1] == h[j - 1] ? 0 : 1;
      cur[j] = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
    }
    prev = cur;
  }
  return math.max(0, 1 - prev[h.length] / r.length);
}

double mean(List<double> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

double median(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}
