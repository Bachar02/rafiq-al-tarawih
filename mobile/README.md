# Rafiq — mobile app

A Quran reader (the whole Quran, opened where you stopped, with juz, page and
bookmark navigation and Arabic search) with a Taraweeh mode: one tap, and the
app follows the imam's recitation live in the same text. English, French and
Arabic (right to left). Design and architecture: [docs/DESIGN.md](docs/DESIGN.md).

Taraweeh mode runs entirely on the phone, offline: the Quran Whisper model
(bundled, 55 MB) and the Dart port of the engine, in a background isolate.
The development server is still there for experiments (Settings → Developer
→ *Recognise on a computer*).

## Run it

1. **Bundle the speech model** (once; it is not in git):
   ```bash
   py tools/whisper_export/install_model.py
   ```
   It copies `build/whisper_onnx/quran-basetrim-*` (made by `tools/whisper_export/`)
   into `assets/models/`. Without it the app builds, but Taraweeh mode says
   it has no speech model.
2. **Run the app**:
   ```bash
   cd mobile
   flutter run
   ```

On the emulator, let it hear the laptop's microphone with
`adb emu avd hostmicon` (off by default).

**Check it on a phone** with real recitations, in real time, no server:
```bash
py eval/phone_streams.py
flutter test integration_test/ondevice_test.dart -d <device>
# while it waits (the install empties the app's folder):
adb push eval/results/phone_streams/. /sdcard/Android/data/app.rafiq.rafiq/files/streams/
```

**The development server** (optional): `python -m rafiq_server --host 0.0.0.0 --port 8765`,
then Settings → Developer → *Recognise on a computer*, and the address
(`10.0.2.2:8765` on the emulator, the laptop's Wi-Fi address on a phone).

## Toolchain
- Flutter 3.47.9 (Dart 3.13), the version CI pins.
- **JDK 17+ for Android builds.** The Android project uses AGP 8.13 / Gradle 8.14 /
  Kotlin 2.3, the minimum Flutter 3.47 supports. If Flutter still uses an older
  bundled JDK: `flutter config --jdk-dir <path-to-jdk-17-or-newer>`.
- minSdk 24 (Android 7.0): Flutter 3.47's minimum. targetSdk and compileSdk 36.

## Develop
```bash
flutter analyze
flutter test                                   # unit, engine-over-real-sockets, controller, widget
dart format -l 120 lib test
python tool/sync_quran.py                      # after rebuilding data/quran.json
bash tool/goldens.sh check                     # golden screenshots, Linux renders (Docker)
```

**Strings** live in `lib/l10n/app_{en,fr,ar}.arb` (English is the template).
`flutter pub get` regenerates `lib/l10n/generated/`, which is committed;
`test/l10n/` fails if French or Arabic misses a message or a placeholder. The
French and Arabic texts are drafts awaiting native review.

**Scroll performance on a phone** (profile mode; the R2 budgets are in PLAN.md §18):
```bash
flutter drive --profile -d <device> --driver=test_driver/perf_driver.dart \
  --target=integration_test/quran_view_perf_test.dart
python tool/perf_report.py --markdown
```

| Path | What |
|---|---|
| `lib/core/` | framework-free logic: models, wire protocol, PCM, backoff, endpoints, normalize, prayer times |
| `lib/core/engine/` | the recognition engine in Dart (index, matcher, tracker, VAD, segmenter, listener), a port of `engine/` checked against its golden files |
| `lib/data/` | bundled Quran (with juz, page and hizb lookups), settings, the reading store |
| `lib/l10n/` | strings (ARB) and the generated localizations |
| `lib/services/` | platform adapters: microphone, WebSocket engine, wakelock, health check, notifications, location |
| `lib/app/` | app shell, routes, theme, shared components |
| `lib/features/quran_view/` | `QuranView`: the whole Quran as one virtualized text, shared by both modes |
| `lib/features/reader/` | the home screen, reading position, bookmarks |
| `lib/features/navigate/`, `search/` | Go to (surahs, juz, pages, bookmarks) and search |
| `lib/features/listen/` | Taraweeh mode: the session state machine (`ListenController`) and its screen |
| `lib/features/prayer/` | prayer times, the place, and the adhan's scheduling (`AdhanSync`) |
| `lib/features/settings/` | settings screen |
| `test/support/fakes.dart` | fakes for every seam, and a test harness wired like `main.dart` |

## Licenses
Quran text: Tanzil Project, CC BY 3.0 (`assets/quran/NOTICE.txt`).
Fonts (all SIL OFL 1.1, licence beside each in `assets/fonts/`): Amiri Quran (`OFL.txt`),
Amiri (`OFL-Amiri.txt`), Newsreader (`OFL-Newsreader.txt`), IBM Plex Sans (`OFL-IBMPlexSans.txt`),
IBM Plex Sans Arabic (`OFL-IBMPlexSansArabic.txt`).
Towns and countries: GeoNames, CC BY 4.0 (`assets/places/NOTICE.txt`; rebuild with `py data/build_places.py fetch` then `py data/build_places.py`).
Adhan recording: chosen by the owner, made into the app's two sounds by `py data/build_adhan.py`; its source and licence are to be recorded in `assets/adhan/NOTICE.txt` before release.
Prayer times: `adhan_dart`, MIT.
Speech model: Tarteel `whisper-base-ar-quran`, Apache 2.0, run with sherpa-onnx (Apache 2.0).
Brand assets (wordmark, app icon) and the surah display-name table: Rubric Phase 3 handoff.
