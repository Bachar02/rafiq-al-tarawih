import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/place_tile.dart' show relativeDay;
import '../../app/components/page_toggle.dart';
import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/reading_store.dart';
import '../../l10n/l10n.dart';

/// "Count this reading?": the pages that stayed on screen long enough to
/// read, by day, each a toggle (all on). *Count* adds the ticked ones to the
/// daily log and the khatm and sets the others aside; *Don't count these*
/// sets them all aside; *Not now* (or dismissing) keeps them waiting.
///
/// Says the outcome in a snackbar. Does nothing if no page is waiting.
Future<void> showReadingReview(BuildContext context, WidgetRef ref) async {
  final shown = ref.read(readingSessionProvider).pending;
  if (shown.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final counted = await showRubricSheet<ReadingLog>(context, builder: (_) => _ReviewSheet(shown: shown));
  if (counted == null) return; // not now
  final ok = await ref.read(readingSessionProvider.notifier).review(shown: shown, counted: counted);
  // Queued, not replacing: a "Khatm complete" just shown stays first.
  messenger.showSnackBar(SnackBar(
    content: Text(!ok
        ? l.reviewFailed
        : counted.isEmpty
            ? l.reviewCount(0)
            : l.reviewCounted(counted.length)),
  ));
}

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.shown});

  final ReadingLog shown;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  /// The ticked pages, by day: all of them to begin with.
  late final Map<String, Set<int>> _ticked = {
    for (final e in widget.shown.days.entries) e.key: {...e.value},
  };

  ReadingLog get _counted => ReadingLog({
        for (final e in _ticked.entries)
          if (e.value.isNotEmpty) e.key: e.value
      });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final now = ref.read(clockProvider)();
    final days = widget.shown.days.keys.toList()..sort((a, b) => b.compareTo(a)); // today first
    final count = _counted.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: l.reviewTitle, explanation: l.reviewExplanation),
          for (final key in days) ...[
            if (days.length > 1 || ReadingLog.dayKey(now) != key)
              Padding(
                padding: const EdgeInsets.only(top: RubricSpace.s4),
                child: Text(
                  relativeDay(l, ReadingLog.parseDay(key) ?? now, now).toUpperCase(),
                  style: RubricText.overlineFor(context).copyWith(color: c.inkSecondary),
                ),
              ),
            const SizedBox(height: RubricSpace.s2),
            Wrap(
              spacing: RubricSpace.s2,
              runSpacing: RubricSpace.s1,
              children: [
                for (final page in [...widget.shown.days[key]!]..sort())
                  PageToggle(page: page, on: _ticked[key]!.contains(page), onChanged: (_) => _toggle(key, page)),
              ],
            ),
          ],
          const SizedBox(height: RubricSpace.s6),
          FilledButton(onPressed: () => Navigator.pop(context, _counted), child: Text(l.reviewCount(count))),
          const SizedBox(height: RubricSpace.s2),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, const ReadingLog()),
                  child: Text(l.reviewDiscard, textAlign: TextAlign.center),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.reviewNotNow, textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _toggle(String day, int page) => setState(() {
        final pages = _ticked[day]!;
        if (!pages.remove(page)) pages.add(page);
      });
}
