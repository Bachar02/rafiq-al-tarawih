"""Wire format. Kept separate from the engine's dataclasses on purpose: the
engine can rename or restructure internals without breaking the app, and the
app contract is readable in one place."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class SurahOut(BaseModel):
    index: int
    name_ar: str
    name_translit: str
    name_en: str
    ayah_count: int
    first_verse_id: int
    has_basmala: bool


class VerseOut(BaseModel):
    id: int
    surah: int
    ayah: int
    ref: str
    text: str


class Position(BaseModel):
    verse_id: int
    surah: int
    ayah: int
    ref: str


class Candidate(BaseModel):
    position: Position  # where the reciter is now (last matched word)
    first_ref: str  # first verse the match touches
    score: float
    matched_text: str  # the normalized stream words that aligned


class MatchRequest(BaseModel):
    text: str = Field(max_length=2000)
    k: int = Field(default=5, ge=1, le=20)


class MatchResponse(BaseModel):
    tokens: list[str]  # the query after normalization
    candidates: list[Candidate]


class StateOut(BaseModel):
    position: Position | None  # what the app shows: detected surah + ayah
    status: Literal["idle", "tracking", "uncertain", "lost"]
    confidence: float
    pending: Position | None  # a first guess or far jump awaiting confirmation
    alternatives: list[Position]  # other plausible positions when the text is ambiguous
    candidates: list[Candidate]


class Hint(BaseModel):
    """Optional help from the user. Detection works without it; at most one field."""

    surah: int | None = Field(default=None, ge=1, le=114)
    juz: int | None = Field(default=None, ge=1, le=30)


class TrackRequest(BaseModel):
    chunks: list[str] = Field(max_length=500)
    hint: Hint | None = None


class TrackResponse(BaseModel):
    states: list[StateOut]


class SimulateRequest(BaseModel):
    surah: int = Field(ge=1, le=114)
    from_ayah: int = Field(default=1, ge=1)
    to_ayah: int | None = Field(default=None, ge=1)
    noise: Literal["clean", "light", "heavy"] = "light"
    fatiha_every: int = Field(default=0, ge=0, le=100)
    seed: int = 0
    join_late: int = Field(default=0, ge=0, le=30)  # words missed before the app started listening
    hint: Literal["none", "surah", "juz"] = "none"  # what the app is told (default: nothing)


class SimStep(BaseModel):
    text: str  # what the simulated ASR "heard"
    truth: Position | None  # None for a noise chunk
    heard: list[str]  # refs of every verse in the chunk
    state: StateOut
    correct: bool | None  # displayed position acceptable? None for noise chunks


class Report(BaseModel):
    steps: int
    accuracy: float
    acceptable: float
    coverage: float
    mean_abs_error: float
    wrong_jumps: int
    mean_recovery: float
    unrecovered: bool
    time_to_lock: int | None  # chunks until the right surah + ayah was first shown
    first_shown_wrong: bool


class SimulateResponse(BaseModel):
    steps: list[SimStep]
    report: Report
    told: str | None  # the hint the app was given, in words; None = it had to find it alone
