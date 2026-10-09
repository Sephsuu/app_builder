import 'dart:async';
import 'dart:typed_data';

import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

/// Immutable display snapshot. Stable text is still subject to final review.
class LiveRecognitionSnapshot {
  const LiveRecognitionSnapshot({
    this.stable = '',
    this.provisional = '',
    this.processingTime = Duration.zero,
    this.firstTextTime,
    this.notice,
  });
  final String stable;
  final String provisional;
  final Duration processingTime;
  final Duration? firstTextTime;
  final String? notice;
}

/// Serial, overlapping-window preview. Full-recording recognition remains the
/// authoritative result. This is chunked Whisper, not a streaming acoustic model.
class LiveRecognition {
  LiveRecognition({
    required this.infer,
    required this.cancelInference,
    required this.onUpdate,
    this.maxProcessingTime = const Duration(seconds: 8),
  }) {
    _task = WhisperStreamTask.start(
      audio: _audio.stream,
      config: const WhisperStreamConfig(
        updateInterval: Duration(seconds: 3),
        windowDuration: Duration(seconds: 12),
        confirmationLag: Duration(seconds: 3),
      ),
      startInference: _inferWindow,
      cancelInference: cancelInference,
      releaseEngine: () {},
    );
    _subscription = _task.updates.listen(
      _publish,
      onError: (Object error) {
        if (!_closed && !_paused) {
          _paused = true;
          onUpdate(
            LiveRecognitionSnapshot(
              stable: _stable,
              provisional: _partial,
              processingTime: _processingTime,
              firstTextTime: _firstTextTime,
              notice:
                  'Live preview paused. Tap Stop to recognize the full recording.',
            ),
          );
        }
      },
    );
  }

  final Future<WhisperResult> Function(Float32List, String?) infer;
  final void Function() cancelInference;
  final void Function(LiveRecognitionSnapshot) onUpdate;
  final Duration maxProcessingTime;
  final _audio = StreamController<RecordingChunk>();
  final _clock = Stopwatch()..start();
  late final WhisperStreamTask _task;
  late final StreamSubscription<WhisperStreamUpdate> _subscription;
  Future<WhisperResult>? _inFlight;
  Completer<void>? _cooldown;
  Timer? _cooldownTimer;
  Future<void>? _closing;
  bool _closed = false;
  bool _paused = false;
  String _stable = '';
  String _partial = '';
  Duration _processingTime = Duration.zero;
  Duration? _firstTextTime;

  void add(RecordingChunk chunk) {
    if (!_closed && !_paused) _audio.add(chunk);
  }

  Future<WhisperResult> _inferWindow(
    Float32List samples,
    String? context,
  ) async {
    // Give the phone breathing room after each inference, based on its measured
    // cost. Waiting is cancellable; no additional inference jobs are queued.
    if (_processingTime > Duration.zero) {
      _cooldown = Completer<void>();
      _cooldownTimer = Timer(
        Duration(
          milliseconds: (_processingTime.inMilliseconds ~/ 4).clamp(250, 1500),
        ),
        () {
          if (!_cooldown!.isCompleted) _cooldown!.complete();
        },
      );
      await _cooldown!.future;
    }
    if (_closed || _paused) throw StateError('Preview stopped');
    // Do not ask the model to invent words for exactly silent buffers.
    if (!samples.any((sample) => sample != 0)) {
      return const WhisperResult(
        text: '',
        language: '',
        languageProbability: -1,
        segments: [],
        processingTime: Duration.zero,
        systemInfo: 'silence',
      );
    }
    final timer = Stopwatch()..start();
    final future = infer(samples, context);
    _inFlight = future;
    try {
      final result = await future;
      _processingTime = timer.elapsed;
      return result;
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
  }

  void _publish(WhisperStreamUpdate update) {
    if (_closed) return;
    _stable = update.confirmedText;
    _partial = update.partialText;
    if (_firstTextTime == null && update.text.trim().isNotEmpty) {
      _firstTextTime = _clock.elapsed;
    }
    _paused = _processingTime > maxProcessingTime;
    onUpdate(
      LiveRecognitionSnapshot(
        stable: _stable,
        provisional: _partial,
        processingTime: _processingTime,
        firstTextTime: _firstTextTime,
        notice: _paused
            ? 'Preview is slow on this phone. Tap Stop for the full transcription.'
            : null,
      ),
    );
  }

  /// Idempotent and waits until native work settles before engine reuse.
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _clock.stop();
    _cooldownTimer?.cancel();
    if (_cooldown != null && !_cooldown!.isCompleted) _cooldown!.complete();
    await _subscription.cancel();
    final inFlight = _inFlight;
    await _task.cancel();
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        /* Expected cancellation. */
      }
    }
    await _audio.close();
  }
}
