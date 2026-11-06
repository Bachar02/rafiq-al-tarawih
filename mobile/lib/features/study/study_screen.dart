import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/quran_text.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/quran.dart';
import '../../data/study_text.dart';
import '../../l10n/l10n.dart';
import 'study_source_sheet.dart';

/// The meaning of one ayah at a time: the ayah, then its translation or its
/// tafsir, exactly as published, with the publisher and version under it.
///
/// Swipe (or use the buttons) to move to the next or previous ayah, across
/// surahs. The reader underneath does not move: this is a study view, not a
/// second reading position.
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key, required this.verseId, this.kind = StudyKind.translation});

  final int verseId;
  final StudyKind kind;

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  late final PageController _pages = PageController(initialPage: widget.verseId - 1);
  late int _verseId = widget.verseId;
  late StudyKind _kind = widget.kind;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final target = (_verseId + delta).clamp(1, Quran.verseCount);
    if (target == _verseId) return;
    _pages.animateToPage(target - 1, duration: RubricMotion.settle, curve: RubricMotion.standard);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final verse = quran.verse(_verseId);
    final source = ref.watch(studySourceProvider(_kind));
    return Scaffold(
      appBar: AppBar(
        // The ayah's reference, compact: a title that changes with every
        // swipe, sized like a sheet title so long surah names fit.
        title: Text(
          '${names.of(verse.surah)} ${verse.surah}:${verse.ayah}',
          style: RubricText.sheetTitle.copyWith(color: context.colors.ink),
        ),
        actions: [
          IconButton(
            tooltip: l.chooseText,
            icon: const Icon(Icons.library_books_outlined),
            onPressed: source == null ? null : () => chooseStudySource(context, ref, _kind),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s2, RubricSpace.gutter, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<StudyKind>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: StudyKind.translation,
                    icon: const Icon(Icons.translate, size: 18),
                    label: Text(l.translation),
                  ),
                  ButtonSegment(
                    value: StudyKind.tafsir,
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: Text(l.tafsir),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: Quran.verseCount,
              onPageChanged: (i) => setState(() => _verseId = i + 1),
              itemBuilder: (context, i) => _StudyPage(verse: quran.verse(i + 1), kind: _kind),
            ),
          ),
          _StepBar(
            onPrevious: _verseId > 1 ? () => _step(-1) : null,
            onNext: _verseId < Quran.verseCount ? () => _step(1) : null,
          ),
        ],
      ),
    );
  }
}

/// One ayah and its text, scrolling as one column.
class _StudyPage extends ConsumerWidget {
  const _StudyPage({required this.verse, required this.kind});

  final Verse verse;
  final StudyKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(settingsProvider.select((s) => s.textScale));
    final source = ref.watch(studySourceProvider(kind));
    final c = context.colors;
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s4, RubricSpace.gutter, RubricSpace.s8),
        children: [
          AyahBlock(
            verse: verse,
            tone: AyahTone.reading,
            // Smaller than the reader's column: the meaning is what this
            // view is for, and it should start on the first screen.
            fontSize: 22 * scale,
            justify: false,
          ),
          Divider(height: RubricSpace.s8, color: c.hairline),
          if (source != null)
            ref.watch(studyTextProvider(source.key)).when(
                  data: (text) => StudyAyahText(source: source, ayah: text.ayah(verse.id)),
                  loading: () => const Padding(
                    padding: EdgeInsets.all(RubricSpace.s8),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => Text(
                    context.l10n.textLoadFailed,
                    style: RubricText.label.copyWith(color: c.inkSecondary),
                  ),
                ),
        ],
      ),
    );
  }
}

/// A translation or tafsir of one ayah, its footnotes, and its credit line.
class StudyAyahText extends StatelessWidget {
  const StudyAyahText({super.key, required this.source, required this.ayah});

  final StudySource source;
  final StudyAyah ayah;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final ui = Localizations.localeOf(context).languageCode;
    final arabic = source.language == 'ar';
    final body = arabic
        ? RubricText.labelLgAr.weighted(400).copyWith(fontSize: 18, height: 32 / 18, color: c.ink)
        : RubricText.labelLg.weighted(400).copyWith(height: 27 / 17, color: c.ink);
    final small = (arabic ? RubricText.captionAr : RubricText.caption).copyWith(color: c.inkSecondary);
    final caption = RubricText.caption.copyWith(color: c.inkSecondary);
    final textLocale = Locale(source.language);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (source.language != ui) ...[
          Text(l.inLanguage(textLanguageName(l, source.language)), style: caption),
          const SizedBox(height: RubricSpace.s2),
        ],
        // The text keeps its own direction and language, whatever the
        // interface: an Arabic tafsir reads right to left in English too,
        // and a screen reader pronounces it as Arabic.
        Directionality(
          textDirection: source.direction,
          child: Text(ayah.text.trim(), locale: textLocale, style: body),
        ),
        if (ayah.footnotes.trim().isNotEmpty) ...[
          const SizedBox(height: RubricSpace.s4),
          Semantics(
            header: true,
            child: Text(l.footnotes, style: RubricText.label.weighted(500).copyWith(color: c.inkSecondary)),
          ),
          const SizedBox(height: RubricSpace.s1),
          Directionality(
            textDirection: source.direction,
            child: Text(ayah.footnotes.trim(), locale: textLocale, style: small),
          ),
        ],
        const SizedBox(height: RubricSpace.s6),
        Text(source.name(ui), style: RubricText.label.weighted(500).copyWith(color: c.ink)),
        Text(l.textSourceLine(source.credit(ui), source.version), style: caption),
        if (source.kind == StudyKind.translation) ...[
          const SizedBox(height: RubricSpace.s3),
          Text(l.translationNote, style: caption),
        ],
      ],
    );
  }
}

/// The language a text is written in, named in the interface language.
String textLanguageName(AppLocalizations l, String code) => switch (code) {
      'ar' => l.textLanguageAr,
      'fr' => l.textLanguageFr,
      _ => l.textLanguageEn,
    };

class _StepBar extends StatelessWidget {
  const _StepBar({required this.onPrevious, required this.onNext});

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.hairline))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s2, vertical: RubricSpace.s1),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // arrow_back / arrow_forward mirror in right-to-left layouts,
              // as the page swipe does.
              Flexible(
                child: TextButton.icon(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.arrow_back, size: 20),
                  label: Text(l.previousAyah, overflow: TextOverflow.ellipsis),
                ),
              ),
              Flexible(
                child: TextButton.icon(
                  onPressed: onNext,
                  // Label first, then the arrow pointing onward.
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  label: Text(l.nextAyah, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
