"""Recitations for testing on-device recognition on a phone or the emulator.

Builds a few streams from EveryAyah recordings (several reciters, a clean
room, a mosque and the back of a mosque), each starting a little late, and
writes them as 16 kHz mono PCM16 WAV files with their timelines. The app's
integration test (mobile/integration_test/ondevice_test.dart) replays them in
real time through the on-device engine, with the real speech model, and scores
the result the way eval/audio_bench.py scores the server.

    py eval/phone_streams.py                    # -> eval/results/phone_streams/
    adb push eval/results/phone_streams/. /sdcard/Android/data/app.rafiq.rafiq/files/streams/

The audio stays out of git (EveryAyah's recordings are theirs); this script
rebuilds it.
"""

from __future__ import annotations

import json
import sys
import wave
from pathlib import Path

import numpy as np
from audio_bench import ROOMS
from audiolib import build_stream, degrade
from rafiq.asr import SAMPLE_RATE
from rafiq.quran import get_quran

OUT = Path(__file__).resolve().parent / "results" / "phone_streams"

# (name, reciter, [(surah, first ayah, last ayah)...], room, seconds missed at the start)
STREAMS = [
    ("alafasy-duha-clean", "Alafasy_128kbps", [(93, 1, 11)], "clean", 1.2),
    ("alafasy-fatiha-kahf-mosque", "Alafasy_128kbps", [(1, 1, 7), (18, 1, 6)], "mosque", 0.8),
    ("husary-hajj-mosque", "Husary_128kbps", [(22, 30, 33)], "mosque", 1.5),
    ("sudais-araf-far", "Abdurrahmaan_As-Sudais_192kbps", [(7, 29, 32)], "far", 2.0),
]


def main() -> int:
    q = get_quran()
    OUT.mkdir(parents=True, exist_ok=True)
    index = []
    for seed, (name, reciter, ranges, room, join) in enumerate(STREAMS):
        verse_ids = [q.verse(s, a).id for s, first, last in ranges for a in range(first, last + 1)]
        audio, timeline = build_stream(q, reciter, verse_ids)
        audio = degrade(audio, ROOMS[room], seed=seed)
        clip = audio[int(join * SAMPLE_RATE) :]
        pcm = (np.clip(clip, -1, 1) * 32767).astype("<i2")
        with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SAMPLE_RATE)
            w.writeframes(pcm.tobytes())
        index.append(
            {
                "name": name,
                "reciter": reciter,
                "room": room,
                "join": join,
                "seconds": round(len(clip) / SAMPLE_RATE, 2),
                "timeline": [[round(s, 3), round(e, 3), v] for s, e, v in timeline],
            }
        )
        print(f"{name}: {len(clip) / SAMPLE_RATE:.1f} s, {len(verse_ids)} ayahs")
    (OUT / "streams.json").write_bytes((json.dumps(index, indent=1) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
