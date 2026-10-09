# Bidirectional refinement — 10 October 2026

Implemented directly in the existing Flutter Android app. The two supplied master
prompts contain the same requirements. This pass extends the existing working
translation, recognition and playback integrations; it does not replace them.
The code and build checks below pass. Language-quality and physical-device
acceptance remain incomplete and must not be presented as production readiness.

## Audit and compatibility decisions

| Area | Existing implementation and decision |
| --- | --- |
| Framework | Flutter 3.44.2 / Dart 3.12.2; StatefulWidget UI and a ChangeNotifier translation controller. Preserve architecture and black/yellow Salin styling. |
| Tagalog ASR | whisper_cpp_flutter_plus 0.5.1, whisper.cpp, pinned multilingual Tiny Q5_1 (~32 MB) and Base Q5_1 (~63 MB). Four CPU threads, final greedy best-of 1, `tl`, temperature increment 0.2. Keep final decoding unchanged. Tiny provides optional provisional previews; installed Base can finalize. |
| Cebuano ASR | Existing imported 190,085,487-byte Q5_1 Small derivative of `eemberda/phcodeswitch-ceb-dvo`, pinned revision and SHA-256 in `cebuano-model-manifest.json`. Uses the fine-tuning's `tl` decoder prompt with beam size 5, not an invented stock Whisper `ceb` token. Separate checkpoint; preview disabled. Limited dialect/code-switch validation. |
| Audio | Shared microphone, 16 kHz mono float32 PCM, requested 100 ms chunks, five-minute cap. Buffers drain before finalization; no new gain, resampling, silence trimming or denoising. Existing optional Android NoiseSuppressor stays off by default. |
| Translation | Real quantized NLLB-200 distilled 600M ONNX inference, ONNX Runtime Android 1.23.2 CPU, SentencePiece 0.2.0 JNI. `tgl_Latn` 256174 ↔ `ceb_Latn` 256035. Source prefix and forced target verified by native tests and pinned tokenizer. No dictionary substitution. |
| Limits | Existing 8,000-character / 512-token per-passage guards, output completion checks and native two-minute timeout remain. Optional independent-line mode keeps the 8,000-character total guard and applies native token/output/timeout limits separately to each line. Long batches may take multiple timeouts' worth of time; switching or clearing cancels the batch. |
| Resources | Translation downloads total 899,478,308 bytes plus packaged mobile graphs and temporary installation space. 64-bit Android only; native worker and cancellation fence keep Whisper and translation from competing for memory. No new resident models or parallel microphone pipeline. Prior phone PSS measurements are historical, not new measurements in this pass. |
| TTS | Android TextToSpeech, installed non-network voices only; `tl`/`fil` for Tagalog, exact `ceb` for Bisaya. Availability checked before playback. Missing voices produce a local notice. Existing speak/stop/replay behavior retained; pause was not available. |
| Startup | The app opens the branded Salin landing page and its existing Start button pushes the translator. The translator back arrow returns to the landing page. Recognition and translation model checks stay lazy inside the translator; no timer or new network request was added. The previous multi-step onboarding flow is no longer on the app's launch path. |
| Dependencies | None added or upgraded. Model hashes, Android min API 24, Java 17, ONNX runtime, SentencePiece and Flutter dependencies unchanged. |

Primary compatibility sources checked:
[NLLB model card](https://huggingface.co/facebook/nllb-200-distilled-600M/blob/main/README.md),
[pinned tokenizer config](https://huggingface.co/Xenova/nllb-200-distilled-600M/blob/261c31d1a5732c67cdd16d80e8d6088507c7ccea/tokenizer_config.json),
[Android Voice](https://developer.android.com/reference/android/speech/tts/Voice),
[Android NoiseSuppressor](https://developer.android.com/reference/android/media/audiofx/NoiseSuppressor).
NLLB and the imported Cebuano checkpoint carry noncommercial research licenses;
the NLLB publisher does not release it as a production deployment model.
Existing research notices remain. A commercial release needs a suitable model
and licensing decision, as well as release signing (currently debug signing).

## Implemented behavior

- Every direction retains its own source, translation and translation failure.
  Speech metadata retains raw recognition, language, model, timing and audio
  notice. Swapping restores that direction without reinterpreting or retranslating
  text. Restored results say **Saved translation**. Completed history survives.
- Cancelled, failed and empty recordings restore the previous draft. Starting
  another recording first awaits native cancellation. Switching remains locked
  during microphone preparation, capture and final recognition.
- Request and playback generations reject late output even after swapping away
  and back. Playback waits for previous cancellation to finish; retranslation
  resets its generation and active history item. Controls correctly distinguish
  current-result playback from history playback.
- **Review before translating** is optional; automatic final-text translation
  remains the default. Missing translation weights leave the final source for
  review/setup. Provisional recognition never enters translation.
- Unchanged edits retain valid output. Changed edits invalidate it. Explicit
  **Clear current turn** affects only the selected direction and leaves history.
- **Translate each line separately** is an opt-in inference refinement for
  independent messages. It uses the actual existing model sequentially, preserves
  blank lines, and commits one result/history entry only if all lines succeed.
  Cancellation or any line failure rejects the entire partial result. Default
  passage inference keeps contextual continuity and unchanged decoding.
- Direction selector plus Speak/type → Review → Translate → Play/copy indicators
  reflect the selected draft. Translation completion requires a successful result.
  Recording status names the active language and wraps at large text sizes.
  Removed the redundant translation progress bar and aligned preview notices with
  the actual **Stop** control. Copy/edit/retry/playback are working controls.

## Actual translation comparison

Run `tools/compare_translation.py` in the pre-existing evaluation venv. It verifies
source weights and mobile graphs, then runs actual CPU ONNX inference. Results:
[`translation-refinement-comparison.json`](../benchmarks/translation-refinement-comparison.json).
The 28 cases comprise 14 in each direction: everyday/casual speech, questions,
commands, negation, affixes, dates, names, numbers, long clauses, English mixing,
and separate lines. For the 22 single-line cases the candidate uses exactly the
same inference path; results are reused and explicitly have no second timing.
The six multiline cases have separate baseline and candidate inference runs.

| Diagnostic | Measurement |
| --- | --- |
| Baseline Tagalog → Bisaya | 14 cases; median 4.35 s; range 2.45–13.03 s |
| Baseline Bisaya → Tagalog | 14 cases; median 5.24 s; range 2.43–13.09 s |
| Six multiline cases | Median baseline 7.61 s; independent-line candidate 9.19 s |
| Literal required-name omissions | Baseline 3; candidate 2 across all cases |

Example: the baseline omitted `Nasaan si Maria?` when it preceded two other
messages on separate lines. Independent-line inference returned `Hain si Maria?`
and both other translations. The reverse multiline baseline dropped the entire
book-giving command; the candidate restored a command, but still replaced Juan
with a pronoun. Another casual Cebuano example had poor wording in both modes.
These are narrow diagnostic findings, not a general accuracy improvement.

The [`translation-cases.json`](translation-cases.json) reference translations are
explicitly AI-drafted and pending independent fluent-speaker review. No human
review or adequacy score is claimed. This does **not** satisfy the requested
manually reviewed reference-set acceptance criterion. Do not use literal name
retention as a semantic quality metric. NLLB still makes serious meaning errors,
including aspect/subject errors and invented time specificity on longer text.

## Speech and noise evidence

No acoustic preprocessing or ASR decoding changed, so no recognition improvement
is claimed. New host CLI runs used the verified existing Tiny and Cebuano Small
weights on the two available public Filipino recordings and one available
Cebuano clip. Raw results, commands, model hashes, reference provenance, scores
and host wall times are in
[`current-host-asr-diagnostic.json`](../benchmarks/current-host-asr-diagnostic.json).

| Host diagnostic | WER | CER | Wall time including CLI/model initialization |
| --- | --- | --- | --- |
| Tagalog Tiny, two clips | 72.00% | 18.43% | 0.71 s and 0.59 s |
| Cebuano Small, one clip | 41.94% | 21.99% | 6.43 s |

This CLI uses host acceleration and is not the Android application runtime. The
tiny dataset and publisher references cannot establish representative accuracy,
Android latency, app regression parity or acoustic enhancement quality. Existing
noise fixtures and scoring tools remain usable, but actual paired microphone
recordings with suppression on/off require hardware. Do not enable suppression
by default on the strength of these results.

## Verification

- Before changes: **44 Flutter tests passed**.
- Before restoring the landing page, **58 Flutter tests passed**.
- After the landing-page navigation change: **56 Flutter tests passed**, including
  the asset/start/main/back/settings navigation flow and both
  ASR-to-translation direction routes using test doubles, final-only routing,
  editing/retry, retained drafts, stale results, review mode, cancellation restore,
  copy payloads, independent-line failure/cancellation, voices, onboarding retry,
  audio validation and layouts at 320/390/430 widths, landscape and 2× text.
- `flutter analyze`: **no issues**.
- `./gradlew :app:cleanTestDebugUnitTest :app:testDebugUnitTest`: **3 native
  NLLB token tests passed** after clearing previous test results and executing again.
- `python3 -m unittest discover -s tools -p 'test_*.py'`: **4 passed**.
- ARM64 debug APK built; ARM64 release APK built (~101 MB). Release configuration
  still uses existing debug signing; this is not a signed store release.
- Rendered screenshots captured via the existing layout suite and visually
  inspected: `build/salin-ui/capture-text.png`, `build/salin-ui/result.png`.
  Widget screenshots use test-double text and are not translation evidence.
- Real model evaluation: 28 NLLB cases, six independent-line comparisons and
  three host ASR clips as described above. No inference service was used.
- `git diff --check`: clean.

No Android device was connected (`adb devices -l` empty). End-to-end physical
microphone recognition, installed-voice pronunciation/availability, airplane
mode, cold startup timing, memory/thermal performance and noise comparisons were
not run in this pass. Historical device reports are not counted as fresh tests.

## Files changed and remaining acceptance

Application changes: `translation_controller.dart`, `speech_home_screen.dart`,
`conversation_widgets.dart`, `live_recognition.dart`, `onboarding_gate.dart`.
Tests: `translation_controller_test.dart`, `translation_screen_test.dart`,
`widget_test.dart`. Evaluation: `tools/compare_translation.py`, the case set,
two benchmark JSON reports, this report, evaluation README and root README.
No dependency manifests or model files changed.

Next acceptance work: independent fluent Tagalog/Cebuano review of the case set
and model outputs; held-out multi-speaker speech recordings; connected Android
tests of both directions, cancellation, voices and airplane mode; matched clean
and noisy acoustic testing; device latency/memory/thermal runs. Cebuano speech
requires the existing verified model import, and Cebuano playback requires an
installed exact-language offline voice. No new voice was installed or verified.
The app remains Android-first and research/demo licensed. These limitations
prevent claiming the entire production-readiness acceptance list is complete.
