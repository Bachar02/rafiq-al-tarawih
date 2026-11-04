import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';

/// Where the reader is (surah, juz, page) and the reader's actions. The only
/// part of the reader that rebuilds as the text scrolls.
class ReaderBar extends ConsumerWidget {
  const ReaderBar({
    super.key,
    required this.onNavigate,
    required this.onSettings,
    this.onSearch,
  });

  /// Surahs, juz, pages and bookmarks.
  final VoidCallback onNavigate;
  final VoidCallback? onSearch;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final verse = quran.verse(ref.watch(readingPositionProvider));
    final surah = quran.surah(verse.surah);
    final meta = '${names.of(surah.index)} · Juz ${quran.juzOf(verse.id)} · Page ${quran.pageOf(verse.id)}';

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(RubricSpace.s1, RubricSpace.s1, RubricSpace.s1, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Surahs, juz and bookmarks',
            onPressed: onNavigate,
            icon: const Icon(Icons.toc),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: '${names.of(surah.index)}, ayah ${verse.ayah}. Juz ${quran.juzOf(verse.id)}, '
                  'page ${quran.pageOf(verse.id)}. Open the index',
              excludeSemantics: true,
              child: InkWell(
                onTap: onNavigate,
                borderRadius: BorderRadius.circular(RubricRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s2, vertical: RubricSpace.s1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        surah.nameAr,
                        maxLines: 1,
                        textDirection: TextDirection.rtl,
                        style: RubricText.surahAr.copyWith(fontSize: 22, height: 1.3, color: c.ink),
                      ),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RubricText.caption.copyWith(color: c.inkSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onSearch != null)
            IconButton(tooltip: 'Search the Quran', onPressed: onSearch, icon: const Icon(Icons.search)),
          IconButton(tooltip: 'Settings', onPressed: onSettings, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
    );
  }
}
