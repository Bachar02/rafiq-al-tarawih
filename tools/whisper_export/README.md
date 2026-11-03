# On-device speech model export (Phase 6)

Turns the server's Quran speech model into files the phone can run with
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), and checks they are as good.

```bash
py -m venv .venv-export                         # heavy, export-only deps (torch etc.)
.venv-export/Scripts/python -m pip install torch --index-url https://download.pytorch.org/whl/cpu
.venv-export/Scripts/python -m pip install openai-whisper onnx onnxscript onnxruntime sherpa-onnx huggingface_hub
.venv-export/Scripts/python -m pip install -e engine

.venv-export/Scripts/python tools/whisper_export/export_quran_whisper.py   # -> build/whisper_onnx/
.venv/Scripts/python        tools/whisper_export/prepare_clips.py          # reference clips + server transcripts
.venv-export/Scripts/python tools/whisper_export/validate_onnx.py          # ONNX vs server, same audio
```

Then on a phone: run the server (`python -m rafiq_server --host 0.0.0.0`), open
the app → Settings → Developer → **On-device speech benchmark**. It downloads
the model and clips from `/dev/asr` and reports speed and accuracy.

| File | What |
|---|---|
| `export_quran_whisper.py` | Tarteel `whisper-base-ar-quran` (pinned revision) → OpenAI layout → sherpa-onnx export |
| `sherpa_export_onnx.py` | sherpa-onnx's export script, vendored unmodified (Apache-2.0) |
| `prepare_clips.py` | 22 clips (6 reciters × clean/mosque) with the server model's transcripts |
| `validate_onnx.py` | word accuracy, ayah detection and speed of the ONNX model vs the server |

**Findings (2026-11-03, laptop CPU):**
- **Accuracy:** 97.4% word accuracy, against 98.6% for the server model on the same audio.
- **Silence pad required:** append **2 s of silence** to every chunk. Without it the model drops the last word or two (81% accuracy), and sherpa's `tail_paddings` setting does not help.
- **Speed scales with length:** cost grows with chunk length (sherpa removes Whisper's fixed 30 s window), about 0.7 s per typical chunk on 2 threads.
- **Size:** 160 MB for int8, mostly the decoder's 51,865-token embedding. Trimming the vocabulary to Quran tokens is the obvious optimization for both size and speed.
