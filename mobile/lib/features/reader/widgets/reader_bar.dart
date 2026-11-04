import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../l10n/l10n.dart';
import '../../../data/settings.dart';

/// Where the reader is (surah, juz, page) and the reader's actions. The only
/// part of the reader that rebuilds as the text scrolls.
class ReaderBar extends ConsumerWidget {
  const ReaderBar({
    super.key,
    required this.onNavigate,
    required this.onSettings,
    this.onSearch,
    this.onToggleLayout,
  });

  /// Surahs, juz, pages and bookmarks.
  final VoidCallback onNavigate;
  final VoidCallback? onSearch;
  final VoidCallback onSettings;

  /// Switch between scroll and pages (shown when the bar has room).
  final VoidCallback? onToggleLayout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l = context.l10n;
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final verse = quran.verse(ref.watch(readingPositionProvider));
    final surah = quran.surah(verse.surah);
    final juz = quran.juzOf(verse.id), page = quran.pageOf(verse.id);
    final pages = ref.watch(settingsProvider.select((s) => s.readingLayout)) == ReadingLayout.pages;
    // On a narrow phone the place (juz, page) keeps the room; the layout
    // stays one tap away in Settings.
    final roomy = MediaQuery.sizeOf(context).width >= 360;
    final where = l.juzPage(juz, page);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(RubricSpace.s1, RubricSpace.s1, RubricSpace.s1, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: l.tooltipNavigate,
            onPressed: onNavigate,
            icon: const Icon(Icons.toc),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: l.semReaderBar(names.of(surah.index), verse.ayah, juz, page),
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
                      // The name on one line; where in the Quran, which
                      // matters most on a narrow phone, alone on the next.
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: surah.nameAr,
                              style: RubricText.surahAr.copyWith(fontSize: 22, height: 1.3, color: c.ink),
                            ),
                            if (!names.isArabic)
                              TextSpan(
                                text: '  ${names.of(surah.index)}',
                                style: RubricText.caption.copyWith(color: c.inkSecondary),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        where,
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
          if (onToggleLayout != null && roomy)
            IconButton(
              tooltip: pages ? l.tooltipScrollView : l.tooltipPageView,
              onPressed: onToggleLayout,
              icon: Icon(pages ? Icons.view_day_outlined : Icons.auto_stories_outlined),
            ),
          if (onSearch != null)
            IconButton(tooltip: l.tooltipSearch, onPressed: onSearch, icon: const Icon(Icons.search)),
          IconButton(tooltip: l.settings, onPressed: onSettings, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
    );
  }
}
