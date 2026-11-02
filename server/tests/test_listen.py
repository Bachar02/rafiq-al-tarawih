"""/ws/listen end to end, with a scripted transcriber so no model is needed."""

from __future__ import annotations

import json

import numpy as np
from fastapi.testclient import TestClient
from rafiq.asr import ListenerConfig
from rafiq.matching import get_index

from rafiq_server.app import Engine, create_app

SR = 16_000


class ScriptedTranscriber:
    def __init__(self, lines: list[str]) -> None:
        self.lines = list(lines)

    def transcribe(self, audio) -> str:
        return self.lines.pop(0) if self.lines else ""


def tone(seconds: float) -> np.ndarray:
    t = np.arange(int(seconds * SR)) / SR
    return (0.3 * np.sin(2 * np.pi * 220 * t)).astype("<f4")


def silence(seconds: float) -> np.ndarray:
    return np.zeros(int(seconds * SR), dtype="<f4")


def client_with(lines: list[str]) -> TestClient:
    """Finals only: a scripted transcriber has one line per final chunk."""
    eng = Engine(
        get_index(), transcriber=ScriptedTranscriber(lines), listener_config=ListenerConfig(partial_every_s=0)
    )
    return TestClient(create_app(eng))


class ConstantTranscriber:
    def transcribe(self, audio) -> str:
        return "والضحى والليل إذا سجى"


def run(ws, audio: np.ndarray) -> list[dict]:
    assert ws.receive_json() == {"type": "ready"}
    for i in range(0, len(audio), 4000):  # 250 ms frames, like the browser
        ws.send_bytes(audio[i : i + 4000].tobytes())
    ws.send_text(json.dumps({"type": "end"}))
    messages = []
    while (msg := ws.receive_json())["type"] != "done":
        messages.append(msg)
    return messages


def test_listen_detects_surah_and_ayah_from_audio():
    client = client_with(["والضحى والليل إذا سجى", "ما ودعك ربك وما قلى"])
    audio = np.concatenate([tone(2.0), silence(0.6), tone(2.0), silence(0.6)])
    with client.websocket_connect("/ws/listen") as ws:
        heard = run(ws, audio)
    finals = [m for m in heard if m["type"] == "heard"]
    assert len(finals) == 2
    assert finals[-1]["state"]["position"]["ref"] == "93:3"
    assert finals[0]["start"] < finals[0]["end"] <= finals[1]["start"]


def test_listen_accepts_a_hint():
    client = client_with(["فبأي آلاء ربكما تكذبان", "فبأي آلاء ربكما تكذبان"])
    audio = np.concatenate([tone(2.0), silence(0.6), tone(2.0), silence(0.6)])
    with client.websocket_connect("/ws/listen?surah=55") as ws:
        heard = run(ws, audio)
    state = [m for m in heard if m["type"] == "heard"][-1]["state"]
    assert (state["position"] or state["pending"])["surah"] == 55


def test_listen_sends_live_partials_before_the_final():
    client = TestClient(create_app(Engine(get_index(), transcriber=ConstantTranscriber())))
    with client.websocket_connect("/ws/listen") as ws:
        msgs = run(ws, np.concatenate([tone(4.0), silence(0.6)]))
    types = [m["type"] for m in msgs]
    assert types[0] == "partial" and types[-1] == "heard"
    assert types.count("partial") >= 3  # ~every 0.5 s of a 4 s breath
    assert msgs[0]["state"]["position"]["ref"] == "93:2"  # the screen moves before the pause


def test_listen_without_asr_reports_error():
    app = create_app(Engine(get_index(), transcriber=None))
    app.state.engine.transcriber = None  # force "not installed" even if the extra is present
    with TestClient(app).websocket_connect("/ws/listen") as ws:
        msg = ws.receive_json()
    assert msg["type"] == "error" and "engine[asr]" in msg["message"]
