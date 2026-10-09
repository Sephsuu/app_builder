# Salin onboarding and conversation UI

Implemented October 10, 2026. The three-step flow now appears only in first-run
onboarding. Returning users open a single conversation translator screen.

## Behavior

- Welcome, three numbered interactive example steps, back navigation, and
  Start Translating. Examples are explicitly labeled; they do not request
  microphone access or pretend to run a model. Demo playback explains that a
  real installed voice is used on the translator screen.
- `SharedPreferencesAsync` persists completion only after a successful write.
  Preference read/write errors provide retry without losing onboarding state.
- One main screen contains source/target selectors, speaker swap, microphone,
  Stop/Cancel, original and translated text, copy/edit, installed offline TTS,
  and scrollable conversation history. Translate Again begins a new recording
  directly. Completed results scroll into view.
- History retains successful original/translation pairs and their direction for
  the current session. Replaying an older entry uses its own target language.
  Failed or cancelled/stale outputs are never archived. Conversation text is
  not persisted across app restarts.
- Idle, microphone startup, listening, final recognition, translation, playback,
  model loading/download and error states have explicit feedback. Sticky
  recording controls remain accessible while scrolling. Backgrounding cancels
  capture and stops playback; permission denial returns an actionable error.

## Actual microphone waveform

The existing 16 kHz mono float32 recording stream supplies RMS per captured
chunk, using the same validated samples retained for Whisper. No samples are
changed, gated, resampled or discarded for visualization. A logarithmic visual
envelope with attack/release smoothing feeds 36 bars interpolated over 90 ms.
Silence approaches zero height. There are no random or decorative level events.
The waveform is shown only while recording. Subscriptions and service streams
are closed on disposal.

Existing Whisper Tiny/Base and Cebuano model selection, NLLB offline translation,
exact-language native offline TTS, model verification/import/download, live
captions, diagnostics, noise suppression and settings remain connected to the
existing services. No cloud inference or production mock was introduced.

## Validation

- `flutter analyze`: no issues.
- `flutter test --dart-define=SALIN_SCREENSHOTS=true`: all 44 tests passed.
  Coverage includes measured PCM levels, quiet/loud/silence smoothing, capture
  disposal, lifecycle interruption, denied permission, both translation
  directions, history playback, stale results, onboarding persistence/failure
  retry and immediate repeat recording.
- Responsive widget checks: 320×568, 390×844, 430×932 and 844×390, plus 2× text.
- `flutter build apk --debug --target-platform android-arm64`: successful.
- Pixel 8 Android emulator: launched native app, completed welcome and all
  three steps, entered main UI, force-stopped, installed the updated APK with
  data preserved, and relaunched directly into the translator. This checks the
  real Android preference backend, beyond the injected widget-test store.

The emulator has no installed AI models. This pass validates native startup,
setup presentation and onboarding persistence, not physical microphone quality,
acoustic transcription/translation accuracy or availability of Cebuano TTS.
Those checks still require a physical device with the existing models/voices.
Prior model evaluation limits remain in the earlier implementation reports.

## Screenshots

Native Android screenshots use the production app without injected AI services:

- [Welcome](salin-conversation-ui/android-welcome.png)
- [Onboarding result](salin-conversation-ui/android-onboarding-result.png)
- [Main screen and setup](salin-conversation-ui/android-main.png)
- [Returning user after APK update](salin-conversation-ui/android-returning-user.png)

Widget renderings below use deterministic injected test services; their text is
layout-test data and does not demonstrate AI inference quality:

- [Ready to record](salin-conversation-ui/widget-capture-empty.png)
- [Source text](salin-conversation-ui/widget-capture-text.png)
- [Completed translation](salin-conversation-ui/widget-result.png)
- [Preserved settings](salin-conversation-ui/widget-settings.png)
