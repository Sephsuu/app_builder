# Implementation and verification — 9 October 2026

The normal ARM64 app is installed on the connected Galaxy A16. Translation's
low-memory crash has been addressed and an optional Cebuano speech model has
been converted, evaluated and installed. **Full accuracy, mixed-speech,
noise-robustness and voice-to-voice acceptance remain incomplete.**

## Translation crash

Android's exit history showed repeated LOW_MEMORY process kills, including the
reported process at roughly 2 GB RSS. This was an OS memory kill, which a Dart or
Java exception handler cannot catch. The original decoder materialized a roughly
1 GiB float32 vocabulary-projection matrix.

`tools/prepare_mobile_nllb.py` produces packaged ONNX graphs referencing the
original SHA-verified downloaded weights. The vocabulary projection now runs in
ordered 8192-row slices. Weight values and quantization scales are unchanged;
ConstantFolding is disabled so the slices do not become another full matrix.
Encoder and decoder sessions remain sequential, Whisper is released before
translation, and a free-memory admission check rejects jobs when RAM is low.

- Device: Samsung Galaxy A16 SM-A165F, Android 16, ARM64, total RAM 3,740,844 KiB.
- Four short native translations completed, in both directions, in 11.6–17.8 s.
- Sampled peak PSS: 905,625 KiB (884 MiB); no low-memory kill in this smoke run.
- Cancellation fence completed in 231 ms and a subsequent translation succeeded.
- Ten host mobile-graph outputs exactly matched the original graph outputs.
  This includes its existing quality errors, rather than proving good translation.
- A separate real Base-ASR → release → translation run stayed alive, sampled
  909,764 KiB peak PSS (888 MiB), but translation of its longer, imperfect source
  hit the 120-second timeout. The app now explains this timeout and retains the
  source. **That longer end-to-end translation did not pass.**

Raw results: [phone smoke](../benchmarks/nllb-galaxy-a16-smoke.json),
[host parity](../benchmarks/nllb-mobile-host-smoke.json),
[longer pipeline](../benchmarks/base-to-translation-galaxy-a16.json).
These are sampled measurements, not a guarantee against future OS memory kills.
Tests used local files without changing the phone's radios; airplane-mode and
thermal endurance tests still need to be performed.

## Recognition and mixed speech

Stock multilingual Tiny/Base has no native Cebuano token. Renaming that mode
would not address the user's recognition problem. Verified installed Base is
now selected for final Tagalog recognition by default, with Tiny retained for
live captions. Users can still choose Tiny. The existing two-recording Filipino
comparison measured WER .70 for Tiny and .40 for Base; this narrow result does
not establish accuracy for “Kumain ka na ba?” or mixed speech.

The separately trained [eemberda/phcodeswitch-ceb-dvo model](https://huggingface.co/eemberda/phcodeswitch-ceb-dvo)
was pinned to revision `3a6999b22f5ebd754a25ce59c54897e2ac1e930d`, converted
from Safetensors to GGML F16 and quantized with official whisper.cpp v1.8.2 Q5_1.
All 50,257 regular tokenizer entries were checked against the installed Whisper
vocabulary; mel filters and decoder control tokens were verified. The derivative
loaded in the app's actual packaged native runtime. No PyTorch-reference token
parity test was performed.

The publisher trains Davao Cebuano and Cebuano–English speech using the `tl`
decoder prompt. This app uses that prompt only with the trained checkpoint.
The publisher's reported WER is not this app's result. License: CC-BY-NC-4.0,
consistent with the authorized research/demo scope; attribution is packaged.

One public native-speaker Cebuano recording with English brand names was
resampled from 48 kHz stereo to 16 kHz mono, without added gain or trimming.
The first aligned 11.954 seconds were compared on the same phone/runtime with
four CPU threads. The publisher marks its text human-validated; boundaries were
not independently reviewed.

| Model / decoding | WER | CER | Processing time |
|---|---:|---:|---:|
| Original Tiny, greedy | .8710 | .3546 | 7.42 s |
| Trained Cebuano Small, greedy | .4839 | .4043 | 37.18 s |
| Trained Cebuano Small, beam 5 | .4194 | .1773 | 42.64 s |

[Raw comparison and provenance](../benchmarks/cebuano-galaxy-a16-comparison.json).
This is one recording/speaker; no general accuracy claim follows. All outputs
still contained errors. Natural repetitions were not dictionary-corrected.

Cebuano voice is enabled only after verification of the trained model. It runs
with five-beam decoding after Finish; live captions are disabled to avoid repeated
large-model inference. With Tagalog selected, **Cebuano / mixed speech** is an
optional experimental mode. Choose the dominant source for translation.
Cebuano–English is the training focus; **Tagalog–Cebuano mixing, Taglish, accents,
noise and the user's exact utterance have not been validated**. The original
Tagalog models are not replaced by this candidate.

### Reproduce the model installation

The file is `ggml-cebuano-small-q5_1.bin`, 190,085,487 bytes, SHA-256
`43b3973c2baaff647a92619102c24e3dd0ed1f0e00993b7e3ecd68231dfc587f`.
The phone has both its private installed copy and a reinstall copy in
`Download/Sulti/`. New installations use **Import Cebuano speech model** and
Android's file picker. Import streams into a temporary file, enforces size and
SHA-256, then atomically replaces the verified model. Cancellation and wrong
files leave an existing verified model intact. No model has been publicly uploaded.

For a fresh conversion, fetch the source files using
`evaluation/cebuano-model-manifest.json`, install NumPy/Safetensors in a separate
Python environment, then run:

```sh
python tools/convert_cebuano_whisper.py evaluation/private/cebuano-asr \
  --tiny <verified-ggml-tiny-q5_1.bin> \
  --output evaluation/private/cebuano-asr/ggml-cebuano-small-f16.bin
<whisper.cpp-v1.8.2-quantize> \
  evaluation/private/cebuano-asr/ggml-cebuano-small-f16.bin \
  evaluation/private/cebuano-asr/ggml-cebuano-small-q5_1.bin q5_1
```

The converter validates source/Tiny hashes before writing. Verify the derivative
hash above before import. Source and generated weights are ignored local assets.

## Existing translation, voices and noise limits

NLLB remains the authorized noncommercial research model: pinned Xenova int8
export, roughly 900 MB downloaded weights, exact Tagalog/Cebuano tokenization.
Actual short outputs included `Hindi ako pupunta sa Mayo 12.` →
`Dili ako moadto sa Mayo 12.` and `Asa si Maria?` → `Saan si Maria?`.
`Dili ko gusto og kape.` → `Hindi ako nagustuhan ng kape.` remains a meaning/grammar
failure. Translation quality has not passed acceptance.

The phone reported no installed offline Tagalog or Cebuano TTS voice. The app
explains the missing target voice and retains the translation; **complete offline
voice-to-voice playback is unavailable on this phone**. No supplementary TTS model
has been added.

Original microphone capture remains 16 kHz mono float32, with no added gain,
resampling, trimming or VAD. Optional Android NoiseSuppressor remains off by
default and falls back when unavailable. Synthetic two-recording Tiny diagnostics
produced WER .70 clean, .76 at nominal 10 dB, 1.18 at 0 dB, 1.30 with changing
noise, 1.28 quiet/noisy and .62 with added pauses. These do not run Android
suppression and establish no denoising gain. Paired acoustic tests remain needed.

## Validation and delivery

- 30 Flutter tests passed, including final-only translation, cancellation fences,
  stale results, edit/retry, target voice, Base default/user choice, Cebuano voice
  routing, and rejected stock-Cebuano/cancelled-import paths.
- Flutter analyzer clean; ARM64 release build successful.
- Three native tokenizer/language-code tests passed.
- Phone tests used public recordings, not private microphone recordings.
- Normal production entry point `lib/main.dart` was restored; diagnostic entry
  points are not installed as the final app.
- Release APK: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`,
  55,404,683 bytes, SHA-256
  `f61dd3af83077116557f8dd434762852887cde03c9aaa58531534b0f8c7c31ab`.

The report does not claim the user's misrecognized phrase is fixed. A fresh
recording with retained final text is needed to assess that case, alongside a
larger held-out Cebuano/mixed corpus, paired noise tests, target voices and longer
release-app endurance tests.
