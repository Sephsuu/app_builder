import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

/// Replaceable audio input so device tests can replay licensed PCM through the
/// exact same service without acquiring or retaining a user's microphone audio.
abstract interface class SpeechCapture {
  Future<bool> requestPermission();
  Future<Stream<RecordingChunk>> start();
  Future<void> stop();
}

class MicrophoneCapture implements SpeechCapture {
  final _recorder = WhisperRecorder();
  @override
  Future<bool> requestPermission() => _recorder.requestPermission();
  @override
  Future<Stream<RecordingChunk>> start() =>
      _recorder.start(sampleRate: 16000, chunkMilliseconds: 100);
  @override
  Future<void> stop() => _recorder.stop();
}
