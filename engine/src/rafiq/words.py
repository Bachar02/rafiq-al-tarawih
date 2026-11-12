"""Word-level tracking: which word of the ayah is the imam reciting right now?

The ayah tracker (`rafiq.tracking`) answers "where in the Quran?" from a few
seconds of Whisper text. This module answers the finer question, "which word?",
from a stream of letters as a streaming CTC model emits them, about one every
80 ms. It never searches the whole Quran: it is *anchored* by the ayah tracker
and follows the text from there, which is what makes it cheap and safe.

Because the text being recited is known, this is alignment, not recognition.
Each heard letter extends an edit-distance alignment against a window of the
expected text (about 20 words behind the imam and 30 ahead), one row per
letter, so the cost per letter is a few hundred additions:

    D'[j] = min(D[j-1] + sub(u, ref[j-1]),   # heard letter u says ref letter j-1
                D[j]   + ins(u),             # u is extra (noise, a model error)
                D'[j-1] + del(ref[j-1]))     # ref letter j-1 was not heard

`D[j]` is the cost of "the imam has just said reference letter j-1". The
cheapest `j` is where he is. On top of plain edit distance:

* **Tajweed and orthography.** Letters that are written but often not heard
  (long vowels, the alef of hamzat al-wasl and of tanween, the lam of al- before
  a sun letter) are cheap to drop, and letters that sound alike are cheap to
  confuse. Stretched vowels (madd) cost nothing: a CTC model emits a letter
  once however long it is held.
* **Pauses** are not evidence: no letters, no change.
* **Repetition.** The imam often goes back a few words, or to the start of the
  ayah. Every word start behind the current position is reachable at a fixed
  cost (`back_cost`), so after a few letters the repeat wins.
* **Basmala.** Before ayah 1 of a surah it may be recited aloud or not, so it is
  an optional segment of the expected text, skippable for free.
* **Resync.** No position is ever more than `resync_cost` worse than the best,
  so a jump inside the window is found after a few words.
* **Leaving the window** (al-Fatiha of a new rakʿah, a far jump): every letter
  then costs about one, the recent error rate climbs, the word is no longer
  shown, and the caller re-anchors from the ayah tracker.

The tracker never uses time: it is fed letters, in order. That keeps it
independent of the speech model (any CTC model whose tokens normalize to
Arabic letters, including subword ones) and exactly reproducible in Dart
(`mobile/lib/core/engine/word_tracker.dart`, golden tests), which is why
confidence is built from sums and ratios only.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from rafiq.matching.index import QuranIndex
from rafiq.normalize import normalize

# Status values, as the ayah tracker names them.
IDLE, TRACKING, UNCERTAIN, LOST = "idle", "tracking", "uncertain", "lost"

# Written but often not heard: long vowels and the alef of hamzat al-wasl or
# tanween. Dropping one, or hearing a spurious one (a madd), is half an error.
WEAK = frozenset("اوي")

# Sun letters: the lam of al- before them is assimilated ("ash-shams").
SUN = frozenset("تثدذرزسشصضطظلن")

# Letters a speech model confuses (emphatic and plain, similar sounds).
_SIMILAR = ["ضد", "ظذ", "ذز", "صس", "طت", "حه", "قك", "عا", "ثس", "غخ"]
SIMILAR = frozenset(p for a, b in _SIMILAR for p in (a + b, b + a))


@dataclass(frozen=True, slots=True)
class WordTrackerConfig:
    behind: int = 20  # words of the window behind the imam: how far back a repetition is found
    ahead: int = 30  # words of the window ahead of the imam
    anchor_slack: int = 12  # words after an anchor where the imam may already be (the anchor is late)
    sub_cost: float = 1.0
    similar_cost: float = 0.5  # a letter heard as a similar-sounding one
    ins_cost: float = 1.0  # a heard letter that is not in the text
    weak_ins_cost: float = 0.5
    del_cost: float = 1.0  # a letter of the text that was not heard
    weak_del_cost: float = 0.4
    back_cost: float = 2.0  # going back to an earlier word start (the imam repeats)
    resync_cost: float = 6.0  # no position is ever worse than the best by more than this
    error_window: int = 12  # letters over which the recent error rate is measured
    max_error: float = 0.45  # recent cost per letter above this: not sure where the imam is
    burst: int = 3  # ...and so is this much cost over the last `burst` letters: he has just
    burst_cost: float = 2.0  # left the text (a repeat, al-Fatiha), so stop highlighting at once
    min_margin: float = 1.0  # the best must beat every position more than 2 words away by this
    min_letters: int = 8  # letters after an anchor before a word is first shown
    confirm: int = 4  # letters a backward or far move must hold before it is shown
    lost_after: int = 30  # consecutive unsure letters before the word is no longer shown
    # Verse ranges the imam leaves for where he was, not for what follows: al-Fatiha.
    # Anchored inside one, the window ends with it ("amin" is not 2:1 "الم").
    excursions: tuple[tuple[int, int], ...] = ((1, 7),)


@dataclass(frozen=True, slots=True)
class WordState:
    word: int | None  # stream position of the word being recited (None: not shown)
    status: str
    confidence: float  # 0..1: low recent error and a clear margin over rivals
    basmala: int | None = None  # reciting the basmala before this verse id (word is then None)


class WordTracker:
    def __init__(
        self,
        index: QuranIndex,
        config: WordTrackerConfig = WordTrackerConfig(),
        basmala_verses: Iterable[int] | None = None,
    ) -> None:
        """`basmala_verses`: verse ids preceded by a recited basmala (default: from the Quran data)."""
        self.index = index
        self.config = config
        if basmala_verses is None:
            q = index.quran
            basmala_verses = [s.first_verse_id for s in q.surahs if s.has_basmala]
        # Stream position of the first word of each such ayah -> its verse id.
        self._basmala_at = {index.verse_span(v)[0]: v for v in sorted(basmala_verses)}
        self._basmala_words = index.words[slice(*index.verse_span(1))]  # al-Fatiha 1:1
        self._excursions = [(index.verse_span(a)[0], index.verse_span(b)[1]) for a, b in config.excursions]
        self.reset()

    # -- public API ------------------------------------------------------

    def reset(self) -> None:
        """Forget everything: idle until the next `anchor`."""
        self._anchored = False
        self._letters: list[str] = []
        self._weak: list[bool] = []
        self._pos: list[int] = []  # stream position each letter belongs to (basmala: the word before)
        self._bas: list[int] = []  # verse id whose basmala the letter belongs to, else 0
        self._keys: list[tuple[int, int, int]] = []
        self._starts: list[int] = []  # j at the start of each (non-basmala) word
        self._skips: dict[int, int] = {}  # basmala: j at its end -> j at its start
        self._d: list[float] = [0.0]
        self._w0 = self._w1 = 0
        self._end = len(self.index.words)  # the window never goes past this
        self._total = 0.0
        self._ring: list[float] = []
        self._letters_seen = 0
        self._shown: int | None = None
        self._pending: int | None = None
        self._pending_count = 0
        self._ok_run = 0
        self._unsure = 0
        self._resume = 0  # sure letters still needed after a pause before highlighting again
        self._prev_best = 0
        self._state = WordState(None, IDLE, 0.0)

    @property
    def state(self) -> WordState:
        return self._state

    def anchor(self, word: int) -> WordState:
        """The ayah tracker says the imam is at (or a little past) stream position `word`."""
        cfg = self.config
        n = len(self.index.words)
        word = min(max(word, 0), n - 1)
        self.reset()
        self._anchored = True
        for lo, hi in self._excursions:
            if lo <= word < hi:
                self._end = hi
        self._build(max(0, word - cfg.behind))
        lo, hi = word - 2, word + cfg.anchor_slack
        self._d = [0.0 if lo <= self._pos_of(j) <= hi else cfg.resync_cost for j in range(len(self._d))]
        self._apply_skips(self._d)
        self._ring = [0.0]
        self._state = WordState(None, UNCERTAIN, 0.0)
        return self._state

    def pause(self) -> WordState:
        """The imam has been silent a long time (rukuʿ, sujud, between rakʿahs).

        He may now start anything, al-Fatiha above all, whose first letters
        (bism, al-) fit almost anywhere. So nothing is highlighted again until
        `confirm` letters agree with the text.
        """
        self._resume = self.config.confirm
        if self._state.status == TRACKING:
            self._state = WordState(self._state.word, UNCERTAIN, self._state.confidence, self._state.basmala)
        return self._state

    def feed(self, tokens: str | Iterable[str]) -> WordState:
        """New tokens from the speech model, in order (any text: it is normalized to letters)."""
        if isinstance(tokens, str):
            tokens = [tokens]
        for token in tokens:
            for u in normalize(token).replace(" ", ""):
                if self._anchored:
                    self._step(u)
        return self._state

    # -- the expected text -------------------------------------------------

    def _build(self, w0: int) -> None:
        """The window of expected letters: words [w0, w0 + behind + ahead)."""
        cfg = self.config
        w1 = min(self._end, w0 + cfg.behind + cfg.ahead)
        letters, weak, pos, bas, keys, starts, skips = [], [], [], [], [], [], {}

        def add_word(text: str, p: int, verse: int, k0: int) -> None:
            for k, ch in enumerate(text):
                letters.append(ch)
                sun_lam = k == 1 and text[0] == "ا" and ch == "ل" and len(text) > 2 and text[2] in SUN
                weak.append(ch in WEAK or sun_lam)
                pos.append(p)
                bas.append(verse)
                keys.append((p, 1 if verse else 0, k0 + k))

        for p in range(w0, w1):
            verse = self._basmala_at.get(p)
            if verse is not None:
                begin, k0 = len(letters), 0
                for w in self._basmala_words:
                    add_word(w, p - 1, verse, k0)
                    k0 += len(w)
                skips[len(letters)] = begin
            starts.append(len(letters))
            add_word(self.index.words[p], p, 0, 0)

        self._letters, self._weak, self._pos, self._bas, self._keys = letters, weak, pos, bas, keys
        self._starts, self._skips = starts, skips
        self._w0, self._w1 = w0, w1
        self._d = [self.config.resync_cost] * (len(letters) + 1)

    def _pos_of(self, j: int) -> int:
        """Stream position after `j` letters: the word of the last letter consumed."""
        return self._pos[j - 1] if j > 0 else self._w0 - 1

    def _apply_skips(self, d: list[float]) -> None:
        for end, begin in self._skips.items():
            if d[begin] < d[end]:
                d[end] = d[begin]

    def _rebase(self, w0: int) -> None:
        """Slide the window forward, keeping each letter's cost."""
        old = {k: j + 1 for j, k in enumerate(self._keys)}
        old_d = self._d
        self._build(w0)
        cap = self.config.resync_cost
        self._d = [cap] + [old_d[old[k]] if k in old else cap for k in self._keys]

    # -- one heard letter --------------------------------------------------

    def _step(self, u: str) -> None:
        cfg = self.config
        d, ref, weak = self._d, self._letters, self._weak
        ins = cfg.weak_ins_cost if u in WEAK else cfg.ins_cost
        new = [0.0] * len(d)
        new[0] = d[0] + ins
        for j in range(1, len(d)):
            r = ref[j - 1]
            if r == u:
                sub = 0.0
            elif r + u in SIMILAR:
                sub = cfg.similar_cost
            else:
                sub = cfg.sub_cost
            best = d[j - 1] + sub
            x = d[j] + ins
            if x < best:
                best = x
            x = new[j - 1] + (cfg.weak_del_cost if weak[j - 1] else cfg.del_cost)
            if x < best:
                best = x
            begin = self._skips.get(j)
            if begin is not None and new[begin] < best:
                best = new[begin]
            new[j] = best

        low = min(new)
        self._total += low
        for j in range(len(new)):
            new[j] -= low
        b = self._best(new)
        for s in self._starts:
            if s >= b:
                break
            if cfg.back_cost < new[s]:
                new[s] = cfg.back_cost
        for j in range(len(new)):
            if new[j] > cfg.resync_cost:
                new[j] = cfg.resync_cost
        self._apply_skips(new)
        self._d = new

        self._letters_seen += 1
        self._ring.append(self._total)
        if len(self._ring) > cfg.error_window + 1:
            self._ring.pop(0)
        # Already at the last letter of the window before this one: this letter
        # is past the end of the text (after al-Fatiha: "amin", then his surah).
        beyond = b == len(new) - 1 and self._prev_best == b
        self._prev_best = b
        self._display(b, beyond)

    def _best(self, d: list[float]) -> int:
        """Cheapest j; on a tie the one nearest the shown word, then the earliest."""
        best, best_gap = 0, None
        for j in range(len(d)):
            if j and d[j] > d[best]:
                continue
            gap = abs(self._pos_of(j) - self._shown) if self._shown is not None else 0
            if j == 0 or d[j] < d[best] or gap < best_gap:
                best, best_gap = j, gap
        return best

    # -- display policy ----------------------------------------------------

    def _display(self, b: int, beyond: bool) -> None:
        cfg = self.config
        d = self._d
        here = self._pos_of(b)
        margin = cfg.resync_cost
        for j in range(len(d)):
            if abs(self._pos_of(j) - here) > 2 and d[j] - d[b] < margin:
                margin = d[j] - d[b]
        k = len(self._ring) - 1
        error = (self._ring[-1] - self._ring[0]) / k if k else 0.0
        burst = self._ring[-1] - self._ring[-1 - min(k, cfg.burst)]
        ok = (
            error <= cfg.max_error
            and burst < cfg.burst_cost
            and margin >= cfg.min_margin
            and self._letters_seen >= cfg.min_letters
            and not beyond
        )
        self._ok_run = self._ok_run + 1 if ok else 0
        self._unsure = 0 if ok else self._unsure + 1
        if self._resume:
            self._resume = self._resume - 1 if ok else cfg.confirm

        if ok:
            if self._shown is None:
                if self._ok_run >= cfg.confirm:
                    self._shown, self._pending, self._pending_count = here, None, 0
            elif 0 <= here - self._shown <= 2:
                self._shown, self._pending, self._pending_count = here, None, 0
            else:
                if self._pending is not None and abs(here - self._pending) <= 1:
                    self._pending_count += 1
                else:
                    self._pending, self._pending_count = here, 1
                if self._pending_count >= cfg.confirm:
                    self._shown, self._pending, self._pending_count = here, None, 0

        if self._unsure >= cfg.lost_after:
            self._shown, self._pending, self._pending_count = None, None, 0
            status = LOST
        elif ok and self._shown == here and not self._resume:
            status = TRACKING
        else:
            status = UNCERTAIN
        quality = max(0.0, 1.0 - error)
        confidence = quality * min(1.0, margin / cfg.back_cost)
        basmala = None
        if status == TRACKING and b > 0 and self._bas[b - 1]:
            basmala = self._bas[b - 1]
        word = None if basmala else self._shown
        self._state = WordState(word, status, confidence, basmala)

        if here - self._w0 > cfg.behind + 5 and self._w1 < self._end:
            self._rebase(here - cfg.behind)
