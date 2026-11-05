import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/components/settings_group.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/khatm.dart';
import '../../data/quran.dart';
import '../../l10n/l10n.dart';

/// "Dec 3, 2026", in the interface language.
String formatDay(AppLocalizations l, DateTime day) => DateFormat.yMMMd(l.localeName).format(day);

/// "12 days left · ends Dec 3, 2026", or "Past the planned end · 40 pages left".
String khatmTimeLine(AppLocalizations l, KhatmPlan plan, DateTime today) => plan.overdue(today)
    ? '${l.khatmPastEnd} · ${l.khatmPagesLeft(plan.remaining)}'
    : '${l.khatmDaysLeft(plan.daysLeft(today))} · ${l.khatmEnds(formatDay(l, plan.endsOn))}';

/// The khatm planner: start a plan, follow it, change its end or stop it,
/// and the khatms already finished. Opened from More and from Bookmarks.
class KhatmScreen extends ConsumerWidget {
  const KhatmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final book = ref.watch(khatmProvider);
    final plan = book.active;
    return Scaffold(
      appBar: AppBar(title: Text(l.khatmPlanner)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, 0, RubricSpace.gutter, RubricSpace.s8),
        children: [
          if (plan == null) const _NewPlan() else _ActivePlan(plan: plan),
          if (book.finished.isNotEmpty)
            RubricGroup(
              label: l.khatmFinished,
              children: [
                for (final r in book.finished)
                  RubricRow(
                    label: l.khatmCompletedOn(formatDay(l, r.completedOn)),
                    detail: l.khatmInDays(r.days),
                    trailing: Icon(Icons.check, size: 20, color: c.inkSecondary),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

void _saveFailed(BuildContext context) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(context.l10n.khatmSaveFailed)));

/// No plan yet: how long, from where, and Start.
class _NewPlan extends ConsumerStatefulWidget {
  const _NewPlan();

  @override
  ConsumerState<_NewPlan> createState() => _NewPlanState();
}

class _NewPlanState extends ConsumerState<_NewPlan> {
  static const lengths = [15, 30, 60];

  int _days = 30;

  /// A date picked instead of a length.
  DateTime? _pickedEnd;
  bool _fromHere = true;
  bool _saving = false;

  DateTime get _today => dateOnly(ref.read(clockProvider)());

  DateTime get _endsOn {
    final t = _today;
    return _pickedEnd ?? DateTime(t.year, t.month, t.day + _days - 1);
  }

  Future<void> _pickDate() async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 5, today.month, today.day),
      initialDate: _endsOn,
      helpText: context.l10n.khatmLastDay,
    );
    if (picked != null && mounted) setState(() => _pickedEnd = dateOnly(picked));
  }

  Future<void> _start(int startPage) async {
    setState(() => _saving = true);
    final ok = await ref.read(khatmProvider.notifier).start(endsOn: _endsOn, startPage: startPage);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) _saveFailed(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final quran = ref.watch(quranProvider);
    final here = quran.pageOf(ref.watch(readingPositionProvider));
    final fromHere = _fromHere && here > 1;
    final days = daysBetween(_today, _endsOn) + 1;
    Widget check(bool on) => on ? Icon(Icons.check, size: 20, color: c.ink) : const SizedBox(width: 20);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: RubricSpace.s2),
        Text(l.khatmExplanation, style: RubricText.label.copyWith(color: c.inkSecondary)),
        RubricGroup(
          label: l.khatmFinishIn,
          children: [
            for (final n in lengths)
              RubricRow(
                label: l.khatmDays(n),
                detail: n == 30 ? l.khatmJuzADay : null,
                selected: _pickedEnd == null && _days == n,
                trailing: check(_pickedEnd == null && _days == n),
                onTap: () => setState(() {
                  _days = n;
                  _pickedEnd = null;
                }),
              ),
            RubricRow(
              label: l.khatmPickDate,
              value: _pickedEnd == null ? null : formatDay(l, _pickedEnd!),
              selected: _pickedEnd != null,
              trailing: check(_pickedEnd != null),
              onTap: _pickDate,
            ),
          ],
        ),
        RubricGroup(
          label: l.khatmStartAt,
          children: [
            if (here > 1)
              RubricRow(
                label: l.khatmFromHere,
                detail: l.pageNumber(here),
                selected: fromHere,
                trailing: check(fromHere),
                onTap: () => setState(() => _fromHere = true),
              ),
            RubricRow(
              label: l.khatmFromBeginning,
              selected: !fromHere,
              trailing: check(!fromHere),
              onTap: () => setState(() => _fromHere = false),
            ),
          ],
        ),
        const SizedBox(height: RubricSpace.s6),
        Text(
          l.khatmPreview((Quran.pageCount / days).ceil(), formatDay(l, _endsOn)),
          textAlign: TextAlign.center,
          style: RubricText.caption.copyWith(color: c.inkSecondary),
        ),
        const SizedBox(height: RubricSpace.s2),
        FilledButton(
          onPressed: _saving ? null : () => _start(fromHere ? here : 1),
          child: Text(l.khatmStart),
        ),
      ],
    );
  }
}

/// A plan in progress: how far, today, the days left, and its actions.
class _ActivePlan extends ConsumerWidget {
  const _ActivePlan({required this.plan});

  final KhatmPlan plan;

  Future<void> _changeEnd(BuildContext context, WidgetRef ref, DateTime today) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 5, today.month, today.day),
      initialDate: plan.endsOn.isBefore(today) ? today : plan.endsOn,
      helpText: context.l10n.khatmLastDay,
    );
    if (picked == null || !context.mounted) return;
    if (!await ref.read(khatmProvider.notifier).changeEnd(picked) && context.mounted) _saveFailed(context);
  }

  Future<void> _stop(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.khatmStopTitle),
        content: Text(l.khatmStopBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l.khatmStopConfirm)),
        ],
      ),
    );
    if (stop != true || !context.mounted) return;
    if (!await ref.read(khatmProvider.notifier).stop() && context.mounted) _saveFailed(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final quran = ref.watch(quranProvider);
    final today = dateOnly(ref.read(clockProvider)());
    final next = plan.nextPage ?? plan.startPage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: RubricSpace.s4),
        Container(
          padding: const EdgeInsets.all(RubricSpace.s4),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(RubricRadius.md)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.khatmPagesRead(plan.read), style: RubricText.labelLg.copyWith(color: c.ink)),
              const SizedBox(height: RubricSpace.s3),
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: plan.read / Quran.pageCount,
                    minHeight: 4,
                    color: c.ink,
                    backgroundColor: c.hairline,
                  ),
                ),
              ),
              const SizedBox(height: RubricSpace.s3),
              Text(
                l.khatmToday(plan.readOn(today), plan.todayTarget(today)),
                style: RubricText.label.copyWith(color: c.ink),
              ),
              Text(khatmTimeLine(l, plan, today), style: RubricText.caption.copyWith(color: c.inkSecondary)),
            ],
          ),
        ),
        const SizedBox(height: RubricSpace.s4),
        FilledButton.icon(
          onPressed: () {
            ref.read(readerRequestsProvider.notifier).open(quran.pages.start(next));
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          icon: const Icon(Icons.menu_book_outlined, size: 20),
          label: Text(l.khatmContinue(next)),
        ),
        const SizedBox(height: RubricSpace.s2),
        OutlinedButton.icon(
          onPressed: () => _changeEnd(context, ref, today),
          icon: const Icon(Icons.event_outlined, size: 20),
          label: Text(l.khatmChangeEnd),
        ),
        const SizedBox(height: RubricSpace.s2),
        TextButton(onPressed: () => _stop(context, ref), child: Text(l.khatmStop)),
      ],
    );
  }
}
