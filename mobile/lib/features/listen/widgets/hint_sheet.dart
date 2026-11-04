import 'package:flutter/material.dart';

import '../../../app/components/settings_group.dart';
import '../../../app/components/sheet.dart';
import '../../../app/components/surah_tile.dart';
import '../../../app/theme.dart';
import '../../../core/recognition/models.dart';
import '../../../data/quran.dart';
import '../../../data/surah_names.dart';
import '../../../l10n/l10n.dart';

/// The user's choice in the hint sheet (distinguishes "no hint" from "cancelled").
class HintChoice {
  const HintChoice(this.hint);
  final Hint? hint;
}

/// Optional help: "tonight starts at surah X / juz N". The engine finds the
/// imam without it and a wrong hint cannot trap it. Changing it restarts the
/// listening session (the engine applies hints at session start), and the
/// sheet says so when a session is active.
Future<HintChoice?> showHintSheet(
  BuildContext context, {
  required Quran quran,
  required SurahNames names,
  Hint? current,
  bool active = false,
}) =>
    showRubricSheet<HintChoice>(
      context,
      expand: true,
      builder: (_) => _HintSheet(quran: quran, names: names, current: current, active: active),
    );

enum _Mode { none, surah, juz }

class _HintSheet extends StatefulWidget {
  const _HintSheet({required this.quran, required this.names, this.current, required this.active});

  final Quran quran;
  final SurahNames names;
  final Hint? current;
  final bool active;

  @override
  State<_HintSheet> createState() => _HintSheetState();
}

class _HintSheetState extends State<_HintSheet> {
  late _Mode _mode = switch (widget.current) {
    SurahHint() => _Mode.surah,
    JuzHint() => _Mode.juz,
    null => _Mode.none,
  };
  String _query = '';

  void _pick(Hint? hint) => Navigator.of(context).pop(HintChoice(hint));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: l.hintSheetTitle,
            explanation: widget.active ? '${l.hintSheetExplanation} ${l.hintSheetRestarts}' : l.hintSheetExplanation,
          ),
          const SizedBox(height: RubricSpace.s4),
          SegmentedButton<_Mode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _Mode.none, label: Text(l.hintNone)),
              ButtonSegment(value: _Mode.surah, label: Text(l.hintSurah)),
              ButtonSegment(value: _Mode.juz, label: Text(l.hintJuz)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) {
              setState(() => _mode = s.first);
              if (s.first == _Mode.none) _pick(null);
            },
          ),
          const SizedBox(height: RubricSpace.s4),
          Expanded(
            child: switch (_mode) {
              _Mode.none => Text(
                  l.hintNoneExplanation,
                  style: RubricText.caption.copyWith(color: context.colors.inkSecondary),
                ),
              _Mode.surah => _surahList(),
              _Mode.juz => _juzList(),
            },
          ),
        ],
      ),
    );
  }

  Widget _surahList() {
    final selected = widget.current is SurahHint ? (widget.current! as SurahHint).surah : null;
    final surahs = searchSurahs(widget.quran, widget.names, _query);
    return Column(
      children: [
        TextField(
          decoration:
              InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.l10n.searchByNameOrNumber),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: RubricSpace.s2),
        Expanded(
          child: ListView.builder(
            itemCount: surahs.length,
            itemBuilder: (context, i) => SurahTile(
              surah: surahs[i],
              names: widget.names,
              selected: surahs[i].index == selected,
              onTap: () => _pick(SurahHint(surahs[i].index)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _juzList() {
    final selected = widget.current is JuzHint ? (widget.current! as JuzHint).juz : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: RubricSpace.s6),
      child: RubricGroup(
        children: [
          for (var juz = 1; juz <= widget.quran.juzCount; juz++)
            RubricRow(
              label: context.l10n.juzNumber(juz),
              value: widget.names.of(widget.quran.juzStartSurah(juz).index),
              selected: juz == selected,
              onTap: () => _pick(JuzHint(juz)),
            ),
        ],
      ),
    );
  }
}

/// Short label for the hint chip.
String hintLabel(AppLocalizations l, Hint hint, SurahNames names) => switch (hint) {
      SurahHint(:final surah) => l.hintTonightSurah(names.of(surah)),
      JuzHint(:final juz) => l.hintTonightJuz(juz),
    };
