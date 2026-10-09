// Developer-only entry point. Replays licensed test PCM through the actual
// recording service, native engine and caption widget. Never used by lib/main.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';
import 'package:offline_speech_translator/features/speech/data/local_whisper_speech_service.dart';
import 'package:offline_speech_translator/features/speech/data/speech_capture.dart';
import 'package:offline_speech_translator/features/speech/application/live_recognition.dart';
import 'package:offline_speech_translator/features/speech/presentation/live_caption_card.dart';
import 'package:offline_speech_translator/features/translation/data/local_translation_service.dart';
import 'package:offline_speech_translator/features/translation/domain/translation.dart';

const root =
    '/data/user/0/com.example.offline_speech_translator/files/evaluation';
const audioName = String.fromEnvironment(
  'ASR_TEST_AUDIO',
  defaultValue: 'sample.f32',
);
const useBase = bool.fromEnvironment('ASR_TEST_BASE');
const withPreview = bool.fromEnvironment('ASR_TEST_LIVE', defaultValue: true);
const cancelTest = bool.fromEnvironment('ASR_TEST_CANCEL');
const withTranslation = bool.fromEnvironment('ASR_TEST_TRANSLATE');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Probe()));
}

class ReplayCapture implements SpeechCapture {
  ReplayCapture(this.samples);
  final Float32List samples;
  final controller = StreamController<RecordingChunk>();
  final done = Completer<void>();
  Timer? timer;
  var position = 0;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<Stream<RecordingChunk>> start() async {
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final end = (position + 1600).clamp(0, samples.length);
      controller.add(
        RecordingChunk(Float32List.sublistView(samples, position, end), 16000),
      );
      position = end;
      if (position == samples.length) {
        timer!.cancel();
        done.complete();
      }
    });
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    timer?.cancel();
    if (!controller.isClosed) unawaited(controller.close());
  }
}

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  LiveRecognitionSnapshot snapshot = const LiveRecognitionSnapshot();
  var status = 'Starting device verification';
  @override
  void initState() {
    super.initState();
    unawaited(run());
  }

  Future<void> run() async {
    final report = <String, Object?>{
      'model': useBase ? 'base' : 'tiny',
      'live': withPreview,
      'audio': audioName,
    };
    LocalWhisperSpeechService? service;
    StreamSubscription<LiveRecognitionSnapshot>? subscription;
    try {
      final bytes = await File('$root/$audioName').readAsBytes();
      final data = ByteData.sublistView(bytes);
      final samples = Float32List(bytes.length ~/ 4);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = data.getFloat32(i * 4, Endian.little);
      }
      final capture = ReplayCapture(samples);
      service = LocalWhisperSpeechService(captureFactory: () => capture);
      final updates = <Map<String, Object?>>[];
      final clock = Stopwatch();
      subscription = service.liveUpdates.listen((update) {
        updates.add({
          'at_ms': clock.elapsedMilliseconds,
          'text': update.stable + update.provisional,
          'processing_ms': update.processingTime.inMilliseconds,
          'notice': update.notice,
        });
        if (mounted) setState(() => snapshot = update);
      });
      await service.startRecording(
        language: 'tl',
        preferAccuracy: useBase,
        livePreview: withPreview,
      );
      clock.start();
      if (cancelTest) {
        await Future<void>.delayed(const Duration(seconds: 4));
        await service.cancelTranscription();
        final before = updates.length;
        await Future<void>.delayed(const Duration(seconds: 1));
        report.addAll({
          'cancelled': true,
          'stale_updates': updates.length - before,
        });
        return;
      }
      if (mounted) setState(() => status = 'Replaying public Filipino speech');
      await capture.done.future;
      report['audio_ms'] = clock.elapsedMilliseconds;
      if (mounted) setState(() => status = 'Finalizing');
      final finish = Stopwatch()..start();
      final result = await service.stopRecordingAndTranscribe();
      report.addAll({
        'final_text': result.text,
        'finish_ms': finish.elapsedMilliseconds,
        'updates': updates,
        'first_text_ms': updates
            .where((u) => (u['text'] as String).trim().isNotEmpty)
            .firstOrNull?['at_ms'],
      });
      if (withTranslation) {
        service.releaseModel();
        final translationClock = Stopwatch()..start();
        report['translation'] = await LocalTranslationService().translate(
          result.text,
          TranslationLanguage.tagalog,
          TranslationLanguage.cebuano,
        );
        report['translation_ms'] = translationClock.elapsedMilliseconds;
      }
      if (mounted) {
        setState(() {
          status = 'Finished';
          snapshot = LiveRecognitionSnapshot(stable: result.text);
        });
      }
    } catch (error, stack) {
      report['error'] = '$error';
      report['stack'] = '$stack';
    } finally {
      await subscription?.cancel();
      await service?.dispose();
      await File(
        '$root/result-${useBase ? 'base' : 'tiny'}-${withPreview ? 'live' : 'batch'}.json',
      ).writeAsString(jsonEncode(report));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(status),
            LiveCaptionCard(
              snapshot: snapshot,
              finalizing: status == 'Finalizing',
            ),
          ],
        ),
      ),
    ),
  );
}
