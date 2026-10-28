# Plan — Rafiq al-Tarawih

> The imam recites → the phone shows the current Surah:Ayah, live, offline.

## 1. Where we are (review)

**Good:** clear one-feature MVP, engine-first, verified Quran data (31 tests pass), global verse ids make windows and error metrics simple.

**Gaps to fix:**
- No eval data yet, so we can't measure anything. This is the biggest risk.
- Engine is Python, but the app must run **offline on a phone**. We need a plan for that now (see §4).
- No CI.
- Small inconsistency: `.gitignore` says Flutter is Phase 3, the README says Phase 5.

## 2. Tech stack

| Layer | Choice | Why |
|---|---|---|
| Engine (reference) | **Python 3.11**, pytest, ruff | Fast to iterate on |
| Matching | Word index + IDF voting + word-level fuzzy alignment (**rapidfuzz** for edit distance) | Fast (~6 ms), no ML, gives exact spans |
| VAD | **Silero VAD** | Small, accurate, has an ONNX version |
| ASR | **Whisper fine-tuned on Quran** (`tarteel-ai/whisper-base-ar-quran`) | Already knows Quranic Arabic |
| ASR runtime | **faster-whisper** (laptop) → **sherpa-onnx** (phone) | sherpa-onnx runs Whisper + VAD on-device and has Flutter bindings |
| Dev server | **FastAPI** (+ WebSocket for audio in Phase 5) | Serves the playground now, streams phone audio later |
| Playground | One static HTML page, no build step | Try the product in a browser at any stage |
| Mobile | **Flutter**, `record` package for the mic | One codebase for iOS and Android |
| Display text | Tanzil **Uthmani** + KFGQPC Hafs font | The script users expect to see |
| CI | **GitHub Actions**: ruff + pytest + eval on every PR | Catches accuracy regressions |

## 3. How it works

```
mic ─► VAD (cut silence) ─► ASR (2–4 s chunks) ─► normalize text
     ─► match against the Quran index (top-k candidates)
     ─► tracker (picks the most likely position given the previous one)
     ─► UI: Surah:Ayah + highlighted text + confidence
```

- **Normalize:** remove diacritics and tatweel; unify alef forms (أ/إ/آ → ا), ى→ي, ة→ه, and hamza seats. The same function runs on Quran text and on ASR output.
- **Match:** a word n-gram inverted index finds candidate ayahs, then fuzzy alignment scores them. Windows can span ayah boundaries, because the imam crosses them mid-chunk.
- **Track:** an HMM-style beam over verse ids. Transition prior: *stay* or *+1* is very likely, a small jump back (repetition) is likely, and a far jump is rare. Optional seed: "tonight starts at juz N".
- **Confidence:** low confidence → keep showing the last good ayah (dimmed) rather than flickering. When the app recovers, it snaps to the new position.

## 4. On-device strategy (decide now)

Python can't ship inside Flutter. So:
- **Python stays the reference implementation** and is where all experiments happen.
- In Phase 6, port `normalize` + `match` + `track` to **Dart**. It's small, deterministic code with no ML in it.
- **Shared golden test files** (JSON: input → expected output) run against both Python and Dart, so the two can't drift apart.
- The ML parts (VAD + ASR) run through sherpa-onnx, with models exported to ONNX and int8-quantized.

## 5. Phases

| # | Deliverable | Done when |
|---|---|---|
| 0 | Data pipeline ✅ | — |
| 1 ✅ | `normalize` + `match` (text → ayah, no ML) | ≥99% top-1 on clean ayah text, and ≥95% on noisy text fragments (deleted or swapped words) |
| 2 | Eval set + metrics harness | ~10 reciters from EveryAyah, plus ≥2 h of real Taraweeh recordings with ayah timestamps. Harness reports the five metrics below |
| 3 | ASR baseline (audio → text → ayah) | Numbers on the eval set; know where it fails |
| 4 🟡 | Tracker (text-level done) | Stability and recovery clearly beat Phase 3 |
| 5 | Flutter MVP + FastAPI WebSocket | Works in a real mosque with a laptop nearby |
| 6 | On-device (Dart port + sherpa-onnx) | Fully offline on a mid-range Android phone, latency < 3 s |

## 6. Metrics (from the README)

Ayah accuracy · position error (in ayahs) · wrong jumps per hour · latency · recovery time.
**Phase 6 targets:** ≥90% correct ayah on screen, <1 wrong jump per 20 min, <3 s latency.

## 7. Product decisions (proposed answers)

- **Start point:** automatic, with an optional "juz tonight" seed.
- **Pauses / between rak'ahs:** hold the last position. Al-Fatiha (recited every rak'ah) is detected, shown, and then the tracker resumes right after where the last rak'ah ended.
- **Repeats / skips:** handled by the tracker's transition prior.
- **Low confidence:** freeze and dim. Never show a far jump until it's confirmed twice.
- **Can't hear:** show a "listening…" state with a mic-level indicator.

## 8. Risks

- **Mosque acoustics** (echo, loudspeakers, crowd noise). Mitigation: real recordings in the eval set early, plus reverb augmentation.
- **Similar ayahs** (e.g. repeated phrases in Ar-Rahman). Mitigation: the tracker's context does the work here, not the matcher.
- **Audio licensing.** Keep recordings out of git (already gitignored); store only manifests.
- **Phone performance.** Mitigation: whisper-base int8, or fall back to a smaller CTC model.

## 9. Progress (2026-10-28)

**Built:** normalize → matching → tracking, a recitation simulator, a metrics harness, a FastAPI dev server, and the web playground. Also CI and 82 tests.

**Benchmark** (`eval/text_benchmark.py`, simulated ASR text):

| Scenario | Right ayah (±1) | Wrong jumps / 100 chunks |
|---|---|---|
| clean | 99% | 0.03 |
| heavy noise + al-Fatiha every rak'ah | 97% | 0.05 |

**Findings worth remembering:**
- Tanzil puts the basmala inside ayah 1 of 112 surahs. It's now split out at build time; otherwise it would put 113 copies of the phrase in the index.
- A hypothesis must survive a chunk that doesn't support it. Otherwise one noisy chunk kills the correct position.
- After al-Fatiha, measure the next position from where the imam was before it, never from 1:7.
- Show nothing until the first guess is confident. A wrong first ayah is worse than a 2-second wait.

**Next:** Phase 2 (real recordings) and Phase 3 (ASR). Simulated text is kinder than a mosque, so treat these numbers as a floor for catching regressions, not as a promise of real-world accuracy.
