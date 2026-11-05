import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../data/khatm.dart';
import '../../../l10n/l10n.dart';
import '../../../data/settings.dart';

/// Where the reader is (surah, juz, page) and the reader's actions. The only
/// part of the reader that rebuilds as the text scrolls.
class ReaderBar extends ConsumerWidget {
  const ReaderBar({
    super.key,
    required this.onOpenSurahs,
    this.onSearch,
    this.onToggleLayout,
  });

  /// The Surahs tab (surahs, juz, pages).
  final VoidCallback onOpenSurahs;
  final VoidCallback? onSearch;

  /// Switch between scroll and pages.
  final VoidCallback? onToggleLayout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l = context.l10n;
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final verse = quran.verse(ref.watch(readingPositionProvider));
    final surah = quran.surah(verse.surah);
    final juz = quran.juzOf(verse.id), page = quran.pageOf(verse.id);
    final pages = ref.watch(settingsProvider.select((s) => s.readingLayout)) == ReadingLayout.pages;
    // A khatm in progress sets today's target; otherwise the daily goal does.
    final plan = ref.watch(khatmProvider.select((b) => b.active));
    final today = dateOnly(ref.read(clockProvider)());
    final dailyGoal = ref.watch(settingsProvider.select((s) => s.dailyGoalPages));
    if (plan == null) ref.watch(readingProgressProvider);
    final goal = plan?.todayTarget(today) ?? dailyGoal;
    final read = plan?.readOn(today) ?? (goal == 0 ? 0 : ref.read(readingProgressProvider.notifier).today);
    final progress = plan != null ? l.semKhatmToday(read, goal) : l.semTodayProgress(read, goal);
    final where = goal == 0
        ? l.juzPage(juz, page)
        // On a narrow phone only the count; the line under the bar and the
        // screen reader say the rest.
        : '${l.juzPage(juz, page)} · ${MediaQuery.sizeOf(context).width >= 360 ? l.todayProgress(read, goal) : '$read/$goal'}';

    final bar = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(RubricSpace.s2, RubricSpace.s1, RubricSpace.s1, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: goal == 0
                  ? l.semReaderBar(names.of(surah.index), verse.ayah, juz, page)
                  : '${l.semReaderBar(names.of(surah.index), verse.ayah, juz, page)}. $progress',
              excludeSemantics: true,
              child: InkWell(
                onTap: onOpenSurahs,
                borderRadius: BorderRadius.circular(RubricRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s2, vertical: RubricSpace.s1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The name on one line; where in the Quran, which
                      // matters most on a narrow phone, alone on the next.
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: surah.nameAr,
                              style: RubricText.surahAr.copyWith(fontSize: 22, height: 1.3, color: c.ink),
                            ),
                            if (!names.isArabic)
                              TextSpan(
                                text: '  ${names.of(surah.index)}',
                                style: RubricText.caption.copyWith(color: c.inkSecondary),
                              ),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Icon(Icons.expand_more, size: 20, color: c.inkSecondary),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        where,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RubricText.caption.copyWith(color: c.inkSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onToggleLayout != null)
            IconButton(
              tooltip: pages ? l.tooltipScrollView : l.tooltipPageView,
              onPressed: onToggleLayout,
              icon: Icon(pages ? Icons.view_day_outlined : Icons.auto_stories_outlined),
            ),
          if (onSearch != null)
            IconButton(tooltip: l.tooltipSearch, onPressed: onSearch, icon: const Icon(Icons.search)),
        ],
      ),
    );
    if (goal == 0) return bar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        // Today's progress toward the goal: ink on the hairline, quiet.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RubricSpace.gutter),
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: LinearProgressIndicator(
                value: (read / goal).clamp(0.0, 1.0),
                minHeight: 2,
                color: c.ink,
                backgroundColor: c.hairline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
