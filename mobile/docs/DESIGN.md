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
   visible (dimmed text, "not sure" chip, alternatives), never hidden.
3. **Readable in a dark mosque, at arm's length.** Large Arabic, dark theme by default,
   high contrast, the screen kept awake while listening.
4. **Glanceable.** The current ayah is always on screen, and the answer to "where are we?"
   takes under a second to read.

### 2.2 Screens

**Listen (home):** the whole app on one screen.

```
┌───────────────────────────────┐
│ رفيق             ● Live   ⚙   │  app bar: connection dot, settings
├───────────────────────────────┤
│  ┌─────────────────────────┐  │
│  │  الأعراف                 │  │  Now card
│  │  Al-A'raf · ayah 29/206  │  │   surah (Amiri, large)
│  │  ● Following   ▂▂▂▂▂▂░   │  │   status chip + confidence
│  └─────────────────────────┘  │
│  could also be 26:127 · 26:145│  alternatives (only when ambiguous)
│ ┌───────────────────────────┐ │
│ │  …وَأَقِيمُوا وُجُوهَكُمْ ﴿٢٩﴾ │ │  Surah text, RTL, current ayah
│ │  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │ │   highlighted, auto-scrolled
│ │  فَرِيقًا هَدَىٰ ﴿٣٠﴾        │ │   ("Back to imam" if user scrolls)
│ └───────────────────────────┘ │
│   [ Tonight: Juz 8  ✕ ]       │  optional hint chip
│            ( 🎤 )             │  big mic button with level ring
└───────────────────────────────┘
```

**States** shown in the Now card and status chip:

| State | Chip | Now card |
|---|---|---|
| idle | — | "Tap the microphone when the imam begins" |
| connecting | Connecting… | "Loading the speech model…" after 3 s |
| searching | Listening | "Listening… finding the surah" |
| following | ● Following (green) | surah + ayah, full contrast |
| uncertain | Not sure (amber) | last good ayah, dimmed |
| lost | Lost (red) | last ayah, dimmed, "can't hear clearly" |
| reconnecting | Reconnecting… | last ayah kept, banner with attempt count |
| error | — | explanation + action (Retry / Open settings / Server settings) |

**Hint sheet:** Nothing (default) / Surah (searchable list) / Juz (1–30 grid).

**Settings:** server address with a *Test connection* button (shows reachable, speech
model, latency), keep screen awake, text size, show diagnostics, about and attribution.

**Diagnostics (opt-in):** a live transcript feed under the surah text, for field testing.

### 2.3 Visual language
- **Color:** dark by default (Taraweeh is at night). A deep green-teal primary, a warm
  gold for ayah markers, amber for uncertain and red for lost. Light theme supported.
- **Type:** Amiri Quran (OFL, bundled) for Quranic text and surah names; the platform
  font for UI. The Quran text scales with the text-size setting.
- **Motion:** only where it carries meaning: the highlight moves to the new ayah, the
  mic ring pulses with input level. No decorative animation.

## 3. Behavior rules
- **Listening keeps the screen awake** (wakelock). Released on stop.
- **App goes to background:** stop capture and close the session (Android and iOS will
  not keep the mic anyway). On return, show "Paused" with one-tap resume.
- **Network drop while listening:** keep the mic running, reconnect with backoff
  (0.5 s → 8 s, unlimited while the user is listening), keep only the newest 2 s of
  audio. The last ayah stays on screen, marked as reconnecting.
- **Mic denied:** explain why the mic is needed, and offer *Open settings*.
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
| UI | Flutter (3.19, Dart 3.3) | one codebase for Android and iOS |
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
