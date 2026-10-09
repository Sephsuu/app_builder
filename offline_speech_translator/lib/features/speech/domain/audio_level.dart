import 'dart:math' as math;

/// RMS is measured from the captured PCM without modifying inference audio.
double audioRms(Iterable<double> samples) {
  var energy = 0.0;
  var count = 0;
  for (final sample in samples) {
    if (!sample.isFinite) continue;
    energy += sample * sample;
    count++;
  }
  return count == 0 ? 0 : math.sqrt(energy / count).clamp(0.0, 1.0);
}

/// Logarithmic display range (-60 to 0 dBFS), with fast attack/slow release.
/// This is a visualization envelope, not a speech gate or confidence estimate.
class AudioLevelEnvelope {
  double _level = 0;
  double add(double rms) {
    final target = rms <= .001
        ? 0.0
        : ((20 * math.log(rms.clamp(.001, 1)) / math.ln10 + 60) / 60).clamp(
            0.0,
            1.0,
          );
    _level += (target - _level) * (target > _level ? .7 : .35);
    if (_level < .005) _level = 0;
    return _level;
  }

  void reset() => _level = 0;
}
