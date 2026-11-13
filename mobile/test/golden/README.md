# Golden files

Two kinds of reference output live here:

- `normalize.json`: Dart-port parity data for the text normalizer, generated
  from the Python engine by `tools/golden/make_golden.py`.
- `screens/*.png`: golden screenshots of the Rubric screens
  (`screens_golden_test.dart`).

## Screenshots

The widget tests render text in the Ahem test font, where every glyph is a box.
They cannot see a glyph that a real font lacks (the ʿ/Ḥ bug) or text that only
overflows at real metrics. The screenshot tests load the app's bundled fonts
from `FontManifest.json` (AmiriQuran, Amiri, Newsreader, IBM Plex Sans,
IBM Plex Sans Arabic, Material Icons; `flutter_test_config.dart`) and fail if
any of them is missing.

| File | Scene |
|---|---|
| `following_dark.png` | Following 93:3, dark theme (the default) |
| `following_light.png` | Following 93:3, light theme |
| `not_sure.png` | Engine unsure on 2:255: the last sure ayah is held, dashed rule |
| `fatiha_excursion.png` | Al-Fatiha (1:3) inside Ar-Rahman: 55:13 stays on screen |
| `repeated_in_surah.png` | Repeated words at the start: Al-Kahf named, no ayah marked, its two ayahs and "Stay on" to choose |
| `repeated_held.png` | Repeated words after 93:3, light: 93:3 held as the last sure ayah, Ar-Rahman only a possibility, chosen in the text |
| `ar_repeated_across.png` | Arabic interface, right to left: words in three surahs, one choice each |
| `small_phone_2_282.png` | 320×568, Quran text 1.3 and system text 1.3, on 2:282 (the longest ayah) |
| `error_notice.png` | The Notice when the server cannot be reached |
| `settings.png` | Settings, top of the screen |
| `hint_sheet.png` | The "Tonight's starting point" sheet |

Phones are 360×780 logical pixels (320×568 for the small one), rendered at a
device pixel ratio of 2.

### Determinism: Linux only, small tolerance

Each OS rasterises text with its own font engine, so a Windows or macOS render
never matches a Linux one exactly. The goldens are therefore **Linux renders**:

- CI (ubuntu) compares them as part of `flutter test`. On other systems the
  screenshot group is skipped with a message.
- To check or re-render them on any machine, use Docker, which runs the same
  Flutter version on linux/amd64 as CI:

  ```sh
  mobile/tool/goldens.sh check    # diffs land in test/golden/failures/
  mobile/tool/goldens.sh update   # re-render screens/*.png, then review them
  ```

  Keep the image tag in `tool/goldens.sh` in step with `flutter-version` in
  `.github/workflows/ci.yml`. A Flutter upgrade re-renders all goldens.

`RubricGoldenComparator` (`test/support/golden.dart`) allows rasterizer noise
and nothing visible:

- **Visible difference:** any RGBA channel differs by more than 24/255. One such
  pixel fails the test. A missing-glyph box, an overflow stripe or a 1 px shift
  each change many pixels by far more than that.
- **Faint difference:** a channel delta of 1–24 (anti-aliasing rounding that can
  vary with CPU features). These pass while they affect at most 1% of the
  pixels.

On failure, CI uploads `test/golden/failures/` (the test image, the golden,
and masked and isolated diffs) as the `golden-failures` artifact.

### When a screen changes on purpose

Run `mobile/tool/goldens.sh update` and look at every changed PNG before
committing it. A golden is only as good as the review of the image.
