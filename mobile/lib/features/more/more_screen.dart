import 'package:flutter/material.dart';

import '../../app/components/settings_group.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/l10n.dart';

/// Everything that is not reading: settings, and the features still to come,
/// shown where they will live, visibly not yet working.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: Text(l.navMore)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, 0, RubricSpace.gutter, RubricSpace.s8),
        children: [
          RubricGroup(
            children: [
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
                (l.soonTranslation, l.soonTranslationDetail),
                (l.soonTafsir, l.soonTafsirDetail),
                (l.soonKhatm, l.soonKhatmDetail),
                (l.soonNotes, l.soonNotesDetail),
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
