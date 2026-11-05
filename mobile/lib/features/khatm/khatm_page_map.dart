import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/page_toggle.dart';
import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/khatm.dart';
import '../../data/quran.dart';
import '../../l10n/l10n.dart';

/// The pages of each juz, as a printed mushaf lists them: from the page the
/// juz starts on to the page before the next juz starts (juz 3: pages 42 to
/// 61; juz 4 starts on page 62).
List<List<int>> juzPages(Quran quran) => [
      for (var j = 1; j <= 30; j++)
        [
          for (var p = quran.pageOf(quran.juzs.start(j));
              p < (j == 30 ? Quran.pageCount + 1 : quran.pageOf(quran.juzs.start(j + 1)));
              p++)
            p,
        ],
    ];

/// The khatm's pages at a glance, and where the user corrects them: 30 juz
/// tiles, filled as their pages are read. A tile opens its pages, each one
/// a toggle, to mark read or unread (a mistake, a paper mushaf).
class KhatmPageMap extends ConsumerWidget {
  const KhatmPageMap({super.key, required this.plan});

  final KhatmPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final juzs = juzPages(ref.watch(quranProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: RubricSpace.s6, bottom: RubricSpace.s1),
          child: Semantics(
            header: true,
            child:
                Text(l.khatmMap.toUpperCase(), style: RubricText.overlineFor(context).copyWith(color: c.inkSecondary)),
          ),
        ),
        Text(l.khatmMapHint, style: RubricText.caption.copyWith(color: c.inkSecondary)),
        const SizedBox(height: RubricSpace.s3),
        GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: RubricSpace.s2,
          crossAxisSpacing: RubricSpace.s2,
          children: [
            for (final (i, pages) in juzs.indexed)
              _JuzTile(
                juz: i + 1,
                read: pages.where(plan.pages.containsKey).length,
                total: pages.length,
                onTap: () => showRubricSheet<void>(context, builder: (_) => _JuzSheet(juz: i + 1, pages: pages)),
              ),
          ],
        ),
      ],
    );
  }
}

/// One juz: its number, and a fill for the share of its pages read
/// (all read: solid ink).
class _JuzTile extends StatelessWidget {
  const _JuzTile({required this.juz, required this.read, required this.total, required this.onTap});

  final int juz, read, total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = read == total;
    return Semantics(
      button: true,
      label: context.l10n.semJuzTile(juz, read, total),
      excludeSemantics: true,
      child: Material(
        color: done ? c.ink : c.surface,
        borderRadius: BorderRadius.circular(RubricRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Center(
                child: Text(
                  '$juz',
                  style: RubricText.label.copyWith(color: done ? c.ground : c.ink),
                  textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4)),
                ),
              ),
              if (!done && read > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: read / total,
                    child: Container(height: 4, color: c.ink),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One juz's pages, each a toggle: read or not.
class _JuzSheet extends ConsumerStatefulWidget {
  const _JuzSheet({required this.juz, required this.pages});

  final int juz;
  final List<int> pages;

  @override
  ConsumerState<_JuzSheet> createState() => _JuzSheetState();
}

class _JuzSheetState extends ConsumerState<_JuzSheet> {
  String? _error;

  Future<void> _set(Iterable<int> pages, bool read) async {
    final ok = await ref.read(khatmProvider.notifier).setRead(pages, read: read);
    if (mounted) setState(() => _error = ok ? null : context.l10n.khatmSaveFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final plan = ref.watch(khatmProvider.select((b) => b.active));
    if (plan == null) {
      // The last page completed the khatm (or it was stopped): nothing to mark.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final read = widget.pages.where(plan.pages.containsKey).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: l.juzNumber(widget.juz),
            explanation: l.khatmJuzPages(widget.pages.first, widget.pages.last, read, widget.pages.length),
          ),
          const SizedBox(height: RubricSpace.s4),
          Wrap(
            spacing: RubricSpace.s2,
            runSpacing: RubricSpace.s1,
            children: [
              for (final p in widget.pages)
                PageToggle(page: p, on: plan.pages.containsKey(p), onChanged: (on) => _set([p], on)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: RubricSpace.s2),
            Text(_error!, style: RubricText.label.copyWith(color: c.ink)),
          ],
          const SizedBox(height: RubricSpace.s4),
          OutlinedButton(
            onPressed: read == widget.pages.length ? null : () => _set(widget.pages, true),
            child: Text(l.khatmMarkAllRead),
          ),
          const SizedBox(height: RubricSpace.s2),
          TextButton(
            onPressed: read == 0 ? null : () => _set(widget.pages, false),
            child: Text(l.khatmMarkAllUnread),
          ),
        ],
      ),
    );
  }
}
