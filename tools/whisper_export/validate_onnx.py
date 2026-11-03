"""Stage 2 of the on-device validation (.venv-export): ONNX model vs the server model.

Transcribes the clips written by prepare_clips.py with sherpa-onnx (the
runtime the app will use), in fp32 and int8 and with 1/2/4 threads, and
reports per variant:
  * word accuracy against the true ayah text (both models, same audio),
  * whether the matcher finds the right ayah from the transcript,
  * time per clip. Laptop CPU cores are ~2-3x faster than a phone's big
    cores, so these are a floor; the phone benchmark in the app is the real test.

    .venv-export/Scripts/python tools/whisper_export/validate_onnx.py
"""

from __future__ import annotations

import json
import statistics
import sys
import time
import wave
from pathlib import Path

import numpy as np
import sherpa_onnx
from rafiq.matching import Matcher, get_index
from rafiq.normalize import tokenize
from rapidfuzz.distance import Levenshtein

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "whisper_onnx"


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path)) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768.0


def word_accuracy(hyp: str, ref: str) -> float:
    h, r = tokenize(hyp), tokenize(ref)
    return max(0.0, 1 - Levenshtein.distance(h, r) / max(len(r), 1))


def recognizer(precision: str, threads: int) -> sherpa_onnx.OfflineRecognizer:
    suffix = ".int8.onnx" if precision == "int8" else ".onnx"
    return sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=str(BUILD / f"quran-base-encoder{suffix}"),
        decoder=str(BUILD / f"quran-base-decoder{suffix}"),
        tokens=str(BUILD / "quran-base-tokens.txt"),
        language="ar",
        task="transcribe",
        num_threads=threads,
    )


SILENCE_PAD_S = 2.0  # without trailing silence the model drops the last word(s); see README


def transcribe(rec: sherpa_onnx.OfflineRecognizer, audio: np.ndarray) -> tuple[str, float]:
    t = time.perf_counter()
    stream = rec.create_stream()
    stream.accept_waveform(16000, np.concatenate([audio, np.zeros(int(SILENCE_PAD_S * 16000), np.float32)]))
    rec.decode_stream(stream)
    return stream.result.text.strip(), (time.perf_counter() - t) * 1000


def main() -> int:
    clips = json.loads((BUILD / "clips.json").read_text(encoding="utf-8"))
    index = get_index()
    matcher = Matcher(index)
    q = index.quran

    def found(text: str, verse_id: int) -> bool:
        matches = matcher.match(text, k=1)
        return bool(matches) and matches[0].first_verse <= verse_id <= matches[0].last_verse

    server_acc = statistics.fmean(word_accuracy(c["server_text"], q.by_id(c["verse_id"]).text) for c in clips)
    server_found = sum(found(c["server_text"], c["verse_id"]) for c in clips)
    server_ms = statistics.median(c["server_ms"] for c in clips)
    print(f"{'variant':<16} {'word acc':>8} {'ayah found':>10} {'median ms':>9} {'ms per audio s':>14}")
    found_col = f"{server_found:>6}/{len(clips):<3}"
    print(f"{'server (CT2 cpu)':<16} {server_acc:>8.1%} {found_col} {server_ms:>9.0f} {'(fixed 30 s)':>14}")

    detail = {}
    for precision in ("fp32", "int8"):
        for threads in (1, 2, 4):
            rec = recognizer(precision, threads)
            transcribe(rec, np.zeros(16000, dtype=np.float32))  # warm-up
            accs, hits, times, per_sec = [], 0, [], []
            for c in clips:
                audio = read_wav(BUILD / "clips" / f"{c['name']}.wav")
                text, ms = transcribe(rec, audio)
                accs.append(word_accuracy(text, q.by_id(c["verse_id"]).text))
                hits += found(text, c["verse_id"])
                times.append(ms)
                per_sec.append(ms / c["seconds"])
                detail.setdefault(c["name"], {})[f"{precision}-{threads}t"] = (text, round(ms))
            label = f"{precision} {threads} thr"
            found_col = f"{hits:>6}/{len(clips):<3}"
            timing = f"{statistics.median(times):>9.0f} {statistics.median(per_sec):>14.0f}"
            print(f"{label:<16} {statistics.fmean(accs):>8.1%} {found_col} {timing}")

    print("\nper clip (int8, 2 threads vs server):")
    for c in clips:
        text, ms = detail[c["name"]]["int8-2t"]
        mark = "" if tokenize(text) == tokenize(c["server_text"]) else "   <- differs"
        print(f"  {c['name']:<34} {ms:>5} ms | {text}{mark}")
        if mark:
            print(f"  {'':<34} {'server':>8} | {c['server_text']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
