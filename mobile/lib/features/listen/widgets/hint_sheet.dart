import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/recognition/models.dart';
import '../../../data/quran.dart';

/// The user's choice in the hint sheet (distinguishes "no hint" from "cancelled").
class HintChoice {
  const HintChoice(this.hint);
  final Hint? hint;
}

/// Optional help: "tonight is surah X / juz N". Detection works without it.
Future<HintChoice?> showHintSheet(BuildContext context, {required Quran quran, Hint? current}) {
  return showModalBottomSheet<HintChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: _HintSheet(quran: quran, current: current)),
  );
}

enum _Mode { none, surah, juz }

class _HintSheet extends StatefulWidget {
  const _HintSheet({required this.quran, this.current});

  final Quran quran;
  final Hint? current;

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Help the app (optional)', style: context.text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Rafiq finds the surah by itself. Telling it where the imam is tonight makes the first detection faster. '
            'If the hint is wrong, it still finds the right place.',
            style: context.text.bodySmall?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: 16),
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.none, label: Text('No hint')),
              ButtonSegment(value: _Mode.surah, label: Text('Surah')),
              ButtonSegment(value: _Mode.juz, label: Text('Juz')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) {
              setState(() => _mode = s.first);
              if (s.first == _Mode.none) _pick(null);
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: switch (_mode) {
              _Mode.none => const SizedBox.shrink(),
              _Mode.surah => _surahList(),
              _Mode.juz => _juzGrid(),
            },
          ),
        ],
      ),
    );
  }

  Widget _surahList() {
    final q = _query.trim().toLowerCase();
    final surahs = widget.quran.surahs.where((s) {
      if (q.isEmpty) return true;
      return '${s.index}' == q ||
          s.nameTranslit.toLowerCase().contains(q) ||
          s.nameEn.toLowerCase().contains(q) ||
          s.nameAr.contains(_query.trim());
    }).toList();
    final selected = widget.current is SurahHint ? (widget.current! as SurahHint).surah : null;
    return Column(
      children: [
        TextField(
          autofocus: false,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), hintText: 'Search by name or number', isDense: true),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: surahs.length,
            itemBuilder: (context, i) {
              final s = surahs[i];
              return ListTile(
                selected: s.index == selected,
                leading: SizedBox(width: 32, child: Text('${s.index}', style: context.text.labelLarge)),
                title: Text(s.nameTranslit),
                subtitle: Text('${s.nameEn} · ${s.ayahCount} ayahs'),
                trailing: Text(s.nameAr, style: const TextStyle(fontFamily: quranFont, fontSize: 22)),
                onTap: () => _pick(SurahHint(s.index)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _juzGrid() {
    final selected = widget.current is JuzHint ? (widget.current! as JuzHint).juz : null;
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 110, childAspectRatio: 1.3),
      itemCount: widget.quran.juzCount,
      itemBuilder: (context, i) {
        final juz = i + 1;
        final start = widget.quran.juzStartSurah(juz);
        return Padding(
          padding: const EdgeInsets.all(4),
          child: juz == selected
              ? FilledButton(onPressed: () => _pick(JuzHint(juz)), child: _JuzLabel(juz: juz, start: start))
              : OutlinedButton(onPressed: () => _pick(JuzHint(juz)), child: _JuzLabel(juz: juz, start: start)),
        );
      },
    );
  }
}

class _JuzLabel extends StatelessWidget {
  const _JuzLabel({required this.juz, required this.start});

  final int juz;
  final Surah start;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Juz $juz', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(start.nameTranslit, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
        ],
      );
}

/// Short label for the hint chip.
String hintLabel(Hint hint, Quran quran) => switch (hint) {
      SurahHint(:final surah) => 'Tonight: ${quran.surah(surah).nameTranslit}',
      JuzHint(:final juz) => 'Tonight: Juz $juz',
    };
