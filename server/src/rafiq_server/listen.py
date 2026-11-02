"""Live listening over a WebSocket: audio in, detected surah + ayah out.

Protocol (`/ws/listen?surah=55` or `?juz=30` for an optional hint):

    client -> server   binary frames: float32 little-endian PCM, 16 kHz, mono, any length
                       text {"type": "end"}: no more audio; flush and finish
    server -> client   {"type": "ready"}                 model loaded, start sending
                       {"type": "partial", ...HeardOut}  live preview while the imam is still reciting
                       {"type": "heard", ...HeardOut}    final transcript of a chunk + tracker state
                       {"type": "done"}                  after "end" has been processed
                       {"type": "error", "message"}      then the socket closes

The browser resamples to 16 kHz before sending, so the server never decodes
audio formats. Recognition runs in a worker thread, one call at a time per
connection. If it falls behind, all audio waiting in the queue is merged into
one feed, so the next result is about *now*, never a backlog of stale previews.
"""

from __future__ import annotations

import asyncio
import contextlib
import json

import numpy as np
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from rafiq.asr import EnergyVad, Heard, Listener, Segmenter

from rafiq_server import schemas

router = APIRouter()


@router.websocket("/ws/listen")
async def listen(ws: WebSocket, surah: int | None = None, juz: int | None = None) -> None:
    await ws.accept()
    eng = ws.app.state.engine
    if eng.transcriber is None:
        await ws.send_json(
            {"type": "error", "message": 'Speech recognition is not installed: pip install -e "engine[asr]"'}
        )
        await ws.close()
        return

    try:
        hint = schemas.Hint(surah=surah, juz=juz)
    except ValueError as e:
        await ws.send_json({"type": "error", "message": f"bad hint: {e}"})
        await ws.close()
        return

    # First connection loads the model (downloads it once, ~150 MB).
    if hasattr(eng.transcriber, "load"):
        await asyncio.to_thread(eng.transcriber.load)
    listener = Listener(Segmenter(EnergyVad()), eng.transcriber, eng.tracker(hint), eng.listener_config)
    await ws.send_json({"type": "ready"})

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

    async def worker() -> None:
        while True:
            samples = await queue.get()
            if samples is None:
                for h in await asyncio.to_thread(listener.flush):
                    await ws.send_json(heard_json(h))
                await ws.send_json({"type": "done"})
                return
            # Catch up: merge everything that arrived while we were busy.
            blocks, end = [samples], False
            while not queue.empty():
                nxt = queue.get_nowait()
                if nxt is None:
                    end = True
                    break
                blocks.append(nxt)
            merged = blocks[0] if len(blocks) == 1 else np.concatenate(blocks)
            for h in await asyncio.to_thread(listener.feed, merged):
                await ws.send_json(heard_json(h))
            if end:
                queue.put_nowait(None)

    task = asyncio.create_task(worker())
    try:
        while not task.done():
            msg = await ws.receive()
            if msg["type"] == "websocket.disconnect":
                break
            if msg.get("bytes"):
                queue.put_nowait(np.frombuffer(msg["bytes"], dtype="<f4").copy())
            elif msg.get("text"):
                with contextlib.suppress(json.JSONDecodeError):
                    if json.loads(msg["text"]).get("type") == "end":
                        queue.put_nowait(None)
                        await task
                        break
    except WebSocketDisconnect:
        pass
    finally:
        if not task.done():
            task.cancel()
