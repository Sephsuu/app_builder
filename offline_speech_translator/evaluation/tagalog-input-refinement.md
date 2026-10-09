# Tagalog speech-text translation: casing regression

The reported input was `saan tayo pupunta mamaya`, with `atong paglawak` as
the reported wrong output. That exact wrong output did not reproduce on the
current pinned weights. However, the lowercase input produced
`asa man kita sa ulahi` on both the host and the connected Android phone,
omitting the movement expressed by `pupunta`.

Sending `Saan tayo pupunta mamaya` instead produced
`Asa kita moadto sa ulahi` on both systems. This restores the movement and
later-time meaning in this example. It is a targeted diagnostic result, not a
general translation-accuracy score or independent fluent-speaker approval.

## Change

`LocalTranslationService` now sentence-cases an entirely lowercase opening
word before Tagalog-to-Bisaya inference. It leaves internal casing, mixed-case
names such as `iPhone`, words, punctuation, numbers and newlines intact. It does
not guess punctuation, split sentences, substitute translations or alter the
displayed/saved original. Bisaya-to-Tagalog input remains unchanged.

The translation checkpoint, tokenizer, language IDs and greedy decoder are
unchanged. Whisper recognition, audio capture, TTS, landing page and navigation
are unchanged. No dependency, download or extra inference pass was added.

## Evidence and limits

- [Host results](../benchmarks/tagalog-input-host.json): six lowercase inputs,
  each compared against its sentence-cased input through the existing
  `tools/evaluate_nllb.py::translate` mobile-graph greedy decoder. The user's
  example recovers `moadto`; the book-giving command and eating question differ
  only in output casing; the negative/date example is unchanged. The longer
  eating/aspect sentence remains wrong in both variants. Casing does not fix
  the model's underlying grammatical and semantic weaknesses.
- [Android results](../benchmarks/tagalog-input-android.json): real inference on
  model `25057RN09G`, arm64, using the installed verified checkpoint. Raw input
  took 73.505 seconds; capitalized input took 69.799 seconds. These observations
  were collected while the screen was asleep, and are not a controlled speed
  comparison. The probe was stopped after this required pair completed; its
  other three cases are explicitly **not** claimed as completed.
- Exploratory three-candidate beam search improved some host examples but
  changed a correct book-giving instruction into a wrong movement instruction.
  It was not adopted. No broad decoder improvement is claimed.
- The new example is in `translation-cases.json`. Its reference is AI-drafted
  and marked as awaiting fluent-speaker review; the user's reported output is
  stored separately from the measured outputs.

Validation: all 61 Flutter tests pass, including input-preservation rules and
the native channel's prepared input/language codes. `flutter analyze` reports
no issues. The normal debug APK was built, installed over the temporary probe
without clearing app data, and launched again.

## Reproduce the phone comparison

`tools/tagalog_translation_probe.dart` is a developer-only entry point that
writes actual model outputs and per-case errors to
`files/evaluation/tagalog-translation-result.json` in the app's private data.
Build with `--dart-define=RAW_INPUT=true` for the raw native-input baseline;
omit it for the production service's input preparation. It needs the installed
translation weights. It contains diagnostic inputs, never replacement outputs.

```sh
flutter build apk --debug --target-platform android-arm64 -t tools/tagalog_translation_probe.dart --dart-define=RAW_INPUT=true
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.example.offline_speech_translator/.MainActivity
adb exec-out run-as com.example.offline_speech_translator cat files/evaluation/tagalog-translation-result.json
```

Wait for the report to say `complete: true` to claim the whole probe completed.
Always restore the application afterward:

```sh
flutter build apk --debug --target-platform android-arm64 -t lib/main.dart
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.example.offline_speech_translator/.MainActivity
```
