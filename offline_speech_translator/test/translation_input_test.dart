import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/translation/data/translation_input.dart';
import 'package:offline_speech_translator/features/translation/domain/translation.dart';

void main() {
  test('sentence-cases unpunctuated Tagalog without guessing punctuation', () {
    expect(
      prepareTranslationInput(
        'saan tayo pupunta mamaya',
        TranslationLanguage.tagalog,
      ),
      'Saan tayo pupunta mamaya',
    );
  });

  test('preserves words, names, numbers, punctuation and whitespace', () {
    for (final pair in [
      (
        'pakibigay kay Juan ang 3 libro bukas',
        'Pakibigay kay Juan ang 3 libro bukas',
      ),
      (
        '  “saan si Maria?”\nNasaan si Juan?',
        '  “Saan si Maria?”\nNasaan si Juan?',
      ),
      ('i-send kay Ana.', 'I-send kay Ana.'),
      ('hindi ako pupunta sa Mayo 12', 'Hindi ako pupunta sa Mayo 12'),
    ]) {
      expect(
        prepareTranslationInput(pair.$1, TranslationLanguage.tagalog),
        pair.$2,
      );
    }
  });

  test('does not rewrite mixed-case names or already capitalized inputs', () {
    for (final text in [
      'iPhone ang gamit ni Juan.',
      'eBay ang pangalan.',
      'Saan tayo pupunta mamaya?',
      '3 libro para kay Juan.',
      '',
      '   ',
    ]) {
      expect(prepareTranslationInput(text, TranslationLanguage.tagalog), text);
    }
  });

  test('leaves the reverse direction unchanged', () {
    const text = 'asa ta moadto unya';
    expect(prepareTranslationInput(text, TranslationLanguage.cebuano), text);
  });
}
