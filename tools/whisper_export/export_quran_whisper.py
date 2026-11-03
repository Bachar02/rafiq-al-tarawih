"""Export the Quran Whisper model for on-device recognition (sherpa-onnx).

    .venv-export/Scripts/python tools/whisper_export/export_quran_whisper.py

Pipeline:
1. Download Tarteel's whisper-{base,tiny}-ar-quran (Apache-2.0) at a pinned revision.
2. Convert the Hugging Face checkpoint to OpenAI's whisper layout (same
   architecture, different parameter names).
3. Run sherpa-onnx's own export script on it: encoder/decoder ONNX (+ int8),
   tokens. sherpa-onnx's export drops Whisper's fixed 30 s window, so a short
   chunk costs proportionally less — the property on-device latency needs.

Output: build/whisper_onnx/quran-<size>-{encoder,decoder}[.int8].onnx, quran-<size>-tokens.txt
Heavy dependencies (torch, openai-whisper) live in .venv-export only.
"""

from __future__ import annotations

import argparse
import os
import runpy
import shutil
import sys
from pathlib import Path

import torch
import whisper
from huggingface_hub import hf_hub_download
from whisper.model import ModelDimensions

# Tarteel's Quran fine-tunes (Apache-2.0), pinned: the export must be reproducible.
MODELS = {
    "base": ("tarteel-ai/whisper-base-ar-quran", "5c3c53fdf9272c4f6ee0bee09a1e5a4a615ee25c"),
    "tiny": ("tarteel-ai/whisper-tiny-ar-quran", "c3d7e624af5c81bef25a10a2af3a5a84cb4dd0f0"),
}
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "whisper_onnx"


def hf_to_openai(state: dict[str, torch.Tensor]) -> dict[str, torch.Tensor]:
    """Rename Hugging Face Whisper parameters to OpenAI whisper's names."""
    out: dict[str, torch.Tensor] = {}
    for key, value in state.items():
        if key == "proj_out.weight":  # tied to the token embedding in OpenAI's layout
            continue
        k = key.removeprefix("model.")
        k = k.replace("encoder.embed_positions.weight", "encoder.positional_embedding")
        k = k.replace("decoder.embed_positions.weight", "decoder.positional_embedding")
        k = k.replace("decoder.embed_tokens", "decoder.token_embedding")
        k = k.replace("encoder.layer_norm", "encoder.ln_post")
        k = k.replace("decoder.layer_norm", "decoder.ln")
        k = k.replace(".layers.", ".blocks.")
        k = k.replace(".self_attn_layer_norm", ".attn_ln")
        k = k.replace(".encoder_attn_layer_norm", ".cross_attn_ln")
        k = k.replace(".final_layer_norm", ".mlp_ln")
        k = k.replace(".self_attn.", ".attn.")
        k = k.replace(".encoder_attn.", ".cross_attn.")
        k = k.replace(".q_proj", ".query").replace(".k_proj", ".key").replace(".v_proj", ".value")
        k = k.replace(".out_proj", ".out")
        k = k.replace(".fc1", ".mlp.0").replace(".fc2", ".mlp.2")
        out[k] = value
    return out


def build_checkpoint(size: str) -> Path:
    repo, revision = MODELS[size]
    import json

    config = json.loads(Path(hf_hub_download(repo, "config.json", revision=revision)).read_text())
    weights = torch.load(hf_hub_download(repo, "pytorch_model.bin", revision=revision), map_location="cpu")
    dims = ModelDimensions(
        n_mels=config["num_mel_bins"],
        n_audio_ctx=config["max_source_positions"],
        n_audio_state=config["d_model"],
        n_audio_head=config["encoder_attention_heads"],
        n_audio_layer=config["encoder_layers"],
        n_vocab=config["vocab_size"],
        n_text_ctx=config["max_target_positions"],
        n_text_state=config["d_model"],
        n_text_head=config["decoder_attention_heads"],
        n_text_layer=config["decoder_layers"],
    )
    state = hf_to_openai(weights)
    model = whisper.model.Whisper(dims)
    missing, unexpected = model.load_state_dict(state, strict=False)
    # alignment_heads is a buffer OpenAI sets separately; nothing else may be missing.
    missing = [m for m in missing if m != "alignment_heads"]
    if missing or unexpected:
        raise SystemExit(f"weight mapping failed: missing={missing} unexpected={unexpected}")
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"quran-{size}.pt"
    torch.save({"dims": dims.__dict__, "model_state_dict": model.state_dict()}, path)
    print(f"converted checkpoint: {path}")
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", choices=sorted(MODELS), default="base")
    args = ap.parse_args()

    checkpoint = build_checkpoint(args.model)

    # sherpa-onnx's script was written for torch's classic (TorchScript) ONNX
    # exporter; recent torch defaults to the dynamo exporter, which handles its
    # dynamic axes and KV caches differently. Ask for the classic one.
    original_export = torch.onnx.export
    torch.onnx.export = lambda *a, **k: original_export(*a, **{"dynamo": False, **k})

    # sherpa-onnx's script loads a model by name; serve ours under its size's name.
    original_load = whisper.load_model
    whisper.load_model = lambda name, *a, **k: original_load(str(checkpoint), *a, **k)
    cwd = Path.cwd()
    os.chdir(OUT)
    sys.argv = ["sherpa_export_onnx.py", "--model", args.model]
    try:
        runpy.run_path(str(Path(__file__).with_name("sherpa_export_onnx.py")), run_name="__main__")
    finally:
        os.chdir(cwd)
        whisper.load_model = original_load
        torch.onnx.export = original_export

    for f in OUT.glob(f"{args.model}-*"):
        target = OUT / f.name.replace(f"{args.model}-", f"quran-{args.model}-", 1)
        shutil.move(f, target)
    for f in sorted(OUT.glob(f"quran-{args.model}-*")):
        print(f"{f.name:<36} {f.stat().st_size / 1e6:7.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
