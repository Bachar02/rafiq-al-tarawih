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

## 21. Build 0.3 plan: khatm planner and notes (agreed 2026-11-05)

**Scope now:** the khatm planner and notes, built to the same standard as 0.2: tests, goldens, three languages, accessibility.

**Later, in this order:**
1. Taraweeh on the phone, once the Galaxy A16 is plugged in for the §16 benchmark.
2. A GitHub-style chart of reading discipline.
3. Translations, tafsir and audio, once licensed sources are confirmed.
4. The Play Console account. The iPhone needs a Mac.

**Dropped:** recording real mosque audio (not permitted).

**Starting state:** branch `feat/quran-reader`, at the end of §20, with history tidied. It is to be pushed and merged into `master` by the owner through a PR. Start 0.3 on a new branch from `master` once that is merged.

**Rules, unchanged:**
- **Simple, robust, scalable.** No feature added just to look bigger.
- **Store rules:** save before showing; an unreadable record is copied aside (`<key>.unreadable.<time>`) before any write; a failed write is reported, never thrown.
- **Same checks as 0.2:** every string in English, French and Arabic (`test/l10n`); every screen passes `test/accessibility_test.dart`; goldens for new screens via `mobile/tool/goldens.sh`.
- **The owner commits and pushes.** No AI attribution in commits, PRs or files.

### 21.1 Data (lib/data/)

**First, `ReadingLog.keepDays`: 90 → 400.** The discipline chart will need a full year of history. It is a one-line change, with a test.

**`khatm.dart`:**
- `KhatmPlan` (immutable):
  - `startedOn` and `endsOn`: local dates, `endsOn` inclusive.
  - `startPage`: where the reading order begins.
  - `pages`: `Map<int page, String dayKey>`, the day each page was *first* read during the plan.
  - Derived values:
    - `remaining = 604 − pages.length`;
    - `readOn(day)` = the pages whose dayKey is that day;
    - `daysLeft(today) = max(1, endsOn − today + 1)`;
    - `overdue(today)`;
    - `todayTarget(today) = ceil((remaining + readOn(today)) / daysLeft)`. Today's reading must not shrink today's target.
    - `nextPage` = the first unread page, scanning from `startPage` and wrapping around.
  - JSON `{"v":1, …}`.
- `KhatmRecord {startedOn, completedOn}` and `KhatmBook {active?, finished: [KhatmRecord]}`.

**`note.dart`:** `Note {verseId, text, createdAt, updatedAt}`.
- One note per ayah.
- Text trimmed, at most 2000 characters; an empty text deletes the note.

**`ReadingStore`:** add `khatm()` / `saveKhatm(KhatmBook)` (key `khatm.v1`) and `notes()` / `saveNotes(List<Note>)` (key `notes.v1`).
- Same validation as bookmarks: verse ids 1..6236, pages 1..604, unknown versions kept aside.
- Update `FailingStore` in `test/features/reader_screen_test.dart`.

### 21.2 Khatm planner

**`features/khatm/khatm_controller.dart`** (`Notifier<KhatmBook>`, uses `clockProvider`):
- `start(endsOn, startPage)`, `changeEnd(endsOn)` and `stop()` save first, then update the state.
- `recordPages(pages)`: adds only pages not already in the plan, stamped with today's key.
  - It is called from `ReadingProgressController.movedTo` for the pages it counts, so the "read past it" rule (§19) is the only definition of reading.
  - Saving is fire-and-forget with a dirty flag, flushed with the reading position on pause, like `ReadingProgressController`.
- **Completion:** when `pages` covers all 604, the plan moves to `finished` (`completedOn` = today) and `active` becomes null.

**`khatm_screen.dart`**, opened from More (it replaces the "Khatm planner — Soon" row) and from the Bookmarks card:
- **No plan:**
  - A one-line explanation.
  - Length choices: 15 days, 30 days ("a juz a day"), 60 days, or a date you pick (`showDatePicker`).
  - Start choices: "where I am reading (page N)" or "from the beginning".
  - A *Start* button.
- **Active plan:**
  - "Page X of 604 read" with a progress bar.
  - "Today: a of b pages".
  - "N days left · ends <date>", the date formatted by `intl` `DateFormat.yMMMd(locale)`.
  - *Continue khatm (page N)*, which calls `readerRequestsProvider.open(pages.start(nextPage))`.
  - *Change end date*.
  - *Stop this khatm*, with a confirmation dialog.
- **Overdue:** "Past the planned end · X pages left", and *Change end date*.
- **Finished khatms:** a quiet list, "Completed <date> · in N days".
- **Completion moment:** the reader shows one calm snackbar ("Khatm complete"). It reacts to `finished` growing, through `ref.listen`.

**Integration:**
- **Reader bar:** when a plan is active, "Today a/b" comes from the plan and supersedes the daily goal. The 2 px line follows it. The daily goal applies only when there is no plan.
- **Bookmarks tab:** when a plan is active, a card at the top with "Khatm · page X of 604 · today a/b". Tapping it opens the khatm screen.

**Tests:**
- Target arithmetic, including: reading ahead lowers tomorrow's target; overdue; wrap-around of `nextPage`; re-reading a page adds nothing.
- Completion moves the plan to `finished`.
- Long plans (365 days) keep every page, independent of the log.
- JSON round-trip, and unreadable records kept aside.
- Widget flows: start, continue, change end, stop, the bar and the card.
- Goldens: the screen with no plan and with an active plan.

### 21.3 Notes

**`features/notes/notes_controller.dart`** (`Notifier<List<Note>>`, newest updated first): `save(verseId, text)`, `delete(verseId)` and `restore(note)` for Undo. Save first, then update the state.

**`note_sheet.dart`:**
- A bottom sheet with the ayah's reference, a multiline `TextField` (autofocus, `maxLength` 2000) and *Save*.
- *Delete* appears when a note already exists.
- The text direction follows the note's content (`Bidi.detectRtlDirectionality` from `intl`), both while editing and when shown.

**Entry point:** the ayah sheet gets *Add a note* / *Edit note*, next to Bookmark, Share and Copy.

**In the text:** `AyahBlock.noted` and `QuranView.notedVerses` show a small note icon in the margin, under the bookmark ribbon. `MushafPageView` shows the same as a `WidgetSpan` before the ayah. The semantics label gains ", note".

**Bookmarks tab:**
- A segmented control: **Bookmarks | Notes**.
- Notes list: reference, place, the note's first two lines and the date. Tap to read there. A trailing edit button opens the sheet. Swipe deletes, with Undo.
- An empty state explains how to add a note.

**More:** remove "Notes — Soon" (the feature now lives in the ayah sheet and Bookmarks).

**Tests:**
- Save, edit, empty text deletes, the 2000-character limit, Undo restores the note with its dates.
- A failed save is reported and nothing changes.
- The icon appears in both layouts.
- RTL and LTR notes.
- Goldens: the note sheet and the Notes list.

### 21.4 Order of work (each step one commit, all checks green)
1. Data models, the store, `keepDays` 400, and unit tests.
2. The khatm controller and its hook into reading progress, with tests.
3. The khatm screen, the reader bar, the Bookmarks card and More, with strings, tests and goldens.
4. The notes controller, the sheet and the ayah-sheet entry, with tests.
5. Note icons in both layouts, the Bookmarks | Notes tabs, strings, tests and goldens.
6. `DESIGN.md`, this section's results, version 0.3.0, a release build, and a check on the emulator.

### 21.5 Results (build 0.3, 2026-11-05)

Built on `feat/khatm-notes` from `master`, in six commits as §21.4 planned, each with all checks green.

- **Data:** `KhatmPlan` / `KhatmBook` (`khatm.v1`, pages grouped by day) and `Note` (`notes.v1`) in the reading store, with the same rules as bookmarks: readable parts kept, the original copied aside, failed writes reported. `ReadingLog.keepDays` is 400.
- **Khatm planner:** as planned in §21.2. One deviation: Start's "from the beginning" has no "Page 1" caption, so the Start button fits on a 360 × 780 screen.
- **Notes:** as planned in §21.3. Two deviations, both from the emulator check:
  - *Save* sits beside the sheet's title, pinned above the field. Below the field, the keyboard hid it.
  - The field starts at three lines, not four.
- **Bookmarks | Notes** is a segmented control at the top of the tab's body, not in the app bar, so it grows with 200% system text.
- **Strings:** 47 new messages in English, French and Arabic (full Arabic plural forms). The "Khatm planner" and "Notes" placeholders are gone from More.
- **Totals:** 279 tests (212 before), 28 golden screenshots (4 new: the planner with and without a plan, the note sheet, Notes; More, Bookmarks and the ayah sheet re-rendered). The release APK builds as 0.3.0+3.
- **Emulator** (Pixel XL API 36, release build, installed over 0.2): the reading position and bookmark from 0.2 were kept. Checked:
  - starting a 30-day plan from page 423;
  - *Continue*, then two page turns giving "Today 2/21" in the bar;
  - the Bookmarks card, still there after two reinstalls;
  - adding a note, its icon in the page view, and the Notes list.
- **Emulator note:** with Docker Desktop running, the emulator hangs at boot (all vCPU threads). Quit Docker (and `wsl --shutdown`) first, and cold boot with `-gpu swiftshader_indirect`.

**Open after 0.3:**
1. Native review of the new French and Arabic strings.
2. Not seen on a phone yet: the date picker in Arabic.

### 21.6 Reading that counts (2026-11-05, after the owner's first try)

**Why:** after trying 0.3 the owner found the tracking too easy to fool. A page counted when the reader moved past it, so scrolling through counted pages nobody read, and there was no way to undo a wrong count.

**What changed** (agreed with the owner: time on the page, then a review; a page map for corrections):
- **Time on the page** (`PageDwell`): a page is proposed once it has stayed in view long enough to read it.
  - That is 0.15 s per word on the page, at least 4 s: about 20 s for a full page.
  - Time runs only while the reader is in view, and goes to the page at the top. Two visits add up.
  - This replaces "moved forward past it" everywhere. Flings and the scrubber count nothing.
- **Review** (`ReadingSessionController`, the *Count this reading?* sheet):
  - Proposed pages wait, saved, until a session is over: the next time the app opens, or after 3 minutes or more away.
  - The sheet lists them by day as toggles. *Count* records the ticked ones in the daily log and the khatm. *Don't count these* sets them aside. *Not now* keeps them waiting.
  - Waiting pages show in "Today" in the meantime.
- **Page map** in the planner: 30 juz tiles; each opens its pages (mushaf juz boundaries) as toggles, with *Mark all read / unread*.
  - For mistakes and paper-mushaf reading.
  - It changes the khatm only, not the daily log.
- **Simpler underneath:** the log and the khatm now take only explicit, saved-first changes. Their delayed saves are gone.
- **Totals:** 297 tests, 30 golden screenshots (new: the review sheet, a juz sheet; the planner re-rendered), accessibility checks on both sheets. There are 15 new strings in three languages, and the daily-goal explanation was reworded.

### 21.7 After 0.3
- **Taraweeh on the phone:** the §16 benchmark on the Galaxy A16, then §17 M2.
- **Reading discipline chart:** a year grid of days shaded by pages read, from `ReadingLog` (now kept 400 days). It goes in the Bookmarks or More area, with a weekly or yearly toggle and no streak pressure.

## 22. Build 0.4: translations and tafsir (2026-11-06)

**Sources (agreed with the owner):** all four come from [QuranEnc.com](https://quranenc.com), are bundled offline, and match our 6236 ayahs surah by surah.

| | English | French | Arabic |
|---|---|---|---|
| Translation | Saheeh International (Noor International Center), 1.1.2 | Muhammad Hamidullah, 1.0.2 | — |
| Tafsir | none licensed: Al-Muyassar, labelled "In Arabic" | Al-Mukhtasar (Tafsir Center for Quranic Studies), 1.0.0 | At-Tafsir Al-Muyassar (King Fahd Complex), 1.0.0 |

**Why QuranEnc:**
- **Tanzil is ruled out:** its translations are for non-commercial use only.
- **QuranEnc's terms** allow republishing as long as:
  - the text is not changed;
  - the publisher, QuranEnc.com and the version are named;
  - each text is kept at QuranEnc's latest version;
  - no inappropriate ads are shown.
- **Commercial use:** the terms say nothing about it. Rafiq is free and has no ads.
- **English tafsir:** QuranEnc has none. Getting the English Mukhtasar needs the Tafsir Center's permission (a request was drafted for the owner).

**Data** (`data/build_texts.py`, `data/texts.json`, `data/README.md`):
- **Sources:** QuranEnc's SQLite databases, kept verbatim in `data/raw/quranenc/` with their SHA-256 pinned.
- **Build:** text and footnotes are copied byte for byte to `mobile/assets/texts/<key>.json`, plus a `catalog.json`.
- **Validation:** every text is checked against `quran-data.xml`. Any mismatch aborts the build.
- **Commands:** `updates` reports a newer QuranEnc version (run it before each release), and `fetch` takes it.
- **CI:** runs `pytest data` and `build_texts.py --check`.

**App:**
- **Study view** (`features/study/`):
  - It opens from the ayah sheet's Translation and Tafsir buttons (now live; Listen stays "coming soon"), or from More → *Translation and tafsir* at the reading position.
  - It shows the ayah, then a Translation | Tafsir switch.
  - The text appears as published, with footnotes, the name, and "credit · version · QuranEnc.com".
  - A translation also carries the note that it conveys the meanings and is not the Quran.
  - Swipe, or tap *Previous ayah* / *Next ayah*, to move across surahs. The reader's position does not move.
  - Each text keeps its own direction and language, so an Arabic tafsir reads right to left in English and a screen reader voices it as Arabic.
- **Choice:** the text in the interface language by default. Otherwise English for translations and Arabic for tafsir. In the Arabic UI, the translation is English.
  - It can be changed from the study view or from Settings → Translation and tafsir. Saved as `translation_key` / `tafsir_key`.
  - A saved key that is no longer bundled falls back to the default.
- **Loading:** texts load on first use, parsed in an isolate, and are kept in memory. A broken file shows a message instead of crashing, and is not retried.
- **Attribution:** every text is listed in Settings → About, and in `assets/texts/NOTICE.txt`.
- **Ayah sheet:** the Translation · Tafsir · Listen row now sits right under the ayah. On the emulator the sheet stops at 70% of the screen, and at the bottom the row was hidden until scrolled. "Listening … coming soon" moved to the foot of the sheet.
- **Theme fix:** screen titles (Newsreader) had no Arabic fallback, so Arabic titles depended on the phone's fonts and showed as empty boxes in renders. They now fall back to IBM Plex Sans Arabic. No existing golden changed.

**Totals:**
- **Tests:** 315 (297 before) and 7 data-pipeline tests.
- **Goldens:** 32 (new: the study view in English, and Al-Muyassar in the Arabic UI; re-rendered: ayah sheet, More, Settings, French Settings).
- **Accessibility:** the study view and source sheet pass in both themes and at 200% text.
- **Strings:** 17 new strings in three languages, and 4 placeholders removed.
- **Size:** about 6.7 MB of JSON before APK compression.
- **Version:** 0.4.0+4.

**Emulator** (Pixel XL API 36, release build installed over 0.3):
- The reading position from 0.3 was kept (page 339).
- Ayah 22:58 → Translation showed Saheeh International with its credit line and the translation note.
- Tafsir showed Al-Muyassar, labelled "In Arabic". It is the largest file (2.5 MB) and opened without a visible wait.
- A swipe moved to 22:59.

**Open after 0.4:**
1. Native review of the new French and Arabic strings, and of the French and Arabic source names and credits.
2. Ask the Tafsir Center for the English Mukhtasar.
3. Optional: a second translation per language (Rowwad in English, Rachid Maach in French), one `texts.json` entry each.

## 23. Build 0.5 plan: the reading chart and a daily reminder (agreed 2026-11-07)

**Goal:** a reason to open Rafiq every day, without pressure. The owner chose:
- **A gentle run:** "5 days in a row" and the best run. There are no flames and no "you lost your streak" message: a missed day is just an empty square, and today does not break the run until it is over.
- **An opt-in daily reminder:** a local notification at a time the user picks. It is skipped on days the user has already read.
- **Placement:** a card at the top of the Bookmarks tab, which opens a full Reading screen.

**What counts:** pages in the daily reading log (confirmed in the review), plus pages waiting for review, the same as "Today" in the reader bar. The khatm page map is for corrections, so it does not count.

**Chart:**
- A grid of days, one column per week, the newest on the inline end. Each day is shaded by pages read: none, 1–4, 5–9, 10–19, or 20+ (a juz).
- The card shows the weeks that fit and the run.
- The Reading screen shows 53 weeks with month names, a tapped day's count, the last 7 days against the goal, the run and best run, days read this year, and pages this month. It also has the reminder setting and the hadith on consistency (al-Bukhari and Muslim).

**Reminder** (`flutter_local_notifications` 22.x, which needs AGP 8.11; v23 needs AGP 9):
- **Schedule:** up to 7 one-time notifications, one per day at the chosen time (default 20:00), starting tomorrow if today is already read. Each says the day's target and where to continue. They are rescheduled whenever the app is shown or hidden, so the text stays true.
- **Stops after 7 days:** a user away for a week is not nagged.
- **Offered once,** after the first counted reading, and in Settings and on the Reading screen.
- **Permission:** Android 13+ asks for notification permission. If it is refused, the reminder stays off and the app says where to turn notifications on.
- **No exact alarms:** they need a Play Store permission meant for alarm-clock apps. Inexact delivery comes within an hour of the time, so the setting says "around". Nothing leaves the phone.

**Same checks as before:** three languages, accessibility in both themes and at 200% text, goldens, and an emulator run of a real notification.

### 23.1 Results (build 0.5, 2026-11-07)

Built on `feat/reading-chart` from `master` (after PR #2).

- **Data:** `ReadingStats` (`lib/data/reading_stats.dart`) computes pages per day (log plus pending, each page once), the current and best run, days this year, and pages this month. Day arithmetic is by calendar, so it is safe across daylight saving.
- **Chart** (`features/progress/`):
  - `ReadingGrid` is a painted grid. Weeks start on the locale's first day. It mirrors in right-to-left layouts, rings today, and labels months on the full screen.
  - Each bar of the last 7 days is its own screen-reader item. The test caught them merging into one.
- **Placement:**
  - The card at the top of Bookmarks opens the Reading screen.
  - The reader bar is not an entry point after all. The whole bar is already one tap target (Surahs), and a separate small "Today" target would fail the 48 dp tap-target test.
- **Goal line:** the daily goal, or "Khatm today: N pages" when a khatm sets the day's target.
- **Reminder:**
  - Built on `flutter_local_notifications` 22.3.3 and `timezone`. Core library desugaring is on, and the manifest has the boot and package-replaced receivers.
  - It uses a monochrome book icon, kept from resource shrinking by `res/raw/keep.xml`.
  - Each reminder is the local wall-clock time converted to an instant, so no time-zone database or plugin is needed.
  - Rescheduled when the app is shown or hidden (`AppLifecycleListener` in the shell). Nothing is touched while the reminder is off.
- **Arabic dates:** they now use the same Western digits as the rest of the Arabic interface (`DateFormat.useNativeDigitsByDefaultFor('ar', false)`). The hadith is not set in italics in Arabic.
- **Tests:**
  - **Count:** 348 (315 before).
  - **Goldens:** 35 (new: the Reading screen in English light and Arabic dark, and the Bookmarks card; re-rendered: Bookmarks and both Settings).
  - **Accessibility:** both themes and 200% text. 200% caught the legend overflowing, and it now wraps.
  - **Test fixes:** one older test had to follow Android's real lifecycle order, which `AppLifecycleListener` asserts.
- **Strings:** 31 new strings in three languages.
- **Emulator** (Pixel XL API 36, release build over 0.4):
  - The card and the screen matched the log.
  - Android 16 asked for notification permission, and the app scheduled 7 alarms.
  - With today unread, a reminder set for 18:54 arrived at 18:54: "Your daily reading — 22 pages today. Continue at Al-Hajj, page 340." Page 340 is the khatm's next unread page.
  - Tapping it opened Rafiq.
  - Alarms more than a few minutes away get Android's one-hour window, hence "around" in the setting.

**Open after 0.5:**
1. Native review of the new French and Arabic strings, including the hadith wording (al-Bukhari and Muslim; Arabic «أحب الأعمال إلى الله أدومها وإن قل»).
2. Reading from a paper mushaf does not reach the chart. A way to add pages read elsewhere could come later.

## 24. The way back from the reader (2026-11-08, from the owner's testing)

The owner tapped a note, landed on its ayah, and had no way back to the notes. The same was true of every jump into the reader: a bookmark, the Surahs tab, a search result, the khatm planner's Continue. The phone's back button left the app.

- **What changed:** a jump into the reader now says where it came from (`ReaderOrigin` in `lib/app/navigation.dart`). While there is a way back, the reader shows a pill at the foot of the text ("Back to notes", "Back to bookmarks", "Back to surahs", "Back to search", "Back to the khatm"), and the phone's back button does the same.
- **Where it lands:** the Notes view (the Bookmarks tab now remembers its view), the list scrolled where it was, the search with its query and results, the khatm planner over the tab it came from.
- **The reading place:** if the user only looked (still on the page the jump landed on), the reading position goes back to where it was. If they read on, the new place is kept.
- **When it ends:** when the user takes it, makes another jump, or leaves the Read tab. One level: a new jump replaces the previous way back.
- **Tests:** 9 widget tests (`test/features/reader_return_test.dart`) and 2 goldens (English light after a note, Arabic dark after a search). 5 new strings in three languages.

## 25. Build 0.6: the adhkar and dhikr reminders (2026-11-09)

The owner asked for adhkar, simple to use, and for an opt-in reminder: a dhikr at the top of the screen every couple of hours, shown for 8 seconds or until tapped, even when the app is closed.

**Collections** (morning and evening were the owner's starting point):
- **Morning** (after Fajr) and **Evening** (after Asr) share one list. The evening says its own words where they differ (أمسينا for أصبحنا), and a few adhkar belong to only one of the two.
- **After prayer**: the istighfar, the tahlil, and the tasbih as three counters (33, 33, 33) and the hundredth.
- **Before sleep**: the three Quls, Ayat al-Kursi, the end of al-Baqarah, and the sleeping adhkar (33, 33, 34).
- **Any time**: 16 short adhkar. These are what the reminders draw on, so a morning dhikr never arrives at night.
- Waking up, entering the mosque and other occasions can come later as further collections.

**Content** (`assets/adhkar/adhkar.json`, `NOTICE.txt` beside it):
- **Arabic:** chosen and worded after Hisn al-Muslim, with full tashkeel and each dhikr's sources (al-Bukhari, Muslim, Abu Dawud…).
- **Counts:** set by hand. The site's JSON has wrong repeat counts (7 recorded as 1, for example).
- **Quran:** never retyped. A dhikr holds references (`2:255`, `112`, `2:285-286`), and the app shows the ayahs from its own Tanzil text, with "Translation and tafsir" one tap away.
- **Meanings:** English and French meanings written for Rafiq. Arabic shows the words alone.
- **Checks:** the file is checked when it loads, for real ayahs, known sources, unique ids and counts of at least 1. A broken file leaves the Adhkar empty and the Quran working.

**Screen** (More → Adhkar, the first row, saying "Now: Evening adhkar" when the hour fits):
- **Home:** the five collections with today's progress ("3 of 22 today", "Done today"), and "Now" on the one this hour suggests. It is a word on a row; the list order never changes.
- **A collection:** one card per dhikr, in order. Tap a card each time it is said: a light tick (haptic), the counter goes down to a check, and the list moves on to the next. "Start again" has an undo.
- **Today's counts:** kept on the phone and started again each day. Losing them is harmless, so an unreadable record simply starts again.
- **Text size:** the Arabic follows the Quran text-size setting.

**Dhikr reminders** (on the Adhkar screen and in Settings, off by default):
- **Every 1, 2, 3 or 4 hours** (default 2), from 8:00 to 22:00, never at night. Scheduled 14 days ahead, so they come with the app closed, and moved on whenever the app is shown or hidden.
- **The pop-up:** a heads-up notification on its own channel ("Dhikr reminders"): high importance, no sound, no vibration, `timeoutAfter` 8 s. A tap opens the Adhkar; a swipe dismisses it. The title is "Remember Allah", then the dhikr, and its meaning (not in Arabic).
- **Collapsed:** the Arabic alone. The emulator showed Android joining the dhikr and its meaning on one line, where Arabic and English mixed read in the wrong order. Expanded, the meaning sits under it.
- **Where it shows:** on a phone, Android puts it at the top of the screen, across the width. An app cannot choose the top-right corner: that would need the "display over other apps" permission, which Play restricts and users distrust.
- **Which dhikr:** random-looking but fixed per hour, so rescheduling only cancels or adds what changed (a hundred or so alarms). Never the same dhikr twice in a row.
- **Taraweeh mode:** keeps them away for 3 hours. Nothing pops up over the imam's ayah.
- **Inexact alarms**, as for the daily reminder: one more than a few minutes away may come up to an hour late, so the setting says "a little". The reading reminder now cancels only its own notifications (ids 0–15); dhikr reminders use ids 1000–1499.

**Tests:**
- **Count:** 401 (357 before): data checks, counting, the evening's words, the Quran references, three languages, scheduling, the quiet spell during Taraweeh, and a tap opening the Adhkar.
- **Goldens:** 4 new (the Adhkar home, the morning on Ayat al-Kursi, after prayer in dark, the evening in Arabic) and 3 re-rendered (More, Settings in English and French). The real fonts showed a pause mark touching the passage label, now spaced.
- **Accessibility:** both themes and 200% text.

**Emulator** (Pixel XL API 36, release build over 0.5):
- Turning it on scheduled 107 dhikr alarms (18:00 to 22:00 today, then 8 a day), and the reading reminder kept its own.
- The clock was moved past the 18:00 window (`cmd alarm set-time`), with the app in the background. The dhikr popped up at the top of the screen, silent ("Remember Allah", then the dhikr). Within 12 seconds it had gone, from the screen and from the shade.
- Tapping one opened the Adhkar.
- Alarms a while away get Android's inexact window (here +33 min to +1 h), as for the daily reminder.

**Open:**
1. Native review of the French and Arabic strings, the English and French meanings, and the Arabic notes.
2. A scholar's look at the selection and the sources.
3. A real phone over a day: the heads-up, the 8 seconds, and how far Android moves inexact alarms.

## 26. Build 0.7: prayer times and the adhan (2026-11-10)

The owner asked for the adhan: based on where the user is, on or off, with sound or vibration.

**Prayer times** (More → Prayer times, the first row, saying "Next: Asr, 2:52 PM" once a place is known):
- **Computed on the phone** with `adhan_dart` (MIT, after Meeus), behind `lib/core/prayer/prayer_times.dart`. Nothing is fetched.
- **The place:** "Use my location" (approximate permission only, read once, never in the background) or a town typed and chosen. A position is kept to two decimals (about a kilometre) and never leaves the phone.
- **The towns:** 64,634 towns of 5,000 people or more with their English, French and Arabic names, and 252 countries (`assets/places/`, 2.2 MB, GeoNames CC BY 4.0, built by `data/build_places.py`). The same list names a position (the nearest town) and serves the search, so no geocoding server is asked.
- **The method** follows the place's country (Tunisia, Algeria, Morocco, Egypt, Umm al-Qura, France UOIF, and 16 others; the Muslim World League elsewhere). The user can choose another, the Hanafi Asr, and move each time by up to 30 minutes to match the mosque.
- **Far north:** above 48° Fajr and Isha take a seventh of the night. Inside the polar circles the package gives nonsense, so the nearest latitude with a sunrise and a sunset stands in.
- **Travelling:** when the app is shown, a place that came from the phone's location follows the phone once it is 25 km away. A chosen town never moves.

**The adhan** (off by default; a switch on the Prayer times screen):
- **Each prayer its own way:** adhan, vibration, silent notification, or off. Tap the prayer's row.
- **Recording:** the whole adhan (2 min 34 s) or its opening takbir (31 s). "Test the adhan" calls it at once on the real channel.
- **How it sounds:** a notification's sound on a channel per tone (`adhan_full`, `adhan_takbir`, `adhan_vibrate`, `adhan_silent`), since Android fixes sound and vibration per channel. It follows the notification volume and is quiet when the phone is on silent. A swipe or a tap stops it. The notification leaves the shade after 30 minutes.
- **On the minute:** exact alarms (`SCHEDULE_EXACT_ALARM`), for the adhan only. This reverses §23's "no exact alarms" for this one feature; the reading and dhikr reminders stay inexact. Android 14+ leaves the permission off until the user allows it: the app explains, opens the setting, and until then each prayer gets a silent notification (a call to prayer an hour late is worse than none) and the screen says so.
- **Scheduled 30 days ahead** (about 150 alarms, ids 2000–2498, the same prayer of the same day keeping its id), moved on whenever the app is shown or hidden. After the last day's Isha a notification asks the user to open Rafiq once.
- **Force-stop:** the plugin's list of pending notifications is its own record, not Android's. A phone that force-stops the app drops the alarms and leaves the record. So the first scheduling of each process sets every adhan again (12 at once, the rest 40 ms apart); later ones only what changed.
- **Taraweeh mode** keeps the adhan silent for 3 hours: the microphone is listening.

**The recording** (`android/app/src/main/res/raw/`, notice in `assets/adhan/NOTICE.txt`, built by `data/build_adhan.py`):
- "Beautiful adhan.ogg" by Adam-synagda, Wikimedia Commons, CC0 1.0 (public domain dedication). Kept byte for byte (SHA-1 pinned); the takbir is its first two phrases, cut in the silence after them without re-encoding.
- Checked by machine, not by ear: twelve phrases in the order of the adhan, by their silences and a rough transcription. **The owner should listen to it before release.**
- Other recordings were set aside: one "public domain" file is a 1985 performance taken from YouTube; a 42-second CC0 file is an iqama.
- **No Fajr adhan** ("as-salatu khayrun mina n-nawm") was found under a public-domain dedication, so Fajr plays the general adhan.

**Emulator** (Pixel XL, Android 16, debug build over 0.6):
- Android asked for the approximate location only. Tunis was found in about 20 seconds, and the times matched the tests.
- With alarms not allowed: 147 inexact alarms, Isha with a 17-minute window, and the notice on the screen. Allowed from the notice: the same 147 became exact (`window=0`).
- **The whole adhan plays.** The test's sound was still playing at 147 s and had ended by 160 s. No 30-second cut on Android 16.
- **On time, asleep:** screen off, deep Doze forced, the clock set 20 s before Isha: the notification was posted 18 ms after the minute.
- **A platform trap, found and fixed.** Android 16 gathers an app's ungrouped notifications into one group, and marks a newcomer silent before it sounds when another is already in the shade. The first adhan with a reading reminder present was mute (`MUTE_REASON_FLAG_SILENT`, read from the event log and Android's source). The adhan now names its own group: with a reading reminder and four adhans in the shade, Fajr sounded at full volume and kept playing.

**Tests:** 478 (401 before).
- The times against the NOAA solar equations, worked out apart from the package (Tunis on two dates, Makkah, Jakarta, Honolulu), the methods, the Hanafi Asr, offsets, the far north and the poles.
- The settings record (round trip, parts a later version wrote, unreadable records set aside), the town list (search in three languages, nearest town, bad rows), scheduling, each alert, the permission refused and taken back, Taraweeh, travelling, the day moving on.
- Accessibility in both themes and at 200% text. 200% found two real faults: the times list opened scrolled after the intro, and a row overflowed.
- 6 new goldens, More re-rendered. 107 new strings in three languages.

**Decisions for the owner:**
1. **Jerusalem** is listed once, in Palestine, and PS is named "Palestine" in English. GeoNames files the city under IL. This is an editorial choice, written in `data/build_places.py` (`COUNTRY_OF`) and `assets/places/NOTICE.txt`, and one line to change.
2. **The recording:** listen to it; replace it if another muezzin is preferred (one file and its SHA-1).
3. **Play:** confirm in the Play Console whether `SCHEDULE_EXACT_ALARM` needs a declaration. Data safety now includes approximate location, used on the device only.

**Open:**
1. A real phone (Galaxy A16): the whole adhan with the screen off, and what Samsung's battery saver does to the alarms.
2. The same Android 16 grouping silences the daily reading reminder when a dhikr is in the shade (seen on the emulator). Giving those two kinds a group is the likely fix; not done here, untested.
3. A Fajr recording. iOS: the default sound only (a 30-second limit, 64 pending notifications), unverified without a Mac.
4. Native review of the new French and Arabic strings and of the method names.
5. Later: a background top-up of the month, a reminder before the prayer, Qibla, adhkar "Now" from the real prayer times.

## 27. Taraweeh on the phone, offline (2026-11-11)

The owner asked for Taraweeh mode to work with no laptop and no internet. It now does: the whole recognition pipeline runs on the phone (§15's shipping target, §17 M2).

**The engine in Dart** (`mobile/lib/core/engine/`): index, matcher, tracker, energy VAD, segmenter and listener, a port of `engine/src/rafiq/` (normalize was ported in §16).
- **Exact parity, checked:** `tools/golden/make_golden.py` now also writes the matcher's results on 190 queries, the tracker's state after every step of 15 scenarios (10 recordings of real speech-model output from `eval/results/transcripts`, 4 simulated noisy streams with al-Fatiha every rakʿah, and one with hint, lock, "the imam is here", preview and reset: over 1,500 steps), and the segmenter's chunks on synthetic audio built from integers. The Dart tests reproduce them all exactly (confidence to the 3 places Python reports). CI checks the files are current.
- **rapidfuzz** was reimplemented (Levenshtein similarity, `fuzz.ratio`, `process.extract`'s order) and checked against it on 1,614 real misheard words and 20,000 word pairs: no difference.
- **One change to the Python tracker:** its "check right where I expect" loop iterated a set, whose order follows hashing. It now uses a fixed order (end, then anchor), which the port reproduces. The engine tests and both benchmark gates are unchanged.

**On the phone** (`OnDeviceRecognitionEngine`, `lib/services/ondevice/`), behind the existing `RecognitionEngine` interface, so the Taraweeh screen did not change:
- **One background isolate** runs segmenter, speech model and tracker; the UI isolate only batches the microphone into 250 ms frames. The reader never waits on recognition.
- **Catch-up, as the server does it (§11, §12):** audio that arrives during a transcription is merged and transcribed as one block, so the next result is about *now*. Past 15 s the oldest is dropped, and a short notice says so in the interface language.
- **Partials adapt to the phone:** live previews only while a transcription costs under half the audio's length (a running average), and at most half the model's time. Otherwise finals only. On the emulator, uncapped previews kept the model busy 95% of the time, which over a Taraweeh means heat and battery.
- **Speech model:** the Quran Whisper `quran-basetrim` (int8, 55 MB, §16), 2 threads, 0.5 s of trailing silence. It is **bundled in the app** (`assets/models/`) and copied once to the app's storage, where sherpa-onnx opens it by path: no download, so it works offline from the first run. A new model version replaces the old copy.
- **Not in git:** the model files are 55 MB. `tools/whisper_export/install_model.py` copies them from `build/whisper_onnx/` and writes a manifest (sizes, SHA-256). A build without them works, and Taraweeh mode says it has no speech model.
- **Failures** are explained, not shown raw: the model could not start (memory or storage: try again), or the build has no model.
- **The development server** stays, behind Settings → Developer → *Recognise on a computer* (off by default). Its address and *Test connection* show only while that is on. The introduction now says Taraweeh mode works on the phone without internet, and "Taraweeh without a computer" left the *Coming soon* list.

**End to end on the emulator** (`integration_test/ondevice_test.dart`): four recitations built by `eval/phone_streams.py` from EveryAyah (three reciters; clean, mosque and the back of a mosque, as in `eval/audio_bench.py`), each joined late, told nothing, played in real time through the bundled model. Scored like the server benchmark: a final is acceptable when the ayah on screen is within one of an ayah heard in it.

| Recording | Right ayah | Found after | Wrong finals | Ayah delay (median) | Model busy |
|---|---|---|---|---|---|
| Alafasy, Ad-Duha 1–11, clean | 100% | 4.9 s | 0 | 0.7 s | 51% |
| Alafasy, al-Fatiha then al-Kahf 1–6, mosque | 91% | 8.2 s | 1 | 2.3 s | 49% |
| Husary, al-Hajj 30–33, mosque | 77% | 2.9 s | 0 | 1.8 s | 42% |
| Sudais, al-Aʿrāf 29–32, back of a mosque | 42% | 30 s | 0 | 3.1 s | 56% |

Before the cap on previews, the same run: 100%, 91%, 81% and 67% right; 0.4 s delay on the clean one; the model busy 71–96% of the time. The far room's score moves most between runs: it takes 30 s to find the imam in both, and the finals before that count as wrong with only 12 in all. No wrong jump on screen in any run but one final in the mosque al-Fatiha stream.

- **First run:** copying the model out of the bundle took 2.4 s, and loading it 4.4 s the first time (1.1–1.2 s after).
- **The emulator is not a phone.** It runs on this laptop's x86 CPU, several times faster than a budget phone's (the Galaxy A32 needed 3.1 s for a typical chunk, §16). On such a phone the engine falls back to finals only, and each ayah shows when the imam pauses after it.

**Tests:** 494 (482 before): the golden parity tests above, the engine through a real isolate with a scripted model (each ayah, partials, lock and "the imam is here" in order, falling behind, the three failures, cancel), the listener's adaptive and capped partials, which engine the app uses, the new notices and the developer switch. Goldens re-rendered for More, the introduction and the hint sheet ("Getting ready…" behind it). Strings: 8 new and 4 reworded in three languages, 3 removed.

**Next, on the owner's phone (Galaxy A16):**
1. `integration_test/ondevice_test.dart` on the phone itself: the real speed, and whether previews stay on.
2. A real Taraweeh-like test: the phone on a table during a jahrī prayer (Maghrib, ʿIshāʾ).
3. A 90-minute session: battery and heat.
4. If it is too slow: a smaller or distilled Quran model behind the same loader (§16's decision rule).
5. Release: the release APK for arm64 phones is 91 MB (the model is 55 MB of it). Play Asset Delivery can move the model to an install-time pack.

## 28. Build 0.9: reminders that are seen, and no audio (2026-11-11)

The owner, testing 0.8: the adhkar "disappear quickly" and "appear only in the notification bar"; they should show "in the screen (top right) as a small readable indication" and stay until tapped. The other notifications "are missed most of the times". And the recitation audio is dropped: the app is already over 50 MB.

**Why they were missed** (found in the code, then seen on the emulator):
- **The dhikr removed itself after 8 seconds** (`timeoutAfter`, §25). With the phone in a pocket it was gone before anyone looked.
- **The reading reminder had default importance:** a sound and an icon, never at the top of the screen.
- **Android 16's grouping trap (§26, open item 2):** the reading reminder and the dhikr had no group, so one arriving while another of the app's was in the shade was marked silent.
- **Inexact alarms:** the reading reminder could come up to an hour late.
- **After a force-stop** the dhikr alarms were gone, and the plugin's own record still listed them, so rescheduling changed nothing (the adhan already set everything again per process; the dhikr did not).

**The dhikr card** (`android/.../Dhikr.kt`, the app's own Kotlin; reverses §25's "an app cannot choose the top-right corner"):
- **A small card at the top right of the screen, over any app,** until it is tapped: "Remember Allah" in rubric red, the dhikr in Amiri, its meaning (two lines at most; none in Arabic), a ✕. Rubric's colours, light or dark with the phone. Touches elsewhere go to the app underneath. One at a time: a new dhikr replaces the words.
- **Needs "Appear on top"** (`SYSTEM_ALERT_WINDOW`, "Display over other apps" on a Pixel). Turning dhikr reminders on explains it and opens the setting. Android 11 and later open the list of apps, not Rafiq's page, so the text says to find Rafiq in it. "Use notifications instead" skips it.
- **Without it,** a dhikr is a silent, high-importance notification in a group of its own that stays in the shade until tapped (it opens the Adhkar) or swiped away. Taking the card back later asks for permission to notify, which choosing the card skipped.
- **One alarm at a time:** Dart sends the two weeks of adhkar; Kotlin keeps them and sets only the next alarm, and each one that fires sets the one after it. On the minute when exact alarms are allowed (the adhan asks), else within Android's window. A restart of the phone or an update sets the next again and shows a card that was still waiting. Every process sends the list once, so a force-stop is mended the next time the app opens.
- **Settings** (Adhkar screen and Settings): *On the screen* (allowed or not; opens the setting either way) and *Show one now*.
- What flutter_local_notifications scheduled for the dhikr before (ids 1000–1499) is cancelled once. iOS keeps the plugin path, without the 8 seconds.

**The reading reminder:** a new channel, `reading_reminder`, of high importance (at the top of the screen, with the phone's sound), since Android fixes a channel's importance once created; the old `daily_reading` is deleted. Its own group. On the minute when exact alarms are allowed.

**The audio is gone:** the *Coming soon* group on More (its only row was recitation audio), and the greyed *Listen* button and its line in the ayah sheet. Translation and Tafsir now share the row. 6 strings removed.

**Emulator** (Pixel XL, Android 16, debug build over 0.8):
- *Show one now*: the card at the top right, over the app and over the home screen. A tap closed it (its window gone).
- **The real thing:** the app's process killed, the clock moved to 13:59:45. At 14:00 Android started the app's receiver and the card came up; the 16:00 alarm was set (exact, `window=0`).
- **It stays:** screen off for 40 s, on, unlocked: the card was still there. The process holding it is "important foreground", so Android does not reclaim it.
- **Force-stop:** the alarm survived it on Android 16; opening the app set it again in any case.
- **Without "Appear on top":** at 16:00 nothing showed, because the app was not allowed to notify either (the gap fixed above). Allowed, at 18:00: a notification of importance 4 in group `dhikr`, which stayed; a tap opened the Adhkar.
- **The reading reminder** at 18:10, with that dhikr already in the shade: sound and vibration (`notification_alert` buzz=1 beep=1), importance 4, group `reading`. Before, this is the case Android 16 silenced.

**Tests:** 499 (494 before): turning on with the card, allowed already, notifications instead, the setting refused, neither allowed, the card taken back later, show one now, the close label, and More without the audio. Goldens re-rendered: More and the ayah sheet. Strings: 8 new, 1 reworded, 6 removed, in three languages.

**Open:**
1. **The Galaxy A16:** the card with One UI ("Appear on top"), and whether Samsung's battery saver lets the alarms through with the app closed for a day. If it does not, Settings → Apps → Rafiq → Battery → Unrestricted, and perhaps a hint in the app.
2. **Play:** `SYSTEM_ALERT_WINDOW` is a special permission the user grants; confirm in the Play Console that it needs no declaration, alongside `SCHEDULE_EXACT_ALARM` (§26).
3. Native review of the new French and Arabic strings.

**The adhan recording** (same day, the owner's choice, for every prayer):
- `data/adhan/adhan.mp3` (MP3, 16 kHz mono, 2 min 32 s, twelve phrases), SHA-1 pinned in `data/build_adhan.py`, which now makes both sounds from it: `adhan_full.mp3` (the whole adhan) and `adhan_takbir.mp3` (the four opening takbirs, cut at 26.0 s in the silence after them, with a 0.3 s fade).
- **Louder:** the recording peaked at -9.9 dBFS; both files are raised to -1 dBFS (+8.9 dB). A notification plays at the notification volume, so a quiet file is a quiet adhan.
- **Same names** (`adhan_full`, `adhan_takbir`): Android finds a channel's sound by name, so phones with the app already installed play the new one after the update, with no new channel. The `.ogg` files are gone (two raw resources of one name do not build); the check in CI says so if one comes back.
- **Its source and licence are not recorded yet.** The CC0 credit for the earlier recording left Settings → About and the README. Before release, write in `assets/adhan/NOTICE.txt` who recited it and what allows Rafiq to ship it, and add a credit if the licence asks for one.

## 29. Word tracking, phase 1: the WordTracker before any model (2026-11-12)

**The decision behind it** (research, 2026-11-11/12): keep the Quran Whisper for finding the ayah and recovering, and add word-by-word tracking from a small **streaming CTC model** whose letters are *aligned* against the known text, not recognised. Aligning is almost free; Whisper's per-chunk decoder (≈1.9 s fixed on the Galaxy A32, §16) is what is expensive.
- **The model:** our own Zipformer2 CTC (icefall, causal, ~20–25M parameters, letter units), aiming at 22–30 MB int8. It loads through the sherpa-onnx we already ship (`OnlineZipformer2CtcModelConfig` is in 1.13.4; results carry `tokens` and `timestamps`, not probabilities).
- **Not Muno459/zipformer_p-arabic-v2** (the best ready model, 73 MB): its licence forbids paid or ad-supported apps, and the owner wants the core free of that. **NVIDIA's Arabic FastConformer** (CC BY 4.0, EveryAyah in training, ~115M parameters, not streaming) serves as an offline labeller and baseline, not on the phone.
- **Data:** EveryAyah (about 390 h; its card: "Licensing of the individual recordings is not documented") plus CC BY word timings (cpfair/quran-align, QuranLab). Tadabur is non-commercial: excluded. No corpus documents the rights to the recordings themselves, the Whisper model we ship included: get advice before monetising.
- **The benchmark reciters** (`eval/audio_bench.py`, `eval/phone_streams.py`) must be held out of training.

**Phase 1, done:** the word tracker, built and measured on simulated letter streams, independent of any model.
- **`rafiq.words.WordTracker`** (Python reference) and `mobile/lib/core/engine/word_tracker.dart` (port). Anchored by the ayah tracker at a word; then fed letters, one row of an edit-distance alignment per letter against a window of the text (20 words behind, 30 ahead, sliding with the imam). About 100–170 µs a letter in Python; a CTC model emits about 12 a second.
- **What it handles:** silent letters cheap to drop (long vowels, hamzat al-wasl, the lam of al- before a sun letter) and similar sounds cheap to confuse; madd and pauses cost nothing; going back to any earlier word start at a fixed cost (repeats); the basmala as an optional segment; any position in the window found again within a few words.
- **Failing safe:** it stops highlighting when the recent error rate climbs, at once after a burst of bad letters, and once past the end of its window. Anchored in al-Fatiha, the window ends with 1:7 ("amin" is close to 2:1 "الم"). `pause()` after a long silence (rukuʿ, sujud) makes it re-confirm with fresh letters, because bism and al- fit almost anywhere. Lost after 30 unsure letters, for the ayah tracker to anchor it again.
- **Model-independent:** any tokens that normalize to Arabic letters (letters, subwords, words, with diacritics) and no use of time. Confidence is sums and ratios, so Dart reproduces Python exactly.
- **`rafiq.word_sim`:** letter streams with timing and the truth per letter: misheard, dropped (silent ones three times as often) and invented letters, garbled words, repeats of 2–6 words, a whole ayah again, fillers ("amin", takbir, coughs), the basmala aloud half the time, al-Fatiha every few ayahs after 15–40 s of silence. `run` plays the ayah tracker: anchors 4 s late at the word heard 2 s before, at the start, after each far jump, and when lost.

**`eval/word_benchmark.py`** (30 passages; CI runs `--quick --check`, 4 s). Over the letters after the first anchor:

| Scenario | Shown | Exact | Within one word | Wrong (> 2 words off) |
|---|---|---|---|---|
| clean | 97.8% | 98.6% | 99.9% | 0.06% |
| light | 88.5% | 95.5% | 99.5% | 0.37% |
| light + al-Fatiha | 78.8% | 95.6% | 99.4% | 0.39% |
| heavy | 62.9% | 90.8% | 99.0% | 0.49% |
| heavy + al-Fatiha | 55.8% | 91.3% | 98.9% | 0.49% |
| broken (a model that hears little) | 9.1% | 82.2% | 97.0% | 0.63% |

The wrong highlights left are blips of 1–4 letters (0.1–0.4 s) when the imam goes back: his first letters also fit what he would have said next. Tuning chose fewer wrong words over more time shown (`burst_cost` 2.0 over 2.5). Simulated letters are kinder and more regular than a real model's, so these are regression floors, not promises.

**Tests:** 11 Python (`engine/tests/test_words.py`: clean, a late anchor, a repeat, the basmala aloud and not, leaving the text, al-Fatiha's window, a pause, subword tokens, simulated and broken streams). Dart: `test/core/word_tracker_golden_test.dart` replays `test/golden/word_tracker.json` (6 scenarios, about 3,200 calls: idle, tracking, uncertain, lost, the basmala, pauses, re-anchors, window slides), every state exact. 501 Flutter tests (499 before), 119 engine tests (108 before).

**Not yet:** nothing in the app uses it. No model, no UI, no change to `RecognitionEngine` or `TrackState`.

**Next:**
1. **Real streams without our model:** NVIDIA's CTC (offline, laptop) and faster-whisper's word timestamps over `eval/phone_streams.py`, scored against CC BY word timings (quran-align covers Alafasy and Husary). Needs those downloads: ask first.
2. **Training data pipeline and a first Zipformer2-small CTC run** (cloud GPU), with a provenance file for every source.
3. **Go/no-go:** letter error on held-out reciters with mosque augmentation, real-time factor on the A32 and A16 (bench screen), and the word tracker within one word on real streams.
4. **Integration** behind a flag after the Ramadan release candidate: the engine anchors the word tracker from the ayah tracker, calls `pause()` on long silences, and adds the word to what the screen shows.

## 30. Word tracking, phase 2: the word tracker on real Whisper output (2026-11-12)

**What was measured:** the word tracker (§29) fed with what Rafiq's Quran Whisper **actually produced**, not simulated letters. No model was run and nothing was downloaded: `eval/word_replay.py` replays the 40 recordings already in `eval/results/transcripts` (12 reciters × clean, mosque and far rooms, 60 minutes of recitation, 6,040 partials and 701 finals) through the **existing ayah tracker, unchanged**, and the word tracker anchored from it (`rafiq.word_eval`).
- **Whisper is not a letter stream:** each partial re-transcribes the breath so far and revises itself. The word tracker is snapshotted at each breath's start, every result restores the snapshot and feeds its whole text, and a final commits. `pause()` after a 2.5 s gap between breaths.
- **Anchoring:** after a final, at the ayah tracker's word, when the word tracker is idle or lost or the two disagree by more than one ayah.
- **Two modes:** *partials + finals* (a phone fast enough for previews) and *finals only* (a slow phone, §27). Finals-only reuses the result times recorded with partials running: slightly pessimistic.
- **Truth:** ayah level is **exact** (each stream's timeline). Word level is **approximate**: the recordings have no word timings, so each ayah's time is shared out among its words by letter count.
- **The model:** these recordings are the laptop's **faster-whisper int8** (CTranslate2) build of the same Tarteel model, not FP32 and not the phone's sherpa-onnx int8 export. The device was not recorded; ~0.34 s a call, the same for 1 or 6 s of audio (Whisper's fixed 30 s window), matches the CPU.

**Laptop, faster-whisper int8, 40 runs** (`eval/results/word_replay/laptop_int8.json`):

| | Partials + finals | Finals only |
|---|---|---|
| **Exact, ayah level** | | |
| Highlighted word in the ayah being recited | 96.4% | 76.1% |
| Highlighted word in a wrong ayah (neither that one nor the one before) | **0.00%** | **0.00%** |
| Wrong-ayah stretches per hour | 0 | 0 |
| Ayah tracker's ayah right (for comparison, all recited time) | 79.2% | 81.1% |
| **Approximate, word level** | | |
| Word highlighted (share of recited time) | 64.7% | 65.3% |
| Within one word, when highlighted | 81.9% | 33.6% |
| More than two words off, when highlighted | 4.2% | 48.9% |
| **Useful: highlighted and within one word (all recited time)** | **53.0%** | **21.9%** |
| Aligned: within one word of the audio the result covered | 84.4% | 83.8% |
| Word starts → highlighted (median / p90) | 0.76 / 1.94 s | 3.72 / 6.93 s |
| Recovery to a right highlight (median / p90) | 0.60 / 1.80 s | 4.85 / 7.95 s |
| First right-ayah highlight (median) | 11.0 s | 17.2 s |
| **Speech model, as recorded** | | |
| Transcription per result (median / p90) | 338 / 423 ms | 395 / 464 ms |
| Audio end → result ready (median / p90) | 0.35 / 0.51 s | 0.63 / 0.83 s |

By room (partials + finals): useful 62% clean, 55% mosque, 41% far; never a wrong ayah in any room.

**What it says:**
- **The tracking is right; Whisper's timing is the limit.** Against the audio each result covered, the highlight is within one word 84% of the time in both modes. On screen, the offsets centre half a word *behind*, and the "more than two words off" cases are mostly 3+ words behind: a result is ready 0.35 s after its audio, and partials come every 0.5 s at best. The other ~16% is in part the letter-count interpolation (long madd, silence inside a recording).
- **Never a wrong ayah:** anchored by the ayah tracker, the word tracker did not once highlight a word outside the ayah being recited or the one before it, in any room.
- **Finals only is not usable for word highlighting:** the highlight sits on the last word of the previous breath while the imam recites the next one, for 3.7 s on average. Coverage looks the same, but only 22% of the time is it the right word. On a phone that cannot run partials (the A32, §16), Whisper alone cannot drive word highlighting; at most it can be hidden between pauses.
- **Coverage is capped by detection:** 11 s to the first right ayah (median), out of ~90 s runs, and longer in the far room.

**Phone, sherpa-onnx int8:** **not measured yet**, as no phone was connected. `integration_test/ondevice_test.dart` now also writes each stream's events and timeline into `results.json` (test code only), and `eval/word_replay.py results.json` scores it the same way, reported apart from the laptop. The run reinstalls the app, which wipes its data on the device.

**Limits:** studio EveryAyah audio with simulated rooms, no imam repeats or rakʿah pauses, and the Tarteel Whisper was trained on EveryAyah: optimistic. Word-level numbers rest on interpolated times. The simulated benchmark (§29) is a different measurement and is not mixed in.

**Not changed:** the app, the recognition pipeline, the ayah tracker. Nothing highlights words for users.

**Tests:** 4 new (`engine/tests/test_word_eval.py`: interpolation and the basmala, partials that revise themselves, finals only, the scores on hand-made screens). 123 engine tests.

**Next (each needs the owner's go-ahead):**
1. **The phone run** on the A16 (a spare phone, or after a backup): sherpa int8's own text and timing, and whether partials stay on.
2. **Exact word truth:** the CC BY quran-align timings (small, Alafasy and Husary among them) would replace the interpolation for those reciters.
3. **A streaming CTC model** (§29) is what removes Whisper's 0.35–0.85 s result age and 0.5 s cadence, and what a phone without partials needs.

## 31. Word tracking, phase 3: exact word timings for the evaluation (2026-11-12)

**Why:** §30's word-level numbers rested on word times shared out by letter count. This replaces them with measured times where they exist, to make the evaluation trustworthy before deciding whether a new speech model is needed.

**The data** (the owner approved this one download):
- **quran-align**, Collin Fair, `release-2016-11-24`, https://github.com/cpfair/quran-align. Data **CC BY 4.0**, code MIT.
- One archive, 5,807,871 bytes, SHA-256 `5eeb045d8a7895208c94d2d7ec243567f8f550728835411527c4ffa1e789c9b7`. GitHub publishes no digest for assets that old: the size matched the release API and the hash is pinned in `eval/fetch_quran_align.py`. Each kept file is also checked against the SHA-1 the archive's own README lists.
- **Kept, unchanged, outside git** (`eval/data/`, ignored): the 6 recitations our recordings use, the README, the licence, and `SOURCE.txt` with the attribution. The archive and the other 6 recitations were discarded.
- **Two flaws in the published data:** the Sudais file carries the aligner's crash log on a line before its JSON (only the JSON is read), and Shuraym's 12:76 has no timing (33 deletions).

**Checks, before anything was scored** (`eval/verify_quran_align.py`):
1. **The words they number:** Tanzil Uthmani split on spaces, without its 4,578 pause marks and without the basmala. This fits 99.82–99.92% of ayahs' highest word index in all six files; with the marks counted, 55%. That is `Verse.text_uthmani` without the marks.
2. **Mapping onto our words** (Simple Clean, normalized; monotone, by letters): **6,236 of 6,236 ayahs (100%)** with every group at least half alike (99.60% at least 70%). 76,901 groups, 366 not one-to-one, almost all the vocative: Uthmani يٰٓأَيُّهَا is our يا ايها. The 99% threshold was met.
3. **Against our audio**, the very EveryAyah files the recordings were built from (the local cache, nothing downloaded): the last word ends inside the file, and the first word's start and the last word's end are within 0.25 s and 0.6 s of where speech starts and ends.

| Our files | Timed on | Pass | First word vs speech start (median) | Verdict |
|---|---|---|---|---|
| Alafasy 128 | same | 57/60 | −0.035 s | trusted, 3 ayahs excluded |
| Sudais 192 | same | 6/6 | −0.050 s | trusted |
| Minshawy Murattal 128 | same | 4/4 | +0.035 s | trusted |
| Shuraym 128 | same | 4/4 | +0.010 s | trusted |
| **Husary 128** | **Husary 64** | 10/10 | +0.010 s | **trusted:** the other bitrate is cut the same |
| **Abdul Basit Murattal 192** | **Abdul Basit Murattal 64** | 4/4 | −0.065 s | **trusted** |

The three Alafasy failures are real timing errors in the data: in 55:11 and 55:24 the last word ends 1.7–2 s before its held madd does, and in 78:12 the first word starts 0.6 s early, in silence. **An ayah that fails is excluded from exact scoring.** The check covers each ayah's first and last word only; inside an ayah, word boundaries rest on the author's stated accuracy (mean under 73 ms against another tool).

**Exact against interpolated, on the same recordings, ayahs and moments** (`eval/word_replay.py --truth quran-align`; 22 of the 40 laptop recordings, 32 minutes; laptop faster-whisper int8; `eval/results/word_replay/laptop_int8_exact.json`):

| | P+F exact | P+F interpolated | Finals exact | Finals interpolated |
|---|---|---|---|---|
| Wrong ayah (exact, timeline) | 0.00% | 0.00% | 0.00% | 0.00% |
| Within one word, when highlighted | **85.5%** | 82.4% | **23.0%** | 32.7% |
| More than two words off | **2.2%** | 4.3% | **57.5%** | 48.0% |
| Useful: highlighted and within one word | **54.2%** | 52.2% | **14.4%** | 20.4% |
| Aligned: within one word of the audio covered | **98.8%** | 86.3% | **99.2%** | 83.4% |
| Word start → highlighted (median / p90) | **1.17 / 1.77 s** | 0.84 / 2.26 s | **4.75 / 6.78 s** | 3.88 / 6.93 s |
| Recovery (median / p90) | 0.52 / 1.35 s | 0.62 / 1.85 s | 5.60 / 8.60 s | 5.25 / 9.70 s |

Same files (15 runs) and other bitrate (7 runs) agree: useful 53.9% and 54.5% with partials.

**What the exact truth changed:**
- **The word tracker is more accurate than §30 said.** Against the word at the end of the audio each result covered, it is right 73% of the time, one word behind 24%, ahead 2%; within one word 98.8%. Interpolation had made it look ahead (+1: 26%) and 12 points worse. Its errors are timing, not tracking.
- **Whisper's delay is longer than §30 said:** a word is highlighted 1.17 s after it starts (median), not 0.84 s.
- **Finals only is worse than §30 said:** 14% useful, not 20–22%, and 57% of the highlighted time more than two words off.
- **Unchanged:** never a wrong ayah; partials double what finals alone give.

**Limits:** 32 of 60 minutes have exact word truth (6 of 12 reciters); the rest stay interpolated (§30). Still studio audio with simulated rooms, no imam repeats, and a Whisper trained on EveryAyah. Laptop recordings only: the phone (sherpa int8) is postponed with the A16.

**Tests:** 6 new (`engine/tests/test_word_truth.py`: the words quran-align numbers, the whole mapping and the vocative, a refused mapping, timings shared out and missing, the crash log, both truths scored at the same moments), using only data in the repository. 129 engine tests.

**Not changed:** the app, the recognition pipeline, the ayah tracker.

## 32. Word tracking, phase 4: smarter highlighting from the same results (2026-11-12, not committed)

**Question:** can the display hide stale words, or move ahead between Whisper results, to make word highlighting better without a new model? Evaluation only (`rafiq.word_display`, `eval/word_display_bench.py`): the recorded laptop Whisper output (faster-whisper int8) replayed through the unchanged ayah and word trackers. Every moment is **confirmed** (a result supports it), **predicted** (estimated between results) or **hidden**. A policy sees only the results that have arrived by then. The baseline policy reproduces §31 exactly.
- **Suppression:** hide a confirmed word once its audio is older than 0.5, 0.75, 1, 1.5 or 2 s.
- **Prediction:** pace in letters per second of speech, measured on each finished breath. The highlight walks on from where the imam was when the last result's audio ended, by at most 1–2 words, never into the next ayah, not after a pause (unless the usual pause length is modelled), only after 2–4 breaths of plausible pace, not for 2 results after he goes back, and not past a horizon. 32 variants.
- **Fairness:** chosen on 15 exact-truth runs (Alafasy, Sudais, Minshawy, Shuraym) by useful − 2 × wrong, then reported on held-out reciters: Husary and Abdul Basit (exact, 7 runs) and 18 more runs (interpolated truth, reported apart).

**Partials + finals** (wrong = more than two words off; shares of recited time):

| | Tuning, 15 runs | | | Held-out exact, 7 runs | | |
|---|---|---|---|---|---|---|
| | useful | wrong | latency | useful | wrong | latency |
| Baseline | 53.9% | 2.05% | 1.15 s | 54.5% | 0.36% | 1.34 s |
| Hide > 1 s | 50.1% | 0.70% | 1.12 s | 47.9% | 0.00% | 1.34 s |
| Hide > 1.5 s | 52.4% | 1.06% | 1.15 s | 50.9% | 0.04% | 1.34 s |
| Hide > 2 s | 53.5% | 1.54% | 1.15 s | 52.6% | 0.24% | 1.34 s |
| Predict (1 ahead, pause modelled) | 59.9% | 1.40% | 0.75 s | 55.7% | 0.36% | 1.06 s |
| Predict + hide > 1.5 s | 59.1% | 0.64% | 0.75 s | 52.7% | 0.05% | 1.06 s |

- **Suppression** trades useful time for fewer wrong words, smoothly, with no sharp optimum. At 1.5 s: wrong time −48% (tuning) and −89% (held-out) for 1.5 and 3.6 points of useful time. Wrong stretches per hour 150 → 103 and 37 → 9.
- **Prediction** helps most where Whisper lags most, the fast imams (Shuraym: useful 48.6% → 58.5%, wrong 6.5% → 2.1%, combined), and little or not at all for slow ones with long madd (Husary −4 points combined). Its tuning gain (+6.0 points) shrinks to +1.2 on held-out reciters. The highlight moves back twice as often (1.0 → 2.2 a minute), and a third of the time what is shown is a guess. On the interpolated held-out set it looks worse (useful −2.6), but that truth runs late (§31), which penalises any highlight that moves ahead: inconclusive there.
- **Never a wrong ayah** with any policy.

**Finals only:** the baseline shows a word more than two off 43% of the time. Suppression is essential (at 2 s: 1.5%) but leaves 84–90% of the time hidden and 10% useful; prediction adds 1–2 points. Neither makes word highlighting viable without live previews.

**Verdict:** suppression is one comparison, cuts wrong highlights on every held-out set, and is required if word highlighting is ever shown (1–1.5 s, the exact value depending on how a wrong word is weighed against none). Prediction's out-of-sample gain is small, it doubles backward corrections, and its handling of repeats, rakʿah pauses and al-Fatiha is untested on real audio (these recordings have none). It does not justify its complexity now.

**Limits:** 22 exact runs, 6 reciters, 3–6 runs per reciter (by-reciter and by-room numbers include the tuning runs); studio audio with simulated rooms; laptop model only; finals-only reuses timings recorded with partials running. Results: `eval/results/word_display/laptop_int8.json`. Tests: 5 new (`engine/tests/test_word_display.py`), 134 engine tests.

## 33. Word highlighting in Taraweeh mode, behind a developer flag (2026-11-12, not committed)

**The feature:** Settings → Developer → *Highlight the word (experimental)*, **off by default**. On, Taraweeh mode colours the word being recited in `rubric` (the cinnabar of the margin rule and the end marker), on the scrolling reader. No prediction: the word is the one the speech model last confirmed. The Whisper model, the ayah tracker and every existing behaviour are unchanged.

**How it works:**
- **In the recognition isolate** (`ondevice_engine.dart`): a `WordFollower` (`lib/core/engine/word_follower.dart`) next to the ayah tracker, created **only when the flag is on**. Partials are fed to a copy of the word tracker taken at the breath's start (`WordTracker.copy()`), so a revision replaces rather than adds; finals commit. After a final it anchors from the ayah tracker when idle or lost or more than an ayah apart, `pause()` after a 2.5 s gap, `pause()` when audio is dropped, and it anchors on "the imam is here". If it ever throws, it is switched off for the session and the ayahs carry on. The result travels as `Heard.word` (verse, Simple Clean word index); the server engine sends none.
- **The same as evaluated:** on 5 recordings of real Whisper output (1,000 events), the Dart follower reproduces Python's `replay_words` (§30–31) event for event (golden `word_follow.json`).
- **Uthmani words** (`lib/core/text/word_map.dart`): the reader shows Uthmani, the engine counts Simple Clean words. Port of `map_verse` (§31), equal to Python on **all 6,236 ayahs** (golden `word_map.json`, the 805 not one-to-one), all trusted. Each Uthmani word is one displayed piece (the text cut at its spaces, pause marks kept with their word), checked on every ayah. An untrusted mapping highlights nothing.
- **What is shown** (`lib/features/listen/word_highlight.dart`): a word only if the flag is on, the session is listening, the latest result named a word (one without hides it at once), the ayah engine is sure, the word is in the ayah the screen marks (so nothing during al-Fatiha's excursion or the basmala), the mapping is trusted, and its audio is at most **1.5 s** old (arrival minus transcription time; *Hide the word after* offers 0.75–3 s). A timer hides a stale word even if no result comes again; stopping, pausing or failing clears it.
- **The text does not change:** `AyahBlock` cuts the current ayah into one span per piece, each space kept with its piece, so the characters, font, shaping and line breaks are those of the plain text; only one word's colour differs. Without a word it is built exactly as before.

**Tests:** 29 new, 530 Flutter tests in all (49 screenshot goldens skipped off Linux); 129 engine tests; analyzer, format, golden check, data checks and the text, detection and word gates pass.

**Not verified:**
- On a phone: speed (a copy and a partial's letters per transcript, expected well under 1 ms), whether partials stay on, the highlight in a dim hall, TalkBack, battery. The 1.5 s rests on laptop recordings (§32).
- The screenshot goldens (Docker was not running). The new Developer rows are last in their group; run `mobile/tool/goldens.sh check`.
- The mushaf pages layout has no word highlight (Taraweeh mode uses the scrolling reader).

## 34. A miss is not doubt: the recognition evidence signal (2026-11-13, not committed)

**Why:** after testing on a phone, the owner saw the app hesitate. Replaying the 40 recorded laptop Whisper runs (`eval/results/transcripts`) through the tracker showed why: a chunk that matches no Quran (a breath's first word, "āmīn", a takbīr) returned `uncertain` with confidence 0, and the screen took it as doubt ("Not sure", LAST SURE, the numeral dimmed). Of the uncertain finals that had a position, 147 of 158 were such misses, and 157 of 158 showed the right ayah. Confidence 0 cannot be the signal: an exact tie between rivals (the refrain of Ash-Shuʿarāʾ) also has confidence 0.

**What changed:**
- **The engine says it** (`rafiq.tracking.TrackState.evidence`, the Dart `TrackerState.evidence`): false for a miss, true for every result that matched (and for "the imam is here"). Nothing else in the tracker changed: the 2,196 golden states are identical in every earlier field, and the text, detection and word gates give the same numbers.
- **The wire and the isolate carry it:** `StateOut.evidence` (the server), `TrackState.evidence` (the app; a server that does not send it counts as evidence), and the on-device engine's messages.
- **The screen reads it** (`ListenState.trackStatus`): after a miss, the last verdict with evidence stands. Doubt on evidence (rivals, an unconfirmed far jump, a tie) still shows "Not sure"; four misses in a row are still `lost`; misses confirm nothing, so "No new match yet" still comes after 10 s. `track` keeps the engine's own verdict. Word highlighting (developer setting) still follows the engine's status, as evaluated in §32.

**Effect on the same recordings** (laptop model, studio audio with simulated rooms, after the first detection; the ayah shown is unchanged):

| | "Not sure" on screen | Sure ↔ unsure flips |
|---|---|---|
| Partials + finals, before → after | 42.4% → 6.0% | 21.0 → 3.0 a minute |
| Finals only, before → after | 25.7% → 2.9% | 4.0 → 0.3 a minute |

One final is shown as sure and wrong, before and after alike (Husary, on evidence): a tracker error, not a held miss.

**Tests:** Python 8 new (a miss, silence and one word that fits anywhere; misses until lost; a previewed miss; idle; an exact tie; a far rival; the user's position; the server field). Dart 13 new (the same engine cases, the golden field, the protocol, the on-device engine, the screen's rule, the controller). 547 Flutter tests, 179 Python (data, engine, server); ruff, format, analyze, the three gates, every `--check` and the Android debug build pass. **Not run:** the screenshot goldens (Docker was not running); no widget changed, and the one golden built on `uncertain` uses an evidence-bearing state.

**Not changed:** the candidates, the lock, the Taraweeh position (§35 onward, as agreed).

## 35. Repeated text: an unconfirmed position is decided by its own text (2026-11-13, not committed)

**The fault:** a lone Ar-Rahman refrain at cold start showed 55:13 at confidence 0.865, though the refrain is 31 ayahs. The tracker asks the matcher for 8 candidates; ties go to the earliest copies (55:13…55:30), and those 8 lie within the 80 words the rival test calls "near" (a plausible repeat). No rival, so the margin was the best score itself. Across the Quran, 436 of 9,860 repeated 4–7-word phrases were shown at cold start, every one repeated within a single surah (109:3/109:5, 84:2/84:5, 18:89/18:92, …). Joining on each copy of each of them, the first ayah shown was wrong 31% of the time. The surah was always right; the ayah was not. IDF cannot tell these phrases from unique ones (the distributions overlap); a second ayah scoring as well tells them apart perfectly.

**The rule** (`TrackerConfig.tie_margin` = 0.05, Python and Dart alike): while a position is unconfirmed (cold start, or a far jump awaiting confirmation), another ayah scoring within 0.05 of the best is a rival however close, and confirming needs real confidence (the cold-start rule, now for far jumps too). Nothing changes where the screen already is. No surah is special-cased.

**Results:**
- **Repeated text:** on the 937 joins, no first ayah shown (pending, with the other copies as alternatives) instead of 286 wrong; right by the second chunk 93% (74% before). No repeated verse or phrase is shown at cold start.
- **Unique text:** cold start on 10,190 unique ayahs and windows: 9,233 shown, all right (before: 9,244 shown, 5 wrong; the other 6 no longer shown fit two places exactly, such as 102:3 inside 102:4).
- **Text benchmark:** wrong jumps per 100 steps 0.03 → 0.00 (clean), 0.06 → 0.03 (light, heavy), 0.03 → 0.00 (with rakʿahs); exact 0.945 → 0.944 with rakʿahs, light.
- **Detection benchmark** (300 joins a row): unchanged, 0% first-shown-wrong.
- **The 40 recordings:** every final, accuracy and wrong jump unchanged; per-room medians unchanged. **4 runs detect later** (+0.5, +1.0, +1.0, +3.7 s): their passages start at the earlier of two nearby copies (22:30 and 22:32 open "ذلك ومن يعظم", 7:29 and 7:31 share "عند كل مسجد"), and the old tracker flashed the earliest copy on a preview before the words differed. In the +3.7 s run that guess vanished again at the next final; both trackers confirm 22:30 at the same moment.
- **Remaining:** 8 wrong displays over the 937 joins, all near-duplicates in Ar-Rahman (55:58 like 55:22), not ties.

**Tests:** Python 10 new (an exact tie close by, a misheard word between two copies, a near tie, the refrain, joining on a later copy, every repeated verse, unique ayahs unchanged, a far jump into a refrain, after lost and al-Fatiha, a far jump on distinct words); Dart the same 10; 5 new golden scenarios (32 steps), Python and Dart equal on all 2,228 states. 189 Python and 557 Flutter tests; every gate and check passes.

**For Phase 2:** a tie that stays in one surah means "this surah, ayah undecided": show the surah and wait, never a chip per copy. The state carries a pending verse and at most 3 alternatives; telling "one surah" apart for sure needs the full tied set, a field Phase 2 should add rather than infer from 3.
