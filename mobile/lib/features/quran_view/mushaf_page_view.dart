import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/components/quran_text.dart';
import '../../app/theme.dart';
import '../../core/text/quran_display.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';
import '../../l10n/l10n.dart';
import 'book_items.dart';

/// Jumps for a [MushafPageView]. Calls before it is attached do nothing.
class MushafPageController {
  _MushafPageViewState? _view;

  /// The page shown now (1..604), once attached.
  int? get page => _view?._page;

  /// Show the page [verseId] is on.
  void jumpToVerse(int verseId) => _view?._jumpToPage(_view!.widget.quran.pageOf(verseId));
}

/// The Quran one Madinah-mushaf page at a time, swiped right to left as a
/// printed mushaf is turned: the next page comes from the left.
///
/// Each page holds exactly the ayahs Tanzil places on it (PLAN.md §18, R1),
/// flowing as one paragraph per surah: the text is not a facsimile of the
/// printed lines, so a page longer than the screen scrolls within itself.
/// The same text size, ayah taps and marks as the scrolling reader.
class MushafPageView extends StatefulWidget {
  const MushafPageView({
    super.key,
    required this.quran,
    required this.names,
    required this.initialVerse,
    this.controller,
    this.textScale = 1.0,
    this.highlightedVerse,
    this.bookmarkedVerses = const {},
    this.notedVerses = const {},
    this.onAyahTap,
    this.onAyahLongPress,
    this.onPageChanged,
    this.onUserScroll,
    this.bottomPadding = 0,
  });

  final Quran quran;
  final SurahNames names;

  /// The view opens on this verse's page.
  final int initialVerse;
  final MushafPageController? controller;
  final double textScale;
  final int? highlightedVerse;

  /// Ayahs that carry the bookmark ribbon.
  final Set<int> bookmarkedVerses;

  /// Ayahs that carry the note icon.
  final Set<int> notedVerses;
  final ValueChanged<Verse>? onAyahTap;
  final ValueChanged<Verse>? onAyahLongPress;

  /// A new page settled into view (1..604).
  final ValueChanged<int>? onPageChanged;

  /// The user scrolled within a page (for hiding floating controls).
  final ValueChanged<ScrollDirection>? onUserScroll;

  /// Room at the end of each page for an overlay.
  final double bottomPadding;

  /// Mushaf pages are denser than the scrolling text: 22px × the text size.
  static const baseFontSize = 22.0;

  @override
  State<MushafPageView> createState() => _MushafPageViewState();
}

class _MushafPageViewState extends State<MushafPageView> {
  late final PageController _pages;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.quran.pageOf(widget.initialVerse);
    _pages = PageController(initialPage: _page - 1);
    widget.controller?._view = this;
  }

  @override
  void didUpdateWidget(MushafPageView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._view == this) old.controller!._view = null;
      widget.controller?._view = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._view == this) widget.controller!._view = null;
    _pages.dispose();
    super.dispose();
  }

  void _jumpToPage(int page) {
    if (!_pages.hasClients) return;
    _pages.jumpToPage(page - 1);
  }

  void _settled(int index) {
    _page = index + 1;
    widget.onPageChanged?.call(_page);
  }

  @override
  Widget build(BuildContext context) {
    // A mushaf turns right to left in every interface language.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PageView.builder(
        controller: _pages,
        itemCount: widget.quran.pages.count,
        onPageChanged: _settled,
        itemBuilder: (context, i) => _MushafPage(
          quran: widget.quran,
          names: widget.names,
          page: i + 1,
          fontSize: MushafPageView.baseFontSize * widget.textScale,
          highlightedVerse: widget.highlightedVerse,
          bookmarkedVerses: widget.bookmarkedVerses,
          notedVerses: widget.notedVerses,
          onAyahTap: widget.onAyahTap,
          onAyahLongPress: widget.onAyahLongPress,
          onUserScroll: widget.onUserScroll,
          bottomPadding: widget.bottomPadding,
        ),
      ),
    );
  }
}

/// One page: a header, its ayahs as flowing paragraphs (a surah's header and
/// basmala where one begins), and the page number at the foot.
class _MushafPage extends StatefulWidget {
  const _MushafPage({
    required this.quran,
    required this.names,
    required this.page,
    required this.fontSize,
    required this.highlightedVerse,
    required this.bookmarkedVerses,
    required this.notedVerses,
    required this.onAyahTap,
    required this.onAyahLongPress,
    required this.onUserScroll,
    required this.bottomPadding,
  });

  final Quran quran;
  final SurahNames names;
  final int page;
  final double fontSize;
  final int? highlightedVerse;
  final Set<int> bookmarkedVerses;
  final Set<int> notedVerses;
  final ValueChanged<Verse>? onAyahTap;
  final ValueChanged<Verse>? onAyahLongPress;
  final ValueChanged<ScrollDirection>? onUserScroll;
  final double bottomPadding;

  @override
  State<_MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<_MushafPage> {
  /// One per ayah span; replaced on every build, disposed with the page.
  var _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers = [];
  }

  /// The page's ayahs in runs, one per surah.
  List<List<Verse>> _runs() {
    final quran = widget.quran;
    final runs = <List<Verse>>[];
    for (var id = quran.pages.start(widget.page); id <= quran.pages.end(widget.page); id++) {
      final v = quran.verse(id);
      if (runs.isEmpty || runs.last.first.surah != v.surah) runs.add([]);
      runs.last.add(v);
    }
    return runs;
  }

  /// Which ayah each span of the page's text is, for a long press.
  final _spanVerse = Map<InlineSpan, Verse>.identity();

  /// One key per paragraph (runs are fixed for a page), to find its text.
  final _runKeys = <int, GlobalKey>{};

  TextSpan _paragraph(List<Verse> verses, Color ink, Color mark, Color ribbon) {
    final spans = <InlineSpan>[];
    for (final v in verses) {
      final tap = widget.onAyahTap;
      final recognizer = tap == null ? null : (TapGestureRecognizer()..onTap = () => tap(v));
      if (recognizer != null) _recognizers.add(recognizer);
      for (final (marked, icon) in [
        (widget.bookmarkedVerses.contains(v.id), Icons.bookmark),
        (widget.notedVerses.contains(v.id), noteIcon),
      ]) {
        if (!marked) continue;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 2),
            child: Icon(icon, size: widget.fontSize * 0.55, color: ribbon),
          ),
        ));
      }
      final style = v.id == widget.highlightedVerse ? TextStyle(backgroundColor: mark) : null;
      final span = TextSpan(
        text: '${displayAyahText(v.uthmani)}${ayahEndMarker(v.ayah)} ',
        recognizer: recognizer,
        style: style,
      );
      _spanVerse[span] = v;
      spans.add(span);
    }
    return TextSpan(
      style: RubricText.quranBody.copyWith(fontSize: widget.fontSize, height: 2.0, color: ink),
      children: spans,
    );
  }

  /// A long press on paragraph [run]: the ayah under the finger, found by
  /// the text's own hit test.
  void _longPress(int run, Offset global) {
    final hold = widget.onAyahLongPress;
    final paragraph = _runKeys[run]?.currentContext?.findRenderObject();
    if (hold == null || paragraph is! RenderParagraph) return;
    final position = paragraph.getPositionForOffset(paragraph.globalToLocal(global));
    final verse = _spanVerse[paragraph.text.getSpanForPosition(position)];
    if (verse != null) hold(verse);
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    _spanVerse.clear();
    final c = context.colors;
    final l = context.l10n;
    final quran = widget.quran;
    final first = quran.verse(quran.pages.start(widget.page));
    final caption = RubricText.caption.copyWith(color: c.inkSecondary);

    return LayoutBuilder(
      builder: (context, constraints) {
        final justify = justifyQuran(
          columnWidth: constraints.maxWidth - 2 * RubricSpace.gutter,
          fontSize: widget.fontSize,
        );
        return Semantics(
          label: l.pageNumber(widget.page),
          child: NotificationListener<UserScrollNotification>(
            onNotification: (n) {
              if (n.metrics.axis == Axis.vertical) widget.onUserScroll?.call(n.direction);
              return false;
            },
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                RubricSpace.gutter,
                RubricSpace.s2,
                RubricSpace.gutter,
                RubricSpace.s4 + widget.bottomPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The running head: the surah at the start, the juz at the end.
                  Row(
                    children: [
                      Text(quran.surah(first.surah).nameAr, style: caption),
                      const Spacer(),
                      Text(l.juzNumber(quran.juzOf(first.id)), style: caption),
                    ],
                  ),
                  Divider(color: c.hairline),
                  for (final (i, run) in _runs().indexed) ...[
                    if (run.first.ayah == 1)
                      SurahHeader(
                        quran: quran,
                        surah: quran.surah(run.first.surah),
                        names: widget.names,
                        scale: widget.fontSize / RubricText.quranBody.fontSize!,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: RubricSpace.s1),
                      child: GestureDetector(
                        // Screen readers bookmark through each ayah's sheet
                        // (its span is a link); this is the sighted shortcut.
                        excludeFromSemantics: true,
                        onLongPressStart:
                            widget.onAyahLongPress == null ? null : (d) => _longPress(i, d.globalPosition),
                        child: Text.rich(
                          _paragraph(run, c.ink, c.mark, c.inkSecondary),
                          key: _runKeys.putIfAbsent(i, GlobalKey.new),
                          textAlign: justify ? TextAlign.justify : TextAlign.start,
                          textScaler: TextScaler.noScaling,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: RubricSpace.s2),
                  Text(arabicDigits(widget.page), textAlign: TextAlign.center, style: caption),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
