import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/speech/domain/audio_validation.dart';

void main() {
  test('rejects empty, silent, nonfinite and out-of-range PCM', () {
    for (final samples in <List<double>>[
      [],
      [0, 0],
      [double.nan],
      [double.infinity],
      [1.1],
    ]) {
      expect(() => validateAudio(samples), throwsFormatException);
    }
  });
  test('preserves quiet speech and valid full-scale PCM', () {
    validateAudio([0, 0.000001, -0.000001]);
    validateAudio([-1, 0, 1]);
  });
}
