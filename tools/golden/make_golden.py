"""Golden files: the Python engine's outputs, for checking the Dart port against.

The app will run the engine's logic in Dart (Phase 6). Every piece that is
ported gets a golden file generated here from the Python reference, and a
Dart test that must reproduce it exactly, so the two can never drift apart.

    .venv/Scripts/python tools/golden/make_golden.py            # regenerate
    .venv/Scripts/python tools/golden/make_golden.py --check    # CI: fail if stale
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from dataclasses import replace
from pathlib import Path

from rafiq.asr import EnergyVad, Segmenter
from rafiq.matching import Matcher, get_index
from rafiq.normalize import normalize
from rafiq.quran import get_quran
from rafiq.simulate import NoiseConfig, simulate
from rafiq.tracking import Tracker
from rafiq.word_eval import replay_words
from rafiq.word_sim import LetterNoise, run, simulate_letters
from rafiq.word_truth import map_verse, uthmani_words
from rafiq.words import WordTracker

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "mobile" / "test" / "golden"

# Real faster-whisper outputs (with diacritics, odd spellings, hallucinations).
ASR_SAMPLES = [
    "وَاللَّيْلِ إِذَا سَجَى",
    "عَمَّ يَتَسَاءَلُونَ",
    "قُلْ أَهَلُ رَبِّي بِالْإِسْطِ وَأَقِيمُوا وُجُوهَكُمْ",
    "يَا بَنِي آدَمَ خُذُوا زِينَتَكُمْ عِنْدَ كُلِّ مَسْجِدٍ وَكُنْ وَشَرَهُ",
    "وَالْمُؤْمِنِينَ",
    "الٓمٓ ذَٰلِكَ ٱلْكِتَـٰبُ",
    "Rafiq 123 — test",
    "",
    "   ",
    "فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ!؟",
]


def normalize_cases() -> list[dict]:
    q = get_quran()
    rng = random.Random(1448)
    verses = rng.sample(q.verses, 300) + [q.verse(1, 1), q.verse(2, 255), q.verse(95, 1), q.verse(97, 1)]
    inputs = []
    for v in verses:
        inputs += [v.text, v.text_uthmani]
    inputs += ASR_SAMPLES
    inputs += [s.basmala_uthmani for s in q.surahs if s.basmala_uthmani]
    seen, cases = set(), []
    for text in inputs:
        if text not in seen:
            seen.add(text)
            cases.append({"input": text, "normalized": normalize(text)})
    return cases


# Recorded real ASR (eval/audio_bench.py --record): reciters and rooms that
# differ, so the tracker meets misheard words, noise and al-Fatiha.
TRANSCRIPTS = ROOT / "eval" / "results" / "transcripts"
RECORDINGS = [
    "Abdul_Basit_Murattal_192kbps__mosque__p0",
    "Abdurrahmaan_As-Sudais_192kbps__far__p0",
    "Alafasy_128kbps__clean__p1",
    "Alafasy_128kbps__mosque__p0",
    "Ghamadi_40kbps__far__p0",
    "Hudhaify_128kbps__clean__p0",
    "Husary_128kbps__mosque__p0",
    "MaherAlMuaiqly128kbps__far__p0",
    "Minshawy_Murattal_128kbps__clean__p0",
    "Nasser_Alqatami_128kbps__mosque__p0",
]


def recording(name: str) -> list[dict]:
    rec = json.loads((TRANSCRIPTS / f"{name}.json").read_text(encoding="utf-8"))
    return [{"text": e["text"], "final": e["final"]} for e in rec["events"]]


def state_json(st) -> list:
    """A tracker state, as the Dart test compares it."""
    return [
        st.verse_id,
        st.word,
        st.status,
        st.confidence,
        st.pending_verse,
        list(st.alternatives),
        st.upcoming_verse,
        [[c.start, c.end, c.score] for c in st.candidates[:3]],
    ]


def match_cases() -> list[dict]:
    """Queries -> the matcher's top 5, over real ASR text and simulated noise."""
    index = get_index()
    matcher = Matcher(index)
    queries: list[tuple[str, int, int | None]] = []
    for name in RECORDINGS[:5]:
        for e in recording(name):
            if e["final"] and e["text"]:
                queries.append((e["text"], 0, None))
    for seed, (a, b) in enumerate([(2, 40), (1500, 1530), (4900, 4950), (6100, 6130)]):
        for step in simulate(index, a, b, NoiseConfig.preset("heavy"), seed=seed)[:25]:
            queries.append((step.text, 0, None))
    # Restricted searches, as a lock or a hint makes them.
    al_rahman = index.verse_span(4901)[0], index.verse_span(4978)[1]
    for text in ["فبأي آلاء ربكما تكذبان", "الرحمن علم القرآن", "الحمد لله رب العالمين"]:
        queries.append((text, *al_rahman))
    cases, seen = [], set()
    for text, lo, hi in queries:
        if (text, lo, hi) in seen:
            continue
        seen.add((text, lo, hi))
        found = matcher.match(text, k=5, lo=lo, hi=hi)
        cases.append(
            {
                "text": text,
                "lo": lo,
                "hi": hi,
                "matches": [[m.start, m.end, m.score, m.first_verse, m.last_verse] for m in found],
            }
        )
    return cases


def tracker_cases() -> list[dict]:
    """Scenarios: a list of steps fed to a fresh tracker, and its state after each."""
    index = get_index()
    matcher = Matcher(index)
    quran = get_quran()
    scenarios: list[tuple[str, list[dict]]] = []
    for name in RECORDINGS:
        scenarios.append((name, recording(name)))
    heavy = NoiseConfig(
        word_corrupt=0.25, word_drop=0.10, word_insert=0.06, garbage_chunk=0.08, fatiha_every=4
    )
    for seed, (a, b, skip) in enumerate([(2, 30, 5), (2050, 2080, 2), (4901, 4940, 0), (6090, 6130, 7)]):
        steps = simulate(index, a, b, heavy, seed=100 + seed, skip_words=skip)
        scenarios.append((f"simulated {a}-{b}", [{"text": st.text, "final": True} for st in steps]))
    juz30 = quran.juz_span(30)
    rahman = quran.surah(55)
    bayyinah = simulate(index, 6159, 6166, NoiseConfig.preset("light"), seed=7)
    scenarios.append(
        (
            "hint, lock, position, reset",
            [{"hint": list(juz30)}]
            + [{"text": st.text, "final": True} for st in bayyinah[:6]]
            + [{"lock": [rahman.first_verse_id, rahman.last_verse_id]}]
            + [{"text": "فبأي آلاء ربكما تكذبان", "final": True}] * 2
            + [{"text": "الحمد لله رب العالمين الرحمن الرحيم", "final": True}]
            + [{"position": quran.verse(55, 26).id}]
            + [{"text": "ويبقى وجه ربك ذو الجلال والإكرام", "final": True}]
            + [{"text": "فبأي آلاء ربكما تكذبان", "final": False}]
            + [{"lock": None}, {"reset": True}]
            + [{"text": st.text, "final": True} for st in bayyinah[6:]],
        )
    )
    cases = []
    for name, steps in scenarios:
        tracker = Tracker(matcher)
        out = []
        for step in steps:
            if "hint" in step:
                tracker.hint(*step["hint"])
                out.append(None)
            elif "lock" in step:
                tracker.lock(*(step["lock"] or [None]))
                out.append(None)
            elif "position" in step:
                out.append(state_json(tracker.set_position(step["position"])))
            elif "reset" in step:
                tracker.reset()
                out.append(None)
            else:
                st = tracker.update(step["text"]) if step["final"] else tracker.preview(step["text"])
                out.append(state_json(st))
        cases.append({"name": name, "steps": steps, "states": out})
    return cases


class _Recorder:
    """A word tracker that writes down every call and the state it returned."""

    def __init__(self, tracker: WordTracker) -> None:
        self._t = tracker
        self.ops: list[list] = []
        self.states: list[list] = []

    def __getattr__(self, name: str):
        return getattr(self._t, name)

    def _log(self, op: list, st) -> object:
        self.ops.append(op)
        self.states.append([st.word, st.status, round(st.confidence, 12), st.basmala])
        return st

    def reset(self) -> None:
        self._t.reset()
        self._log(["reset"], self._t.state)

    def anchor(self, word: int):
        return self._log(["anchor", word], self._t.anchor(word))

    def pause(self):
        return self._log(["pause"], self._t.pause())

    def feed(self, tokens):
        tokens = [tokens] if isinstance(tokens, str) else list(tokens)
        return self._log(["feed", tokens], self._t.feed(tokens))


def word_tracker_cases() -> list[dict]:
    """Scenarios of letters fed to the word tracker, and its state after each call."""
    index = get_index()
    light, heavy = LetterNoise.preset("light"), LetterNoise.preset("heavy")
    streams = [
        ("light, mid-surah", 1500, 1507, light, 3),
        ("heavy with al-Fatiha, ar-Rahman's refrain", 4901, 4910, replace(heavy, fatiha_every=4), 5),
        ("clean across short surahs and their basmala", 6205, 6221, LetterNoise.preset("clean"), 1),
        ("light with al-Fatiha", 300, 308, replace(light, fatiha_every=4), 4),
        ("a model that hears little", 2050, 2054, LetterNoise.preset("broken"), 2),
    ]
    cases = []
    for name, a, b, noise, seed in streams:
        rec = _Recorder(WordTracker(index))
        run(rec, simulate_letters(index, a, b, noise, seed=seed))
        cases.append({"name": name, "ops": rec.ops, "states": rec.states})

    # By hand: idle, al-Fatiha's own window, "amin", a pause, subwords in model spelling.
    rec = _Recorder(WordTracker(index))
    rec.feed("بسم")
    rec.anchor(0)
    for p in range(*index.verse_span(1)):
        rec.feed(f"▁{index.words[p][:2]}ِ")
        rec.feed(index.words[p][2:])
    for p in range(index.verse_span(2)[0], index.verse_span(7)[1]):
        for ch in index.words[p]:
            rec.feed(ch)
    for ch in "امين":
        rec.feed(ch)
    rec.pause()
    lo, _ = index.verse_span(3000)
    rec.anchor(lo)
    for p in range(lo + 3, lo + 14):
        rec.feed(list(index.words[p]))
    rec.pause()
    for p in range(lo + 14, lo + 18):
        for ch in index.words[p]:
            rec.feed(ch)
    rec.reset()
    rec.feed("الله")
    cases.append({"name": "by hand", "ops": rec.ops, "states": rec.states})
    return cases


def word_map_cases() -> dict:
    """Uthmani -> Simple Clean word mapping of every ayah (rafiq.word_truth): the ones not one-to-one."""
    index = get_index()
    cases = []
    ok = 0
    for v in index.quran:
        lo, hi = index.verse_span(v.id)
        m = map_verse(uthmani_words(v.text_uthmani), index.words[lo:hi], 0)
        ok += m.ok
        identity = all(us == ps and len(us) == 1 for us, ps in m.groups)
        if not identity or not m.ok:
            cases.append([v.id, [[list(us), list(ps)] for us, ps in m.groups], round(m.worst, 9)])
    return {"ayahs": len(index.quran), "ok": ok, "not_identity": cases}


# Recorded real Whisper output replayed by the word follower: what the phone
# must do event for event (rafiq.word_eval.replay_words, PLAN.md §30).
WORD_FOLLOW_RECORDINGS = [
    "Alafasy_128kbps__mosque__p0",
    "Husary_128kbps__mosque__p0",
    "Abdurrahmaan_As-Sudais_192kbps__far__p0",
    "Minshawy_Murattal_128kbps__clean__p0",
    "Abdul_Basit_Murattal_192kbps__mosque__p0",
]


def word_follow_cases() -> list[dict]:
    matcher = Matcher(get_index())
    cases = []
    for name in WORD_FOLLOW_RECORDINGS:
        rec = json.loads((TRANSCRIPTS / f"{name}.json").read_text(encoding="utf-8"))
        shown = replay_words(rec, matcher)
        events = [[e["text"], e["final"], e["start"], e["end"]] for e in rec["events"]]
        cases.append({"name": name, "events": events, "words": [s.word for s in shown]})
    return cases


# Synthetic audio for the segmenter, from integers only, so Python and Dart
# build the very same samples: (seconds, amplitude, period in samples).
# Recitation-like bursts and pauses over a low hum, then a long run-on.
SEGMENTER_PIECES = [
    (1.0, 0, 50), (2.2, 9000, 80), (0.5, 0, 50), (0.6, 7000, 70), (0.2, 0, 50),
    (1.4, 8000, 90), (1.2, 0, 50), (0.15, 9000, 60), (1.3, 0, 50), (3.0, 6000, 75),
    (0.35, 0, 50), (8.5, 7500, 85), (0.4, 0, 50), (2.0, 3000, 66), (2.5, 0, 50),
]  # fmt: skip
NOISE = 300


def synth_audio() -> list[int]:
    x, out = 1448, []
    for seconds, amp, period in SEGMENTER_PIECES:
        for t in range(int(seconds * 16000)):
            x = (1103515245 * x + 12345) % 2147483648
            noise = (x >> 16) % (2 * NOISE + 1) - NOISE
            p = t % period
            rising = 2 * p < period
            tone = (4 * p * amp) // period - amp if rising else 3 * amp - (4 * p * amp) // period
            out.append(max(-32768, min(32767, tone + noise)))
    return out


def segmenter_cases() -> dict:
    import numpy as np

    samples = np.array(synth_audio(), dtype=np.float32) / 32768.0
    seg = Segmenter(EnergyVad())
    events = []
    block = 4000
    for i in range(0, len(samples), block):
        for s in seg.push(samples[i : i + block]):
            events.append(["final", i + block, round(s.start, 6), round(s.end, 6), len(s.audio)])
        if (i // block) % 6 == 5:
            p = seg.in_progress(0.6)
            if p is not None:
                events.append(["partial", i + block, round(p.start, 6), round(p.end, 6), len(p.audio)])
    for s in seg.flush():
        events.append(["flush", len(samples), round(s.start, 6), round(s.end, 6), len(s.audio)])
    return {"pieces": SEGMENTER_PIECES, "noise": NOISE, "block": block, "events": events}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    files = {
        "normalize.json": normalize_cases(),
        "match.json": match_cases(),
        "tracker.json": tracker_cases(),
        "segmenter.json": segmenter_cases(),
        "word_tracker.json": word_tracker_cases(),
        "word_map.json": word_map_cases(),
        "word_follow.json": word_follow_cases(),
    }
    stale = []
    for name, cases in files.items():
        path = OUT / name
        text = json.dumps(cases, ensure_ascii=False, indent=0 if name == "normalize.json" else None) + "\n"
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                stale.append(name)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
            print(f"wrote {path} ({len(cases)} cases)")
    if stale:
        print(f"stale golden files: {stale}; run tools/golden/make_golden.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
