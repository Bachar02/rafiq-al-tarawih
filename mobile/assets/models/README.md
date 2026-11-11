# The on-device speech model

Taraweeh mode recognises the recitation on the phone with the files in this
folder, which are not kept in git (55 MB):

- `encoder.int8.onnx`, `decoder.int8.onnx`, `tokens.txt`: Whisper-base
  fine-tuned on Quran recitation (Tarteel `whisper-base-ar-quran`,
  Apache 2.0), exported for sherpa-onnx and its vocabulary trimmed to the 660
  tokens Quran transcripts use.
- `manifest.json`: each file's size and SHA-256, and the model's version.

Put them here before building the app:

```bash
py tools/whisper_export/install_model.py
```

It copies them from `build/whisper_onnx/` (made by the scripts in
`tools/whisper_export/`, see its README). A build made without them works,
but Taraweeh mode says it has no speech model.
