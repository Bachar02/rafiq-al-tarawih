"""Live listening over a WebSocket: audio in, detected surah + ayah out.

Protocol (`/ws/listen?surah=55` or `?juz=30` for an optional hint):

    client -> server   binary frames: float32 little-endian PCM, 16 kHz, mono, any length
                       text {"type": "end"}: no more audio; flush and finish
    server -> client   {"type": "ready", "device"}           model loaded, start sending
                       {"type": "partial", ...HeardOut}      live preview while the imam is still reciting
                       {"type": "heard", ...HeardOut}        final transcript of a chunk + tracker state
                       {"type": "warning", "message"}        something was skipped; the session goes on
                       {"type": "done"}                      after "end" has been processed
                       {"type": "error", "message"}          unrecoverable; the socket then closes

The browser resamples to 16 kHz before sending, so the server never decodes
audio formats. Recognition runs in a worker thread, one call at a time per
connection. If it falls behind, all audio waiting in the queue is merged into
one feed, so the next result is about *now*; if even that exceeds
`MAX_BACKLOG_S`, the oldest audio is dropped. Bad input from a client (a
malformed frame, NaNs) is repaired or skipped with a warning, never fatal.
"""

from __future__ import annotations

import asyncio
import json
import logging

import numpy as np
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from rafiq.asr import SAMPLE_RATE, EnergyVad, Heard, Listener, Segmenter

from rafiq_server import schemas

log = logging.getLogger("rafiq.listen")
router = APIRouter()

MAX_FRAME_S = 10.0  # one frame longer than this is a client bug, not a microphone
MAX_BACKLOG_S = 15.0  # audio waiting longer than this is dropped, oldest first


def decode_frame(data: bytes) -> np.ndarray:
    """Client bytes -> clean samples. Raises ValueError with a client-readable reason."""
    if len(data) % 4:
        raise ValueError(f"frame of {len(data)} bytes is not float32 PCM (length must be a multiple of 4)")
    if len(data) // 4 > MAX_FRAME_S * SAMPLE_RATE:
        raise ValueError(f"frame longer than {MAX_FRAME_S:.0f} s; send audio in small blocks")
    samples = np.frombuffer(data, dtype="<f4").copy()
    if not np.isfinite(samples).all():
        samples = np.nan_to_num(samples, nan=0.0, posinf=0.0, neginf=0.0)
    return np.clip(samples, -1.0, 1.0, out=samples)


def take_backlog(first: np.ndarray, queue: asyncio.Queue) -> tuple[np.ndarray, int, bool]:
    """Merge everything queued behind `first`; keep at most MAX_BACKLOG_S of the newest.

    Returns (audio to feed, samples dropped, end-of-stream seen).
    """
    blocks, end = [first], False
    while not queue.empty():
        nxt = queue.get_nowait()
        if nxt is None:
            end = True
            break
        blocks.append(nxt)
    merged = blocks[0] if len(blocks) == 1 else np.concatenate(blocks)
    limit = int(MAX_BACKLOG_S * SAMPLE_RATE)
    if len(merged) > limit:
        return merged[-limit:], len(merged) - limit, end
    return merged, 0, end


async def close_with_error(ws: WebSocket, message: str) -> None:
    try:
        await ws.send_json({"type": "error", "message": message})
        await ws.close()
    except (WebSocketDisconnect, RuntimeError):
        pass  # the client is already gone


@router.websocket("/ws/listen")
async def listen(ws: WebSocket, surah: int | None = None, juz: int | None = None) -> None:
    await ws.accept()
    eng = ws.app.state.engine
    if eng.transcriber is None:
        await close_with_error(ws, 'Speech recognition is not installed: pip install -e "engine[asr]"')
        return
    try:
        hint = schemas.Hint(surah=surah, juz=juz)
    except ValueError as e:
        await close_with_error(ws, f"bad hint: {e}")
        return

    # The first connection loads the model (downloading it once, ~150 MB).
    try:
        if hasattr(eng.transcriber, "load"):
            await asyncio.to_thread(eng.transcriber.load)
    except Exception as e:
        log.exception("ASR model failed to load")
        await close_with_error(ws, f"could not load the speech model: {e}")
        return

    listener = Listener(Segmenter(EnergyVad()), eng.transcriber, eng.tracker(hint), eng.listener_config)
    await ws.send_json({"type": "ready", "device": getattr(eng.transcriber, "active_device", None)})
    queue: asyncio.Queue[np.ndarray | None] = asyncio.Queue()

    def heard_json(h: Heard) -> dict:
        out = schemas.HeardOut(
            type="heard" if h.final else "partial",
            text=h.text,
            start=round(h.start, 2),
            end=round(h.end, 2),
            asr_ms=h.asr_ms,
            state=eng.state(h.state),
        )
        return out.model_dump()

    async def send(payload: dict) -> bool:
        """False if the client has gone (Starlette raises on a closed socket)."""
        try:
            await ws.send_json(payload)
            return True
        except (WebSocketDisconnect, RuntimeError):
            return False

    async def run(fn, *args) -> list[Heard] | None:
        """Recognition in a worker thread. A failure there is reported, not swallowed."""
        try:
            return await asyncio.to_thread(fn, *args)
        except Exception as e:
            log.exception("listener failed")
            await close_with_error(ws, f"recognition failed: {e}")
            return None

    async def worker() -> None:
        while True:
            first = await queue.get()
            if first is None:
                events = await run(listener.flush)
                if events is not None and all([await send(heard_json(h)) for h in events]):
                    await send({"type": "done"})
                return
            audio, dropped, end = take_backlog(first, queue)
            if dropped:
                listener.skip(dropped)
                skipped = f"fell behind: skipped {dropped / SAMPLE_RATE:.1f} s of audio"
                if not await send({"type": "warning", "message": skipped}):
                    return
            events = await run(listener.feed, audio)
            if events is None:
                return
            for h in events:
                if not await send(heard_json(h)):
                    return
            if end:
                queue.put_nowait(None)

    task = asyncio.create_task(worker())
    try:
        while not task.done():
            msg = await ws.receive()
            if msg["type"] == "websocket.disconnect":
                break
            if msg.get("bytes") is not None:
                try:
                    queue.put_nowait(decode_frame(msg["bytes"]))
                except ValueError as e:
                    await ws.send_json({"type": "warning", "message": str(e)})
            elif msg.get("text"):
                try:
                    kind = json.loads(msg["text"]).get("type")
                except (json.JSONDecodeError, AttributeError):
                    kind = None
                if kind == "end":
                    queue.put_nowait(None)
                    await task
                    break
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        if not task.done():
            task.cancel()
