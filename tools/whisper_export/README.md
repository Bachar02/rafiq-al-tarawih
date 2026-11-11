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
.venv-export/Scripts/python tools/whisper_export/trim_vocab.py --model base   # -> quran-basetrim-* (55 MB)
.venv/Scripts/python        tools/whisper_export/install_model.py              # -> mobile/assets/models/ (the app's bundle)
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
| `trim_vocab.py` | keep only the 660 tokens Quran transcripts use; re-quantize (what the app ships) |
| `install_model.py` | copy the trimmed model into the app bundle, with a manifest (sizes, SHA-256, version) |

**Findings (2026-11-03, laptop CPU):**
- **Accuracy:** 97.4% word accuracy, against 98.6% for the server model on the same audio.
- **Silence pad required:** append **2 s of silence** to every chunk. Without it the model drops the last word or two (81% accuracy), and sherpa's `tail_paddings` setting does not help.
- **Speed scales with length:** cost grows with chunk length (sherpa removes Whisper's fixed 30 s window), about 0.7 s per typical chunk on 2 threads.
- **Size:** 160 MB for int8, mostly the decoder's 51,865-token embedding. Trimming the vocabulary to Quran tokens is the obvious optimization for both size and speed.

**Phone round 1 (Galaxy A32, a budget phone with 2 fast and 6 slow cores):**
- **Speed:** 3.6 s per typical chunk on 2 threads, slower than real time. 4 threads were *slower*, because they spill onto the slow cores. Accuracy was 96.6%.
- **Whisper-tiny:** rejected. It's 1.8× faster but only 80% accurate and misses ayahs.
- **Where the time goes:** mostly the decoder, not the encoder. Its fp32 51,865-token projection is read in full for every token, and diacritized Arabic is many tokens per word.
- **Vocabulary trim:** 660 tokens. Transcripts are identical on all 22 clips, the model shrinks from 160 to 55 MB, and it runs about 25% faster on the laptop. More is expected on phones, which are memory-bound.
