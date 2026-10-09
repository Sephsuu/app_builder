# Sulti — local Tagalog / Cebuano translator

Android-first Flutter research/demo application. Tagalog speech is recognized
with the existing Whisper Tiny/Base implementation. NLLB translates finalized or
edited text **in both directions**, entirely on-device after installation.
Playback uses an installed offline voice for the exact target language.

**Current limits:** an optional, separately trained Cebuano Small checkpoint now
supports Cebuano voice after Finish. It is slower and still makes errors. Its
training focuses on Cebuano–English; mixed Tagalog–Cebuano is experimental and
not validated. Offline voices depend on the device. Noise suppression stays off
by default; no recognition improvement from it is claimed.

See the [pre-change audit](evaluation/implementation-audit.md) and
[verification and limitations](evaluation/implementation-results.md).

## Run

```sh
flutter pub get
flutter run -d <ANDROID_DEVICE_ID>
```

1. Install the speech model (~32 MB Tiny; ~63 MB Base). Verified installed Base
   is selected for final Tagalog recognition by default; Tiny remains available.
   For Cebuano voice, use **Import Cebuano speech model** and select the converted
   `ggml-cebuano-small-q5_1.bin` (190,085,487 bytes). The app verifies its SHA-256.
   On the tested Galaxy A16 it is already installed, with a reinstall copy in
   `Download/Sulti/`. Conversion instructions are in the report.
2. Install the translation model (~900 MB). This is an explicit, resumable,
   checksum-verified download, separate from speech setup.
3. Choose Tagalog or Bisaya as the source. The target is always the other
   language. The swap control clears the old text and stops its translation or
   playback. Direction controls are disabled during recording/final recognition.
4. For the selected source language, record and Finish. Only the final transcript is translated.
   Live captions never trigger translation. English and auto-detect remain
   available for recognition only. Cebuano uses the trained Small model with
   five-beam decoding after Finish; live captions are disabled for this model.
   For experimental mixed speech with a Tagalog source, enable **Cebuano / mixed
   speech**. Choose the dominant source language for translation.
5. Alternatively use **Enter Tagalog/Bisaya text**. Edit the source and choose
   **Translate source text**. A failure preserves the source and exposes Retry.
6. **Play translation** selects an installed offline target-language voice.
   If none exists, the translation stays visible and the app explains the limit.
7. After setup, repeat with airplane mode enabled to verify the installed
   resources on your actual phone. No inference API or server is used.

## Compatibility and dependencies

- Flutter, Dart SDK constraint `^3.12.2`, Android min API 24, Java 17.
- Existing `whisper_cpp_flutter_plus: ^0.5.1` remains unchanged. Tiny and Base
  model URLs, SHA-256 hashes and final decoding settings are unchanged.
- Added Android `com.microsoft.onnxruntime:onnxruntime-android:1.23.2` (MIT), CPU
  backend, and SentencePiece 0.2.0 (Apache-2.0), built through CMake with a pinned
  archive SHA-256. No new Flutter runtime dependency was added.
- NLLB is enabled only in a **64-bit Android process**. Its weights occupy
  899,478,308 bytes; installation also needs temporary space. Actual native
  working memory exceeds file size; this is a large model for lower-memory
  phones. Encoder and decoder sessions are loaded sequentially, and Whisper is
  released before translation. New recording waits for translation cancellation
  and native resource release. The mobile decoder splits vocabulary projection
  into ordered slices, avoiding the original ~1 GiB float matrix allocation.
  Physical Galaxy A16 smoke tests sampled **884–888 MiB process PSS** and no
  low-memory kill. A free-memory check rejects jobs when RAM is already low.
  Long translation timed out at two minutes; shorten the source and retry.
- Android's existing `NoiseSuppressor` and `TextToSpeech` APIs need no additional
  model or plugin. Noise suppression may not exist or grant control on every
  device; the original microphone recorder is the fallback.
- iOS, desktop and web are not validated deployment targets. The Android
  integration is not silently replaced by cloud inference on those platforms.

## Model and tokenization

Translation uses the quantized ONNX export of Meta NLLB-200 distilled 600M:
`Xenova/nllb-200-distilled-600M`, revision
`261c31d1a5732c67cdd16d80e8d6088507c7ccea`.

| Source / target language | NLLB code | Token ID | TTS locale family |
|---|---|---:|---|
| Tagalog | `tgl_Latn` | 256174 | `tl` / `fil` |
| Cebuano | `ceb_Latn` | 256035 | `ceb` only |

The original SentencePiece normalization/BPE is used through a small JNI bridge,
including the fairseq offset and unknown-token mapping. Encoder input is
`[source language, text tokens, EOS]`; decoder prefix is `[EOS, target language]`.
Greedy generation retains self/cross-attention caches. Inputs over 512 tokens,
outputs that fail to finish within the limit, and empty output are rejected with
an actionable error instead of silently dropping text. Inference runs on a
serial native worker with cancellation and a two-minute execution timeout.
Model output is not dictionary-corrected or rewritten.

Real host and Android smoke runs produced output in both directions. They also
exposed meaning errors and a dropped proper name in Cebuano → Tagalog output.
The model has **not passed translation-quality acceptance**. Review the source
and result; the UI does not present its output as a verified translation.

[Exact artifact hashes](evaluation/nllb-model-manifest.json) are verified on
installation and on first discovery in a process. Weights live in private,
non-backed-up app storage. The APK packages small derived graphs and their
embedded graph constants; the large downloaded weight files are not in the APK.

**Research license:** Meta's model and the ONNX derivative are CC-BY-NC-4.0.
Meta describes NLLB as a research model not released for production deployment.
This is the noncommercial demo option approved for this implementation; it is
not a commercial production baseline. Retain attribution and obtain a suitable
model/license before changing the intended use.

## Audio path and noise evaluation

Default capture is unchanged: VOICE_RECOGNITION, mono float32 PCM at 16 kHz,
100 ms requested chunks, no added gain, VAD, resampling or silence trimming.
The five-minute recording cap, serial live preview, Finish/Cancel, and optional
Base final refinement remain. Exact silence and malformed PCM are rejected;
quiet speech is retained.
The prior [live-caption verification](benchmarks/adaptive-live-captions.md)
remains available.

The experimental switch attaches Android NoiseSuppressor to a separate but
format-compatible AudioRecord session. It starts before microphone capture,
processes both preview and final audio, and drains buffers before finalization.
If unavailable, capture falls back to the original recorder and shows a notice.
Repeated full-scale samples produce an amplitude/clipping advisory, never a
fabricated recognition-confidence or SNR score.

There is no actual-room denoising benchmark yet. The existing two public Filipino
FLEURS recordings were also tested with deterministic noise mixtures. These are
baseline diagnostics, not proof of improved real-world accuracy. The experimental
switch must remain off by default until paired clean/noisy physical-device WER,
CER, quiet-word retention, latency and memory tests justify enabling it.

## Tests and developer tools

```sh
flutter test
flutter analyze
# JAVA_HOME must point to the installed Android Studio JBR or another JDK 17+.
cd android
./gradlew :app:testDebugUnitTest
```

- Flutter tests cover final-text routing, both language pairs, editing/retry,
  duplicate requests, cancellation, stale results, voice selection, stopping
  during voice discovery, recording controls and phone-width layout.
- Native unit tests cover NLLB source/target token construction and code rejection.
- `tools/fetch_evaluation_models.py` fetches the same pinned weights for developer
  checks; `tools/evaluate_nllb.py` performs real local model inference and checks
  tokenizer parity. Evaluation Python dependencies belong in a separate venv.
- `tools/offline_device_probe.dart` is an explicit developer-only Flutter entry
  point for native inference/voice checks. It is never the production entry point.
- `tools/prepare_noise_fixtures.py`, `tools/run_noise_benchmark.py`, and the existing
  `tools/score_asr.py` provide reproducible WER/CER diagnostics. Generated audio
  remains in ignored `evaluation/private/`; do not retain private recordings in git.

## Remaining acceptance work

1. Broaden the Cebuano and mixed-speech evaluation with held-out speakers and
   actual user recordings. The converted Davao checkpoint has only a one-clip
   physical-device comparison; Tagalog–Cebuano mixing is not validated.
2. Broaden translation latency, memory, thermal and airplane-mode checks beyond
   the completed Galaxy A16 smoke tests. Run native-speaker review of questions,
   negation, names, numbers, code-switching and longer sentences in both directions.
3. Run paired acoustic recordings with suppression on/off on real hardware. Do
   not infer denoising quality from synthetic mixtures or cleaner-sounding audio.
4. Test available installed voices and pronunciation in airplane mode. If no
   Cebuano voice is present, a supplementary model such as MMS-TTS Cebuano needs
   a separately licensed, verified mobile conversion; it has not been added.

For physical-device comparisons, use the same phone, release APK, model hashes
and human-checked recordings. Record phone/OS/RAM, room noise, battery state,
cold versus warm runs, processing time divided by audio duration, WER/CER and
peak memory. Repeat each sample three times, including quiet speech, pauses,
short utterances, longer speech and code-switching. Compare suppression on/off
using matched acoustic playback, then check the complete pipeline in airplane
mode. Emulator inference cannot establish microphone enhancement quality.

## References and attribution

- [Whisper Flutter runtime](https://pub.dev/packages/whisper_cpp_flutter_plus)
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
- [Meta NLLB model card and license](https://huggingface.co/facebook/nllb-200-distilled-600M)
- [Pinned ONNX export](https://huggingface.co/Xenova/nllb-200-distilled-600M/tree/261c31d1a5732c67cdd16d80e8d6088507c7ccea)
- [SentencePiece 0.2.0](https://github.com/google/sentencepiece/tree/v0.2.0)
- [ONNX Runtime Android](https://onnxruntime.ai/docs/build/android.html)
- [Android NoiseSuppressor](https://developer.android.com/reference/android/media/audiofx/NoiseSuppressor)
- [Android offline voice capabilities](https://developer.android.com/reference/android/speech/tts/Voice)
- [Google FLEURS, CC-BY-4.0](https://huggingface.co/datasets/google/fleurs)
