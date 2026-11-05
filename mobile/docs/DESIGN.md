# Rafiq mobile — design

> A Quran reader, opened every day where you stopped reading. During
> Taraweeh, one tap follows the imam live in the same text.

## 1. Scope

**Two experiences, one app** (product decision, PLAN.md §18):
- **The reader (home):** the whole Quran as one continuous text, opened at the personal reading position; Go to
  (surahs, juz, the 604 Madinah-mushaf pages, bookmarks), search (references, pages, juz, surah names, Arabic
  text), bookmarks, notes, a khatm planner, text size, light/dark/system, English, French and Arabic.
- **Taraweeh mode (the signature):** one tap from the reader; the app listens to the imam and marks the ayah
  being recited, with honest uncertainty, corrections and a surah lock.

| In | Not in (by decision, not by omission) |
|---|---|
| Reading, navigation, search, bookmarks, notes, a khatm plan, two independent positions | Accounts, sync, prayer times, adhkar, streaks |
| Taraweeh mode, Ḥafṣ only | Other riwāyāt (Qālūn, Warsh) |
| A page *number* for every ayah (page starts) | A facsimile of the printed page (the text flows) |
| Recognition on the laptop server (this build) | On-device recognition (PLAN.md §17 M2), offline claims |

**Recognition runs on the laptop server** (`/ws/listen`, see `server/src/rafiq_server/listen.py`).
The phone captures audio and renders the result. On-device recognition replaces the server behind
the same interface later (§4.2), without UI changes. The reader needs no server.

## 2. Experience

### 2.1 Principles
1. **The Quran first.** The text is the screen; chrome stays small. The reader opens straight on the
   text, where the user stopped.
2. **One tap to follow.** No setup on the hot path: the reader's Taraweeh button starts listening (after a
   one-time introduction). The server address is remembered.
3. **Never confidently wrong.** Show nothing rather than a wrong ayah. Uncertainty is
   visible (hollow marker, dimmed number, dashed rule, alternatives), never hidden.
4. **Readable in a dark mosque, at arm's length.** Large Arabic, Taraweeh mode dark by default,
   high contrast, the screen kept awake while listening.
5. **Two positions, never mixed.** The personal reading position is what the user read; the last
   Taraweeh position is where the imam got to. Neither ever writes the other.

### 2.2 Screens

```
┌ Read ─ Surahs ─ Bookmarks ─ (Taraweeh) ─ More ┐   a labelled bar at the bottom of every screen
Read       the Quran (scroll or pages), the place in the bar; the surah name ▾ opens Surahs
Surahs     surahs (filter by name or number), juz, the 604 pages; a choice opens Read there
Bookmarks  Bookmarks | Notes: the khatm card · continue reading · where Taraweeh ended · bookmarks;
           or the notes, newest edit first
Taraweeh   a button, not a tab: the full-screen mode, listening at once (one tap)
More       Khatm planner, Settings, and what is coming (shown, visibly not yet working)
```
`lib/app/home_shell.dart`. The reader stays alive under the other tabs (its place and scroll
survive); the other tabs are rebuilt on each visit so their lists open at the current place. Back
from any tab returns to Read; back from Read leaves the app. Other tabs open places in the reader
through `readerRequestsProvider` (`lib/app/navigation.dart`), never by reaching into its state.

**Read:**
```
┌───────────────────────────────┐
│ البقرة Al-Baqarah ▾     📖  🔍 │  name ▾ → Surahs · layout · search
│ Juz 1 · Page 21 · Today 4/20  │  where; today's pages (khatm target, or the goal)
│        … ayahs, full ink …  ▌ │  the scrubber: shows while the text moves;
│ ─────── Juz 2 · Page 22 ───── │   drag it, a bubble names page · surah · juz
│ ▮ ayah with a bookmark ribbon │  and a note icon under it when noted
└───────────────────────────────┘
```
- **Tap an ayah:** its sheet: Bookmark / Remove bookmark, Add a note / Edit note, Share, Copy; then Listen, Translation and
  Tafsir, disabled under "Coming soon". The ayah is marked with the `mark` wash while its sheet is open,
  and for two seconds after a jump from search, Surahs or Bookmarks.
- **Press and hold an ayah:** bookmark it (or remove its bookmark) at once, with a light haptic tick
  and Undo. Bookmarked ayahs carry a small ribbon in the margin (in pages, before the ayah).
- **The scrubber:** a handle on the trailing edge, in pages (1..604) so it means the same in both
  layouts. Hidden until the text moves; a page per step while dragged; screen readers get it as a
  slider (ten pages a step).

**Bookmarks:** a segmented control, **Bookmarks | Notes**.
- *Bookmarks:* the khatm card when a plan runs ("72 of 604 pages", today's target, days left; it opens
  the planner), *Continue reading* (the reading position), *Where Taraweeh ended*, then the bookmarks
  with their opening words, place and date. Sort: newest first or Quran order (remembered).
- *Notes:* each note's reference, place, date and first two lines, in the direction the note is
  written. Tap to read there; the trailing button edits it.
- Swipe (or the remove button) deletes, with Undo that restores the item with its own dates; a removal
  that cannot be saved stays in the list and says so.

**More:** Khatm planner, Settings; *Coming soon*: recitation audio, translations, tafsir, Taraweeh
without a computer. Shown where they will live, disabled and labelled "Soon".

**Khatm planner** (More, or the Bookmarks card). One active plan at a time.
- *Start:* finish in 15, 30 ("a juz a day") or 60 days, or by a picked date; start where the reader is
  (page N) or from page 1. A line previews the pace ("About 21 pages a day · ends Dec 3, 2026").
- *Running:* "72 of 604 pages read" with a bar, "Today: 10 of 21 pages", "27 days left · ends Nov 30,
  2026" (or "Past the planned end · 40 pages left"). *Continue khatm (page N)* opens the first unread
  page, reading on from the start page and wrapping round; *Change end date*; *Stop this khatm*, after
  a confirmation. Finished khatms are listed quietly ("Completed Oct 10, 2026 · in 29 days").
- *Today's target adapts:* what was left this morning ÷ the days left (at least one), rounded up.
  Reading ahead lowers tomorrow's target, falling behind raises it, and today's reading never shrinks
  today's target.
- *What counts:* the same rule as the daily goal (below), so there is one definition of reading. A
  page counts the first time it is read during the plan; reading it again adds nothing. The plan keeps
  the day each page was first read, so a year-long plan does not depend on the reading log.
- While a plan runs, its target replaces the daily goal in the reader bar. The last page completes the
  plan: the reader says "Khatm complete · in 29 days" once, and the plan moves to the finished list.

**Notes:** one per ayah, from the ayah sheet. The sheet has the reference with *Save* beside it (pinned,
so it stays in view above the keyboard), a field (up to 2,000 characters), and *Delete note* when one
exists; saving an emptied note deletes it. The sheet
saves the note itself and closes only once it is kept: if the save fails, the text stays in the field
and the sheet says so. The field and every list show a note in the direction it is written
(`Bidi.detectRtlDirectionality`): Arabic right to left, French or English left to right, whatever the
interface language. Noted ayahs carry a small note icon in the margin under the bookmark ribbon (in
pages, before the ayah); screen readers hear ", note".

**Two layouts** (Settings → Reading → Layout, and a toggle in the bar on screens 360 dp and wider):
- *Scroll:* the whole Quran as one text (`QuranView`, §2.2b).
- *Pages:* the 604 Madinah-mushaf pages, one per screen, turned like a mushaf (the next page comes
  from the left, in every interface language). Each page holds exactly Tanzil's ayahs for it, flowing
  inline per surah with surah openings where they fall, a running head (surah, juz) and the page number
  in Arabic-Indic digits. The text flows, so a long page scrolls within itself: it is never presented as
  a facsimile. Same taps, sheets, marks and text size as Scroll. Both open at the same reading position
  (in Pages, the page's first ayah).

**Share** (from the ayah sheet): a preview of an image card (the ayah in Amiri Quran, its reference, the
wordmark, in the current theme), then *Share as an image* (rendered from the card at 3×, 1080 px wide)
or *Share as text*.

**Daily reading goal** (Settings → Reading: off, 5, 10, 20, 40 pages). A page counts when the reader
moves forward past it, scrolling or turning one or two pages at a time; jumps and opening the app count
nothing; the last page of the Quran counts when reached. With a goal, the bar's second line ends with
"Today 12/20" (just "12/20" on narrow phones) and a 2 px ink line runs under the bar. No streaks, no
badges. The Pages tab of Go to says where the reader is in the whole Quran ("Page 42 of 604 · 6%").

**Go to:** four tabs, each list opened at the current place; rows of a kind share one height
(measured once from a prototype row) so a 604-row list opens exactly at the current page.
Bookmarks: where Taraweeh ended first, then bookmarks newest first; removing one can be undone.

**Search:** one field. `2:255` (Arabic-Indic digits too), `page 50`, `juz 30`, a bare number (surah,
juz, page), surah names in any language the app knows, Arabic words: matched after the engine's own
`normalize`, so tashkeel, hamza seats and alef forms do not matter. Results in mushaf order, at most
200 shown with the full count.

**Taraweeh mode:** Rubric brand book §6a.
```
┌───────────────────────────────┐
│ ← رفيق                  🔓  ⚙ │  back to reading · wordmark · hint (before following)
│                               │   or surah lock (while following) · settings
│ AYAH                   الضحى  │  position header: numeral (Newsreader) opposite
│ 3        Ad-Duha · 93 · Juz 30│   the surah (Amiri) and its meta line
│ ◆ Following the imam          │  status line: the only place state is put in words
│                               │
│        بِسْمِ ٱللَّهِ ...          │  the same QuranView, live tones: recited ·
│   وَٱلضُّحَىٰ ۝١                 │   current · coming by luminance; cinnabar margin
│ ┃ مَا وَدَّعَكَ ... ۝٣             │   rule + marker on the current ayah
│   ( ◆ Back to the imam · 93:3 )│  only after scrolling/browsing away
│ [notice, when something needs you]
│ Tonight: Juz 7 ×              │  hint chip until the imam is found
│ ▁▂▃ Hearing sound             │  mic level: neutral, never cinnabar
│ (        Stop following      )│  the one control, a full-width pill
└───────────────────────────────┘
```
- **Entering** starts listening at once. The first time only, an introduction sheet says what the mode
  does, that this build needs the server on the same Wi-Fi, that it follows Ḥafṣ only, and how to
  correct it; *Not now* leaves following off.
- **Last night:** if a session ended within 36 hours, the juz of the ayah after where it ended is applied
  as a soft hint (PLAN.md §9: a wrong hint costs almost nothing), shown as a chip with
  "Last night ended at …" and removable.
- **Leaving** (back button or gesture) stops following and saves the last Taraweeh position: the imam's
  main position (`anchor`), never Al-Fatiha at a rakʿah. It is also saved a few seconds after each
  change and when the app goes to the background.

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

**Settings:** grouped rows. Reading (Quran text size with a live 93:3 preview, appearance:
system/light/dark, language: system/English/Français/العربية), Taraweeh (dark during Taraweeh, keep
screen on), Recitation (Ḥafṣ ʿan ʿĀṣim; Qālūn and Warsh not supported), Recognition server (server
build only: address, *Test connection*), Developer (diagnostics, on-device benchmark), About.

**Diagnostics (opt-in):** a live transcript feed under the Quran column, for field testing (English only).

### 2.2b The Quran text: `QuranView`
- **One text for both modes.** `lib/features/quran_view/`: the 114 surah headers (Arabic name, meta,
  basmala except 1 and 9) and 6,236 ayahs as one lazily built list. Only what is on screen (plus a small
  cache) exists, so the cost of a frame does not depend on the surah's length (PLAN.md §18, R2).
- **Jumps are exact.** The list is anchored at an item with the two-sliver "center" technique; a jump is a
  re-anchor, constant time, no extent estimation. A jump to a surah opens at its header; to an ayah with a
  division mark, at the mark; otherwise 8 px above the ayah so high marks are never clipped.
- **Positions are measured in scroll space** (the offset that reveals an item minus the current offset),
  never from paint positions, which are a frame stale when a drag ends.
- **No needless rebuilds.** The item delegates are rebuilt only when what the items show changes (text
  size, tones, the marked ayah); a parent rebuild (the Taraweeh screen's 80 ms mic-level updates) rebuilds
  no ayah. Reading tone skips the tone crossfade machinery entirely.
- **Division marks:** a hairline with "Juz 2 · Page 22", "¼ Hizb 1" or "Page 3" before the ayah that
  starts it (Tanzil's page and hizb-quarter starts, PLAN.md §18 R1). Starts only: the text flows.
- **Display text:** at display time only, a no-break space joins each ayah to its end marker and replaces
  the space before each standalone pause mark (`core/text/quran_display.dart`); `quran.json` is never
  changed.
- **Taraweeh follow-scroll:** only when the followed ayah leaves 25–60% of the height; it returns to
  ~38%. A far move (not built) is a cut, not a long scroll. Scrolling by hand detaches following until the
  ayah is back in view or *Back to the imam* is tapped. The followed ayah is the imam's position in the
  surah the controller shows, so an unsure guess or a lock elsewhere never pulls the text.
- **No flicker:** the controller changes surah only on a *confident* result, a user correction, or
  browsing, and not for Al-Fatiha at each rakʿah. An unsure guess never replaces the text or the number.
- **User control:** tap any ayah, then *The imam is here* (the tracker continues from it) or
  *Stay on this surah* (a hard lock: recognition never searches other surahs, Al-Fatiha excepted).
- **Display names:** curated English and French surah names (`assets/data/surah-names.json`, checked row
  by row against `quran.json` at startup); in Arabic, each surah's own name, never shown twice.

### 2.3 Visual language — Rubric
Tokens live in `lib/app/theme.dart` (from the Phase 3 handoff `tokens.json`).
- **Colour:** everything is ink on a dark page (`ground` #100E0C; light theme on paper #F2ECE0).
  **Cinnabar (`rubric`) has one meaning: the imam's current position** — the position marker, the
  current ayah's margin rule and end marker, the Return-to-imam marker. Never errors, the
  microphone, buttons or decoration. Needs-your-action states use lapis (`signal`) with an icon
  and words. Elevation by lightness only; no shadows, no cards around ayahs.
- **Themes:** the reader follows the phone (system by default; a theme an earlier version saved is
  kept). Taraweeh mode is dark whatever the reader uses, unless *Dark during Taraweeh* is off: a theme
  scoped to its route, carried into screens opened from it, so the reader underneath never changes.
- **Type:** Amiri Quran for Quran text only; Amiri (Arabic) and Newsreader (Latin) for titles and
  the ayah numeral; IBM Plex Sans + IBM Plex Sans Arabic for the interface (Amiri as a last
  fallback for transliteration letters such as ʿ). The Quran text scales 0.85–1.6 with its own
  setting, line height 2.2, justified only when column width ÷ font size ≥ 11.5.
- **The reader's mark:** `mark`, a quiet wash behind one ayah (an open sheet's ayah, a search or bookmark
  just opened). A background only; never the imam's position, which stays cinnabar.
- **Launch:** the Android launch window and the Android 12+ splash show the page colour and the Rafiq
  mark in the theme's ink, day or night; the app icon stays dark in both. (iOS still launches dark.)
- **Accessibility:** tap targets meet 48 dp (Android) and 44 dp (iOS) and every one has a label;
  settings rows are announced as one item with their switch; every main screen lays out at 200% system
  text (checked by `test/accessibility_test.dart`, with text contrast, in both themes).
- **Three languages:** English, French and Arabic, right to left for Arabic (`lib/l10n/`, gen-l10n). Quran
  text is always Arabic and always right to left. Overlines are Latin capitals with letter-spacing; in
  Arabic they have neither (`RubricText.overlineFor`). Interface Arabic falls to IBM Plex Sans Arabic.
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
  app/        shell (app.dart), routes, theme, providers, shared components
  core/       framework-free logic: models, protocol codec, PCM, backoff, normalize
  data/       Quran (+ juz/page/hizb lookups), settings, reading store, surah names
  l10n/       ARB strings and the generated localizations
  services/   platform adapters: microphone, WebSocket recognition, wakelock
  features/
    quran_view/  the shared Quran text (BookIndex, QuranView, headers and marks)
    reader/      home: reading position, reading progress, bookmarks, ayah sheet
    bookmarks/   the Bookmarks tab (Bookmarks | Notes)
    khatm/       KhatmController and the planner screen
    notes/       NotesController and the note sheet
    navigate/    Go to         search/   QuranSearch (pure Dart) and its screen
    listen/      Taraweeh mode: ListenController (unchanged), its screen, last Taraweeh position
    settings/
```
Dependencies point downward only. `features` never touches `record` or WebSockets directly; it talks
to the interfaces in §4.2. Everything below `features` is unit-tested without Flutter widgets.

**Persistence** (`data/reading_store.dart`): the reading position, the last Taraweeh position,
bookmarks, notes (`notes.v1`), the reading log (`reading_log.v1`, 400 days, for a year chart later) and
the khatm book (`khatm.v1`: the active plan with each page's first day, grouped by day, and the finished
khatms) are versioned JSON records. A record that cannot be read, whole or in part, is copied aside
(`<key>.unreadable.<time>`) before any write can replace it, and its readable parts are kept; a failed
write is reported, never thrown. Bookmarks, notes and khatm start / change / stop are saved before they
are shown; pages read are saved a moment later and when the app leaves the foreground, and a failed
save stays pending. Preferences stay in `SettingsStore`, which keeps any value
an earlier version stored (a theme saved as dark stays dark).

### 4.2 Seams (the scalability story)
| Interface | Implementation | Later |
|---|---|---|
| `AudioSource`: 16 kHz mono float32 frames + level | `MicAudioSource` (`record` package) | file playback for demos |
| `RecognitionEngine`: audio in, `RecognitionEvent`s out | `ServerRecognitionEngine` (WebSocket) | on-device engine (PLAN.md §17 M2) |
| `ReadingStore`: positions, bookmarks, notes, reading log, khatm | `PrefsReadingStore` (shared_preferences) | SQLite, if notes outgrow it |
| `Quran` | bundled `assets/quran/quran.json` | |

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
| Storage | shared_preferences | settings, positions, bookmarks, notes, khatm (versioned JSON) |
| Strings | flutter_localizations + gen-l10n (intl) | the official stack; generated code committed |
| Screen awake | wakelock_plus | maintained, both platforms |

## 5. Quality bar
- **Unit tests:** protocol codec, PCM, backoff, the Quran and its divisions (binary search against a
  linear scan of every verse), the reading store (unreadable records are kept), the khatm arithmetic
  (adaptive target, overdue, wrap-around, re-reading, a 365-day plan), notes, search, settings,
  `BookIndex` round-trips for all 6,350 items, translations complete in every language.
- **Controller tests:** the full session state machine with fake audio and a fake engine.
- **Engine integration test:** `ServerRecognitionEngine` against a real local WebSocket server.
- **Widget tests:** the reader (restore after restart, background save, failed saves, bookmarks, notes,
  copy, search, Go to), the khatm planner (start, continue, change end, stop, the bar and the card,
  completion), the Notes view, Taraweeh mode in every state (auto-start, the introduction once, leaving, both
  positions, last night's hint), `QuranView` (virtualization, jumps, follow, detach), Arabic RTL and
  French, small phones at large text in every language.
- **Golden screenshots** with the real fonts, rendered on Linux (`tool/goldens.sh`): reader, Taraweeh,
  search, Go to, settings, the introduction, the khatm planner, the note sheet, Notes, Arabic and French.
- **Accessibility** (`test/accessibility_test.dart`): Flutter's tap-target, label and contrast
  guidelines on every main screen in both themes, and every screen at 200% system text.
- **Performance:** the R2 budgets on a real phone (`integration_test/`, `tool/perf_report.py`).
- **CI:** `dart format`, `flutter analyze` (strict lints), `flutter test`, and a check that the bundled
  Quran asset matches the data pipeline output.
- **Manual end to end:** emulator with the host microphone, against the real backend.
