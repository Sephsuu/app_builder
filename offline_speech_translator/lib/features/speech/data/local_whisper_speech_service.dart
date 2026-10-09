import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

import '../domain/audio_validation.dart';

/// Device-local Tagalog speech recognition backed by whisper.cpp.
///
/// Tiny Q5_1 favors speed; Base Q5_1 is an optional accuracy candidate. Audio
/// is collected during recording and transcribed once when the user finishes,
/// avoiding repeated decoding of the same long recording.
class LocalWhisperSpeechService {
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
  WhisperRecorder? _recorder;
  WhisperTask? _activeTask;
  StreamSubscription<RecordingChunk>? _audioSubscription;
  Completer<void>? _audioDone;
  Object? _audioError;
  StackTrace? _audioErrorStack;
  int _recordedSampleCount = 0;
  String _recordingLanguage = 'tl';

  Stream<int> get recognitionProgress => _recognitionProgress.stream;

  Future<File?> findInstalledModel({bool preferAccuracy = false}) async {
    if (preferAccuracy) return _findVerifiedModel(_baseQ5Model);
    return await _findVerifiedModel(_tinyQ5Model) ??
        await _findVerifiedModel(_baseQ5Model);
  }

  Stream<ModelDownloadProgress> installModel({
    bool preferAccuracy = false,
  }) async* {
    if (_recorder != null || _activeTask != null) {
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

  Future<void> loadModel({bool preferAccuracy = false}) async {
    if (_engine != null && _loadedAccuracyPreference == preferAccuracy) return;
    final model = await findInstalledModel(preferAccuracy: preferAccuracy);
    if (model == null) {
      throw StateError('Install the multilingual Whisper model first.');
    }

    if (_engine != null && _loadedModelPath == model.path) {
      _loadedAccuracyPreference = preferAccuracy;
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
  }

  Future<void> startRecording({
    String language = 'tl',
    bool preferAccuracy = false,
  }) async {
    if (!const {'tl', 'en', 'auto'}.contains(language)) {
      throw ArgumentError.value(language, 'language', 'Unsupported input mode');
    }
    if (_recorder != null || _activeTask != null) {
      throw StateError('A transcription is already in progress.');
    }

    await loadModel(preferAccuracy: preferAccuracy);
    _recordingLanguage = language;
    final recorder = WhisperRecorder();
    _recorder = recorder;
    _recordedChunks.clear();
    _recordedSampleCount = 0;
    _audioError = null;
    _audioErrorStack = null;

    try {
      if (!await recorder.requestPermission()) {
        throw const WhisperException('Microphone permission was not granted');
      }

      final audio = await recorder.start(
        sampleRate: 16000,
        chunkMilliseconds: 100,
      );
      final done = Completer<void>();
      _audioDone = done;
      _audioSubscription = audio.listen(
        (chunk) {
          if (chunk.sampleRate != 16000) {
            _audioError = FormatException(
              'Expected 16000 Hz audio, received ${chunk.sampleRate} Hz.',
            );
            _audioErrorStack = StackTrace.current;
            return;
          }
          _recordedChunks.add(chunk.samples);
          _recordedSampleCount += chunk.samples.length;
        },
        onError: (Object error, StackTrace stackTrace) {
          _audioError = error;
          _audioErrorStack = stackTrace;
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: false,
      );
    } catch (_) {
      _recorder = null;
      await recorder.stop();
      _clearRecording();
      rethrow;
    }
  }

  Future<WhisperResult> stopRecordingAndTranscribe() async {
    final recorder = _recorder;
    if (recorder == null) throw StateError('There is no recording to stop.');

    WhisperTask? task;
    try {
      await recorder.stop();
      await _audioDone?.future;

      final audioError = _audioError;
      if (audioError != null) {
        Error.throwWithStackTrace(
          audioError,
          _audioErrorStack ?? StackTrace.current,
        );
      }
      if (_recordedSampleCount == 0) {
        throw StateError('No microphone audio was captured. Try again.');
      }

      final engine = _engine;
      if (engine == null) throw StateError('Speech model did not load.');

      final samples = Float32List(_recordedSampleCount);
      var offset = 0;
      for (final chunk in _recordedChunks) {
        samples.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      validateAudio(samples);

      task = engine.transcribe(
        samples,
        options: TranscribeOptions(
          language: _recordingLanguage,
          threads: 4,
          greedyBestOf: 1,
          tokenTimestamps: false,
          noTimestamps: true,
        ),
      );
      _activeTask = task;
      final progressSubscription = task.progress.listen(
        _recognitionProgress.add,
      );
      try {
        return await task.result;
      } finally {
        await progressSubscription.cancel();
      }
    } finally {
      _activeTask = null;
      _recorder = null;
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _audioDone = null;
      _clearRecording();
    }
  }

  Future<void> cancelTranscription() async {
    final task = _activeTask;
    _activeTask = null;
    if (task != null) {
      task.cancel();
      try {
        await task.result;
      } catch (_) {
        // Cancellation is expected to complete the task with an error.
      }
    }

    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) await recorder.stop();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _audioDone = null;
    _clearRecording();
  }

  void _clearRecording() {
    _recordedChunks.clear();
    _recordedSampleCount = 0;
    _audioError = null;
    _audioErrorStack = null;
  }

  Future<void> dispose() async {
    await cancelTranscription();
    _engine?.dispose();
    _engine = null;
    await _recognitionProgress.close();
    _models.close();
  }
}
