# Rafiq — mobile app

A Quran reader (the whole Quran, opened where you stopped, with juz, page and
bookmark navigation and Arabic search) with a Taraweeh mode: one tap, and the
app follows the imam's recitation live in the same text. English, French and
Arabic (right to left). Design and architecture: [docs/DESIGN.md](docs/DESIGN.md).

Taraweeh mode records on the phone and, in this build, recognises on the Rafiq
server (a laptop on the same Wi-Fi). On-device recognition comes later, behind
the same `RecognitionEngine` interface. The reader needs nothing but the phone.

## Run it

1. **Start the server** on the laptop, reachable from the network:
   ```bash
   python -m rafiq_server --host 0.0.0.0 --port 8765
   ```
2. **Run the app**:
   ```bash
   cd mobile
   flutter run
   ```
3. **Point the app at the server** (⚙ Settings → Recognition server → *Test connection*):
   - Android emulator: `10.0.2.2:8765` (the default)
   - real phone: the laptop's Wi-Fi IP, e.g. `192.168.1.5:8765`

On the emulator, let it hear the laptop's microphone with
`adb emu avd hostmicon` (off by default).

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
| `lib/core/` | framework-free logic: models, wire protocol, PCM, backoff, endpoints, normalize |
| `lib/data/` | bundled Quran (with juz, page and hizb lookups), settings, the reading store |
| `lib/l10n/` | strings (ARB) and the generated localizations |
| `lib/services/` | platform adapters: microphone, WebSocket engine, wakelock, health check |
| `lib/app/` | app shell, routes, theme, shared components |
| `lib/features/quran_view/` | `QuranView`: the whole Quran as one virtualized text, shared by both modes |
| `lib/features/reader/` | the home screen, reading position, bookmarks |
| `lib/features/navigate/`, `search/` | Go to (surahs, juz, pages, bookmarks) and search |
| `lib/features/listen/` | Taraweeh mode: the session state machine (`ListenController`) and its screen |
| `lib/features/settings/` | settings screen |
| `test/support/fakes.dart` | fakes for every seam, and a test harness wired like `main.dart` |

## Licenses
Quran text: Tanzil Project, CC BY 3.0 (`assets/quran/NOTICE.txt`).
Fonts (all SIL OFL 1.1, licence beside each in `assets/fonts/`): Amiri Quran (`OFL.txt`),
Amiri (`OFL-Amiri.txt`), Newsreader (`OFL-Newsreader.txt`), IBM Plex Sans (`OFL-IBMPlexSans.txt`),
IBM Plex Sans Arabic (`OFL-IBMPlexSansArabic.txt`).
Brand assets (wordmark, app icon) and the surah display-name table: Rubric Phase 3 handoff.
