import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../data/quran.dart';
import '../../../data/surah_names.dart';
import 'hint_sheet.dart';

/// The whole Quran is on the phone: browse to any surah.
Future<int?> showSurahIndex(BuildContext context, {required Quran quran, required SurahNames names, int? current}) =>
    Navigator.of(context)
        .push<int>(MaterialPageRoute(builder: (_) => _SurahIndex(quran: quran, names: names, current: current)));

class _SurahIndex extends StatefulWidget {
  const _SurahIndex({required this.quran, required this.names, this.current});

  final Quran quran;
  final SurahNames names;
  final int? current;

  @override
  State<_SurahIndex> createState() => _SurahIndexState();
}

class _SurahIndexState extends State<_SurahIndex> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final surahs = searchSurahs(widget.quran, widget.names, _query);
    return Scaffold(
      appBar: AppBar(title: const Text('Surahs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s2),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name or number'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s4),
              itemCount: surahs.length,
              separatorBuilder: (_, __) => const Divider(indent: 48),
              itemBuilder: (context, i) => SurahTile(
                surah: surahs[i],
                names: widget.names,
                selected: surahs[i].index == widget.current,
                onTap: () => Navigator.of(context).pop(surahs[i].index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
