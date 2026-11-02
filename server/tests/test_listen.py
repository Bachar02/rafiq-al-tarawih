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
    assert ws.receive_json()["type"] == "ready"
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


# -- robustness: a bad client or a failing model must never hang a session ----


def finals_client(transcriber) -> TestClient:
    eng = Engine(get_index(), transcriber=transcriber, listener_config=ListenerConfig(partial_every_s=0))
    return TestClient(create_app(eng))


def drain(ws) -> list[dict]:
    messages = []
    while (msg := ws.receive_json())["type"] not in ("done", "error"):
        messages.append(msg)
    return [*messages, msg]


def test_malformed_frame_is_a_warning_not_a_crash():
    client = finals_client(ScriptedTranscriber(["والضحى والليل إذا سجى"]))
    with client.websocket_connect("/ws/listen") as ws:
        assert ws.receive_json()["type"] == "ready"
        ws.send_bytes(b"\x00\x01\x02")  # 3 bytes: not float32
        audio = np.concatenate([tone(2.0), silence(0.6)])
        for i in range(0, len(audio), 4000):
            ws.send_bytes(audio[i : i + 4000].tobytes())
        ws.send_text(json.dumps({"type": "end"}))
        msgs = drain(ws)
    assert msgs[0]["type"] == "warning" and "float32" in msgs[0]["message"]
    assert [m["type"] for m in msgs[1:]] == ["heard", "done"]


def test_nan_and_out_of_range_samples_are_repaired():
    client = finals_client(ScriptedTranscriber(["والضحى والليل إذا سجى"]))
    audio = np.concatenate([tone(2.0), silence(0.6)])
    audio[100:200] = np.nan
    audio[300:400] = 50.0
    with client.websocket_connect("/ws/listen") as ws:
        msgs = run(ws, audio)
    assert [m["type"] for m in msgs] == ["heard"]


def test_oversized_frame_is_rejected():
    client = finals_client(ScriptedTranscriber([]))
    with client.websocket_connect("/ws/listen") as ws:
        assert ws.receive_json()["type"] == "ready"
        ws.send_bytes(silence(12.0).tobytes())
        msg = ws.receive_json()
    assert msg["type"] == "warning" and "longer than" in msg["message"]


class BrokenTranscriber:
    def transcribe(self, audio) -> str:
        raise RuntimeError("GPU fell off the bus")


def test_transcriber_failure_reaches_the_client():
    client = finals_client(BrokenTranscriber())
    with client.websocket_connect("/ws/listen") as ws:
        assert ws.receive_json()["type"] == "ready"
        audio = np.concatenate([tone(2.0), silence(0.6)])
        for i in range(0, len(audio), 4000):
            ws.send_bytes(audio[i : i + 4000].tobytes())
        msg = ws.receive_json()
    assert msg["type"] == "error" and "GPU fell off the bus" in msg["message"]


class UnloadableTranscriber:
    def load(self) -> None:
        raise OSError("no internet to download the model")

    def transcribe(self, audio) -> str:
        return ""


def test_model_load_failure_reaches_the_client():
    with finals_client(UnloadableTranscriber()).websocket_connect("/ws/listen") as ws:
        msg = ws.receive_json()
    assert msg["type"] == "error" and "no internet" in msg["message"]


def test_backlog_keeps_only_the_newest_audio():
    import asyncio

    from rafiq_server.listen import MAX_BACKLOG_S, take_backlog

    queue: asyncio.Queue = asyncio.Queue()
    for _ in range(40):  # 40 s waiting behind the current block
        queue.put_nowait(silence(1.0))
    queue.put_nowait(None)
    audio, dropped, end = take_backlog(silence(1.0), queue)
    assert len(audio) == MAX_BACKLOG_S * SR
    assert dropped == (41 - MAX_BACKLOG_S) * SR
    assert end
