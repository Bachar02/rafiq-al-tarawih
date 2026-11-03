import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../data/quran.dart';

/// The whole Quran is on the phone: browse to any surah.
Future<int?> showSurahIndex(BuildContext context, {required Quran quran, int? current}) =>
    Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => _SurahIndex(quran: quran, current: current)));

class _SurahIndex extends StatefulWidget {
  const _SurahIndex({required this.quran, this.current});

  final Quran quran;
  final int? current;

  @override
  State<_SurahIndex> createState() => _SurahIndexState();
}

class _SurahIndexState extends State<_SurahIndex> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final surahs = widget.quran.surahs.where((s) {
      if (q.isEmpty) return true;
      return '${s.index}' == q ||
          s.nameTranslit.toLowerCase().contains(q) ||
          s.nameEn.toLowerCase().contains(q) ||
          s.nameAr.contains(_query.trim());
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Surahs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name or number',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: surahs.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final s = surahs[i];
                return ListTile(
                  selected: s.index == widget.current,
                  leading: CircleAvatar(
                    backgroundColor: context.colors.gold.withOpacity(0.15),
                    foregroundColor: context.colors.gold,
                    child: Text('${s.index}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  title: Text(s.nameTranslit),
                  subtitle: Text('${s.nameEn} · ${s.revelationType} · ${s.ayahCount} ayahs'),
                  trailing: Text(s.nameAr, style: const TextStyle(fontFamily: quranFont, fontSize: 22)),
                  onTap: () => Navigator.of(context).pop(s.index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
