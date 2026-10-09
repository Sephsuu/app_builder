# Adaptive live captions

## Implementation

- `application/live_recognition.dart`: uses the installed plugin's timestamped
  segment merger over 12-second windows, 3-second update interval and 3-second
  confirmation lag. These are periodic Whisper passes, not genuine acoustic
  streaming. New hypotheses replace the provisional tail. Timing overlap helps
  avoid duplication; uncalibrated word timestamps may still make boundary errors.
- Inference is serialized. Cooldown is 25% of the previous inference duration,
  bounded to 250–1500 ms. A preview pass exceeding eight seconds pauses preview
  instead of accumulating more audio for it. These thresholds are workload limits,
  not accuracy or latency promises. Exactly silent windows skip inference.
- Preview temperature fallback is disabled to bound repeated decoding. The final
  pass retains baseline decoding/fallback; no blind word substitutions are used.
- `data/local_whisper_speech_service.dart`: captures PCM once, preserves it for
  final recognition, blocks overlapping recording sessions and uses generation
  guards to reject cancelled/stale results. Cancellation waits for native work
  before reuse/disposal. The five-minute recording cap bounds full audio memory
  to approximately 19.2 MB of float32 PCM, excluding copies/native tensors.
- With Base refinement enabled, the faster installed model handles captions,
  then is unloaded before Base loads for final review. When Tiny is absent, the
  existing Base fallback is used; fastest previews require Tiny to be installed.
- `data/speech_capture.dart`: isolates microphone capture and enables real PCM
  replay through the same service for testing. The production source remains the
  plugin recorder. No new dependency, permission, network inference or upload.
- `presentation/live_caption_card.dart`: naturally wrapping captions, a distinct
  provisional tail, manual scroll retention and a Latest words control.
  `speech_home_screen.dart`: optional preview, Base final review, explicit language
  limits, cancellation/background cleanup, retained raw final text and editing.

Spotify already has the lyrics available; speech recognition has to infer words
from new sound. The app displays real hypotheses only, and cannot promise instant
words or perfectly synchronized word highlighting. Stable preview text can still
be revised by final recognition. Confidence percentages are not shown.

## Tests and measurement scope

Eight app tests passed: existing audio and screen tests plus caption revision,
repetition retention, serial scheduling, cancellation, silence and slow-preview
pause behavior. Analysis passed. See device measurements below. Test transcripts
in unit tests are controlled fixtures, not fabricated production output.

The developer-only entry point `tools/live_device_probe.dart` replays licensed
public PCM at 100 ms intervals through the actual service, native model and
caption widget. It measures the first text event (not exact display scanout),
updates, recording duration and Finish-to-result delay. It does not test the
physical microphone or prove coverage of every accent or Philippine language.
It is never imported by the production `lib/main.dart`.

## Reproduction

Use Google FLEURS `fil_ph` test audio (CC-BY-4.0), not private user recordings.
Dataset: https://huggingface.co/datasets/google/fleurs
References: `data/fil_ph/test.tsv`. This check uses
`10030073068120699612.wav` (12.3 seconds), with the supplied reference transcript.
Audio is 16 kHz mono IEEE float32 WAV; extract its data chunk to raw little-endian
float32 PCM. Files/results are stored locally under ignored `evaluation/private/`.
This is a tiny diagnostic sample, not a representative multi-speaker benchmark.

Push PCM into the app's private `files/evaluation/sample.f32` via ADB and run:

```
flutter build apk --debug --target-platform android-arm64 --target tools/live_device_probe.dart
# Install using adb install -r, then launch MainActivity on an unlocked phone.
# For Base final review append --dart-define=ASR_TEST_BASE=true.
# For cancellation append --dart-define=ASR_TEST_CANCEL=true.
# Read files/evaluation/result-*.json using adb exec-out run-as.
```

Always rebuild/install the normal `lib/main.dart` APK after testing. Reference
scoring uses `tools/score_asr.py` normalization (case folding, punctuation removal,
whitespace collapse). Keep false-correction and semantic review separate.

## Remaining checks

Actual microphone-to-caption latency, multi-speaker Tagalog/Cebuano accuracy,
noise/accents/Taglish, five-minute thermal behavior, peak RSS, full manual scroll
and background/permission stress checks remain required. Translation and TTS are
still placeholders, so there is no full translator offline claim.

## Observed Galaxy A16 results

| Public Filipino clip | Tiny final WER | Base final WER |
| --- | ---: | ---: |
| 10030073068120699612.wav · 12.3 seconds | 38.9% | 27.8% |
| 10016150700374001635.wav · 24.42 seconds | 87.5% | 46.9% |

Aggregate: 35/50 word edits for Tiny (70% WER), 20/50 for Base (40% WER).
Both still make substantial errors. This tiny sample supports keeping Base as an
optional comparison, not claiming accurate Filipino or Cebuano recognition.
Speakers' identities were not established; do not call this a multi-speaker test.
Scoring retains reference digits versus spoken number words, which can inflate
errors. No automatic correction was applied. Summary: `filipino-diagnostic-results.json`.

On the short clip, the actual Flutter Tiny replay emitted text at 6.571 seconds
and again at 11.572 seconds, before the 12.298-second replay ended. Final result
arrived 4.251 seconds after Finish. Base-only preview produced no update before
replay ended and took 21.143 seconds after Finish (including preview cancellation).
The balanced Tiny-preview/Base-final change was made in response. Its foreground
device verification was blocked when the phone locked; do not treat the Tiny-only
and Base-only measurements as a completed test of the combined mode.

Native batch Base on the short clip: 12.402 seconds with two CPU threads versus
10.912 seconds with four, identical text. Four threads retained. On the longer
clip: Tiny 6.140 seconds, Base 12.739 seconds, excluding model loading/UI transfer.
Single runs, not latency percentiles; battery/thermal state was not controlled.
