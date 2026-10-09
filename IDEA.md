# Offline Philippine Language Speech Translator — Simple Project Plan

## 1. Project Overview

Build a **Flutter mobile app** that lets a user speak in a Philippine language (starting with **Tagalog/Filipino**) and receive the translation as **text and spoken audio** in a selected target language. After setup and downloading the models, the translation pipeline should work **without internet**.

**MVP example:**

- **Input language:** Filipino/Tagalog
- **Spoken input:** “Magandang umaga. Kumusta ka?”
- **Target language:** English
- **Translated text:** “Good morning. How are you?”
- **Spoken output:** The phone speaks the English translation.

> Note: Cebuano, Ilocano, Hiligaynon, Waray, and others are Philippine languages, not simply dialects of Tagalog. Their model support and translation quality must be tested individually.

## 2. Main User Flow

```text
Choose source language + target language
                ↓
        Tap microphone button
                ↓
          Record speech
                ↓
   Offline speech-to-text (ASR)
                ↓
        Original transcript
                ↓
     Offline text translation
                ↓
         Translated text
                ↓
    Offline text-to-speech (TTS)
                ↓
   Play translated speech 🔊
```

The app should display **both** original and translated text, with a button to replay the audio. Start with **push-to-talk**, not continuous simultaneous translation.

## 3. MVP Features

| Priority | Feature | Description |
|---|---|---|
| Must | Language selection | Filipino → English (first supported pair) |
| Must | Record voice | Tap to start/stop recording |
| Must | Offline speech recognition | Convert recorded speech to source-language text |
| Must | Offline text translation | Translate transcription into target language |
| Must | Translation display | Show original and translated text |
| Must | Offline speech synthesis | Speak translated text in target language |
| Must | Replay | Replay the last translated audio |
| Should | Error handling | Model unavailable, mic denied, no recognizable speech |
| Later | Regional languages | Cebuano, Ilocano, Hiligaynon, Waray, etc. |
| Later | Live streaming | Continuous speech translation |
| Later | Translation history | Store translations locally |

## 4. Design — Basic Screens

### A. Home / Translator Screen

```text
┌────────────────────────────────┐
│      Offline Translator 🇵🇭    │
│           ● Offline            │
│                                │
│  From: Filipino  →  English    │
│                                │
│       [ 🎙️ Hold / Tap ]       │
│                                │
│  Original                      │
│  Magandang umaga. Kumusta ka?  │
│                                │
│  Translation                   │
│  Good morning. How are you?    │
│                                │
│  [ 🔊 Play translated speech ] │
└────────────────────────────────┘
```

### B. Settings / Model Status

Show which language models are installed, approximate storage usage, and whether offline translation is ready. If a required model is missing, show that it must be downloaded **before** offline use.

## 5. Implementation Architecture

```text
Flutter UI
  ├── Microphone / audio recording
  ├── Language selector
  ├── Transcript and translation display
  └── Audio player
          │
          ▼
Local speech-to-text model (ASR)
          │ text
          ▼
Local text translation model
          │ translated text
          ▼
Local text-to-speech model (TTS)
          │ audio
          ▼
Flutter playback
```

### Suggested models to evaluate

- **ASR:** Whisper (via a compatible offline runtime) for Filipino/English; evaluate Meta MMS or Philippine-language fine-tunes for additional languages.
- **Translation:** NLLB-200 or a tested language-specific offline model, provided the target language pair is supported.
- **TTS:** Piper, MMS-TTS, or another local TTS voice with confirmed support for the **target** language.

**Important:** There is no guaranteed all-in-one, mobile-ready offline model for every Philippine language. Check model licenses, device memory, runtime compatibility, and native-speaker accuracy before committing. A research model may have noncommercial licensing restrictions.

### Deployment choices

**Option A — Recommended for a 24-hour hackathon:** Flutter captures audio; ASR, translation, and TTS run on a **local laptop server**, reached over the same Wi-Fi network. **No internet is required during use**, but the phone needs the nearby laptop and local network.

**Option B — Fully on-device (future target):** Run all three optimized models directly inside Flutter through native/mobile inference libraries. No laptop, Wi-Fi, or internet is needed after installation, but this requires model conversion, device benchmarking, and more development time.

## 6. Development Steps

1. **Set up Flutter UI:** Language dropdowns, microphone control, transcript, translation, play button.
2. **Implement audio recording:** Request microphone permission and record short voice clips.
3. **Integrate ASR:** Return original-language transcript from a locally running model.
4. **Integrate translation:** Pass transcript to local text translation and show the output.
5. **Integrate TTS:** Produce audio from the translated text and play it.
6. **Handle failures:** Missing model, unsupported pair, silence, microphone permissions, processing failure.
7. **Test without internet:** Disable internet and repeat the complete speech → text → translated text → speech flow.
8. **Improve accuracy:** Collect consented test clips with native speakers and measure transcription, translation quality, and latency.

## 7. Proposed 24-Hour Hackathon Schedule

| Time | Task |
|---|---|
| Hours 0–3 | Select one language pair, verify offline models, and run end-to-end model tests |
| Hours 3–7 | Flutter UI and audio recording |
| Hours 7–12 | Integrate speech-to-text and translation |
| Hours 12–16 | Integrate TTS and audio playback |
| Hours 16–20 | Error handling and real-device offline testing |
| Hours 20–24 | Improve UI, test example phrases, and rehearse demo |

## 8. Acceptance Criteria

- [ ] User can select Filipino as source and English as target.
- [ ] User can record a short Filipino phrase.
- [ ] App displays the original transcript.
- [ ] App displays a translated English sentence.
- [ ] App speaks the English sentence aloud.
- [ ] User can replay the translated speech.
- [ ] All inference occurs locally with internet disabled.
- [ ] Errors are clearly displayed for unsupported language pairs or missing models.

## 9. Expansion to Philippine Regional Languages

Add each language only after you verify the full pipeline:

| Language | ASR tested? | Translation tested? | Output TTS tested? |
|---|---|---|---|
| Filipino / Tagalog | Pending | Pending | Pending |
| Cebuano | Pending | Pending | Pending |
| Ilocano | Pending | Pending | Pending |
| Hiligaynon | Pending | Pending | Pending |
| Waray | Pending | Pending | Pending |

**Success metric:** A native speaker can speak a short phrase, see an accurate original transcript and translation, and hear understandable translated speech — all with internet disabled.
