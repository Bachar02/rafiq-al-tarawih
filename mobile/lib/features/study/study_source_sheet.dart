import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/settings_group.dart';
import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/study_text.dart';
import '../../l10n/l10n.dart';
import 'study_screen.dart' show textLanguageName;

/// Choose which translation (or tafsir) is shown, and remember it. Each
/// option says who issued it and, if it is not in the interface language,
/// which language it is in.
Future<void> chooseStudySource(BuildContext context, WidgetRef ref, StudyKind kind) async {
  final l = context.l10n;
  final ui = Localizations.localeOf(context).languageCode;
  final options = ref.read(studyCatalogProvider).of(kind);
  final current = ref.read(studySourceProvider(kind));
  final chosen = await showRubricSheet<StudySource>(
    context,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: kind == StudyKind.translation ? l.chooseTranslation : l.chooseTafsir,
            explanation: l.chooseTextExplanation,
          ),
          const SizedBox(height: RubricSpace.s4),
          RubricGroup(
            children: [
              for (final s in options)
                RubricRow(
                  label: s.name(ui),
                  detail: [
                    s.credit(ui),
                    if (s.language != ui) l.inLanguage(textLanguageName(l, s.language)),
                  ].join(' · '),
                  selected: s.key == current?.key,
                  trailing: s.key == current?.key ? Icon(Icons.check, color: context.colors.ink, size: 20) : null,
                  onTap: () => Navigator.pop(context, s),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  if (chosen == null) return;
  await ref.read(settingsProvider.notifier).update(
        (s) =>
            kind == StudyKind.translation ? s.copyWith(translationKey: chosen.key) : s.copyWith(tafsirKey: chosen.key),
      );
}
