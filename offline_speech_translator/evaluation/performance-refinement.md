# Speech and translation performance — 10 October 2026

## Translation

Profiling on the connected `25057RN09G` ARM64 phone showed that decoder compute,
not the Kotlin vocabulary scan, dominated translation time. The old vocabulary
projection dequantized and transposed 256,206 × 1,024 weights in slices for every
generated token. A separate transpose copied roughly 1 GiB of float data per
token in aggregate.

The generated mobile graph now reshapes the batch-one hidden state and uses
`Gemm(transB=1)` on each contiguous weight slice, then restores the original
logit shape. This expresses the same multiplication without the explicit
transpose. [ONNX Gemm](https://onnx.ai/onnx/operators/onnx__Gemm.html) defines this
transpose attribute. Slice ordering dependencies and disabled constant folding
remain, so the graph does not materialize the whole float vocabulary matrix.
Both first-step and cached decoder branches were regenerated; the encoder is
byte-for-byte unchanged. Original weight files, quantization scales, source and
target IDs, greedy decoding and cancellation/timeout limits remain unchanged.

The packaged graph manifest contains its new checksum. Existing installations
replace only the small packaged graph on first use, using the existing verified
weight downloads. There is no new model download, dependency or API call.

### Measurements

[Host comparison](../benchmarks/translation-gemm-host.json): all 30 diagnostic
outputs match exactly, across both language directions, single sentences,
multiple lines and the reported travel question. Median time: **4.34 → 1.58 s**.
This compares actual ONNX Runtime 1.23.2 CPU inference, including session loads.
Floating-point equivalence for all inputs/devices is not claimed.

[Phone comparison](../benchmarks/translation-gemm-android.json):

| Input | Before | After | Output |
| --- | ---: | ---: | --- |
| `saan tayo pupunta mamaya` | 24.018 s | 11.435 s | `Asa kita moadto sa ulahi` in both |
| Same model input repeated | 19.375 s | 9.268 s | Identical |

The candidate also completed three additional Tagalog cases. Baseline profiling
for the first case measured 18.224 s inside decoder runs and 77 ms selecting
tokens; candidate measured 6.420 s and 78 ms, respectively. Session creation was
approximately 2.5 s total. One candidate memory observation was 848,905 KiB PSS,
not a measured peak. Full sessions are still released between calls to avoid
holding the large translation model alongside Whisper.

These are sequential debug-build observations on one phone, without controlled
thermal or power conditions. The earlier 70-second observations were a different
run and are not used as the baseline. Preserved text includes existing model
mistakes: this is a performance improvement, not a translation-quality claim.

## Speech

The model manager previously hashed the entire Whisper file every time it was
queried. Status checks, recording preparation and Tiny-to-Base finalization
could repeatedly read and hash the same file. The service now remembers a
successful verification in memory, keyed by expected checksum and file path,
size, modification time and change time. Changed, missing or replaced files
are reverified; downloads clear the cache; a fresh service verifies again.
Checksum failures are never cached, and a file that changes during verification
is rejected. No persistent trusted flag is written to disk.

Provisional captions now use 768 encoder frames (15.36 seconds of context) for
their at-most-12-second audio windows, instead of the model's 30-second default.
All captured samples still enter final recognition. A more aggressive 256-frame
minimum was rejected after it generated repetitive preview text on the phone.
The adopted 768-frame context did not produce that repetition in this fixture;
broader speaker/noise testing is still needed, and previews remain provisional.

The public 12.3-second Filipino fixture was replayed through the actual capture
service, Tiny previews and Base final recognition. The same final transcript
must be retained; it is not a perfect transcript and no WER improvement is
claimed. Final recognition continues to use the full audio, full encoder
context, four threads and the existing temperature-fallback settings.

[Phone speech results](../benchmarks/speech-performance-android.json):

| Measured stage | Before | After |
| --- | ---: | ---: |
| Repeat model verification | 1,523 ms | 1 ms |
| Recording preparation after availability check | 2,405 ms | 941 ms |
| First caption after recording begins | 8,070 ms | 4,334 ms |
| Stop to final transcript | 9,828 ms | 8,604 ms |

The final transcript matched exactly. Native final processing alone varied
from 8,043 to 8,229 ms; the finalization improvement comes from overhead,
not a faster or less accurate final decoder. First verification still takes
about two seconds in the debug build. No audio/context is removed from the
authoritative final pass, and Base is not silently replaced by Tiny.

## Validation

All 67 Flutter tests pass. The updated preview/cache tests also pass after the
final conservative context adjustment. Static analysis reports no issues;
Android native unit tests pass. Cache tests cover repeated access, missing and
modified files, failed verification, cache reset and changes during a checksum.
Existing preview tests cover cancellation, stale updates and slow-preview pause.

[Native smoke check](../benchmarks/performance-native-smoke.json) completed four
translations across both directions, cancelled a subsequent request, and
successfully translated again. The cancellation fence completed in 189 ms.
No offline Tagalog/Bisaya TTS voices were installed on this phone; this check
does not claim audible playback. The normal debug app was rebuilt and restored
after the probes, preserving app data and the installed model files.

## Reproduction

`tools/prepare_mobile_nllb.py --projection matmul` recreates the old graph;
`--projection gemm` creates the new one. Use separate private output directories
and place or symlink the original verified weight files and tokenizer into each.
`tools/compare_projection.py --baseline DIR --candidate DIR` verifies the files
and runs the 30-case comparison. It records incomplete progress explicitly.

The device entry points are `tools/tagalog_translation_probe.dart`,
`tools/live_device_probe.dart` and `tools/offline_device_probe.dart`. They are
developer probes, never release entry points. The speech probe now records
verification, preparation, finalization and native-processing times separately.
Use the public fixture `10030073068120699612.wav.f32` as `files/evaluation/sample.f32`.
Build the speech probe with `--dart-define=ASR_TEST_BASE=true`. Always rebuild
`-t lib/main.dart` and restore the normal app afterward without clearing data.
