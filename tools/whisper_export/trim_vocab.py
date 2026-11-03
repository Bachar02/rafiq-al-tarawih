"""Shrink the exported decoder to the vocabulary Quran recitation needs.

Whisper's decoder ends with a 51,865-entry vocabulary projection kept in fp32
(the int8 export quantizes MatMuls but this table is shared with the token
embedding, so it stays full precision). For every token decoded, the phone
reads all ~106 MB of it, and memory bandwidth is what a budget phone lacks.
Quran transcripts use only a few thousand of those tokens.

This keeps:
  * every token needed to write the Quran (Tanzil Uthmani, Simple Clean, and
    the diacritized "simple" text whose style the model actually outputs),
  * every token the model produced in our recorded benchmark runs,
  * all 256 single-byte tokens, so *any* text stays spellable (just in more
    tokens), and the special tokens (start, language, task, end...).
Then it slices the table, renumbers tokens.txt, and remaps every token id in
the model metadata, and re-quantizes to int8.

    .venv-export/Scripts/python tools/whisper_export/trim_vocab.py --model base
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
import urllib.request
from pathlib import Path

import numpy as np
import onnx
import whisper
from onnx import numpy_helper
from onnxruntime.quantization import QuantType, quantize_dynamic

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build" / "whisper_onnx"
VOCAB = ROOT / "build" / "vocab"
TANZIL_SIMPLE = (
    "https://tanzil.net/pub/download/index.php?marks=true&sajdah=true&rub=false&tatweel=false"
    "&quranType=simple&outType=txt-2&agree=true"
)
N_REGULAR = 50257  # Whisper multilingual: regular tokens are 0..50256, specials follow
FIRST_TIMESTAMP = 50364  # timestamps are never produced with no_timestamps; dropped


def quran_lines() -> list[str]:
    simple = VOCAB / "quran-simple.txt"
    if not simple.exists():
        VOCAB.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(TANZIL_SIMPLE, simple)
    lines = []
    raw = ROOT / "data" / "raw"
    for path in (simple, raw / "quran-uthmani.txt", raw / "quran-simple-clean.txt"):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line and not line.startswith("#"):
                lines.append(line.split("|", 2)[2])
    return lines


def model_outputs() -> list[str]:
    """What the model really wrote on our benchmark audio."""
    texts = []
    for rec in (ROOT / "eval" / "results" / "transcripts").glob("*.json"):
        texts += [e["text"] for e in json.loads(rec.read_text(encoding="utf-8"))["events"] if e["text"]]
    clips = BUILD / "clips.json"
    if clips.exists():
        texts += [c["server_text"] for c in json.loads(clips.read_text(encoding="utf-8"))]
    return texts


def kept_regular_tokens() -> list[int]:
    tok = whisper.tokenizer.get_tokenizer(multilingual=True)
    keep = set(range(256))  # single bytes: anything stays spellable
    texts = quran_lines() + model_outputs()
    for text in texts:
        keep.update(tok.encode(text))
        keep.update(tok.encode(" " + text))
        for word in text.split():  # BPE merges depend on the leading space
            keep.update(tok.encode(word))
            keep.update(tok.encode(" " + word))
    regular = sorted(t for t in keep if t < N_REGULAR)
    print(f"corpus: {len(texts)} lines -> keeping {len(regular)} of {N_REGULAR} regular tokens")
    return regular


def trim(size: str) -> None:
    regular = kept_regular_tokens()
    specials = list(range(N_REGULAR, FIRST_TIMESTAMP))
    old_ids = regular + specials
    new_id = {old: new for new, old in enumerate(old_ids)}
    n_vocab = len(old_ids)

    # Decoder: slice the shared vocabulary table (rows of the embedding, or
    # columns of a pre-transposed projection).
    decoder = onnx.load(BUILD / f"quran-{size}-decoder.onnx")
    index = np.array(old_ids, dtype=np.int64)
    sliced = 0
    for init in decoder.graph.initializer:
        arr = numpy_helper.to_array(init)
        if arr.ndim == 2 and arr.shape[0] == 51865:
            init.CopyFrom(numpy_helper.from_array(arr[index], init.name))
            sliced += 1
        elif arr.ndim == 2 and arr.shape[1] == 51865:
            init.CopyFrom(numpy_helper.from_array(arr[:, index], init.name))
            sliced += 1
    if not sliced:
        raise SystemExit("no vocabulary-sized initializer found in the decoder")
    # Output shape metadata may pin the vocab size; relax it.
    for out in decoder.graph.output:
        for dim in out.type.tensor_type.shape.dim:
            if dim.dim_value == 51865:
                dim.dim_value = n_vocab
    trimmed_decoder = BUILD / f"quran-{size}trim-decoder.onnx"
    onnx.save(decoder, trimmed_decoder)

    # Encoder: unchanged weights, but sherpa-onnx reads token ids from its metadata.
    encoder = onnx.load(BUILD / f"quran-{size}-encoder.onnx")
    remapped = 0
    for prop in encoder.metadata_props:
        key, value = prop.key, prop.value
        if key == "n_vocab":
            prop.value = str(n_vocab)
        elif key in {"sot", "eot", "blank_id", "translate", "transcribe", "no_timestamps", "no_speech",
                     "sot_prev", "sot_lm"}:  # fmt: skip
            prop.value = str(new_id[int(value)])
            remapped += 1
        elif key in {"sot_sequence", "all_language_tokens"}:
            prop.value = ",".join(str(new_id[int(v)]) for v in value.split(","))
            remapped += 1
        elif key == "non_speech_tokens":
            prop.value = ",".join(str(new_id[int(v)]) for v in value.split(",") if int(v) in new_id)
            remapped += 1
    onnx.save(encoder, BUILD / f"quran-{size}trim-encoder.onnx")

    # tokens.txt: regular tokens only (base64 bytes + new id), like the original.
    ranks = {}
    tiktoken_file = Path(whisper.__file__).parent / "assets" / "multilingual.tiktoken"
    for line in tiktoken_file.read_text().splitlines():
        if line:
            b64, rank = line.split()
            ranks[int(rank)] = b64
    with open(BUILD / f"quran-{size}trim-tokens.txt", "w") as f:
        for old in regular:
            f.write(f"{ranks[old]} {new_id[old]}\n")
    assert base64.b64decode(ranks[regular[-1]])  # sanity: valid base64

    for part in ("encoder", "decoder"):
        quantize_dynamic(
            model_input=BUILD / f"quran-{size}trim-{part}.onnx",
            model_output=BUILD / f"quran-{size}trim-{part}.int8.onnx",
            op_types_to_quantize=["MatMul"],
            weight_type=QuantType.QInt8,
        )
    print(f"vocab {51865} -> {n_vocab}; {sliced} table(s) sliced; {remapped} metadata keys remapped")
    for f in sorted(BUILD.glob(f"quran-{size}trim-*")):
        print(f"  {f.name:<38} {f.stat().st_size / 1e6:7.1f} MB")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="base", choices=["base", "tiny"])
    args = ap.parse_args()
    trim(args.model)
    return 0


if __name__ == "__main__":
    sys.exit(main())
