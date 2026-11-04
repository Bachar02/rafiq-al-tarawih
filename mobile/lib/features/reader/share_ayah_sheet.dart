import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/sheet.dart';
import '../../app/components/wordmark.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/text/quran_display.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';
import '../../l10n/l10n.dart';
import 'reader_ayah_sheet.dart';

/// Share one ayah: a preview of the image card, then "as an image" or "as
/// text". The image is rendered from the preview itself, at 3×.
Future<void> showShareAyahSheet(BuildContext context, {required Verse verse, required SurahNames names}) =>
    showRubricSheet<void>(context, builder: (context) => _ShareAyah(verse: verse, names: names));

class _ShareAyah extends ConsumerStatefulWidget {
  const _ShareAyah({required this.verse, required this.names});

  final Verse verse;
  final SurahNames names;

  @override
  ConsumerState<_ShareAyah> createState() => _ShareAyahState();
}

class _ShareAyahState extends ConsumerState<_ShareAyah> {
  final _card = GlobalKey();
  bool _busy = false;

  Future<void> _run(Future<void> Function() share) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.shareFailed;
    setState(() => _busy = true);
    try {
      await share();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _asImage() => _run(() async {
        final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final v = widget.verse;
        await ref.read(sharerProvider).shareImage(
              png!.buffer.asUint8List(),
              fileName: 'rafiq-${v.surah}-${v.ayah}.png',
              text: verseReferenceText(v, widget.names),
            );
      });

  Future<void> _asText() =>
      _run(() => ref.read(sharerProvider).shareText(ayahClipboardText(widget.verse, widget.names)));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final maxPreview = MediaQuery.sizeOf(context).height * 0.32;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: l.shareAyah),
          const SizedBox(height: RubricSpace.s4),
          // The card lays out at its own size and is shown scaled down: what
          // is captured is the card, not the preview.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxPreview),
            child: FittedBox(
              fit: BoxFit.contain,
              child: RepaintBoundary(
                key: _card,
                child: AyahCard(verse: widget.verse, names: widget.names),
              ),
            ),
          ),
          const SizedBox(height: RubricSpace.s4),
          FilledButton.icon(
            onPressed: _busy ? null : _asImage,
            icon: const Icon(Icons.image_outlined, size: 20),
            label: Text(l.shareAsImage),
          ),
          const SizedBox(height: RubricSpace.s2),
          OutlinedButton.icon(
            onPressed: _busy ? null : _asText,
            icon: const Icon(Icons.notes_outlined, size: 20),
            label: Text(l.shareAsText),
          ),
        ],
      ),
    );
  }
}

/// "Al-Baqarah 2:255": what goes with a shared image.
String verseReferenceText(Verse verse, SurahNames names) => '${names.of(verse.surah)} ${verse.surah}:${verse.ayah}';

/// One ayah as a card to share: the Quran text in the Book's typeface, its
/// reference, and the wordmark, in the current theme's ink on its paper.
class AyahCard extends StatelessWidget {
  const AyahCard({super.key, required this.verse, required this.names});

  final Verse verse;
  final SurahNames names;

  /// Laid out at a phone's width; captured at 3× (1080 px wide).
  static const width = 360.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final quran = ProviderScope.containerOf(context, listen: false).read(quranProvider);
    final surah = quran.surah(verse.surah);
    // Long ayahs (2:282) get smaller type rather than an endless image.
    final length = verse.uthmani.length;
    final fontSize = length > 900 ? 18.0 : (length > 400 ? 21.0 : 26.0);
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(RubricSpace.s6, RubricSpace.s6, RubricSpace.s6, RubricSpace.s4),
      decoration: BoxDecoration(
        color: c.ground,
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(RubricRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${preparePauseMarks(verse.uthmani)}$nbsp${ayahEndMarker(verse.ayah)}',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            textScaler: TextScaler.noScaling,
            style: RubricText.quranBody.copyWith(fontSize: fontSize, color: c.ink),
          ),
          const SizedBox(height: RubricSpace.s4),
          Divider(color: c.hairline),
          const SizedBox(height: RubricSpace.s2),
          Row(
            children: [
              const Wordmark(height: 18),
              const Spacer(),
              Flexible(
                child: Text(
                  '${surah.nameAr} · ${verse.surah}:${verse.ayah}',
                  textDirection: TextDirection.rtl,
                  overflow: TextOverflow.ellipsis,
                  style: RubricText.surahAr.copyWith(fontSize: 17, height: 1.4, color: c.inkSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
