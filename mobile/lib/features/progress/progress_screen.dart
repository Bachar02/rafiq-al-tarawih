import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/components/settings_group.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../data/reading_stats.dart';
import '../../l10n/l10n.dart';
import 'reading_grid.dart';
import 'reminder.dart';

/// A day and its pages, as the chart and the bars say it.
String dayPagesLabel(BuildContext context, DateTime day, int pages) {
  final l = context.l10n;
  return l.dayPages(DateFormat.MMMEd(l.localeName).format(day), l.pagesCount(pages));
}

/// The run of days, or how to start one.
String runLabel(AppLocalizations l, ReadingStats stats) =>
    stats.currentRun > 0 ? l.readingRun(stats.currentRun) : l.readingRunNone;

/// The Reading screen: a year of days, the last week against the goal, the
/// run and the totals, and the daily reminder. Consistency, not pressure:
/// a missed day is an empty square and nothing more.
class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final stats = ref.watch(readingStatsProvider);
    final selected = _selected ?? stats.today;
    final caption = RubricText.caption.copyWith(color: c.inkSecondary);
    const weeks = 53;
    return Scaffold(
      appBar: AppBar(title: Text(l.yourReading)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s2, RubricSpace.gutter, RubricSpace.s8),
        children: [
          Text(runLabel(l, stats), style: RubricText.sheetTitle.copyWith(color: c.ink)),
          if (stats.bestRun > 0) Text(l.readingBestRun(l.daysCount(stats.bestRun)), style: caption),
          const SizedBox(height: RubricSpace.s4),
          _Panel(
            children: [
              // Opens on today's end; older weeks scroll into view.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: ReadingGrid(
                  stats: stats,
                  weeks: weeks,
                  months: true,
                  selected: selected,
                  semanticLabel: l.semReadingGrid(
                    weeks,
                    l.daysWithReading(stats.daysSince(gridStart(stats.today, weeks, _firstDay(context)))),
                  ),
                  onDay: (day) => setState(() => _selected = day),
                ),
              ),
              const SizedBox(height: RubricSpace.s3),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: RubricSpace.s4,
                runSpacing: RubricSpace.s2,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      dayPagesLabel(context, selected, stats.pagesOn(selected)),
                      style: RubricText.label.copyWith(color: c.ink),
                    ),
                  ),
                  const _Legend(),
                ],
              ),
            ],
          ),
          const SizedBox(height: RubricSpace.s6),
          Semantics(
            header: true,
            child: Text(l.lastSevenDays, style: RubricText.label.weighted(500).copyWith(color: c.ink)),
          ),
          const SizedBox(height: RubricSpace.s3),
          _WeekBars(stats: stats),
          RubricGroup(
            children: [
              RubricRow(label: l.daysThisYear, value: '${stats.daysThisYear}'),
              RubricRow(label: l.pagesThisMonth, value: '${stats.pagesThisMonth}'),
            ],
          ),
          const ReminderSettings(),
          const SizedBox(height: RubricSpace.s8),
          Text(
            l.consistencyHadith,
            textAlign: TextAlign.center,
            // Italic for Latin only: Arabic is never slanted.
            style: RubricText.label.copyWith(
              color: c.ink,
              fontStyle: l.localeName == 'ar' ? FontStyle.normal : FontStyle.italic,
            ),
          ),
          const SizedBox(height: RubricSpace.s1),
          Text(l.consistencyHadithSource, textAlign: TextAlign.center, style: caption),
        ],
      ),
    );
  }
}

int _firstDay(BuildContext context) => MaterialLocalizations.of(context).firstDayOfWeekIndex;

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(RubricRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(RubricSpace.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );
}

/// Less ▢▢▢▢▢ More: the five shades.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final caption = RubricText.caption.copyWith(color: c.inkSecondary);
    // Wraps rather than overflowing with large system text.
    return ExcludeSemantics(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: RubricSpace.s1,
        children: [
          Text(l.chartLess, style: caption),
          const SizedBox(width: RubricSpace.s1),
          for (final shade in readingShades(c))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: DecoratedBox(
                decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(3)),
                child: const SizedBox(width: 12, height: 12),
              ),
            ),
          const SizedBox(width: RubricSpace.s1),
          Text(l.chartMore, style: caption),
        ],
      ),
    );
  }
}

/// The last seven days as bars, today last, with the day's goal as a line.
class _WeekBars extends ConsumerWidget {
  const _WeekBars({required this.stats});

  final ReadingStats stats;

  static const _height = 88.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final plan = ref.watch(khatmProvider.select((b) => b.active));
    final dailyGoal = ref.watch(settingsProvider.select((s) => s.dailyGoalPages));
    final int goal = plan != null ? plan.todayTarget(stats.today) : dailyGoal;
    final days = [for (var i = 6; i >= 0; i--) DateTime(stats.today.year, stats.today.month, stats.today.day - i)];
    final pages = [for (final d in days) stats.pagesOn(d)];
    final top = [goal, ...pages].reduce((a, b) => a > b ? a : b).clamp(1, 1 << 20);
    final caption = RubricText.caption.copyWith(color: c.inkSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _height + 18,
          child: Stack(
            children: [
              if (goal > 0)
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: _height * goal / top,
                  // Quiet, so a count printed across it stays readable.
                  child: Divider(height: 1, thickness: 1, color: c.hairline),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, day) in days.indexed)
                    Expanded(
                      // One node per day: read one by one, never run together.
                      child: Semantics(
                        container: true,
                        label: dayPagesLabel(context, day, pages[i]),
                        excludeSemantics: true,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(pages[i] > 0 ? '${pages[i]}' : '', style: caption.copyWith(height: 1)),
                            const SizedBox(height: 2),
                            Container(
                              width: 20,
                              height: pages[i] == 0 ? 2 : (_height * pages[i] / top).clamp(4, _height),
                              decoration: BoxDecoration(
                                color: pages[i] == 0 ? c.hairline : readingShades(c)[readingLevel(pages[i])],
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: RubricSpace.s1),
        ExcludeSemantics(
          child: Row(
            children: [
              for (final day in days)
                Expanded(
                  child: Text(
                    DateFormat.E(l.localeName).format(day),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: day == stats.today ? caption.copyWith(color: c.ink) : caption,
                  ),
                ),
            ],
          ),
        ),
        if (goal > 0) ...[
          const SizedBox(height: RubricSpace.s2),
          Text(
            plan != null ? l.goalKhatmToday(l.pagesCount(goal)) : '${l.dailyGoal}: ${l.pagesCount(goal)}',
            style: caption,
          ),
        ],
      ],
    );
  }
}

/// The daily reminder: on or off, and when. In Settings and on this screen.
class ReminderSettings extends ConsumerWidget {
  const ReminderSettings({super.key, this.label = true});

  /// Show the group's label (Settings puts it in its own group).
  final bool label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final on = ref.watch(settingsProvider.select((s) => s.reminderOn));
    final minutes = ref.watch(settingsProvider.select((s) => s.reminderMinutes));
    final time = formatMinutes(context, minutes);
    Future<void> toggle(bool value) => value ? turnOnReminder(context, ref) : turnOffReminder(ref);
    return RubricGroup(
      label: label ? l.dailyReminder : null,
      children: [
        RubricRow(
          label: l.dailyReminder,
          detail: on ? l.dailyReminderDetail(time) : l.dailyReminderOff,
          onTap: () => toggle(!on),
          trailing: Switch(value: on, onChanged: toggle),
        ),
        if (on)
          RubricRow(
            label: l.reminderTime,
            value: time,
            onTap: () => chooseReminderTime(context, ref),
          ),
      ],
    );
  }
}

/// The Bookmarks tab's door to the Reading screen: the weeks that fit and
/// the run.
class ReadingCard extends ConsumerWidget {
  const ReadingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final stats = ref.watch(readingStatsProvider);
    final caption = RubricText.caption.copyWith(color: c.inkSecondary);
    final run = runLabel(l, stats);
    final year = l.daysReadThisYear(stats.daysThisYear);
    return Semantics(
      button: true,
      label: '${l.yourReading}. $run. $year',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(RubricRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => AppRoutes.reading(context),
          highlightColor: c.surfaceRaised,
          child: Padding(
            padding: const EdgeInsets.all(RubricSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(l.yourReading, style: RubricText.label.weighted(500).copyWith(color: c.ink)),
                    ),
                    Icon(Icons.chevron_right, color: c.inkSecondary),
                  ],
                ),
                Text(run, style: caption),
                const SizedBox(height: RubricSpace.s3),
                LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ReadingGrid(
                      stats: stats,
                      weeks: ReadingGrid.weeksIn(box.maxWidth),
                      semanticLabel: '',
                    ),
                  ),
                ),
                const SizedBox(height: RubricSpace.s2),
                Text(year, style: caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
