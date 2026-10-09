# Accuracy audit and evaluation gate

This is the original pre-live-caption audit. Current behavior and the first
public Filipino measurements are in [adaptive live captions](../benchmarks/adaptive-live-captions.md).

## Phase 1: audited baseline

This checkout implements ASR only. `SpeechHomeScreen` calls
`LocalWhisperSpeechService`: microphone -> buffered PCM -> Whisper -> result text.
The Cebuano panel is a placeholder; no translation or TTS implementation,
playback, history, correction dictionary or confidence UI exists to validate.
If those features exist elsewhere, provide that checkout before integration.

Runtime: whisper_cpp_flutter_plus 0.5.1, packaged whisper.cpp via FFI; recorder
uses Flutter method/event channels. Multilingual Tiny Q5_1 weights are pinned to
Hugging Face revision f281eb45af861ab5e5297d23694b7d46e090c02c, SHA-256
818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7.
Verified Base Q5_1 is a legacy fallback. CPU backend, four threads, greedy
best-of 1, Tagalog `tl` (verified in bundled whisper.cpp language table), no
timestamps. Library defaults: temperature 0, temperature increment 0.2,
no context true, no-speech threshold 0.6, entropy threshold 2.4,
log-probability threshold -1. No initial prompt, VAD or custom filtering.
Temperature fallback is a candidate for evaluation, not a proven error source.

Recorder contract is mono float32 PCM, requested at 16 kHz in 100 ms chunks.
Service checks reported sample rate, concatenates chunks, and decodes once after
Finish. No resampling or gain transformation is added. Audio remains in memory.
The UI uses setState, native progress and a separate recording stopwatch.

The reported kumayim error cannot be attributed to acoustics versus decoding
without the actual recording. Tiny's suitability for this speaker is unmeasured.
The existing English latency benchmark is not evidence of Tagalog accuracy.

## Phases 2–4: evaluation before tuning

No consented reference recordings are present, so baseline WER/CER and accuracy
improvement are **not measured**. No model, decoding or word replacement changes
were made. New validation rejects empty, exactly silent and malformed PCM;
quiet speech and full-scale samples remain accepted. No uncalibrated loudness
threshold, denoising, gain or VAD was applied.

Collect consented recordings from at least three speakers, with three repeats
per phrase. Cover normal/fast/quiet/loud speech, near/far microphone placement,
clean/moderate noise, pauses, short words and longer dictation. Include kumain,
kumakain, kakain, kinain, kain, kailangan, kaibigan, maganda, magkano, pumunta,
pumunta na and kumusta in natural sentences. Include Taglish, proper nouns,
negation, numbers and questions. Have speakers verify exact reference text.
Do not use synthesized speech as proof of real-speaker accuracy.

Keep audio and results in ignored `evaluation/private/`. For each configuration,
write one JSONL row per recording with string fields:
`id`, `speaker` (pseudonym), `style`, `reference`, `raw`, `corrected`.
Use identical recording IDs/reference transcripts across runs. For the unchanged
baseline, corrected equals raw. Score with:

```
python3 tools/score_asr.py evaluation/private/baseline.jsonl
python3 tools/score_asr.py evaluation/private/candidate.jsonl
```

Scoring applies Unicode NFC, case folding, punctuation-to-space and whitespace
collapse. CER excludes spaces. WER/CER are corpus micro averages; empty references
still count insertions. Also report normalized exact match and corrections that
increase word edit distance. This last count is only a proxy: a fluent reviewer
must separately label false corrections and changes of meaning. Keep punctuation
and capitalization quality as a separate review. Compare per speaker/style by
scoring subsets, and preserve raw results for repeatability.

Evaluate one variable at a time: baseline vs temperature fallback disabled;
then beam search; then a concise contextual prompt; then Base Q5_1 if needed.
Do not promote candidates unless held-out multi-speaker WER/CER improves without
unacceptable false corrections, latency, RAM or crashes. Measure model load,
Finish-to-result latency, peak RSS and three repeat runs on the target phone.
Report median/worst time, crash count, model hash and all decoding parameters.

## Phases 5–7: current safeguards and remaining validation

Transcript editing is available without rerecording. Raw ASR remains in memory
and can be viewed after editing; copying uses the reviewed text. No transcript
or recording is logged or transmitted. No speculative automatic word correction
was introduced. Empty recognition now shows an actionable error.

Translation adequacy, matching displayed Cebuano to TTS input, replay and full
pipeline offline testing await the actual translation/TTS implementation.
Validate those with a competent Cebuano speaker, including negation, aspect,
names, numbers and questions. Never infer those results from ASR tests.

Regression checks: recording timer, Finish, cancellation, permission denial,
model download/verification, copy, edit/save/cancel and raw text retention; repeat
ASR in airplane mode. Unit tests cover malformed/silent/quiet/full-scale audio
and scoring substitutions/insertions/deletions and harmful corrections. Device
microphone, edit interactions, accuracy and airplane-mode checks still require
manual execution; passing build/tests alone does not establish those results.

## Broader Philippine language scope

The app now offers Tagalog/Filipino (`tl`, default), English (`en`) and
experimental automatic language detection (`auto`). Selection is locked during
recording/processing and captured when recording starts. Existing callers retain
Tagalog by default. Translation remains unimplemented.

Inspection of the installed whisper.cpp language table found no dedicated
Cebuano, Ilocano, Hiligaynon, Waray, Kapampangan or Bikol language entries.
Auto-detection is limited to the model's supported inventory; it does not provide
validated support for these languages or reliable within-sentence code switching.
The selector is a capability control, not evidence of improved accuracy.

Regional coverage requires per-language model candidates, licensed/consented
multi-speaker reference sets, on-device accuracy and resource benchmarks, and
translation/TTS evaluation for each advertised language pair. Do not display
unsupported languages as working choices simply by assigning them Tagalog codes.

## Optional Base comparison

“Refine with Whisper Base” selects the pinned multilingual Base Q5_1 descriptor
already present in the project. If it is missing, the app requires its explicit
verified download instead of silently using Tiny. Downloads retain both models;
switching unloads the previous engine. The choice is session-only and defaults to
Tiny on launch. Recorded result labels retain the model actually used even after
switching. The existing optimized native build remains enabled.

Decoding is unchanged to isolate the model variable. No measured Tagalog accuracy
improvement is claimed. Compare the same consented recordings with Tiny and Base,
using `tl` for Tagalog and the scoring procedure above. Record latency and peak
memory too. No vocabulary substitution or new language support is implied.
