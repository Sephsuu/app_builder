# Native ASR optimization benchmark

Measured on Samsung Galaxy A16 (SM-A165F), 2026-10-09.

| Native libraries from arm64 debug APK | Recognition time |
| --- | ---: |
| Before: C kernels without optimization | 45.865239 s |
| After: C kernels compiled with `-O3` | 4.050861 s |

Single run per build, sequentially on the same phone: approximately 11.3× faster.
Both produced the same transcription. This is a diagnostic comparison, not a
statistical latency guarantee or a Tagalog accuracy benchmark.

Configuration: multilingual `ggml-tiny-q5_1.bin`, CPU, four threads, greedy
best-of 1, no timestamps, language `en`. Input is the plugin's public bundled
`example/assets/benchmark/jfk.wav`: 11 seconds, mono, 16 kHz. No user audio used.
The native `processing_us` measurement excludes model loading, microphone
capture, Flutter isolate transfer and UI updates.

The plugin supplied `-O3` for C++ sources only. Its C quantization/math kernels
were unoptimized in the previous debug APK. `android/build.gradle.kts` now sets
`cFlags` for this plugin. Verify `ggml-quants.c` in the generated
`compile_commands.json` contains `-O3` after building.

## Reproduction

1. Build the arm64 APK with `flutter build apk --debug --target-platform android-arm64`.
2. Extract its `lib/arm64-v8a/*.so` into a directory on a test device.
3. Compile `tools/native_asr_benchmark.c` using the Android NDK's
   `aarch64-linux-android24-clang -O3 tools/native_asr_benchmark.c -ldl -o native_asr_benchmark`.
4. Convert the bundled PCM16 WAV to raw little-endian float32 PCM by dividing
   each signed sample by 32768. Preserve mono 16 kHz sampling.
5. Push the harness, public audio and matching model to `/data/local/tmp`.
   Make the harness executable, then run on device:
   `LD_LIBRARY_PATH=<library-directory> ./native_asr_benchmark model.bin jfk.f32 en 4`.
6. Compare `processing_us` and transcription text from JSON stdout. Keep native
   logs on stderr. Run builds sequentially to avoid CPU contention.

For product validation, repeat with fixed Tagalog recordings and measure the
actual app's Finish-to-result latency, cold/warm starts, and transcription
quality. Recognition still starts after Finish; a two-minute recording is not
expected to complete instantly. No cloud inference was added.
