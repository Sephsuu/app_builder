// Developer-only lifecycle regression. Replays public PCM, never microphone audio.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offline_speech_translator/features/speech/data/local_whisper_speech_service.dart';
import 'package:offline_speech_translator/features/translation/application/translation_controller.dart';
import 'package:offline_speech_translator/features/translation/data/local_translation_service.dart';
import 'live_device_probe.dart' show ReplayCapture;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Consecutive turn verification')),
      ),
    ),
  );
  unawaited(probe());
}

Future<void> probe() async {
  const root =
      '/data/user/0/com.example.offline_speech_translator/files/evaluation';
  final rows = <Map<String, Object?>>[];
  final report = <String, Object?>{'complete': false, 'turns': rows};
  final file = File('$root/consecutive-result.json');
  const activity = MethodChannel('sulti/activity_state');
  await activity.invokeMethod<void>('keepScreenOn', true);
  Future<void> save() => file.writeAsString(jsonEncode(report));
  final bytes = await File('$root/sample.f32').readAsBytes();
  final samples = Float32List.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.length ~/ 4,
  );
  late ReplayCapture capture;
  final speech = LocalWhisperSpeechService(
    captureFactory: () => capture = ReplayCapture(samples),
  );
  final controller = TranslationController(
    translator: LocalTranslationService(),
    voice: DeviceSpeechOutput(),
  );
  try {
    for (var i = 0; i < 3; i++) {
      final row = <String, Object?>{'turn': i + 1, 'stage': 'preparing'};
      rows.add(row);
      await save();
      final token = await controller.beginRecording().timeout(
        const Duration(seconds: 30),
      );
      await speech
          .startRecording(preferAccuracy: true)
          .timeout(const Duration(seconds: 30));
      row['stage'] = 'recording';
      await save();
      await capture.done.future;
      row['stage'] = 'recognizing';
      await save();
      final timer = Stopwatch()..start();
      final result = await speech.stopRecordingAndTranscribe().timeout(
        const Duration(seconds: 60),
      );
      row['text'] = result.text;
      row['recognition_ms'] = timer.elapsedMilliseconds;
      speech.releaseModel();
      row['stage'] = 'translating';
      await save();
      final translation = controller.acceptFinal(token, result.text);
      if (i == 1) {
        // Next beginRecording must cancel and drain this translation first.
        unawaited(translation);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        row['stage'] = 'interrupted_for_next_turn';
      } else {
        await translation.timeout(const Duration(seconds: 125));
        row['translation'] = controller.translated;
        row['error'] = controller.error;
        row['stage'] = 'finished';
      }
      await save();
    }
    report['complete'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
  } finally {
    await save();
    controller.dispose();
    await speech.dispose();
    await activity.invokeMethod<void>('keepScreenOn', false);
  }
}
