import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
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
  Future<void>? _stopping;
  @override
  Future<bool> requestPermission() => _recorder.requestPermission();
  @override
  Future<Stream<RecordingChunk>> start() async {
    await _stopping;
    _stopping = null;
    return _recorder.start(sampleRate: 16000, chunkMilliseconds: 100);
  }

  @override
  // WhisperRecorder returns immediately to a second stop caller while the
  // first call is still cleaning up. All callers must await the same fence.
  Future<void> stop() => _stopping ??= _recorder.stop();
}

/// Opt-in Android platform suppression; unsupported devices keep the original
/// capture path. Both paths deliver 16 kHz mono normalized float32 PCM.
class NoiseSuppressedCapture implements SpeechCapture {
  static const _methods = MethodChannel('sulti/noise_capture');
  static const _audio = EventChannel('sulti/noise_audio');
  final _fallback = MicrophoneCapture();
  StreamController<RecordingChunk>? _controller;
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _stopping;
  bool suppressionActive = false;

  @override
  Future<bool> requestPermission() => _fallback.requestPermission();

  @override
  Future<Stream<RecordingChunk>> start() async {
    final controller = StreamController<RecordingChunk>();
    _controller = controller;
    _subscription = _audio.receiveBroadcastStream().listen(
      (dynamic event) {
        try {
          controller.add(decodeFloatPcm(event));
        } catch (error, stack) {
          controller.addError(error, stack);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (error is! MissingPluginException) controller.addError(error, stack);
      },
    );
    try {
      suppressionActive = await _methods.invokeMethod<bool>('start') ?? false;
    } on MissingPluginException {
      suppressionActive = false;
    } on PlatformException {
      suppressionActive = false;
    }
    if (suppressionActive) return controller.stream;
    await _subscription?.cancel();
    _subscription = null;
    unawaited(controller.close());
    _controller = null;
    return _fallback.start();
  }

  @override
  Future<void> stop() => _stopping ??= _stop();
  Future<void> _stop() async {
    if (!suppressionActive) {
      await _fallback.stop();
      return;
    }
    try {
      await _methods.invokeMethod<void>('stop');
    } finally {
      await _subscription?.cancel();
      final controller = _controller;
      _subscription = null;
      _controller = null;
      if (controller != null) unawaited(controller.close());
    }
  }
}

RecordingChunk decodeFloatPcm(dynamic event) {
  if (event is! Uint8List || event.lengthInBytes % 4 != 0) {
    throw const FormatException('Microphone returned misaligned float32 PCM.');
  }
  final bytes = ByteData.sublistView(event);
  final samples = Float32List(event.lengthInBytes ~/ 4);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = bytes.getFloat32(i * 4, Endian.little);
    if (!samples[i].isFinite || samples[i].abs() > 1) {
      throw const FormatException('Microphone returned invalid float32 PCM.');
    }
  }
  return RecordingChunk(samples, 16000);
}
