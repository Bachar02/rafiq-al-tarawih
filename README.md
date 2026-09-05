# Rafiq al-Tarawih — رفيق التراويح

**A companion that lets you follow the imam during Taraweeh.**

## Problem

During Taraweeh it is easy to lose your place in the imam's recitation — you
join late, your attention drifts, the imam moves to a new ayah, and you no
longer know where in the Quran you are. Existing Quran apps let you *read*;
none of them tell you *where the imam currently is*.

## MVP

One feature, done extremely well:

> While the imam is reciting, the app identifies the current Surah and Ayah
> and displays it in real time.

```
imam recites  ──►  app shows  ──►  Ad-Duha 93:2  ──►  93:3  ──►  93:4 ...
```

## Non-goals (for now)

Adhkar · salat tracker · Ramadan statistics · bookmarks · social features ·
accounts · a general-purpose mushaf reader.

These come *after* the recognition engine is reliable. The engine is the moat;
everything else is a normal app feature that anyone can build.

## Core engineering bet

The hard problem is not the app. It is:

> Can we reliably map noisy imam audio to an exact Quran position?

So this repo builds the **engine first**, as a plain Python library with no
Flutter and no server in the way. The app is a client of the engine, not the
other way around.

A second bet shapes the whole design: this is a **tracking** problem, not a
classification problem. The question is not "which ayah is this?" but "given
everything I have heard so far, where am I in the Quran?" A system that knows
it was at 2:120 a second ago should strongly prefer 2:121 over 93:4. Stability
matters more than raw per-segment accuracy — an app that flickers between
distant ayahs is worse than one that lags slightly but stays put.

## Architecture

```
  audio ──► VAD / preprocessing ──► ASR ──► normalization
                                               │
                                               ▼
                                     candidate retrieval        ◄── Quran index
                                               │
                                               ▼
                                       position tracker         ◄── previous state
                                               │
                                               ▼
                                    surah + ayah + confidence
                                               │
                                               ▼
                                        follow-along UI
```

North star: all of this runs **on-device, offline**. Mosque connectivity is
unreliable and the Quran is small enough to ship in the binary. But v0 runs the
engine on a laptop, because the goal of v0 is to find out whether the approach
works at all.

## Roadmap

| Phase | Deliverable | Status |
|-------|-------------|--------|
| 0 | Product definition, repo foundation, Quran data pipeline | **in progress** |
| 1 | Arabic normalization + text→ayah matching (no ML) | not started |
| 2 | Evaluation set of real recitations + product metrics | not started |
| 3 | ASR baseline: audio→text→ayah | not started |
| 4 | Position tracker (stateful, windowed) | not started |
| 5 | Flutter MVP against the engine | not started |
| 6 | On-device inference, real mosque testing | not started |

Phase 1 deliberately contains **no ML**. If `text → ayah` is not rock solid on
clean input, `audio → ayah` has no chance, and we would not be able to tell
which half was broken.

## Metrics that matter

Word error rate is the wrong headline metric. We track product metrics:

- **Ayah accuracy** — fraction of predictions that name the correct ayah.
- **Position error** — *how far* off, in ayahs. Predicting 93:6 for 93:5 is a
  near miss; predicting 2:255 is a catastrophe. These must not score alike.
- **Tracking stability** — how often the displayed ayah jumps somewhere wrong.
- **Latency** — imam speaks an ayah → app displays it.
- **Recovery** — after a failure, how long until the position is right again.

## Open product questions

These change the architecture, so they get decided before the code that depends
on them, not after:

- Does the user pick the starting point ("tonight we begin at Al-Baqarah 1"),
  or is surah detection fully automatic? Seeding the search space is a large
  early reliability win; automatic detection is the magic. Likely: automatic,
  with optional seeding.
- What happens between rak'ahs, and during long pauses?
- What if the imam repeats an ayah, or skips one?
- What does the UI do when confidence drops — freeze, or show alternatives?
- What if the app simply cannot hear?

## Repo layout

```
data/     Quran datasets (raw, verbatim) + the build script that derives quran.json
engine/   the recognition engine — a plain Python library, the heart of the project
eval/     recitation test set + metric harness            (Phase 2)
server/   thin FastAPI wrapper over the engine, for the app to talk to   (Phase 5)
mobile/   Flutter client                                  (Phase 5)
```

## Getting started

Requires Python 3.11+.

```bash
py data/build_quran.py          # derive data/quran.json from the raw sources
cd engine && py -m pip install -e ".[dev]"
py -m pytest
```

## Attribution

Quran text and metadata are from the [Tanzil Project](https://tanzil.net)
(Simple Clean, v1.1), used under Creative Commons Attribution 3.0.
The raw files in `data/raw/` are verbatim copies, including their copyright
notices, and must not be edited. See [data/README.md](data/README.md).
