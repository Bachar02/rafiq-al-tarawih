# rafiq-engine

The Quran position-recognition engine. A plain Python library: no Flutter, no
web framework, no global state. Everything else in the project — the FastAPI
server, the Flutter app — is a client of this package.

Keeping it a library is deliberate. It means the hard part of the product can
be tested, benchmarked and iterated on in a REPL, in seconds, without an
emulator or a microphone.

```bash
py -m pip install -e ".[dev]"
py -m pytest
```

## Layout

| Module | Role |
|--------|------|
| `rafiq.quran` | dataset loading and position arithmetic |
| `rafiq.normalize` | Arabic text normalization (one function for index *and* ASR output) |
| `rafiq.matching` | text → ranked candidate spans: word stream index, IDF voting, fuzzy word alignment |
| `rafiq.tracking` | stateful position tracking: beam search + pluggable transition prior + display policy |
| `rafiq.simulate` | synthetic noisy recitation streams with ground truth |
| `rafiq.evaluation` | product metrics (accuracy, wrong jumps, recovery) |
| `rafiq.asr` | audio → text *(Phase 3)* |

Data flows one way: `normalize → matching → tracking`. Each stage has a
config dataclass with the knobs in one place, and each depends only on the
stage before it — so a stage can be retuned or replaced (e.g. a learned
transition model) without touching the others.

```python
from rafiq.matching import Matcher, get_index
from rafiq.tracking import Tracker

tracker = Tracker(Matcher(get_index()))
for chunk in asr_chunks:  # a few seconds of recitation each
    state = tracker.update(chunk)  # -> verse_id, status, confidence, candidates
```
