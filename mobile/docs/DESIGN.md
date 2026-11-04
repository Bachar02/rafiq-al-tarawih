# Rafiq mobile — v1 design

> Open the app during Taraweeh, tap once, and see which surah and ayah the
> imam is reciting, live, with the text highlighted.

## 1. Scope

**v1 does exactly one job:** follow the imam. Nothing else.

| In v1 | Not in v1 |
|---|---|
| Live surah + ayah, highlighted in the surah text | Mushaf browsing, bookmarks, accounts |
| Optional hint ("tonight is juz 5") | Adhkar, prayer times, statistics |
| Works with the recognition server over Wi-Fi | On-device recognition (Phase 6) |
| Survives bad networks, denied mic, app switching | Background listening with the screen off |

**Recognition runs on the laptop server** (`/ws/listen`, see `server/src/rafiq_server/listen.py`).
The phone captures audio and renders the result. This is Phase 5 of PLAN.md. On-device
recognition replaces the server behind the same interface later (§4.2), without UI changes.

## 2. Experience

### 2.1 Principles
1. **One tap to follow.** No setup on the hot path. The server address is remembered.
2. **Never confidently wrong.** Show nothing rather than a wrong ayah. Uncertainty is
   visible (hollow marker, dimmed number, dashed rule, alternatives), never hidden.
3. **Readable in a dark mosque, at arm's length.** Large Arabic, dark theme by default,
   high contrast, the screen kept awake while listening.
4. **Glanceable.** The current ayah is always on screen, and the answer to "where are we?"
   takes under a second to read.

### 2.2 Screens

**Listen (home):** the whole app on one screen (Rubric, brand book §6a).

```
┌───────────────────────────────┐
│ رفيق                    🔓  ⚙ │  monochrome wordmark · hint (before following)
│                               │   or surah lock (while following) · settings
│ AYAH                   الضحى  │  position header: numeral (Newsreader) opposite
│ 3        Ad-Duha · 93 · Juz 30│   the surah (Amiri) and its meta line
│ ◆ Following the imam          │  status line: the only place state is put in words
│                               │
│        بِسْمِ ٱللَّهِ ...          │  Quran column: one block per ayah, no cards;
│   وَٱلضُّحَىٰ ۝١                 │   recited · current · coming by luminance;
│ ┃ مَا وَدَّعَكَ ... ۝٣             │   cinnabar margin rule + marker on the current
│   وَلَلْـَٔاخِرَةُ ... ۝٤           │   ayah; 40px fade at the bottom
│   ( ◆ Back to the imam · 93:3 )│  only after scrolling/browsing away
│ [notice, when something needs you]
│ ▁▂▃ Hearing sound             │  mic level: neutral, never cinnabar
│ (        Stop following      )│  the one control, a full-width pill
└───────────────────────────────┘
```

**States** (one vocabulary for the status line, the marker and the header; brand book §7).
Precedence, highest first: error → paused → lost → uncertain → No new match yet → Little
sound → Al-Fatiha → Following. Every state differs in marker shape *and* words.

| Source | Status line | Marker | Header |
|---|---|---|---|
| idle | Ready to follow / Not following | — / hollow | — / last position |
| connecting | Connecting… | hollow if a position is held | |
| listening, no position | Listening for the imam | — | — |
| `tracking`, confirmed < 10 s ago | Following the imam | filled | ayah in `ink` |
| ayah 1:x inside another surah | Al-Fatiha | filled | imam's surah and last ayah kept |
| app-inferred: sound, no confirmed update ≥ 10 s | No new match yet | hollow | stays `ink` |
| app-inferred: mic below the quiet level ≥ 10 s | Little sound | hollow | stays `ink` |
| `uncertain` | Not sure | hollow | LAST SURE, dimmed, number held |
| `lost` | Not matching the Quran | hollow | LAST SURE, dimmed, number held |
| reconnecting (server build) | Reconnecting… | hollow | kept |
| paused / error | (the Notice speaks) | — | kept |
| `pending` | nothing: unconfirmed guesses are never shown | | |

The 10-second windows and the quiet level (`quietLevel`, `inferredStateAfter` in
`listen_state.dart`) are uncalibrated starting values.

**Notices** (lapis `signal`, icon + words + one action, above the control): microphone
permission, microphone stopped, recognition server unreachable (server build only),
recognition stopped, following paused, and transient engine warnings.

**Sheets:** Tonight's starting point (None / Surah / Juz), Stay on this surah, and
*The imam is here* (tap an ayah). Max 70% of the screen.

**Settings:** grouped rows. Reading (Quran text size with a live 93:3 preview, keep screen
on, appearance), Recitation (Ḥafṣ ʿan ʿĀṣim; Qālūn and Warsh not supported), Recognition
server (server build only: address, *Test connection*), Developer (diagnostics, on-device
benchmark), About.

**Diagnostics (opt-in):** a live transcript feed under the Quran column, for field testing.

### 2.2b Reader and user control (v1.1)
- **The whole Quran is on the phone** (Uthmani text with tashkeel). The server only says *where*;
  the app opens that place in its own copy. A surah index (tap the surah name) lets the user browse anywhere.
- **Quran column:** the surah's own basmala (not for 1 and 9), then one block per ayah with its end
  marker (۝ + Arabic-Indic numeral). At display time only, a no-break space joins each ayah to its
  marker and replaces the space before each standalone pause mark (`core/text/quran_display.dart`):
  no line ever starts with a marker or a pause mark; `quran.json` is never changed.
- **No flicker:** the reader changes surah only on a *confident* result, a user correction, or browsing,
  and not for al-Fatiha at each rakʿah. An unsure guess never replaces the text or the number.
- **Follow-scroll:** only when the current ayah leaves 25–60% of the column; it returns to ~38%.
  Scrolling by hand detaches following until the ayah is back in view or *Back to the imam* is tapped.
- **User control:** tap any ayah, then *The imam is here* (the tracker continues from it) or
  *Stay on this surah* (a hard lock: recognition never searches other surahs, al-Fatiha excepted).
  The header's lock button does the same, and the lock survives reconnects.
- **Display names:** curated English and French surah names (`assets/data/surah-names.json`,
  checked row by row against `quran.json` at startup); indexes and the Quran data are unchanged.

### 2.3 Visual language — Rubric
Tokens live in `lib/app/theme.dart` (from the Phase 3 handoff `tokens.json`).
- **Colour:** everything is ink on a dark page (`ground` #100E0C; light theme on paper #F2ECE0).
  **Cinnabar (`rubric`) has one meaning: the imam's current position** — the position marker, the
  current ayah's margin rule and end marker, the Return-to-imam marker. Never errors, the
  microphone, buttons or decoration. Needs-your-action states use lapis (`signal`) with an icon
  and words. Elevation by lightness only; no shadows, no cards around ayahs.
- **Type:** Amiri Quran for Quran text only; Amiri (Arabic) and Newsreader (Latin) for titles and
  the ayah numeral; IBM Plex Sans + IBM Plex Sans Arabic for the interface (Amiri as a last
  fallback for transliteration letters such as ʿ). The Quran text scales 0.85–1.6 with its own
  setting, line height 2.2, justified only when column width ÷ font size ≥ 11.5.
- **Motion:** quiet and short. Ayah change: rule and colours crossfade (320 ms); follow-scroll
  600 ms; marker fill 160 ms. Nothing pulses or loops. Reduced motion: scrolls jump.

## 3. Behavior rules
- **Listening keeps the screen awake** (wakelock). Released on stop.
- **App goes to background:** stop capture and close the session (Android and iOS will
  not keep the mic anyway). On return, show "Paused" with one-tap resume.
- **Network drop while listening:** keep the mic running, reconnect with backoff
  (0.5 s → 8 s, unlimited while the user is listening), keep only the newest 2 s of
  audio. The last ayah stays on screen, marked as reconnecting.
- **Mic denied:** explain why the mic is needed and how to allow it, and offer *Try again*.
- **Server unreachable at start:** say so and link to server settings.

## 4. Architecture

### 4.1 Layers
```
lib/
  app/        bootstrap, theme, routing
  core/       framework-free logic: models, protocol codec, PCM, backoff
  data/       Quran repository (bundled asset), settings repository
  services/   platform adapters: microphone, WebSocket recognition, wakelock
  features/   listen/, settings/ — controllers (Riverpod) + widgets
```
Dependencies point downward only. `features` never touches `record` or WebSockets
directly; it talks to the interfaces in §4.2. Everything below `features` is unit-tested
without Flutter widgets.

### 4.2 Seams (the scalability story)
| Interface | v1 implementation | Later |
|---|---|---|
| `AudioSource`: 16 kHz mono float32 frames + level | `MicAudioSource` (`record` package) | file playback for demos |
| `RecognitionEngine`: audio in, `RecognitionEvent`s out | `ServerRecognitionEngine` (WebSocket) | on-device engine (Phase 6) |
| `QuranRepository` | bundled `assets/quran/quran.json` | Uthmani display text |

`ListenController` (a Riverpod `Notifier`) is a state machine over those
interfaces. Tests drive it with fakes.

### 4.3 Wire protocol
Unchanged server protocol (see `listen.py`): binary float32 LE PCM frames at 16 kHz, and
JSON `ready / partial / heard / warning / done / error`. The client batches audio into
~250 ms frames, tolerates unknown message types and fields (forward compatible), and
treats `error` as fatal and `warning` as informational.

### 4.4 Tech choices
| Concern | Choice | Why |
|---|---|---|
| UI | Flutter (3.47, Dart 3.13) | one codebase for Android and iOS |
| State | flutter_riverpod | testable, no codegen, explicit dependencies |
| Mic | record (PCM16 stream at 16 kHz) | native resampling, Android and iOS |
| Socket | web_socket_channel | standard; wrapped behind `RecognitionEngine` |
| Storage | shared_preferences | settings only |
| Screen awake | wakelock_plus | maintained, both platforms |

## 5. Quality bar
- **Unit tests:** protocol codec, PCM conversion and framing, backoff, Quran repository,
  settings.
- **Controller tests:** the full session state machine with fake audio and a fake engine
  (start, follow, reconnect, permission denied, server error, stop).
- **Engine integration test:** `ServerRecognitionEngine` against a real local WebSocket
  server in the test process (handshake, frames, events, drop and reconnect).
- **Widget tests:** the Listen screen in each state, the hint sheet, and settings.
- **CI:** `dart format`, `flutter analyze` (strict lints), `flutter test`, and a check that
  the bundled Quran asset matches the data pipeline output.
- **Manual end to end:** emulator with the host microphone, against the real backend.
