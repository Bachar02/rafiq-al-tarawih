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
- **Phone round 2, budget tier (2026-11-04, Galaxy A32 4G SM-A325F, Android 13, 8 cores: 2 fast + 6 efficiency):** `quran-basetrim` int8, sherpa-onnx 1.13.4, the same 22 clips; typical chunks are ≤ 6.5 s, median 3.1 s of speech.

  | Threads, padding | Typical chunk | Word accuracy |
  |---|---|---|
  | 1, 0.5 s | 4.38 s | 95.2% |
  | **2, 0.5 s** | **3.11 s** | 95.2% |
  | 4, 0.5 s | 3.64 s | 95.2% |
  | 2, 2.0 s | 3.61 s | 96.6% |

  - **§16 rule for this tier: over 3 s → smaller model or cloud fallback.** At best the A32 transcribes a chunk in as long as it took to recite (real-time factor ≈ 1.0), so it can never catch up and every ayah would show more than 3 s late. Accuracy is fine.
  - **Two threads is the best setting.** Four threads is slower because the work spills onto the efficiency cores.
  - **The vocabulary trim did not speed up this phone:** round 1 measured 3.6 s and 96.6%, the same as the 2 thread, 2 s padding row here. (Round 1's configuration was not written down; that row is the only one that matches.) The 1.5 s of extra padding costs 0.5 s, so length-proportional work (mostly the encoder) is about 0.33 s per second of audio, and about 1.9 s per chunk is fixed (mostly decoding). The real split must be measured before choosing the next optimization.
  - **Overall go/no-go is pending the mid-range and flagship phones**, as the rule is decided on mid-range.

## 17. Roadmap to a shippable product (planned 2026-11-03)

**Hard deadline:** Ramadan 2027 starts around 8 February 2027 (to confirm by moon sighting). A closed beta must be in real mosques before then, so the release candidate is due **mid-January 2027**. Taraweeh audio only exists during Ramadan; until then, the daily *jahrī* prayers (Maghrib, ʿIshāʾ, Fajr) supply real mosque audio.

**Principles:** the engine stays the moat and is measured, not guessed. One `RecognitionEngine` interface, two builds (server and on-device). Every number that matters is gated in CI. Never claim more than the app does.

### M0 — Secure the base (first session, ~1 day)
- **Rubric design work** (76 files, uncommitted when this was written): review the diff, commit it on a branch, open a PR, merge.
- **Git history:** the latest commit's message ("Phase 0: …") does not describe its content (the model-size change). Reword it before anything is pushed on top. The earlier "switch to Whisper-tiny" commit is no longer in the history; the code uses `quran-basetrim`.
- **Golden screenshot tests with the real fonts:** dark/light, 320 px at text size 1.3, Not sure, Al-Fatiha, settings. Rendering with the real fonts found missing ʿ/Ḥ glyphs and an overflow that the Ahem-font widget tests missed.
- **Flutter upgrade:** 3.19.5 → current stable, *before* the big work (Dart 3.3 lacks features already needed; packages are 2.5 years behind). Then update CI to the same version.

### M1 — On-device go/no-go (week 1)
- Phone round 2 with `quran-basetrim` (55 MB), on three tiers: budget (Galaxy A32), mid-range and flagship. Apply the §16 rule: under 1.5 s per typical chunk → go.
- If still too slow: try a 4-thread setting, CPU affinity, and NNAPI/XNNPACK. Otherwise a smaller distilled Quran model, or a streaming CTC model.
- **Output:** a written decision, with numbers, in this file.

### M2 — On-device engine (weeks 2–5)
- **Dart port** of `match` and `track` (normalize is done) with golden parity tests against Python in CI; the port must never drift.
- **On-device audio path:** a Dart VAD/segmenter (the loudness VAD with an adaptive floor, §10), live partials, and catch-up without backlog (§11), all running in a background isolate.
- **`OnDeviceRecognitionEngine`** behind the existing interface, so the UI does not change. The fake-engine tests run against both engines.
- **Model delivery:** Play Asset Delivery (install-time pack) or a first-run download with checksum, resume and storage checks. The "Preparing the speech model" state from the brand book.
- **Build flavors:** `server` (development) and `ondevice` (store). The on-device flavor drops all server/Wi-Fi copy and settings, and removes `usesCleartextTraffic`.
- **Budgets, measured on the three phones:** latency under 3 s, a battery and thermal budget for a 2-hour session, and memory.

### M3 — Real-world evaluation (starts now, runs in parallel)
- **Recording protocol and consent:** record jahrī prayers in 3+ mosques (different acoustics) with the phone in realistic positions; label ayah timestamps. This is Phase 2's eval set (§5), still missing.
- Replay recordings through **both** engines with `eval/audio_bench.py`, and gate accuracy, wrong jumps per hour and latency in CI (audio stays out of git; manifests only).
- **Calibrate** with the data: the 10 s inferred-state windows, `quietLevel`, and the qunūt false-match risk.

### M4 — Product completeness (weeks 4–8)
- **Localization:** English, French and Arabic via `flutter_localizations` + ARB files, full RTL, and native-speaker review of the handoff copy and the French surah names.
- **First-run onboarding:** microphone rationale, the Ḥafṣ-only statement, and how to place the phone. A privacy policy page.
- **Open Rubric decisions:**
  - an "Open settings" action for a denied mic (`permission_handler` or `app_settings`);
  - Lucide icons;
  - where browsing lives;
  - copy written outside the spec;
  - the coming-ayah colour at low brightness;
  - Flutter justification on sparse lines (55:14).
- **Accessibility pass:** TalkBack/VoiceOver, large text, reduced motion, contrast on real phones.

### M5 — Release engineering (in parallel from week 3)
- **Signing:** a release keystore (out of git, in CI secrets) and Play App Signing. Versioning from tags.
- **CI/CD:** a GitHub Actions pipeline producing a signed app bundle and APKs per tag; upload to the internal track (Fastlane or the Gradle Play Publisher). iOS: TestFlight, which needs a Mac or a macOS CI runner.
- **Observability:** opt-in, privacy-preserving crash reporting (no audio, no transcripts), plus a local session log the user can export for bug reports.
- **Store listing:** Data safety form ("audio processed on device, not collected") and screenshots from the golden renders.

### M6 — Beta and launch
- **Internal track** by mid-December 2026.
- **Closed beta** with imams and regular worshippers by **mid-January 2027**.
- **Fix window**, then public release in the week before Ramadan 2027.
- **During Ramadan:** collect opt-in Taraweeh recordings to improve the next version.

### First session agenda
1. M0: commit the Rubric work, reword the misnamed commit, add golden screenshot tests.
2. M0: upgrade Flutter and dependencies; keep all tests green.
3. M1: run phone round 2 and record the go/no-go decision.

## 18. Product direction: a Quran reader with Taraweeh mode (approved 2026-11-04)

**Decision:** Rafiq becomes a Quran reading app first, and live Taraweeh tracking is its signature mode. The reader is the home screen. Taraweeh mode is a full-screen mode one tap away, built on the same Quran view. Approved choices:
1. **Continuous scrolling through the whole Quran**, kept only if the A32 benchmark passes.
2. **Two independent positions:** personal reading, and the last Taraweeh position.
3. **One tap starts listening**, after first-run onboarding (shown once) and the microphone permission.
4. **System theme by default**, with "Dark during Taraweeh" on.

Hafs only. The engine, server, protocol and Quran text are unchanged.

**Roadmap:** R1 data → R2 `QuranView` spike → R3 reader and app shell → R4 Taraweeh on `QuranView` → R5 navigation, search, bookmarks → R6 polish, localization, docs.

### R1: page and hizb-quarter data (done)
- `quran.json` gains `pages` (604 page starts, Madinah mushaf) and `hizb_quarters` (240). Every existing field is unchanged.
- The build checks that each division is a complete, ordered partition starting at 1:1, and that every juz starts at its first quarter.
- Engine tests pin hand-written anchors from the printed mushaf: juz start pages (including the irregular 121 and 201), Ayat al-Kursi on page 42, al-Kahf on 293, Ya-Sin on 440.
- Dart `Divisions` does binary-search lookups (`juzs`, `pages`, `quarters`), checked against a linear scan of all 6,236 verses.
- Page marks are **starts only**: the text flows, it is not a page facsimile, and the app never claims to be one.

### R2: `QuranView` spike
**Architecture:** one lazily built list of 6,350 items (114 surah headers and 6,236 ayahs).
- **Jumps:** the list is anchored with the two-sliver "center" technique (items after the anchor grow down, items before it grow up). Any jump is an exact re-anchor in constant time, with no extent estimation and no new dependency.
- **Follow-scroll:** ported with the same constants (comfort zone 25–60%, anchor 38%).
- **Measuring positions:** in scroll space, because scroll notifications arrive before layout, and paint positions are a frame stale exactly when a drag ends (a bug the tests caught).
- **No needless rebuilds:** item delegates are rebuilt only when what the items show changes, so the Taraweeh screen's 80 ms mic-level updates rebuild no ayah. A test checks this.
- **Reading tone** skips the tone crossfade machinery, which is cheaper per ayah while scrolling.

**Why continuous rather than per surah:** per-frame scroll cost is the same either way, because only items on screen exist. The thing that matters is virtualization. A per-surah fallback would only remove reading across surah boundaries (a juz crosses them), not cost.

**Host proxy** (`RAFIQ_PERF=1 flutter test test/perf/quran_view_cost_test.dart`): real fonts, a debug-mode laptop, so only the ratios mean anything.

| Text size | Old eager column, Al-Baqarah frame | `QuranView` open | Scroll frame, median / p90 | Jump, median |
|---|---|---|---|---|
| 1.0 | 313 ms | 19 ms | 2.2 / 9.9 ms | 11 ms |
| 1.6 | 250 ms | 11 ms | 1.1 / 5.6 ms | 6 ms |

**Deciding run, pending: the A32.** It needs a phone (the local emulators are 32-bit x86, which Flutter no longer runs).

```
flutter drive --profile -d <A32> --driver=test_driver/perf_driver.dart --target=integration_test/quran_view_perf_test.dart
py tool/perf_report.py --markdown
```

It covers Al-Baqarah flings, juz 30 across surahs, 20 far jumps and Taraweeh follow, each at text size 1.0 and 1.6.

**Budgets:**
- **Scrolling:** frame build and raster p90 ≤ 16 ms, build p99 ≤ 33 ms, ≤ 5% of frames over budget.
- **Jumps:** p90 ≤ 250 ms.

**If scrolling misses the budget**, the levers in order are:
1. Cache shaped paragraphs per ayah and text size.
2. Split long ayahs into line-range items.
3. Lower `cacheExtent`.

The list architecture stays in every case.

### R3: the reader is home (done)
- **`ReaderScreen`:** the shared `QuranView`, opened at the personal reading position.
  - A bar names the surah, juz and page. It is the only widget that rebuilds while scrolling.
  - A floating Taraweeh button steps aside while reading down.
- **Reading position:** the verse at the top of the reader.
  - Saved one second after scrolling stops, and at once when the app leaves the foreground.
  - A failed save stays pending and is retried.
  - Tests restore it after a simulated restart.
- **`ReadingStore`:** the reading position, the last Taraweeh position and bookmarks, as versioned JSON in shared preferences, keyed by verse id.
  - **An unreadable record is never overwritten.** It is first copied to `<key>.unreadable.<time>`.
  - **A failed write is reported, not thrown.**
  - **Bookmarks are saved before they are shown**, so the UI never claims a bookmark it did not keep.
- **Settings:**
  - The theme follows the system by default. A stored theme is kept: v1 saved every field on any change, so its users keep dark.
  - *Dark during Taraweeh* (on) is a theme scoped to the Taraweeh route. Screens opened from Taraweeh mode inherit it.
- **`AppRoutes`:** every screen-to-screen move in one place.

### R4: Taraweeh mode on `QuranView` (done)
- The recognition controller, its states, corrections, lock, Al-Fatiha handling and reconnects are **unchanged**. Every earlier recognition-state test still runs.
- **One tap from the reader starts listening.**
  - A one-time introduction (microphone, Wi-Fi server build, Ḥafṣ only, how to correct) comes first. It is never shown again; *Not now* leaves following off.
- **Leaving the mode stops following and saves the last Taraweeh position.** That is the imam's main position (`anchor`), never Al-Fatiha at a rakʿah. Taraweeh never writes the reading position (tested).
- **The next night**, if the last session was within 36 hours, the juz after where it ended is applied as a soft hint.
  - It is shown as "Last night ended at …" and is removable.
  - The hint chip now stays visible while listening, until the imam is found.
- `QuranColumn` is removed.

### R5: navigation, search, bookmarks (done)
- **Go to:** Surahs (filterable), Juz, Pages (all 604) and Bookmarks.
  - Every list opens at the current place, exactly, at any text size. Rows share one height, measured from a prototype.
  - The Bookmarks tab starts with where Taraweeh ended. Removing a bookmark can be undone.
- **Search:** one field for references (Arabic-Indic digits too), pages, juz, surah names in any language the app knows, and Arabic text.
  - Arabic text goes through the engine's own `normalize`, so tashkeel, hamza seats and alef forms do not matter.
  - Matching is a scan of 6,236 short strings, a few milliseconds, so there is no index and no isolate.
  - Results are in mushaf order, capped at 200, with the full count.
- Taraweeh mode's index is the same navigator.

### R6: polish, languages, documentation (done)
- **English, French and Arabic**, using Flutter's gen-l10n.
  - About 200 messages, with ICU plurals (the full Arabic forms). The generated code is committed and formatted at the project width (`analysis_options.yaml`).
  - `test/l10n/` fails if a language misses a message or a placeholder.
  - An app language setting (System by default) and one `appLocaleProvider` decide the language. Surah names follow it; in Arabic each surah's own name is used and never shown twice.
  - Arabic is right to left throughout; Quran text is always right to left. Arabic overlines have no letter-spacing or capitals.
  - iOS declares its localizations, and Android sets `supportsRtl`.
- **Settings regrouped:** Reading (text size, appearance, language), Taraweeh (dark during Taraweeh, keep screen on), Recitation, Recognition server, Developer, About.
- **New Rubric token:** `mark`, the reader's wash for a chosen ayah. Cinnabar keeps its one meaning.
- **Tests:** 177, plus 22 golden screenshots with the real fonts (including Arabic and French). DESIGN.md is rewritten for the reader-first app.

### Open after R6
1. **The A32 scroll benchmark (R2's deciding run)**, as soon as the phone is connected. It is one command (above).
2. **Native review of the French and Arabic texts.** They are drafts, as M4 already planned.
3. **Not localized yet:**
   - The developer screens (diagnostics, the on-device benchmark).
   - The server-address validation messages and the server's own error text. Both belong to the server build only.
4. **Later, by decision:**
   - A page-by-page mushaf mode (flowing text per Madinah page, never called a facsimile).
   - Copying or sharing an ayah as an image.
   - Recitation audio, translations, a khatm planner, notes.
5. **§17 M4 items closed by this work:**
   - Localization (drafts).
   - First-run onboarding for Taraweeh.
   - Where browsing lives (the reader is home).

## 19. Build 0.2: reader complete (2026-11-05)

Built on `feat/quran-reader`, in five commits, each with tests and goldens.

- **Page view.** The 604 Madinah-mushaf pages, one per screen, turned right to left like a printed mushaf.
  - Each page holds exactly Tanzil's ayahs, flowing per surah, with a running head and the page number.
  - It is never presented as a facsimile: a long page scrolls within itself.
  - It shares the reading position, ayah taps, marks and text size with the scroll view.
  - A Layout setting (Scroll / Pages) is saved; the bar toggle shows on screens 360 dp or wider.
- **Share an ayah**, as an image card (rendered at 3× from its own preview) or as text.
  - A `Sharer` interface over `share_plus`, the standard Flutter share-sheet plugin (the one new dependency).
- **Reading progress and a daily goal.**
  - **What counts:** a page is read when the reader moves forward past it (one or two pages at a time). Jumps never count, and opening the app counts nothing.
  - **Storage:** a 90-day log, versioned like the other records.
  - **Goals:** off, 5, 10, 20 or 40 pages. Today's count and a 2 px line show in the reader bar. No streaks.
  - The Pages tab shows where the reader is in the whole Quran.
- **Launch screen.** On Android it follows day and night with the Rafiq mark; the app icon stays dark.
- **Accessibility pass.** Flutter's tap-target, label and contrast guidelines run on every main screen, in both themes, and every screen is checked at 200% system text. The pass found and fixed:
  - two settings switches that screen readers announced without a name;
  - a surah-row layout error at large text.
- **Also:** the Kotlin compiler cache is no longer tracked.

**Totals:** 205 tests, 26 golden screenshots, and the Android debug build passes.

**Open after 0.2:**
1. **iOS still launches dark.** The storyboard was not changed, because it cannot be verified without a Mac.
2. **Not yet seen on a device:** the splash and the share sheet. The tests cover the share flow with a fake sharer.
3. **The A32 scroll benchmark** (R2) is still pending. It should now also cover the page view.
4. **Native review** of the new French and Arabic strings.
5. **Next build:** 0.3, Taraweeh on the phone (§17 M1–M2), the critical path to the beta.

## 20. Navigation and bookmarks redesign (2026-11-05)

**Why:** after trying 0.2 on the emulator, finding a surah, moving through the Quran and bookmarking were all too hard:
- Navigation hid behind unlabelled icons.
- There was no fast way through 604 pages.
- Bookmarks were invisible in the text and buried in a tab of Go to.

**What changed** (simple patterns, nothing new underneath):
- **A labelled bottom bar: Read · Surahs · Bookmarks · Taraweeh · More.**
  - Taraweeh stays a one-tap button that starts listening, as approved in §18.
  - Settings moved to More.
  - The floating Taraweeh button over the text is gone.
- **Surahs tab:** the surah list (with a filter), juz and pages. Tapping the surah name (now with a ▾) in the reader opens it.
- **Scrubber:** a handle on the edge that flies through the pages, with a bubble naming the page, surah and juz. It works the same in scroll and page view.
- **Bookmarks:**
  - A ribbon in the text marks bookmarked ayahs.
  - Press and hold an ayah to toggle its bookmark at once, with Undo.
  - The Bookmarks tab lists *Continue reading* and *Where Taraweeh ended*, then the bookmarks, sorted newest first or in Quran order (remembered).
  - Swipe to delete, with Undo restoring the original date.
  - A removal that fails to save stays visible and says so.
- **Placeholders**, shown and visibly disabled:
  - In More: recitation audio, translations, tafsir, a khatm planner, notes, Taraweeh without a computer.
  - In the ayah sheet: Listen, Translation and Tafsir.
- **Design rule:** other tabs open places in the reader through `readerRequestsProvider`, never by reaching into its widget state.
- **Accessibility:** a screen reader announced the page view's long-press area as an unlabelled node. It is now hidden from screen readers, who bookmark through each ayah's sheet.

**Totals:** 212 tests, 29 golden screenshots, and the Android debug build passes.
