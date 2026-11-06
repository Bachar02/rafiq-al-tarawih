import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/settings_group.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/l10n.dart';

/// Everything that is not the text itself: translation and tafsir, the
/// khatm planner, settings, and the features still to come, shown where they
/// will live, visibly not yet working.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final plan = ref.watch(khatmProvider.select((b) => b.active));
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: Text(l.navMore)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, 0, RubricSpace.gutter, RubricSpace.s8),
        children: [
          RubricGroup(
            children: [
              RubricRow(
                label: l.translationAndTafsir,
                detail: l.translationAndTafsirDetail,
                trailing: Icon(Icons.chevron_right, color: c.inkSecondary),
                // Opens at the ayah the reader is on.
                onTap: () => AppRoutes.study(context, verseId: ref.read(readingPositionProvider)),
              ),
              RubricRow(
                label: l.khatmPlanner,
                detail: plan == null ? l.khatmPlannerDetail : l.khatmPagesRead(plan.read),
                trailing: Icon(Icons.chevron_right, color: c.inkSecondary),
                onTap: () => AppRoutes.khatm(context),
              ),
              RubricRow(
                label: l.settings,
                trailing: Icon(Icons.chevron_right, color: c.inkSecondary),
                onTap: () => AppRoutes.settings(context),
              ),
            ],
          ),
          RubricGroup(
            label: l.comingSoon,
            children: [
              for (final (label, detail) in [
                (l.soonRecitation, l.soonRecitationDetail),
                (l.soonOffline, l.soonOfflineDetail),
              ])
                RubricRow(label: label, detail: detail, value: l.soon, enabled: false),
            ],
          ),
        ],
      ),
    );
  }
}
