import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';
import 'package:offline_speech_translator/features/speech/data/local_whisper_speech_service.dart';
import 'package:offline_speech_translator/features/speech/data/speech_capture.dart';
import 'package:offline_speech_translator/features/speech/data/speech_engine.dart';

const recognized = WhisperResult(
  text: 'Saan tayo pupunta mamaya?',
  language: 'tl',
  languageProbability: -1,
  segments: [],
  processingTime: Duration.zero,
  systemInfo: 'test',
);

class Capture implements SpeechCapture {
  final audio = StreamController<RecordingChunk>();
  bool closeOnStop = true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<Stream<RecordingChunk>> start() async {
    audio.add(RecordingChunk(Float32List(1600)..fillRange(0, 1600, .1), 16000));
    return audio.stream;
  }

  @override
  Future<void> stop() async {
    if (closeOnStop && !audio.isClosed) unawaited(audio.close());
  }
}

class Job implements SpeechJob {
  final completion = Completer<WhisperResult>();
  int cancellations = 0;
  @override
  Future<WhisperResult> get result => completion.future;
  @override
  Stream<int> get progress => const Stream.empty();
  @override
  void cancel() {
    cancellations++;
    if (completion.isCompleted) throw StateError('Cancelled a freed job');
    completion.completeError(StateError('cancelled'));
  }
}

class Engine implements SpeechEngine {
  Engine(this.jobs, this.options, this.hang);
  final List<Job> jobs;
  final List<TranscribeOptions> options;
  final bool Function() hang;
  bool disposed = false;
  @override
  SpeechJob transcribe(
    Float32List samples, {
    required TranscribeOptions options,
  }) {
    if (disposed) throw StateError('Disposed engine reused');
    this.options.add(options);
    final job = Job();
    jobs.add(job);
    if (!hang()) job.completion.complete(recognized);
    return job;
  }

  @override
  void dispose() => disposed = true;
}

class Service extends LocalWhisperSpeechService {
  Service({
    required super.captureFactory,
    required super.engineLoader,
    super.audioDrainTimeout = const Duration(milliseconds: 20),
    super.recognitionTimeout = const Duration(milliseconds: 20),
  });
  @override
  Future<File?> findInstalledModel({bool preferAccuracy = false}) async =>
      File('/test-model.bin');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Service service;
  late Capture capture;
  late List<Job> jobs;
  late List<TranscribeOptions> options;
  var hang = false;
  setUp(() {
    jobs = [];
    options = [];
    hang = false;
    service = Service(
      captureFactory: () => capture = Capture(),
      engineLoader: (_) async => Engine(jobs, options, () => hang),
    );
  });
  tearDown(() => service.dispose());

  test(
    'three consecutive turns reload, finish and release without stale state',
    () async {
      for (var turn = 0; turn < 3; turn++) {
        await service.startRecording(livePreview: false);
        final first = service.stopRecordingAndTranscribe();
        final second = service.stopRecordingAndTranscribe();
        expect((await first).text, recognized.text);
        expect((await second).text, recognized.text);
        service.releaseModel();
        await service.cancelTranscription();
      }
      expect(jobs, hasLength(3));
      expect(jobs.every((job) => job.cancellations == 0), isTrue);
      expect(options.every((option) => option.audioContext == 0), isTrue);
    },
  );

  test(
    'missing audio end times out and the next recording can finish',
    () async {
      await service.startRecording(livePreview: false);
      capture.closeOnStop = false;
      final oldCapture = capture;
      await expectLater(
        service.stopRecordingAndTranscribe(),
        throwsA(isA<TimeoutException>()),
      );
      await oldCapture.audio.close();
      await service.startRecording(livePreview: false);
      expect(
        (await service.stopRecordingAndTranscribe()).text,
        recognized.text,
      );
    },
  );

  test(
    'recognition deadline cancels the job before allowing a retry',
    () async {
      hang = true;
      await service.startRecording(livePreview: false);
      await expectLater(
        service.stopRecordingAndTranscribe(),
        throwsA(isA<TimeoutException>()),
      );
      expect(jobs.single.cancellations, 1);
      hang = false;
      await service.startRecording(livePreview: false);
      expect(
        (await service.stopRecordingAndTranscribe()).text,
        recognized.text,
      );
    },
  );

  test(
    'cancel during final recognition settles and permits the next turn',
    () async {
      hang = true;
      await service.startRecording(livePreview: false);
      final finishing = service.stopRecordingAndTranscribe();
      final failure = expectLater(finishing, throwsStateError);
      while (jobs.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await service.cancelTranscription();
      await failure;
      hang = false;
      await service.startRecording(livePreview: false);
      expect(
        (await service.stopRecordingAndTranscribe()).text,
        recognized.text,
      );
    },
  );
}
