from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from rafiq_server.app import create_app


@pytest.fixture(scope="module")
def client() -> TestClient:
    return TestClient(create_app())


def test_health(client):
    body = client.get("/api/health").json()
    assert body["ok"] and body["verses"] == 6236


def test_surahs(client):
    surahs = client.get("/api/surahs").json()
    assert len(surahs) == 114
    assert surahs[92]["name_translit"] and surahs[92]["ayah_count"] == 11
    assert surahs[0]["has_basmala"] is False and surahs[1]["has_basmala"] is True


def test_surah_verses(client):
    verses = client.get("/api/surahs/93").json()
    assert [v["ref"] for v in verses[:2]] == ["93:1", "93:2"]
    assert client.get("/api/surahs/115").status_code == 404


def test_match(client):
    body = client.post("/api/match", json={"text": "والضحى والليل إذا سجى", "k": 3}).json()
    assert body["tokens"] == ["والضحي", "والليل", "اذا", "سجي"]
    best = body["candidates"][0]
    assert best["position"]["ref"] == "93:2" and best["first_ref"] == "93:1"
    assert best["score"] == 1.0


def test_track_replays_chunks(client):
    chunks = ["والضحى والليل إذا سجى", "ما ودعك ربك وما قلى"]
    states = client.post("/api/track", json={"chunks": chunks}).json()["states"]
    assert [s["position"]["ref"] for s in states] == ["93:2", "93:3"]
    assert states[-1]["status"] == "tracking"


def test_track_with_hint(client):
    chunks = ["فبأي آلاء ربكما تكذبان", "فبأي آلاء ربكما تكذبان"]
    states = client.post("/api/track", json={"chunks": chunks, "hint": {"surah": 55}}).json()["states"]
    pos = states[-1]["position"] or states[-1]["pending"]
    assert pos["surah"] == 55


def test_track_reports_alternatives(client):
    chunks = ["فاتقوا الله وأطيعون وما أسألكم عليه من أجر"]
    state = client.post("/api/track", json={"chunks": chunks}).json()["states"][0]
    assert {a["surah"] for a in state["alternatives"]} == {26}


def test_track_empty(client):
    assert client.post("/api/track", json={"chunks": []}).json()["states"] == []


def test_simulate(client):
    body = client.post(
        "/api/simulate", json={"surah": 93, "noise": "clean", "fatiha_every": 0, "seed": 1}
    ).json()
    assert body["report"]["acceptable"] >= 0.8  # a short surah: the cold-start blank weighs a lot
    assert body["report"]["wrong_jumps"] == 0
    last = body["steps"][-1]
    assert last["truth"]["ref"] == "93:11" and last["correct"] is True
    assert body["told"] is None and body["report"]["time_to_lock"] is not None


def test_simulate_with_hint_and_late_join(client):
    body = client.post(
        "/api/simulate", json={"surah": 78, "from_ayah": 10, "hint": "juz", "join_late": 4}
    ).json()
    assert body["told"] == "Juz 30"
    assert body["report"]["time_to_lock"] <= 3


@pytest.mark.parametrize(
    "payload",
    [
        {"surah": 115},
        {"surah": 93, "from_ayah": 10, "to_ayah": 2},
        {"surah": 93, "noise": "deafening"},
    ],
)
def test_simulate_validation(client, payload):
    assert client.post("/api/simulate", json=payload).status_code == 422


def test_playground_is_served(client):
    res = client.get("/")
    assert res.status_code == 200 and "Rafiq Playground" in res.text
