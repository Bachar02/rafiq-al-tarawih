/// Word highlighting in Taraweeh mode (developer setting, off by default;
/// PLAN.md §33): which displayed word of the current ayah to mark, if any.
///
/// Nothing is marked unless every one of these holds, so an uncertain word is
/// hidden rather than shown: the setting is on; the session is listening; the
/// engine's latest result named a word, and the evidence for it is fresh; the
/// ayah engine is sure; the word is in the ayah the screen marks as the
/// imam's (not during al-Fatiha's excursion, not the basmala); and the
/// ayah's Uthmani/Simple Clean word mapping can be trusted. No prediction:
/// the word is the one the speech model last confirmed.
library;

import '../../core/recognition/models.dart';
import '../../core/text/word_map.dart';
import '../../data/quran.dart';
import 'listen_state.dart';

/// The displayed piece of the current ayah to mark (see [displayPieces]), or null.
int? highlightedPiece(
  ListenState state, {
  required bool enabled,
  required Quran quran,
  required DisplayWordMap words,
  required DateTime now,
  required Duration staleAfter,
}) {
  final live = state.liveWord;
  if (!enabled || live == null || state.phase != SessionPhase.listening) return null;
  if (now.difference(live.heardAt) > staleAfter) return null;
  if (state.track.status != TrackStatus.tracking) return null;
  final shown = state.displayed;
  if (shown == null || shown.verseId != live.word.verseId) return null;
  final verse = quran.verse(shown.verseId);
  return words.pieceOf(verseId: verse.id, uthmani: verse.uthmani, simple: verse.text, index: live.word.index);
}
