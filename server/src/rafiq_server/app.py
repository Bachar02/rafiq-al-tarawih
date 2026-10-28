"""HTTP API over the engine, plus the dev playground at `/`.

The server holds no session state: `/api/track` replays the whole chunk list
through a fresh tracker on every call. Replay costs a few milliseconds per
chunk, and statelessness means no session store, no cleanup, and identical
results for identical input — which is what a debugging tool needs. The live
audio path (Phase 5) will use a WebSocket with one tracker per connection.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from functools import cached_property
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from rafiq import evaluation
from rafiq.matching import Match, Matcher, QuranIndex, get_index
from rafiq.quran import Quran
from rafiq.simulate import NoiseConfig, simulate
from rafiq.tracking import Tracker, TrackState

from rafiq_server import schemas

STATIC = Path(__file__).parent / "static"


@dataclass
class Engine:
    """Everything built once per process. Trackers are cheap and per request."""

    index: QuranIndex

    @cached_property
    def matcher(self) -> Matcher:
        return Matcher(self.index)

    @property
    def quran(self) -> Quran:
        return self.index.quran

    def tracker(self, hint: schemas.Hint | None = None) -> Tracker:
        tracker = Tracker(self.matcher)
        if hint and hint.surah:
            s = self.quran.surah(hint.surah)
            tracker.hint(s.first_verse_id, s.last_verse_id)
        elif hint and hint.juz:
            tracker.hint(*self.quran.juz_span(hint.juz))
        return tracker

    # -- presenters: engine objects -> wire format ------------------------

    def position(self, verse_id: int | None) -> schemas.Position | None:
        if verse_id is None:
            return None
        v = self.quran.by_id(verse_id)
        return schemas.Position(verse_id=v.id, surah=v.surah, ayah=v.ayah, ref=v.ref)

    def candidate(self, m: Match) -> schemas.Candidate:
        return schemas.Candidate(
            position=self.position(m.verse_id),
            first_ref=self.quran.by_id(m.first_verse).ref,
            score=round(m.score, 3),
            matched_text=self.index.text(m.start, m.end),
        )

    def state(self, s: TrackState, top: int = 3) -> schemas.StateOut:
        return schemas.StateOut(
            position=self.position(s.verse_id),
            status=s.status,
            confidence=s.confidence,
            pending=self.position(s.pending_verse),
            alternatives=[self.position(v) for v in s.alternatives],
            candidates=[self.candidate(c) for c in s.candidates[:top]],
        )


def create_app(engine: Engine | None = None) -> FastAPI:
    app = FastAPI(title="Rafiq al-Tarawih", version="0.1.0")
    eng = engine or Engine(get_index())

    @app.get("/api/health")
    def health() -> dict:
        return {"ok": True, "verses": len(eng.quran), "words": len(eng.index)}

    @app.get("/api/surahs", response_model=list[schemas.SurahOut])
    def surahs():
        return [schemas.SurahOut.model_validate(s, from_attributes=True) for s in eng.quran.surahs]

    @app.get("/api/surahs/{index}", response_model=list[schemas.VerseOut])
    def surah_verses(index: int):
        if not 1 <= index <= 114:
            raise HTTPException(404, f"no such surah: {index}")
        return [
            schemas.VerseOut(id=v.id, surah=v.surah, ayah=v.ayah, ref=v.ref, text=v.text)
            for v in eng.quran.surah_verses(index)
        ]

    @app.post("/api/match", response_model=schemas.MatchResponse)
    def match(req: schemas.MatchRequest):
        tokens = eng.index.tokenizer(req.text)
        found = eng.matcher.match_tokens(tokens, k=req.k)
        return schemas.MatchResponse(tokens=tokens, candidates=[eng.candidate(m) for m in found])

    @app.post("/api/track", response_model=schemas.TrackResponse)
    def track(req: schemas.TrackRequest):
        tracker = eng.tracker(req.hint)
        return schemas.TrackResponse(states=[eng.state(tracker.update(c)) for c in req.chunks])

    @app.post("/api/simulate", response_model=schemas.SimulateResponse)
    def run_simulation(req: schemas.SimulateRequest):
        surah = eng.quran.surah(req.surah)
        to_ayah = min(req.to_ayah or surah.ayah_count, surah.ayah_count)
        if req.from_ayah > to_ayah:
            raise HTTPException(422, f"from_ayah {req.from_ayah} is after to_ayah {to_ayah}")
        first = eng.quran.verse(req.surah, req.from_ayah).id
        last = eng.quran.verse(req.surah, to_ayah).id
        if last - first > 300:
            raise HTTPException(422, "at most 300 ayahs per simulation")

        noise = replace(NoiseConfig.preset(req.noise), fatiha_every=req.fatiha_every)
        steps = simulate(eng.index, first, last, noise, seed=req.seed, skip_words=req.join_late)

        hint, told = None, None
        if req.hint == "surah":
            hint, told = schemas.Hint(surah=req.surah), f"Surah {surah.name_translit}"
        elif req.hint == "juz":
            juz = eng.quran.juz_of(first)
            hint, told = schemas.Hint(juz=juz), f"Juz {juz}"
        tracker = eng.tracker(hint)
        out: list[schemas.SimStep] = []
        predicted: list[int | None] = []
        for step in steps:
            state = tracker.update(step.text)
            predicted.append(state.verse_id)
            correct = None
            if step.truth_verse is not None:
                correct = state.verse_id is not None and evaluation.position_error(state.verse_id, step) <= 1
            out.append(
                schemas.SimStep(
                    text=step.text,
                    truth=eng.position(step.truth_verse),
                    heard=[eng.quran.by_id(v).ref for v in step.spoken],
                    state=eng.state(state),
                    correct=correct,
                )
            )
        report = evaluation.score(predicted, steps)
        return schemas.SimulateResponse(steps=out, report=schemas.Report(**report.to_dict()), told=told)

    app.mount("/static", StaticFiles(directory=STATIC), name="static")

    @app.get("/", include_in_schema=False)
    def playground():
        return FileResponse(STATIC / "index.html")

    return app


app = create_app()
