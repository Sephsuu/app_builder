import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';
import 'package:offline_speech_translator/features/speech/data/local_whisper_speech_service.dart';
import 'package:offline_speech_translator/features/speech/data/speech_capture.dart';
import 'package:offline_speech_translator/features/speech/domain/audio_level.dart';

class LevelCapture implements SpeechCapture {
  final chunks = StreamController<RecordingChunk>();
  bool permitted = true;
  @override
  Future<bool> requestPermission() async => permitted;
  @override
  Future<Stream<RecordingChunk>> start() async => chunks.stream;
  @override
  Future<void> stop() async {
    if (!chunks.isClosed) await chunks.close();
  }
}

class LevelSpeech extends LocalWhisperSpeechService {
  LevelSpeech(LevelCapture capture) : super(captureFactory: () => capture);
  @override
  Future<void> loadModel({
    bool preferAccuracy = false,
    bool cebuano = false,
  }) async {}
}

void main() {
  test('RMS measures silence, quiet and loud PCM without changing samples', () {
    final samples = Float32List.fromList([.25, -.25, .25, -.25]);
    final before = List<double>.from(samples);
    expect(audioRms(samples), closeTo(.25, .000001));
    expect(samples, before);
    expect(audioRms([0, 0]), 0);
    expect(audioRms([.001, -.001]), closeTo(.001, .000001));
    expect(audioRms([]), 0);
  });
  test('visual envelope grows with speech and decays to silence', () {
    final envelope = AudioLevelEnvelope();
    expect(envelope.add(0), 0);
    final quiet = envelope.add(.002);
    final loud = envelope.add(.2);
    expect(loud, greaterThan(quiet));
    for (var i = 0; i < 20; i++) {
      envelope.add(0);
    }
    expect(envelope.add(0), 0);
    envelope.reset();
    expect(envelope.add(0), 0);
  });
  test(
    'the recognition capture stream publishes measured levels and stops cleanly',
    () async {
      final capture = LevelCapture();
      final speech = LevelSpeech(capture);
      final levels = <double>[];
      final subscription = speech.audioLevels.listen(levels.add);
      await speech.startRecording(livePreview: false);
      final samples = Float32List.fromList([.1, -.1, .1, -.1]);
      capture.chunks.add(RecordingChunk(samples, 16000));
      await Future<void>.delayed(Duration.zero);
      expect(levels, contains(closeTo(.1, .000001)));
      expect(samples, [.1, -.1, .1, -.1].map((x) => x.toFloat32()).toList());
      await speech.cancelTranscription();
      await Future<void>.delayed(Duration.zero);
      expect(levels.last, 0);
      await speech.dispose();
      await subscription.cancel();
    },
  );
}

extension on double {
  double toFloat32() => Float32List.fromList([this]).single;
}
