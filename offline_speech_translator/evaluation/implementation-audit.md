# Audit before implementation — 9 October 2026

This checkout implements ASR, not the TTS described in the request. Translation
and speech output are placeholders. The working baseline is preserved; there is
no existing voice or playback configuration to migrate. The user approved NLLB
for a noncommercial research/demo build.

## Baseline and compatibility

- Flutter/Dart (SDK constraint ^3.12.2), Material 3, Android first; min API 24,
  Java 17, AGP 9.0.1 and Kotlin 2.3.20. Other platform directories are templates;
  iOS does not even declare microphone usage yet.
- `whisper_cpp_flutter_plus` 0.5.1, native whisper.cpp via FFI, CPU/four threads.
  Multilingual Tiny Q5_1 (~32 MB) and optional Base Q5_1 (~63 MB), revision
  `f281eb45af861ab5e5297d23694b7d46e090c02c`, SHA-256 verified downloads.
- Capture: Android AudioRecord/VOICE_RECOGNITION, 16 kHz mono normalized float32,
  little endian channel buffers, requested 100 ms chunks (hardware minimum may
  increase chunk size). No app resampling, normalization, denoising, AGC, VAD,
  trimming or clipping diagnostics. Exact silence/malformed PCM is rejected.
  Five minutes of retained audio is ~19.2 MB; final assembly temporarily adds
  another copy. Actual model working memory is device dependent.
- Final decode: greedy best-of 1, language tl/en/auto, temperature fallback 0.2,
  no timestamps. Preview: overlapping 12-second windows every three seconds,
  serial inference with cooldown, token timestamps, temperature fallback off.
- Offline ASR after explicit model setup. No translation runtime, tokenizer,
  translation weights, TTS runtime or voice model exists in this checkout.
- Baseline `flutter test`: **8 passed**, before edits. Two public CC-BY-4.0
  FLEURS Filipino WAVs and prior reports exist in ignored evaluation/private.
  Historical aggregate WER: Tiny .70, Base .40, just two recordings. These are
  not a fresh run or a representative clean/noisy benchmark.
- ADB found **no attached device**. Actual microphone effects, mobile latency,
  memory, offline installed voices and acoustic quality cannot be measured yet.

## Findings and implementation decision

There is no paired noisy/clean corpus establishing the cause of the reported
errors. The capture path has no explicit suppression; that is an opportunity to
evaluate, not proof that filtering will improve recognition. Use Android's
existing NoiseSuppressor as an **opt-in experimental capture path**, retaining
the original recorder when off or unavailable. It requires no denoising weights
or new DSP dependency. Do not change decode defaults, trim speech or infer SNR
from loudness. RNNoise/WebRTC would require another native library and format
integration without evidence of a benefit here, so they are not added.

Use a pinned int8 ONNX NLLB-200 distilled 600M export (Xenova), with the original
SentencePiece model. Verified language identifiers are `tgl_Latn` / `ceb_Latn`.
Native Android ONNX Runtime and SentencePiece are justified because there is no
existing translation runtime. CPU inference runs on a worker, with bounded input
and generation, cancellation, and model resources closed between stages.
Encoder + merged decoder + tokenizer require about 900 MB on disk, plus temporary
download space and substantial native memory. No phone resource claim is made.

Stock Whisper has no Cebuano token. An independently trained, compatible Cebuano
checkpoint is required; auto or tl on stock Tiny does not solve that limitation.
Preserve Tagalog ASR and provide honest Cebuano capability reporting. The
`eemberda/phcodeswitch-ceb-dvo` candidate uses a tl prompt because it was trained
that way; its published safetensors are not directly accepted by whisper.cpp.

Use installed Android TTS voices only when the exact language matches and the
voice reports no network requirement. Do not substitute Filipino for Cebuano.
MMS-TTS Cebuano is another noncommercial model requiring a separate conversion
and mobile validation; no unvalidated voice replacement is justified now.

The UI will preserve recording/cancel/finish, live captions, Base refinement,
English/auto recognition, copy and editing. Add language swap, actual translation,
retry and playback on the same screen. Request generations bind text, languages
and playback, so stale work cannot overwrite a new operation.

## Primary references

- https://huggingface.co/facebook/nllb-200-distilled-600M (CC-BY-NC-4.0; research,
  not released for production deployment; 512-token training limit)
- https://huggingface.co/Xenova/nllb-200-distilled-600M
- https://github.com/google/sentencepiece/tree/v0.2.0 (Apache-2.0)
- https://onnxruntime.ai/docs/get-started/with-java.html (MIT runtime)
- https://developer.android.com/reference/android/media/audiofx/NoiseSuppressor
- https://developer.android.com/reference/android/speech/tts/Voice
- https://huggingface.co/eemberda/phcodeswitch-ceb-dvo

No new measured WER/CER, translation quality, memory, or mobile speed is claimed
by this audit. See the delivery report for tests actually run after implementation.
