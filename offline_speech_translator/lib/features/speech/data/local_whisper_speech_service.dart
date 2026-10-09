import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

import '../domain/audio_validation.dart';
import '../domain/audio_level.dart';
import '../application/live_recognition.dart';
import 'speech_capture.dart';

/// Device-local Tagalog speech recognition backed by whisper.cpp.
///
/// Tiny Q5_1 favors speed; Base Q5_1 is an optional accuracy candidate. Audio
/// is previewed through serial rolling windows; Finish runs a separate final pass.
class LocalWhisperSpeechService {
  LocalWhisperSpeechService({SpeechCapture Function()? captureFactory})
    // Keep the public injection name stable for replay captures.
    // ignore: prefer_initializing_formals
    : _captureFactory = captureFactory;
  final SpeechCapture Function()? _captureFactory;
  AudioDiagnostics diagnostics = AudioDiagnostics();
  String? noiseNotice;
  static const maxRecordingSeconds = 300;
  final _liveUpdates = StreamController<LiveRecognitionSnapshot>.broadcast();
  final _recordingEnded = StreamController<void>.broadcast();
  final _audioLevels = StreamController<double>.broadcast();
  Stream<double> get audioLevels => _audioLevels.stream;
  Stream<LiveRecognitionSnapshot> get liveUpdates => _liveUpdates.stream;
  Stream<void> get recordingEnded => _recordingEnded.stream;
  LiveRecognition? _preview;
  Future<void>? _starting;
  Future<void>? _cancelling;
  Future<WhisperResult>? _finishing;
  int _generation = 0;
  bool _disposed = false;

  static const modelFileName = 'ggml-tiny-q5_1.bin';
  static const modelSizeLabel = 'about 32 MB';
  static const _legacyModelFileName = 'ggml-base-q5_1.bin';

  static const _tinyQ5Model = WhisperModelDescriptor(
    id: 'whisper-tiny-q5_1-multilingual',
    fileName: modelFileName,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/'
        'f281eb45af861ab5e5297d23694b7d46e090c02c/ggml-tiny-q5_1.bin',
    sha256: '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7',
    approximateBytes: 32_200_000,
    languageScope: WhisperModelLanguageScope.multilingual,
    purpose: WhisperModelPurpose.transcription,
  );

  static const _baseQ5Model = WhisperModelDescriptor(
    id: 'whisper-base-q5_1-multilingual',
    fileName: _legacyModelFileName,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/'
        'f281eb45af861ab5e5297d23694b7d46e090c02c/ggml-base-q5_1.bin',
    sha256: '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898',
    approximateBytes: 62_600_000,
    languageScope: WhisperModelLanguageScope.multilingual,
    purpose: WhisperModelPurpose.transcription,
  );

  final WhisperModelManager _models = WhisperModelManager();
  final StreamController<int> _recognitionProgress =
      StreamController<int>.broadcast();
  final List<Float32List> _recordedChunks = [];

  WhisperEngine? _engine;
  String? _loadedModelPath;
  bool? _loadedAccuracyPreference;
  SpeechCapture? _recorder;
  WhisperTask? _activeTask;
  StreamSubscription<RecordingChunk>? _audioSubscription;
  Completer<void>? _audioDone;
  Object? _audioError;
  StackTrace? _audioErrorStack;
  int _recordedSampleCount = 0;
  String _recordingLanguage = 'tl';
  bool _finalPreferAccuracy = false;
  bool _finalCebuano = false;
  bool? _loadedCebuano;
  static const _cebuanoChannel = MethodChannel('sulti/cebuano_model');

  Future<File?> findCebuanoModel() async {
    try {
      final path = await _cebuanoChannel.invokeMethod<String>('find');
      return path == null ? null : File(path);
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> importCebuanoModel() async {
    if (_recorder != null ||
        _starting != null ||
        _finishing != null ||
        _activeTask != null ||
        _cancelling != null) {
      throw StateError('Finish or cancel the current recording first.');
    }
    return await _cebuanoChannel.invokeMethod<bool>('import') ?? false;
  }

  Stream<int> get recognitionProgress => _recognitionProgress.stream;

  Future<File?> findInstalledModel({bool preferAccuracy = false}) async {
    if (preferAccuracy) return _findVerifiedModel(_baseQ5Model);
    return await _findVerifiedModel(_tinyQ5Model) ??
        await _findVerifiedModel(_baseQ5Model);
  }

  Stream<ModelDownloadProgress> installModel({
    bool preferAccuracy = false,
  }) async* {
    if (_recorder != null ||
        _activeTask != null ||
        _starting != null ||
        _finishing != null ||
        _cancelling != null) {
      throw StateError('Finish or cancel the current recording first.');
    }
    final descriptor = preferAccuracy ? _baseQ5Model : _tinyQ5Model;
    await for (final progress in _models.downloadCatalogModel(descriptor)) {
      yield progress;
    }

    final installedModel = await _findVerifiedModel(descriptor);
    if (installedModel == null) {
      throw StateError('The model download did not finish.');
    }

    // Preserve both model files so users can compare and switch offline.
    _engine?.dispose();
    _engine = null;
    _loadedModelPath = null;
  }

  Future<File?> _findVerifiedModel(WhisperModelDescriptor descriptor) async {
    try {
      return await _models.findCatalogModel(descriptor);
    } on FormatException {
      await _models.delete(descriptor.fileName);
      return null;
    }
  }

  Future<void> loadModel({
    bool preferAccuracy = false,
    bool cebuano = false,
  }) async {
    if (_engine != null &&
        _loadedAccuracyPreference == preferAccuracy &&
        _loadedCebuano == cebuano) {
      return;
    }
    final model = cebuano
        ? await findCebuanoModel()
        : await findInstalledModel(preferAccuracy: preferAccuracy);
    if (model == null) {
      throw StateError('Install the multilingual Whisper model first.');
    }

    if (_engine != null && _loadedModelPath == model.path) {
      _loadedAccuracyPreference = preferAccuracy;
      _loadedCebuano = cebuano;
      return;
    }
    _engine?.dispose();
    _engine = null;
    _loadedModelPath = null;
    _engine = await WhisperEngine.load(
      model.path,
      config: const WhisperConfig(backend: WhisperBackend.cpu),
    );
    _loadedModelPath = model.path;
    _loadedAccuracyPreference = preferAccuracy;
    _loadedCebuano = cebuano;
  }

  Future<void> startRecording({
    String language = 'tl',
    bool preferAccuracy = false,
    bool livePreview = true,
    bool noiseSuppression = false,
    bool cebuano = false,
  }) {
    if (_disposed ||
        _starting != null ||
        _finishing != null ||
        _cancelling != null ||
        _recorder != null) {
      return Future.error(StateError('Speech recognition is busy.'));
    }
    if (!const {'tl', 'en', 'auto', 'ceb'}.contains(language)) {
      return Future.error(
        ArgumentError.value(language, 'language', 'Unsupported input mode'),
      );
    }
    if (language == 'ceb' && !cebuano) {
      return Future.error(
        StateError('Import the trained Cebuano model first.'),
      );
    }
    final generation = ++_generation;
    final operation = _start(
      language,
      preferAccuracy,
      livePreview,
      noiseSuppression,
      generation,
      cebuano,
    );
    _starting = operation;
    return operation.whenComplete(() => _starting = null);
  }

  Future<void> _start(
    String language,
    bool preferAccuracy,
    bool livePreview,
    bool noiseSuppression,
    int generation,
    bool cebuano,
  ) async {
    _finalPreferAccuracy = preferAccuracy;
    _finalCebuano = cebuano;
    if (cebuano) livePreview = false;
    if (!cebuano && preferAccuracy && livePreview) {
      if (await findInstalledModel(preferAccuracy: true) == null) {
        throw StateError(
          'Install Whisper Base before enabling final refinement.',
        );
      }
      _checkGeneration(generation);
    }
    // Use the fast installed model for captions, then swap to Base only after
    // stopping preview. Both native models are never resident simultaneously.
    await loadModel(
      preferAccuracy: preferAccuracy && !livePreview,
      cebuano: cebuano,
    );
    _checkGeneration(generation);
    _recordingLanguage = cebuano
        ? 'tl'
        : language; // Fine-tuning used the tl decoder prompt.
    final recorder =
        _captureFactory?.call() ??
        (noiseSuppression ? NoiseSuppressedCapture() : MicrophoneCapture());
    _recorder = recorder;
    _clearRecording();
    diagnostics = AudioDiagnostics();
    noiseNotice = null;
    try {
      if (!await recorder.requestPermission()) {
        throw const WhisperException('Microphone permission was not granted');
      }
      _checkGeneration(generation);
      final audio = await recorder.start();
      if (recorder is NoiseSuppressedCapture && !recorder.suppressionActive) {
        noiseNotice =
            'Noise suppression is unavailable on this device. Using the original microphone path.';
      }
      _checkGeneration(generation);
      if (livePreview) {
        _preview = LiveRecognition(
          infer: (samples, context) =>
              _recognize(samples, preview: true, context: context),
          cancelInference: () => _activeTask?.cancel(),
          onUpdate: (update) {
            if (generation == _generation && !_disposed) {
              _liveUpdates.add(update);
            }
          },
        );
      }
      final done = Completer<void>();
      _audioDone = done;
      _audioSubscription = audio.listen(
        (chunk) {
          if (generation != _generation) return;
          try {
            if (chunk.sampleRate != 16000) {
              throw FormatException(
                'Expected 16000 Hz audio, received ${chunk.sampleRate} Hz.',
              );
            }
            if (chunk.samples.any((s) => !s.isFinite || s.abs() > 1)) {
              throw const FormatException(
                'Invalid microphone audio. Record again.',
              );
            }
            final remaining =
                maxRecordingSeconds * 16000 - _recordedSampleCount;
            if (remaining <= 0) return;
            final samples = chunk.samples.length <= remaining
                ? chunk.samples
                : Float32List.sublistView(chunk.samples, 0, remaining);
            _recordedChunks.add(samples);
            diagnostics.add(samples);
            _audioLevels.add(audioRms(samples));
            _recordedSampleCount += samples.length;
            _preview?.add(RecordingChunk(samples, 16000));
            if (_recordedSampleCount >= maxRecordingSeconds * 16000) {
              _recordingEnded.add(null);
              unawaited(
                recorder.stop().catchError((Object error, StackTrace stack) {
                  _audioError = error;
                  _audioErrorStack = stack;
                }),
              );
            }
          } catch (error, stack) {
            _audioError = error;
            _audioErrorStack = stack;
            _recordingEnded.add(null);
          }
        },
        onError: (Object error, StackTrace stack) {
          _audioError = error;
          _audioErrorStack = stack;
          if (!done.isCompleted) done.complete();
          _recordingEnded.add(null);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
    } catch (_) {
      await recorder.stop();
      await _closePreview();
      _recorder = null;
      _clearRecording();
      rethrow;
    }
  }

  void _checkGeneration(int generation) {
    if (_disposed || generation != _generation) {
      throw StateError('Recording cancelled.');
    }
  }

  Future<WhisperResult> _recognize(
    Float32List samples, {
    bool preview = false,
    String? context,
  }) async {
    final task = _engine!.transcribe(
      samples,
      options: TranscribeOptions(
        language: _recordingLanguage,
        threads: 4,
        greedyBestOf: 1,
        strategy: _finalCebuano
            ? WhisperSamplingStrategy.beamSearch
            : WhisperSamplingStrategy.greedy,
        beamSize: 5,
        tokenTimestamps: preview,
        noTimestamps: !preview,
        initialPrompt: context,
        // Preview should not spend extra passes on random-temperature fallback.
        // The authoritative final pass retains the baseline decoding settings.
        temperatureIncrement: preview ? 0 : 0.2,
      ),
    );
    _activeTask = task;
    final progress = preview
        ? null
        : task.progress.listen(_recognitionProgress.add);
    try {
      return await task.result;
    } finally {
      await progress?.cancel();
      if (identical(_activeTask, task)) _activeTask = null;
    }
  }

  Future<WhisperResult> stopRecordingAndTranscribe() {
    final pending = _finishing;
    if (pending != null) return pending;
    final recorder = _recorder;
    if (recorder == null || _cancelling != null) {
      return Future.error(StateError('There is no recording to stop.'));
    }
    final operation = _finish(recorder, _generation);
    _finishing = operation;
    return operation.whenComplete(() => _finishing = null);
  }

  Future<WhisperResult> _finish(SpeechCapture recorder, int generation) async {
    try {
      await recorder.stop();
      await _audioDone?.future;
      await _closePreview();
      _checkGeneration(generation);
      if (_audioError != null) {
        Error.throwWithStackTrace(
          _audioError!,
          _audioErrorStack ?? StackTrace.current,
        );
      }
      final samples = Float32List(_recordedSampleCount);
      var offset = 0;
      for (final chunk in _recordedChunks) {
        samples.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      _recordedChunks.clear();
      validateAudio(samples);
      await loadModel(
        preferAccuracy: _finalPreferAccuracy,
        cebuano: _finalCebuano,
      );
      _checkGeneration(generation);
      final result = await _recognize(samples);
      _checkGeneration(generation);
      return result;
    } finally {
      await _closePreview();
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _recorder = null;
      _audioDone = null;
      _clearRecording();
    }
  }

  Future<void> _closePreview() async {
    final preview = _preview;
    // Keep the reference while closing, so concurrent Finish/Cancel await the
    // same native task before anyone can reuse or dispose its context.
    if (preview == null) return;
    await preview.close();
    if (identical(_preview, preview)) _preview = null;
  }

  /// Release ASR before loading the large translation model.
  void releaseModel() {
    if (_recorder != null ||
        _activeTask != null ||
        _starting != null ||
        _finishing != null ||
        _cancelling != null) {
      throw StateError('Finish speech recognition before releasing its model.');
    }
    _engine?.dispose();
    _engine = null;
    _loadedModelPath = null;
    _loadedAccuracyPreference = null;
  }

  Future<void> cancelTranscription() =>
      _cancelling ??= _cancel().whenComplete(() => _cancelling = null);
  Future<void> _cancel() async {
    ++_generation;
    try {
      await _starting;
    } catch (_) {
      /* A cancelled start is expected. */
    }
    final recorder = _recorder;
    try {
      await recorder?.stop();
    } finally {
      await _closePreview();
      final task = _activeTask;
      task?.cancel();
      try {
        await task?.result;
      } catch (_) {
        /* Expected cancellation. */
      }
      try {
        await _finishing;
      } catch (_) {
        /* Expected cancellation. */
      }
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _recorder = null;
      _audioDone = null;
      _clearRecording();
    }
  }

  void _clearRecording() {
    if (!_audioLevels.isClosed) _audioLevels.add(0);
    _recordedChunks.clear();
    _recordedSampleCount = 0;
    _audioError = null;
    _audioErrorStack = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await cancelTranscription();
    _engine?.dispose();
    _engine = null;
    await _recognitionProgress.close();
    await _liveUpdates.close();
    await _recordingEnded.close();
    await _audioLevels.close();
    _models.close();
  }
}
