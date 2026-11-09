import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/quran_text.dart' show Basmala, basmalaFor;
import '../../app/components/settings_group.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/text/quran_display.dart';
import '../../data/adhkar.dart';
import '../../l10n/l10n.dart';
import 'adhkar_controller.dart';

/// The Adhkar screen: the five collections, each with today's progress, the
/// one for this time of day marked "Now".
class AdhkarScreen extends ConsumerWidget {
  const AdhkarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final adhkar = ref.watch(adhkarProvider);
    ref.watch(adhkarDayProvider);
    final day = ref.read(adhkarDayProvider.notifier).today;
    final now = adhkarNow(ref.read(clockProvider)());
    return Scaffold(
      appBar: AppBar(title: Text(l.adhkar)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, 0, RubricSpace.gutter, RubricSpace.s8),
        children: [
          RubricGroup(
            children: [
              for (final collection in AdhkarCollection.values)
                Builder(builder: (context) {
                  final items = adhkar.of(collection);
                  final done = day.doneIn(collection, items);
                  final complete = items.isNotEmpty && done == items.length;
                  return RubricRow(
                    label: collectionTitle(l, collection),
                    detail: complete
                        ? l.adhkarDoneToday
                        : done > 0
                            ? l.adhkarProgress(done, items.length)
                            : collectionWhen(l, collection),
                    value: collection == now ? l.adhkarNow : null,
                    enabled: items.isNotEmpty,
                    trailing: Icon(complete ? Icons.check : Icons.chevron_right, color: c.inkSecondary),
                    onTap: () => AppRoutes.dhikrList(context, collection),
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }
}

/// One collection, to be said in order: tap a dhikr each time it is said.
/// Its counter goes down to a check, and the list moves on to the next.
class DhikrListScreen extends ConsumerStatefulWidget {
  const DhikrListScreen({super.key, required this.collection});

  final AdhkarCollection collection;

  @override
  ConsumerState<DhikrListScreen> createState() => _DhikrListScreenState();
}

class _DhikrListScreenState extends ConsumerState<DhikrListScreen> {
  final _keys = <String, GlobalKey>{};

  AdhkarCollection get _collection => widget.collection;

  Future<void> _count(List<Dhikr> items, int index) async {
    final controller = ref.read(adhkarDayProvider.notifier);
    final dhikr = items[index];
    final reduced = RubricMotion.reduced(context);
    if (controller.today.isDone(_collection, dhikr)) return;
    await controller.count(_collection, dhikr);
    // A tick for each count, felt without looking; a firmer one when done.
    if (!controller.today.isDone(_collection, dhikr)) {
      unawaited(HapticFeedback.selectionClick());
      return;
    }
    // Done: on to the next one still to say.
    unawaited(HapticFeedback.mediumImpact());
    final day = controller.today;
    final next = items.skip(index + 1).where((d) => !day.isDone(_collection, d)).firstOrNull;
    final target = next == null ? null : _keys[next.id]?.currentContext;
    if (target == null || !target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      duration: reduced ? Duration.zero : RubricMotion.scroll,
      curve: RubricMotion.standard,
    );
  }

  Future<void> _reset() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(adhkarDayProvider.notifier);
    final before = await controller.reset(_collection);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l.adhkarStartedAgain),
        action: SnackBarAction(label: l.undo, onPressed: () => controller.restore(before)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final items = ref.watch(adhkarProvider).of(_collection);
    ref.watch(adhkarDayProvider);
    final day = ref.read(adhkarDayProvider.notifier).today;
    final done = day.doneIn(_collection, items);
    final caption = RubricText.caption.copyWith(color: c.inkSecondary);
    return Scaffold(
      appBar: AppBar(
        title: Text(collectionTitle(l, _collection)),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: l.adhkarStartAgain,
            onPressed: items.any((d) => day.countOf(_collection, d) > 0) ? _reset : null,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          // Always in view, unlike the line at the top of the list.
          child: LinearProgressIndicator(
            value: items.isEmpty ? 0 : done / items.length,
            semanticsLabel: l.adhkarProgress(done, items.length),
            minHeight: 3,
            backgroundColor: c.hairline,
            color: c.inkSecondary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s4, RubricSpace.gutter, RubricSpace.s12),
        children: [
          Semantics(
            liveRegion: true,
            child: Text(l.adhkarProgress(done, items.length), style: RubricText.label.copyWith(color: c.ink)),
          ),
          Text(l.adhkarTapToCount, style: caption),
          const SizedBox(height: RubricSpace.s4),
          for (final (i, dhikr) in items.indexed)
            Padding(
              key: _keys.putIfAbsent(dhikr.id, GlobalKey.new),
              padding: const EdgeInsets.only(bottom: RubricSpace.s3),
              child: DhikrCard(
                dhikr: dhikr,
                said: day.countOf(_collection, dhikr),
                onCount: () => _count(items, i),
              ),
            ),
          if (items.isNotEmpty && done == items.length)
            Padding(
              padding: const EdgeInsets.only(top: RubricSpace.s4),
              child: Text(
                l.adhkarAllDone,
                textAlign: TextAlign.center,
                style: RubricText.label.weighted(500).copyWith(color: c.ink),
              ),
            ),
        ],
      ),
    );
  }
}

/// One dhikr: its words (and the Quran it recites), how or when to say it,
/// its meaning in the interface language, who reports it, and its counter.
/// The whole card counts; once said enough it rests in `ink-secondary`.
class DhikrCard extends ConsumerWidget {
  const DhikrCard({super.key, required this.dhikr, required this.said, required this.onCount});

  final Dhikr dhikr;

  /// Times said today.
  final int said;
  final VoidCallback onCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final language = l.localeName;
    final done = said >= dhikr.count;
    // The Quran text-size setting sizes the Arabic, as in the reader.
    final scale = ref.watch(settingsProvider.select((s) => s.textScale));
    final fontSize = RubricText.dhikr.fontSize! * scale;
    final ink = done ? c.inkSecondary : c.ink;
    final caption = RubricText.caption.copyWith(color: c.inkSecondary);
    final note = dhikr.note(language);
    final meaning = dhikr.meaning(language);
    final sources = sourcesLabel(l, ref.watch(adhkarProvider).sourcesOf(dhikr, language));
    return Semantics(
      onTapHint: done ? null : l.hintDhikrCount,
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(RubricRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: done ? null : onCount,
          highlightColor: c.surfaceRaised,
          child: Padding(
            padding: const EdgeInsets.all(RubricSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dhikr.arabic != null)
                  Text(
                    dhikr.arabic!,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.start,
                    textScaler: TextScaler.noScaling,
                    style: RubricText.dhikr.copyWith(fontSize: fontSize, color: ink),
                  ),
                // The meaning right under the words it explains, before any
                // Quran (whose meaning is the translation's).
                if (meaning != null) ...[
                  const SizedBox(height: RubricSpace.s2),
                  Text(meaning, style: RubricText.label.copyWith(color: c.inkSecondary)),
                ],
                for (final passage in dhikr.passages)
                  _Passage(passage: passage, fontSize: fontSize, color: ink, scale: scale),
                if (note != null) ...[
                  const SizedBox(height: RubricSpace.s2),
                  Text(note, style: RubricText.caption.copyWith(color: c.ink)),
                ],
                if (dhikr.passages.isNotEmpty)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      // In line with the text; the tap target stays 48 dp.
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s1)),
                      // The translation and tafsir of the first ayah.
                      onPressed: () => AppRoutes.study(context, verseId: _firstVerse(ref)),
                      child: Text(l.translationAndTafsir),
                    ),
                  ),
                const SizedBox(height: RubricSpace.s2),
                Row(
                  children: [
                    Expanded(child: Text(sources, style: caption)),
                    const SizedBox(width: RubricSpace.s3),
                    _Counter(said: said, count: dhikr.count),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _firstVerse(WidgetRef ref) {
    final p = dhikr.passages.first;
    return ref.read(quranProvider).verseId(p.surah, p.from)!;
  }
}

/// Ayahs inside a dhikr: the surah's name, its basmala for a whole surah,
/// then the text with its end markers, from the app's Quran text.
class _Passage extends ConsumerWidget {
  const _Passage({required this.passage, required this.fontSize, required this.color, required this.scale});

  final QuranPassage passage;
  final double fontSize;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final quran = ref.watch(quranProvider);
    final name = ref.watch(surahNamesProvider).of(passage.surah);
    final basmala = passage.wholeSurah ? basmalaFor(quran, quran.surah(passage.surah)) : null;
    final label = passage.wholeSurah
        ? name
        : '$name ${passage.surah}:${passage.from}${passage.to > passage.from ? '–${passage.to}' : ''}';
    return Padding(
      padding: const EdgeInsets.only(top: RubricSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: RubricText.caption.copyWith(color: c.inkSecondary)),
          // Room for the marks above the first line (a pause sign rises high).
          const SizedBox(height: RubricSpace.s3),
          if (basmala != null) Basmala(text: basmala, scale: scale),
          Text.rich(
            TextSpan(
              children: [
                for (final verse in passage.verses(quran)) ...[
                  TextSpan(text: displayAyahText(verse.uthmani)),
                  TextSpan(text: '${ayahEndMarker(verse.ayah)} '),
                ],
              ],
            ),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.start,
            textScaler: TextScaler.noScaling,
            style: RubricText.quranBody.copyWith(fontSize: fontSize, height: 2.1, color: color),
          ),
        ],
      ),
    );
  }
}

/// Times left, then a check. Grows with large text rather than clipping.
class _Counter extends StatelessWidget {
  const _Counter({required this.said, required this.count});

  final int said;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final done = said >= count;
    return Semantics(
      label: done ? l.semDhikrDone : l.semDhikrCount(said, count),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s3),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: done ? c.surfaceRaised : null,
          shape: StadiumBorder(side: BorderSide(color: done ? c.hairline : c.inkSecondary, width: 1.5)),
        ),
        child: done
            ? Icon(Icons.check, size: 22, color: c.ink)
            : Text('${count - said}', style: RubricText.labelLg.copyWith(color: c.ink)),
      ),
    );
  }
}
