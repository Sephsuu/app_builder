import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/speech/domain/tagalog_transcript_review.dart';

void main() {
  test('keeps raw recognition and tracks automatic formatting separately', () {
    const raw = '  saan  tayo pupunta mamaya  ';
    final review = TagalogTranscriptReview.analyze(raw);
    expect(review.raw, raw);
    expect(review.cleaned, 'Saan tayo pupunta mamaya');
    expect(review.formatting, hasLength(2));
    expect(review.suggestions, isEmpty);
  });
  test('spelling suggestions never silently change the cleaned transcript', () {
    final review = TagalogTranscriptReview.analyze('saan tayo puponta mamya');
    expect(review.cleaned, 'Saan tayo puponta mamya');
    expect(review.suggested, 'Saan tayo pupunta mamaya');
    expect(review.suggestions, hasLength(2));
  });
  test('preserves negation, names, numbers, mixed-case and compound words', () {
    const text =
        "Hindi pupunta si Mamya sa Mayo 12. iPhone at puponta-test, 'mamya'.";
    final review = TagalogTranscriptReview.analyze(text);
    expect(review.cleaned, text);
    expect(review.suggested, text);
  });
  test('does not guess missing words or question punctuation', () {
    final review = TagalogTranscriptReview.analyze('saan tayo mamaya');
    expect(review.cleaned, 'Saan tayo mamaya');
    expect(review.suggested, 'Saan tayo mamaya');
  });
}
