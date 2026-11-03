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
| 3 🟡 | ASR baseline (audio → text → ayah), baseline done | Numbers on the eval set; know where it fails |
| 4 🟡 | Tracker (text-level done) | Stability and recovery clearly beat Phase 3 |
| 5 🟡 | Flutter MVP + FastAPI WebSocket (v1 app built) | Works in a real mosque with a laptop nearby |
| 6 | On-device (Dart port + sherpa-onnx) | Fully offline on a mid-range Android phone, latency < 3 s |

## 6. Metrics (from the README)

Ayah accuracy · position error (in ayahs) · wrong jumps per hour · latency · recovery time.
**Phase 6 targets:** ≥90% correct ayah on screen, <1 wrong jump per 20 min, <3 s latency.

## 7. Product decisions (proposed answers)

- **Start point:** automatic detection of surah and ayah is the core feature. The user can optionally name the surah or juz (a soft hint).
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

**Built:** normalize → matching → tracking, a recitation simulator, a metrics harness, a FastAPI dev server, and the web playground. Also CI with accuracy and detection gates, and 92 tests.

**Detection** (`eval/detection_benchmark.py`): the app opens mid-ayah, anywhere in the Quran, and is told nothing.

| Noise | Found on 1st chunk | Within 3 chunks (~8 s) | First guess wrong |
|---|---|---|---|
| light | 76% | 100% | 0% |
| heavy | 60% | 98% | 0% |

A correct surah or juz hint raises "1st chunk" to about 90% (light) and 80% (heavy). A *wrong* hint costs almost nothing.

**Tracking** (`eval/text_benchmark.py`): 98–99.6% right ayah, ≤0.06 wrong jumps per 100 chunks, including heavy noise with al-Fatiha every rak'ah.

**Findings worth remembering:**
- Tanzil puts the basmala inside ayah 1 of 112 surahs. It's now split out at build time; otherwise it would put 113 copies of the phrase in the index.
- A hypothesis must survive a chunk that doesn't support it. Otherwise one noisy chunk kills the correct position.
- After al-Fatiha, measure the next position from where the imam was before it, never from 1:7.
- Show nothing until the first guess is confident, but don't over-wait. Confirmation during detection must carry real confidence: two copies of the same refrain confirm nothing.
- Truly identical passages (the refrains in Ash-Shu'ara and Ar-Rahman) can't be resolved from text alone, so the app shows the alternatives instead of guessing.

**Next:** Phase 2 (real recordings) and Phase 3 (ASR). Simulated text is kinder than a mosque, so treat these numbers as a floor for catching regressions, not as a promise of real-world accuracy.

## 10. Audio (2026-11-02)

**Built:** `rafiq.asr` (audio → chunks cut at the imam's pauses → Whisper → tracker), a live `/ws/listen` WebSocket, and a 🎤 **Listen** tab (mic or audio file). `eval/audio_check.py` runs real EveryAyah recitations end to end.

**Real audio (Alafasy, app told nothing):**

| Condition | Right ayah | Detected after | Wrong jumps |
|---|---|---|---|
| clean, joined mid-surah | 90–100% | 1–2 chunks | 0 |
| mosque echo (RT60 1.5 s, DRR 0–3 dB) + noise (SNR 15–20) | 91–100% | 1–2 chunks | 0 |
| heavy echo + noise (DRR 0, SNR 15) | 60% | 5 chunks | 0 |

Speech recognition runs at ~0.2× real time on a laptop CPU (about 0.8 s per chunk).

**Findings:**
- Silero VAD treats long tajweed vowels (madd) as "not speech" and cuts mid-word. A loudness VAD with an adaptive noise floor works better for recitation.
- That VAD must also cap its threshold below the loud level. Otherwise listening that starts mid-recitation learns the voice as "noise" and hears nothing.
- The tracker fails safe: with bad audio it waits instead of showing a wrong ayah.

**Biggest lever next:** ASR quality under echo. Options: a larger Quran Whisper (small/turbo), fine-tuning on reverberant audio, or real mosque recordings for the eval set (Phase 2).

## 11. Real-time (2026-11-02)

**Problem:** the screen changed only after the imam *finished* an ayah, so it lagged a whole ayah behind (median 5 s, worst 6.5 s).

**Fixes:**
- **Live partials:** about every 0.5 s mid-breath, the words so far are transcribed and *previewed* by the tracker. Only the final transcript at the pause is committed, so nothing is counted twice.
- **Upcoming ayah:** when an ayah is recited to its end, the screen moves to the next one as soon as the imam pauses. After al-Fatiha, it moves back to where he left off.
- **Catch-up:** if speech recognition falls behind, the server merges the waiting audio and transcribes only *now*. A slow machine updates less often, but it never builds a backlog.
- **Warm-up at load, plus GPU auto-selection** with CPU fallback.

**Measured** with `eval/audio_check.py`, which replays on a real-time clock exactly like the server: median lag from "ayah starts" to "on screen" is **0.1–0.4 s** at full CPU speed, and **~1.1 s** with the laptop on battery (CPU throttled to 1 GHz, ~1.7 s per Whisper call).

**Root limit:** Whisper encodes a fixed 30 s window, so each call costs the same (~0.4 s on CPU) even for 1 s of audio. For the phone (Phase 6), consider a streaming CTC model, whose cost scales with audio length, or a GPU/NPU delegate.

## 12. Robustness (2026-11-02)

**Multi-reciter benchmark:** `eval/audio_bench.py`. 12 reciters (fast Haram imams, slow murattal, melodic, low-bitrate), seeded random passages from anywhere in the Quran (crossing surahs with the basmala), three rooms (clean / mosque / far), always joining late and told nothing. Replays on a real-time clock like the server. Results are saved as JSON and compared against a baseline; `--check` gates accuracy, wrong jumps per hour and detection rate.

**Live-path hardening**, each with a test:
- Malformed or oversized frames and NaN samples are repaired or skipped with a warning, never fatal.
- Transcriber and model-load failures reach the client as errors instead of hanging the session.
- The backlog is capped at 15 s (oldest audio dropped, timestamps stay continuous).
- A 10-minute soak test confirms buffers and timestamps stay bounded.
- Browser: the AudioContext is created inside the click (Chrome would otherwise leave it suspended), mic sessions auto-reconnect with backoff, and mic permission errors are explained.

## 13. Mobile v1 (2026-11-02)

**Built:** `mobile/`, a Flutter app (Android + iOS). Design: `mobile/docs/DESIGN.md`.
- **One screen:** status card (surah, ayah, confidence), the surah text with the current ayah highlighted and auto-followed, a mic button, an optional hint (surah or juz), plus settings with *Test connection*.
- **Recognition sits behind `RecognitionEngine`.** v1 uses the server over `/ws/listen`; Phase 6 swaps in an on-device engine without UI changes.
- **Robustness:**
  - Reconnects forever with backoff, keeping the mic running and only the newest 2 s of audio.
  - Gives a clear "unreachable" error on a wrong address, and waits for the model on first use.
  - Pauses when the app goes to the background; a generation counter prevents ghost events from old sessions.
  - Mic-permission and server errors come with the action that fixes them, and the layout is safe at large font sizes.
- **Quality:** 54 tests (unit, the engine over real sockets, the state machine with fakes, widgets), strict lints, and CI covering format, analyze, test, Android build and Quran-asset sync.

**Toolchain finding:** the mic plugin ships Java 17 bytecode, so the Android build moved to AGP 8.2 / Gradle 8.5 / Kotlin 1.9 and needs JDK 17+.

**Next:** test in a real mosque with a phone and a laptop (Phase 5 exit), then on-device recognition (Phase 6).

## 14. Mobile v1.1: reader and user control (2026-11-03)
- **Quran text:** Uthmani with full tashkeel (Tanzil Uthmani v1.1, verbatim in `data/raw/`, cross-checked against Simple Clean by the build). Matching still uses Simple Clean.
- **Reader:** a mushaf-style page with the current ayah highlighted, recited ayahs dimmed, every ayah tappable, and a surah index.
- **User control:** *Stay on this surah* (`Tracker.lock`, a hard limit with al-Fatiha excepted) and *The imam is here* (`Tracker.set_position`). New `/ws/listen` messages: `lock`, `unlock`, `position`. The engine re-sends the lock after reconnects.

## 15. Going to the Play Store: how it will work

**Today:** the phone records, and a laptop on the same Wi-Fi recognises. That's fine for development, but it can't ship.

**Shipping target: everything on the phone (Phase 6).** The Quran text is already on the phone. The two remaining pieces move there too:
1. **Speech model on-device:** the same Quran-tuned Whisper, exported to ONNX (int8, roughly 60–80 MB), run with sherpa-onnx (it has a Flutter plugin). If mid-range phones are too slow, switch to whisper-tiny or a streaming CTC model.
2. **Tracker in Dart:** normalize, match and track are about 1.5k lines of plain logic. Shared golden test files (input → expected output) are run against both Python and Dart so the two never drift.
3. **No UI change:** this ships as an `OnDeviceRecognitionEngine` behind the existing `RecognitionEngine` interface.

| | On-device (recommended) | Cloud server |
|---|---|---|
| Works in the mosque without internet | ✅ | ❌ needs reliable 4G or Wi-Fi |
| Running cost | none, at any number of users | ~1 CPU core (or a GPU slice) per listener, and Taraweeh puts *every* user online in the same hour |
| Privacy | audio never leaves the phone | recitation audio uploaded |
| Latency | independent of the network | network + server |
| Risk | speed and battery on cheap phones; app size | cost at peak; outages |

So the Play Store build is on-device. The server stays useful for development, the benchmarks, and possibly an optional cloud fallback for very old phones (hosted with `wss://`).

**Play Store checklist (when Phase 6 works):**
- **Build:** release signing (Play App Signing), app bundle, current target API level, and the model delivered with Play Asset Delivery to keep the download small.
- **Security:** remove `usesCleartextTraffic`.
- **Policy:** a privacy policy URL (required for mic apps) and the Data safety form ("audio processed on device, not collected"). The microphone use is explained in-app (done).
- **Attribution:** Tanzil (CC BY 3.0), Amiri Quran (OFL), and the model (Apache 2.0), shown in About (done).
- **Polish:** Arabic UI (localization), crash reporting, then an internal test track, a closed beta with real imams, and public release before Ramadan.

**Order of work:** Dart tracker port with golden parity tests → on-device model, benchmarked on 3 phone tiers → `OnDeviceRecognitionEngine` → store preparation.

## 16. Step 3: on-device feasibility (in progress, 2026-11-03)
- **Model export:** the server's exact model exported for sherpa-onnx (`tools/whisper_export/`, pinned revision, vendored upstream exporter). On the same audio, word accuracy is 97.4% vs 98.6% for the server model.
- **Fix found:** chunks need 2 s of trailing silence (81% → 97% accuracy).
- **Speed:** cost scales with chunk length (no fixed 30 s window), about 0.7 s per typical chunk on 2 laptop threads.
- **Runs on Android:** the app downloads the model from the dev server and transcribes in a background isolate (Settings → Developer → On-device speech benchmark). On the emulator: 96.9% accuracy and 1.5 s per typical chunk, verdict "borderline". **Real phone numbers pending.**
- **Dart port started:** `normalize` is ported and matches the Python engine on 613 golden cases (`tools/golden/`, checked in CI).
- **Known issue:** 160 MB of int8 model, mostly the token embedding. Vocabulary trimming is the planned fix for size and speed.
- **Decision rule:** a typical chunk under 1.5 s on mid-range phones means go on-device. Between 1.5 and 3 s, trim the vocabulary first. Over 3 s, use a smaller model or a cloud fallback.
- **Phone round 1 (Galaxy A32, budget):** 3.6 s per chunk on 2 threads, too slow. Accuracy 96.6% (fine). Whisper-tiny rejected (80% accuracy). The bottleneck is the decoder's full-vocabulary projection.
- **Fix:** trimmed the vocabulary to 660 tokens. Output is identical, the model is 55 MB instead of 160 MB, and it's ~25% faster on the laptop. Phone round 2 is pending.
