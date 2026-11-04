# Rafiq — mobile app

Open it during Taraweeh, tap the microphone, and see which surah and ayah the
imam is reciting, live. Design and architecture: [docs/DESIGN.md](docs/DESIGN.md).

v1 records on the phone and recognises on the Rafiq server (a laptop on the
same Wi-Fi). On-device recognition comes later, behind the same
`RecognitionEngine` interface.

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
3. **Point the app at the server** (⚙ Settings → Server address → *Test connection*):
   - Android emulator: `10.0.2.2:8765` (the default)
   - real phone: the laptop's Wi-Fi IP, e.g. `192.168.1.5:8765`

On the emulator, let it hear the laptop's microphone with
`adb emu avd hostmicon` (off by default).

## Toolchain
- Flutter 3.19.5 (Dart 3.3).
- **JDK 17+ for Android builds.** The microphone plugin ships Java 17 bytecode, so
  the Android project uses AGP 8.2 / Gradle 8.5 / Kotlin 1.9. If Flutter still uses
  an older bundled JDK: `flutter config --jdk-dir <path-to-jdk-17-or-newer>`.
- minSdk 23 (Android 6.0).

## Develop
```bash
flutter analyze
flutter test                                   # unit, engine-over-real-sockets, controller, widget
dart format -l 120 lib test
python tool/sync_quran.py                      # after rebuilding data/quran.json
```

| Path | What |
|---|---|
| `lib/core/` | framework-free logic: models, wire protocol, PCM, backoff, endpoints |
| `lib/data/` | bundled Quran, settings |
| `lib/services/` | platform adapters: microphone, WebSocket engine, wakelock, health check |
| `lib/features/listen/` | the session state machine (`ListenController`) and its screen |
| `lib/features/settings/` | settings screen |
| `test/support/fakes.dart` | fakes for every seam, and a test harness wired like `main.dart` |

## Licenses
Quran text: Tanzil Project, CC BY 3.0 (`assets/quran/NOTICE.txt`).
Fonts (all SIL OFL 1.1, licence beside each in `assets/fonts/`): Amiri Quran (`OFL.txt`),
Amiri (`OFL-Amiri.txt`), Newsreader (`OFL-Newsreader.txt`), IBM Plex Sans (`OFL-IBMPlexSans.txt`),
IBM Plex Sans Arabic (`OFL-IBMPlexSansArabic.txt`).
Brand assets (wordmark, app icon) and the surah display-name table: Rubric Phase 3 handoff.
