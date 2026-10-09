/// Reject malformed or exactly silent normalized PCM, without filtering speech.
/// Quiet audio is retained: amplitude alone cannot distinguish speech from noise.
void validateAudio(List<double> samples) {
  if (samples.isEmpty) {
    throw const FormatException('No microphone audio was captured. Try again.');
  }
  var hasSignal = false;
  for (final sample in samples) {
    if (!sample.isFinite || sample.abs() > 1) {
      throw const FormatException('Invalid microphone audio. Record again.');
    }
    hasSignal |= sample != 0;
  }
  if (!hasSignal) {
    throw const FormatException('The microphone captured silence. Try again.');
  }
}

/// Signal diagnostics only, never a speech-confidence or noise/SNR estimate.
class AudioDiagnostics {
  int samples = 0;
  int fullScaleSamples = 0;
  double peak = 0;

  void add(List<double> chunk) {
    for (final sample in chunk) {
      final amplitude = sample.abs();
      if (amplitude > peak) peak = amplitude;
      if (amplitude >= .999) fullScaleSamples++;
    }
    samples += chunk.length;
  }

  double get fullScaleFraction => samples == 0 ? 0 : fullScaleSamples / samples;
  String? get notice => fullScaleFraction >= .005
      ? 'The microphone signal reached full scale repeatedly. Try speaking farther from the microphone and review the transcript.'
      : null;
}
