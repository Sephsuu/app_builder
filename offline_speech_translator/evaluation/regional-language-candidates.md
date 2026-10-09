# Philippine ASR scope and next candidates

The app's verified language identifiers remain Tagalog (`tl`), English (`en`)
and the installed model's automatic detection mode. Language identifiers alone
are not evidence of accuracy. Cebuano / Bisaya is the user's next priority.
Do not label stock Whisper Tiny/Base as Cebuano models or as supporting all
Philippine languages. The Davao Cebuano candidate below now has an optional evaluated GGML integration;
see [current results](implementation-results.md).

## Cebuano: next evaluation candidate

[eemberda/phcodeswitch-ceb-dvo](https://huggingface.co/eemberda/phcodeswitch-ceb-dvo)
is a Whisper Small model fine-tuned for Davao Cebuano and English–Cebuano speech.
The publisher reports 20.86% test WER; this is their result, not a measurement of
this app. The card notes limited accent/vocabulary coverage. Its CC-BY-NC-4.0
license permits non-commercial use subject to its terms, not general commercial
shipping. Model API revision inspected: `3a6999b22f5ebd754a25ce59c54897e2ac1e930d`.

The repository contains Safetensors/config/tokenizer files, not a ready GGML
artifact. It uses the Tagalog decoder prompt because it was specifically trained
that way; using `tl` with the unmodified stock model does not reproduce this
training. Conversion, tokenizer verification, Q5_1 quantization and a one-clip Galaxy A16
benchmark are complete. PyTorch-reference parity and broader evaluation remain. Do not silently change the
selected Tagalog checkpoint or promise instantaneous Small inference.

[BuzzASR/cebuano](https://huggingface.co/BuzzASR/cebuano) is another candidate,
based on Whisper Large-v3 with an MIT model-card license and publisher-reported
FLEURS evaluation. Its size makes it a poor first candidate for rapid CPU preview
on this target. This is an engineering inference, not an Android benchmark.

## Broader coverage

[facebook/mms-1b-all](https://huggingface.co/facebook/mms-1b-all) lists Tagalog,
Cebuano, Hiligaynon, Ilocano, Waray and other languages with language adapters.
It has one billion parameters and a CC-BY-NC-4.0 license. It needs a different
inference path and mobile conversion/quantization validation. Its broad language
inventory does not establish conversational accuracy or mobile speed.

For each candidate, test held-out native speakers, regional pronunciation,
Taglish/code switching, negation/names/numbers, natural repetition, noise and
quiet speech. Measure WER/CER, first-caption time, final delay, peak memory and
thermal slowdown. Keep language-specific checkpoints replaceable and install
only after confirming format, license and quality. The app has no cloud fallback. Translation has known quality failures and the
tested phone lacks offline target-language voices; see the current results.
