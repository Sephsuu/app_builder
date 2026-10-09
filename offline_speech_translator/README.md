# Sulti — Local Tagalog to Cebuano Voice Translator

Sulti is an Android-first Flutter app for translating spoken Tagalog into spoken Cebuano. This repository is being built in small, verifiable stages. **The current runnable stage performs Tagalog speech recognition locally. Translation and Cebuano speech synthesis are not integrated yet, so this version is not the complete translator.**

## Feasibility and model choices

| Stage | Candidate | Android assessment |
|---|---|---|
| Speech recognition | `whisper.cpp`, multilingual `tiny-q5_1` GGML model | Feasible on Android as a faster, lower-accuracy option. The model download is about 32 MB. Keep multilingual models for Tagalog; English-only variants are unsuitable. |
| Translation | `facebook/nllb-200-distilled-600M`, `tgl_Latn` → `ceb_Latn` | Technically possible to export to ONNX and run with ONNX Runtime Mobile, but large for a phone. The checkpoint is research-oriented, marked CC-BY-NC-4.0, and explicitly not released for production deployment. Treat it as a research benchmark, not a shippable commercial model. |
| Cebuano speech | `facebook/mms-tts-ceb` VITS checkpoint | A Cebuano checkpoint exists, but its published weights are PyTorch/Safetensors rather than a ready Android runtime model. ONNX export, operator coverage, memory, latency, and speech quality need to be measured on device. It is also CC-BY-NC-4.0. |

The app prefers the quantized multilingual Whisper tiny model, pinned to an immutable Hugging Face revision and checked against its SHA-256 before acceptance. Tiny is selected to reduce latency on the target phone, with a possible Tagalog accuracy trade-off. An already installed multilingual base model remains usable. The “Refine with Whisper Base” switch selects Base Q5_1 for optional final review; download it once when prompted. Both files are retained for offline comparison. Live captions use the faster installed model; enabling Base refinement swaps to Base after Finish, with only one model loaded at a time. The switch defaults to Tiny on each app launch. Base accuracy and latency still require measurement on your Tagalog speech; this is not a proven accuracy upgrade. Microphone audio and ASR inference remain on the phone after model installation.

For translation research, export NLLB as an encoder-decoder ONNX model, retain its tokenizer assets, set source language `tgl_Latn`, and force the generated language token to `ceb_Latn`. Test CPU first; then try Android XNNPACK or NNAPI on the actual target hardware. Track the packaged model size, peak process memory, cold start, and sentence latency. If it is too slow or memory-heavy, the practical product direction is a smaller Tagalog–Cebuano model trained or distilled for this pair under a license suitable for the intended use.

For TTS research, export `facebook/mms-tts-ceb` to ONNX and validate waveform output against the PyTorch reference before adding it to Flutter. A possible fallback is Android's installed Cebuano system voice only when the selected voice reports that network access is not required. Voice availability and quality vary by phone, so this fallback cannot be promised as a universal offline feature. If neither path works, show the Cebuano text and explain that local speech is unavailable; do not silently use a cloud voice.

## Proposed full architecture

```text
Flutter Material 3 UI
  ├─ AudioCapture          (Android microphone, 16 kHz mono PCM)
  ├─ SpeechRecognition     (Whisper.cpp native C++ via Flutter FFI)
  ├─ TranscriptEditor      (user reviews/corrects Tagalog text)
  ├─ Translation           (future: NLLB ONNX / ONNX Runtime Mobile)
  ├─ SpeechSynthesis       (future: Cebuano VITS ONNX or verified local voice)
  ├─ AudioPlayback         (local generated WAV)
  ├─ ModelRepository       (explicit setup, private storage, hashes, versions)
  └─ LocalHistory          (optional future SQLite)
```

The presentation layer depends on small speech, translation, and voice interfaces, while each implementation owns its runtime and model lifecycle. For the full phone workflow, run each stage in order and release a large model before loading the next when device memory is tight. The app has no inference server: only the explicit initial model download uses the network. `whisper_cpp_flutter_plus` supplies the native Android whisper.cpp engine, microphone capture, cancellation, and Android CPU support; Flutter owns the screens and interaction state.

## Current implementation

- Material 3 single-screen Flutter application with Tagalog → Bisaya (Cebuano) language display.
- Explicit, one-time model installation with byte progress and a pinned SHA-256.
- Local microphone recording, a recording timer, finish/cancel controls, a final transcription progress indicator, and copyable Tagalog text.
- Optional live captions use overlapping audio windows with a serial inference queue and measured cooldown. Finish runs a separate full-recording pass. See [live-caption verification](benchmarks/adaptive-live-captions.md).
- Tagalog is the default (`tl`), with English and experimental automatic language detection available. Cebuano/Bisaya needs a separately validated model; see [regional candidates](evaluation/regional-language-candidates.md). Audio is not uploaded.
- Recording automatically finishes after five minutes to bound audio memory. Live preview can be disabled before recording; slow preview inference pauses itself while final recognition remains available.
- Model corruption, network failures during setup, microphone permission errors, model-loading state, and inference errors are surfaced in the UI.
- Translation and TTS appear as clearly marked future stages. The interface does not claim that the whole pipeline is offline yet.

## Project layout

```text
lib/
├── main.dart
└── features/
    └── speech/
        ├── data/
        │   └── local_whisper_speech_service.dart
        └── presentation/
            └── speech_home_screen.dart
```

`LocalWhisperSpeechService` owns model storage, model loading, audio capture, live preview and final transcription after recording, cancellation, and native resource disposal. The presentation layer displays the states and results. Translation and TTS can be added behind similarly narrow service interfaces in later stages.

## Dependencies and Android setup

- Flutter/Dart project using Material 3.
- [`whisper_cpp_flutter_plus`](https://pub.dev/packages/whisper_cpp_flutter_plus) provides native `whisper.cpp` bindings for Android and microphone transcription.
- The Android minimum SDK is API 24 to match the plugin's supported minimum.
- Android asks for `RECORD_AUDIO` at runtime. `INTERNET` is present only to support the user's explicit model download; inference does not require it.
- The model is kept in app-private support storage, not in the repository or APK.

## Run on a physical Android phone

1. Install Flutter and Android SDK/NDK tooling, enable USB debugging, and connect the phone.
2. From this directory run:

   ```bash
   flutter pub get
   flutter devices
   flutter run -d <ANDROID_DEVICE_ID>
   ```

3. On first launch, connect to Wi-Fi and tap **Install speech model**. Wait until the model is verified and marked ready.
4. Tap the microphone, allow microphone access, speak a short Tagalog sentence, then tap **Finish**. Use **Cancel** to discard a recording.
5. Once installation succeeds, switch on airplane mode and repeat the speech-recognition test. The app does not use an internet service for ASR.

The faster model download needs a stable connection and roughly 32 MB plus temporary download space. A failed download can be retried. Reinstall the app or clear its application storage to remove the model.

## Offline verification checklist

- [ ] Install and verify the Whisper model while online.
- [ ] Confirm Android's app info shows microphone permission and the model is present in app storage.
- [ ] Enable airplane mode and confirm a new recording transcribes successfully.
- [ ] Confirm microphone permission denial produces an actionable message.
- [ ] Confirm no audio or transcript request appears in network traffic during transcription.
- [ ] Corrupt/delete the model and confirm the app refuses to label ASR ready and offers reinstallation.
- [ ] Separately repeat airplane-mode tests after translation and TTS are implemented; only then describe the *complete pipeline* as offline.

## Physical-device performance procedure

Use the same Android phone, release build, model hash, and fixed set of Tagalog WAV recordings for each run. Record the phone model, Android version, RAM, battery state, room noise, and whether the run is cold or warm.

For each of at least ten utterances, record model-load time, audio duration, ASR processing time, real-time factor (processing seconds ÷ audio seconds), whether Tagalog was detected, and a human-checked transcription error rate. Repeat each sentence three times; report median and slowest latency. Watch Android Studio/Perfetto memory and CPU metrics during the same run. Include short speech, a longer sentence, Taglish, two speaking speeds, and a noisy-room sample. Benchmark translation and synthesis separately after they are integrated, then time the full pipeline and check peak memory while ensuring the app does not load all large models concurrently.

## Known limitations and next stages

Whisper can mishear Taglish, names, noisy speech, and regional pronunciation. The user should be able to edit the transcript before translation is connected. This version is an ASR prototype; it has no Cebuano translation or generated voice yet.

NLLB and MMS-TTS Cebuano are not a safe commercial baseline under their current model-card terms. Their Android runtime conversions are unvalidated here. A production or public release needs a model whose license permits that use, an evaluated Tagalog–Cebuano test set, and a real-device resource benchmark. Do not treat the language labels alone as proof of natural Cebuano output.

Suggested build order:

1. Validate Tagalog Whisper recognition and latency on the target phone.
2. Export and benchmark a licensed translation model with `tgl_Latn` → `ceb_Latn` support.
3. Validate a local Cebuano TTS model or device voice under airplane mode.
4. Connect the three services, add editable transcripts and optional local history, and rerun the offline checklist for every stage.

## Hackathon demo script

1. Show the app's on-device status and install the speech model before the demo.
2. Turn on airplane mode and speak: “Pakiabot ang tubig sa lamesa.”
3. Finish the recording and show the Tagalog transcription; copy it to demonstrate text output.
4. Explain that this build proves the local speech stage. Present translation and Cebuano speech as the next milestones, without claiming the full translator is already offline.

## Model and runtime references

- Whisper mobile Android example and model guidance: https://github.com/ggml-org/whisper.cpp/tree/master/examples/whisper.android
- Pinned multilingual Whisper tiny Q5_1 model file: https://huggingface.co/ggerganov/whisper.cpp/blob/f281eb45af861ab5e5297d23694b7d46e090c02c/ggml-tiny-q5_1.bin
- Pinned multilingual Whisper base Q5_1 fallback model file: https://huggingface.co/ggerganov/whisper.cpp/blob/f281eb45af861ab5e5297d23694b7d46e090c02c/ggml-base-q5_1.bin
- NLLB-200 distilled 600M model card and license: https://huggingface.co/facebook/nllb-200-distilled-600M
- MMS Cebuano TTS model card and files: https://huggingface.co/facebook/mms-tts-ceb
- ONNX Runtime Mobile deployment guide: https://onnxruntime.ai/docs/tutorials/mobile/
- Hugging Face Optimum ONNX export guide: https://huggingface.co/docs/optimum-onnx/onnx/usage_guides/export_a_model
