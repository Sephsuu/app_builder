import 'dart:typed_data';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

abstract interface class SpeechEngine {
  SpeechJob transcribe(
    Float32List samples, {
    required TranscribeOptions options,
  });
  void dispose();
}

abstract interface class SpeechJob {
  Future<WhisperResult> get result;
  Stream<int> get progress;
  void cancel();
}

class NativeSpeechEngine implements SpeechEngine {
  NativeSpeechEngine._(this._engine);
  final WhisperEngine _engine;
  static Future<SpeechEngine> load(String path) async => NativeSpeechEngine._(
    await WhisperEngine.load(
      path,
      config: const WhisperConfig(backend: WhisperBackend.cpu),
    ),
  );
  @override
  SpeechJob transcribe(
    Float32List samples, {
    required TranscribeOptions options,
  }) => _NativeSpeechJob(_engine.transcribe(samples, options: options));
  @override
  void dispose() => _engine.dispose();
}

class _NativeSpeechJob implements SpeechJob {
  _NativeSpeechJob(this._task) {
    // The plugin frees its native job as soon as result completes. Never send
    // cancellation to that pointer while Dart stream cleanup is still awaiting.
    result = _task.result.whenComplete(() => _finished = true);
  }
  final WhisperTask _task;
  bool _finished = false;
  @override
  late final Future<WhisperResult> result;
  @override
  Stream<int> get progress => _task.progress;
  @override
  void cancel() {
    if (!_finished) _task.cancel();
  }
}
