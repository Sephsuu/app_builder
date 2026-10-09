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
