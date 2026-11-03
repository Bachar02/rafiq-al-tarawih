import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../app/theme.dart';
import '../../../core/recognition/models.dart';
import '../../../data/quran.dart';

/// A surah laid out like a mushaf page: ornamental header, basmala, and one
/// flowing justified paragraph of Uthmani text with numbered ayah markers.
///
/// The ayah being recited is highlighted and ayahs already recited are gently
/// dimmed, so the reader sees both "where" and "how far". Every ayah is
/// tappable ([onAyahTap]). Auto-follow scrolls to the exact line of the
/// current ayah inside the paragraph; if the user scrolls by hand, following
/// pauses for [manualHold] and a "Back to the imam" button appears.
class MushafView extends StatefulWidget {
  const MushafView({
    super.key,
    required this.quran,
    required this.surah,
    required this.current,
    required this.confident,
    required this.onAyahTap,
    required this.onOpenSurah,
    this.textScale = 1.0,
    this.manualHold = const Duration(seconds: 8),
  });

  final Quran quran;
  final int surah;

  /// The imam's position (highlighted if it is in this surah).
  final Position? current;

  /// Full-strength highlight when following; softer when not sure.
  final bool confident;
  final ValueChanged<Verse> onAyahTap;
  final ValueChanged<int> onOpenSurah;
  final double textScale;
  final Duration manualHold;

  @override
  State<MushafView> createState() => _MushafViewState();
}

class _MushafViewState extends State<MushafView> {
  final _scroll = ScrollController();
  final _paragraphKey = GlobalKey();
  final _recognizers = <int, TapGestureRecognizer>{}; // by ayah
  final _ranges = <int, TextRange>{}; // ayah -> character range in the paragraph
  DateTime? _manualUntil;
  Timer? _holdTimer;

  bool get _following => _manualUntil == null || DateTime.now().isAfter(_manualUntil!);

  @override
  void initState() {
    super.initState();
    _buildRecognizers();
    _scheduleFollow(animate: false);
  }

  @override
  void didUpdateWidget(MushafView old) {
    super.didUpdateWidget(old);
    if (old.surah != widget.surah) {
      _buildRecognizers();
      // Not here: scrolling notifies listeners (e.g. the app bar), and
      // didUpdateWidget runs during build. Jump after the frame instead.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(0);
        _follow(animate: false);
      });
    } else if (widget.current != old.current && _following) {
      _scheduleFollow();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _buildRecognizers() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _recognizers.clear();
    for (final v in widget.quran.surahVerses(widget.surah)) {
      // Reads `widget` at tap time, so the callback is always the current one.
      _recognizers[v.ayah] = TapGestureRecognizer()..onTap = () => widget.onAyahTap(v);
    }
  }

  void _scheduleFollow({bool animate = true}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow(animate: animate));

  /// Scroll so the first line of the current ayah sits ~30% down the view.
  void _follow({bool animate = true}) {
    final current = widget.current;
    if (!mounted || current == null || current.surah != widget.surah || !_scroll.hasClients) return;
    final range = _ranges[current.ayah];
    final paragraph = _paragraphKey.currentContext?.findRenderObject();
    if (range == null || paragraph is! RenderParagraph || !paragraph.hasSize) return;
    final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: range.start, extentOffset: range.end));
    if (boxes.isEmpty) return;
    final viewport = RenderAbstractViewport.maybeOf(paragraph);
    if (viewport == null) return;
    final target = viewport
        .getOffsetToReveal(paragraph, 0.3, rect: boxes.first.toRect())
        .offset
        .clamp(_scroll.position.minScrollExtent, _scroll.position.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(target);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
      _holdTimer?.cancel();
      setState(() => _manualUntil = DateTime.now().add(widget.manualHold));
      _holdTimer = Timer(widget.manualHold, () {
        if (!mounted) return;
        setState(() => _manualUntil = null);
        _follow();
      });
    }
    return false;
  }

  void _backToImam() {
    _holdTimer?.cancel();
    setState(() => _manualUntil = null);
    _follow();
  }

  TextSpan _paragraph(BuildContext context, List<Verse> verses, double fontSize) {
    final colors = context.colors;
    final ink = context.scheme.onSurface;
    final current = widget.current?.surah == widget.surah ? widget.current : null;
    final highlight = Paint()..color = colors.highlight.withOpacity(widget.confident ? 1 : 0.55);
    final spans = <InlineSpan>[];
    var offset = 0;
    _ranges.clear();
    for (final v in verses) {
      final isCurrent = current?.ayah == v.ayah;
      final recited = current != null && v.ayah < current.ayah;
      final text = v.uthmani;
      final marker = ' ۝${arabicDigits(v.ayah)} ';
      _ranges[v.ayah] = TextRange(start: offset, end: offset + text.length);
      offset += text.length + marker.length;
      final recognizer = _recognizers[v.ayah];
      spans
        ..add(TextSpan(
          text: text,
          recognizer: recognizer,
          style: TextStyle(color: recited ? colors.recited : ink, background: isCurrent ? highlight : null),
        ))
        ..add(TextSpan(
          text: marker,
          recognizer: recognizer,
          style: TextStyle(color: colors.gold, fontSize: fontSize * 0.95),
        ));
    }
    return TextSpan(
      style: TextStyle(fontFamily: quranFont, fontSize: fontSize, height: 2.1, color: ink),
      children: spans,
    );
  }

  @override
  Widget build(BuildContext context) {
    final quran = widget.quran;
    final surah = quran.surah(widget.surah);
    final verses = quran.surahVerses(widget.surah);
    final fontSize = 25.0 * widget.textScale;
    final showBackButton = !_following && widget.current?.surah == widget.surah;

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.paper,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.colors.gold.withOpacity(0.25)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SurahHeader(surah: surah),
                  if (surah.hasBasmala)
                    Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 4),
                      child: Text(
                        surah.basmalaUthmani.isEmpty ? quran.verse(1).uthmani : surah.basmalaUthmani,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontFamily: quranFont, fontSize: fontSize * 1.05, height: 2),
                      ),
                    ),
                  const SizedBox(height: 8),
                  RichText(
                    key: _paragraphKey,
                    text: _paragraph(context, verses, fontSize),
                    textAlign: TextAlign.justify,
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 20),
                  _SurahNav(quran: quran, surah: widget.surah, onOpen: widget.onOpenSurah),
                ],
              ),
            ),
          ),
        ),
        if (showBackButton)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: _backToImam,
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text('Back to the imam'),
              ),
            ),
          ),
      ],
    );
  }
}

/// Ornamental surah title, in the spirit of a printed mushaf.
class SurahHeader extends StatelessWidget {
  const SurahHeader({super.key, required this.surah});

  final Surah surah;

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.gold;
    final small = context.text.labelSmall?.copyWith(color: context.colors.muted, letterSpacing: 0.4);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withOpacity(0.7), width: 1.2),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: gold.withOpacity(0.35)),
          color: gold.withOpacity(0.06),
        ),
        child: Row(
          children: [
            SizedBox(width: 64, child: Text(surah.revelationType, style: small)),
            Expanded(
              child: Text(
                'سُورَةُ ${surah.nameAr}',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: quranFont, fontSize: 24, height: 1.6, color: context.scheme.onSurface),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text('${surah.ayahCount} ayahs', style: small, textAlign: TextAlign.end),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurahNav extends StatelessWidget {
  const _SurahNav({required this.quran, required this.surah, required this.onOpen});

  final Quran quran;
  final int surah;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    // Reading order is right to left: the next surah is on the left.
    return Row(
      children: [
        if (surah < 114)
          Expanded(
            child: TextButton.icon(
              onPressed: () => onOpen(surah + 1),
              icon: const Icon(Icons.chevron_left),
              label: Text(quran.surah(surah + 1).nameTranslit, overflow: TextOverflow.ellipsis),
            ),
          )
        else
          const Spacer(),
        if (surah > 1)
          Expanded(
            child: TextButton(
              onPressed: () => onOpen(surah - 1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(child: Text(quran.surah(surah - 1).nameTranslit, overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          )
        else
          const Spacer(),
      ],
    );
  }
}

/// 29 -> ٢٩
String arabicDigits(int n) => n.toString().split('').map((d) => String.fromCharCode(0x0660 + int.parse(d))).join();
