"""Stage 1 of the on-device validation (main .venv): fixed clips + reference transcripts.

Writes build/whisper_onnx/clips/*.wav (16 kHz mono) and clips.json with, per
clip, the true verse and what the current server model (faster-whisper)
hears. validate_onnx.py (run in .venv-export) then transcribes the very same
audio with the ONNX model, so the comparison is apples to apples.

    .venv/Scripts/python tools/whisper_export/prepare_clips.py
"""

from __future__ import annotations

import json
import sys
import time
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "eval"))

from audiolib import Room, degrade, fetch  # noqa: E402
from rafiq.asr import SAMPLE_RATE, WhisperTranscriber, load_audio  # noqa: E402
from rafiq.matching import get_index  # noqa: E402

OUT = ROOT / "build" / "whisper_onnx" / "clips"

# (reciter, surah, ayah): varied tempo and length, short to long ayahs.
CLIPS = [
    ("Alafasy_128kbps", 93, 2),
    ("Alafasy_128kbps", 78, 1),
    ("Alafasy_128kbps", 18, 1),
    ("Alafasy_128kbps", 55, 13),
    ("Husary_128kbps", 93, 1),
    ("Husary_128kbps", 78, 1),
    ("Abdurrahmaan_As-Sudais_192kbps", 78, 1),
    ("Abdurrahmaan_As-Sudais_192kbps", 93, 1),
    ("Minshawy_Murattal_128kbps", 7, 29),
    ("Saood_ash-Shuraym_128kbps", 7, 30),
    ("MaherAlMuaiqly128kbps", 7, 31),
]
MOSQUE = Room(rt60=1.5, drr_db=3, snr_db=20)


def write_wav(path: Path, audio: np.ndarray) -> None:
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm.tobytes())


def main() -> int:
    q = get_index().quran
    OUT.mkdir(parents=True, exist_ok=True)
    asr = WhisperTranscriber(device="cpu")  # CPU: the honest comparison for a phone
    asr.load()
    rows = []
    for reciter, surah, ayah in CLIPS:
        clean = load_audio(fetch(reciter, surah, ayah))
        for room_name, audio in (("clean", clean), ("mosque", degrade(clean, MOSQUE, seed=1))):
            name = f"{reciter.split('_')[0]}_{surah:03d}{ayah:03d}_{room_name}"
            write_wav(OUT / f"{name}.wav", audio)
            t = time.perf_counter()
            text = asr.transcribe(audio)
            ms = (time.perf_counter() - t) * 1000
            rows.append({
                "name": name,
                "verse_id": q.verse(surah, ayah).id,
                "ref": f"{surah}:{ayah}",
                "room": room_name,
                "seconds": round(len(audio) / SAMPLE_RATE, 2),
                "server_text": text,
                "server_ms": round(ms),
            })
            print(f"{name:<34} {rows[-1]['seconds']:5.1f}s  {ms:6.0f} ms  {text}")
    (OUT.parent / "clips.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(rows)} clips -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
