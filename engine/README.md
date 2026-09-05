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

| Module | Role | Phase |
|--------|------|-------|
| `rafiq.quran` | dataset loading and position arithmetic | 0 |
| `rafiq.normalize` | Arabic text normalization | 1 |
| `rafiq.matching` | text → candidate ayahs | 1 |
| `rafiq.asr` | audio → text | 3 |
| `rafiq.tracking` | stateful position tracking | 4 |
