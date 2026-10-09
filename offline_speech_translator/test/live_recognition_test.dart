import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';
import 'package:offline_speech_translator/features/speech/application/live_recognition.dart';

WhisperResult hypothesis(String text) => WhisperResult(
  text: text,
  language: 'tl',
  languageProbability: -1,
  processingTime: Duration.zero,
  systemInfo: 'test',
  segments: [
    WhisperSegment(
      text: text,
      start: Duration.zero,
      end: const Duration(seconds: 2),
      tokens: [],
      noSpeechProbability: 0,
      speakerTurnNext: false,
    ),
  ],
);
RecordingChunk audio(int seconds) => RecordingChunk(
  Float32List(16000 * seconds)..fillRange(0, 16000 * seconds, .1),
  16000,
);

void main() {
  test(
    'preview context covers the full window and padding within model limits',
    () {
      expect(previewAudioContext(16000 * 3), 768);
      expect(previewAudioContext(16000 * 12), 768);
      for (var samples = 1; samples <= 16000 * 12; samples += 1600) {
        expect(
          previewAudioContext(samples) * 320,
          greaterThanOrEqualTo(samples + 32000),
        );
      }
      expect(previewAudioContext(16000 * 30), 1500);
    },
  );

  test(
    'coalesces audio and close waits for native cancellation without stale text',
    () async {
      final result = Completer<WhisperResult>();
      final updates = <LiveRecognitionSnapshot>[];
      var calls = 0;
      final live = LiveRecognition(
        infer: (_, _) {
          calls++;
          return result.future;
        },
        cancelInference: () {
          if (!result.isCompleted) {
            result.completeError(StateError('cancelled'));
          }
        },
        onUpdate: updates.add,
      );
      live.add(audio(3));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      live.add(audio(3));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 1);
      await live.close();
      await live.close();
      expect(updates, isEmpty);
    },
  );

  test('revises provisional words without concatenating hypotheses', () async {
    var calls = 0;
    final updates = <LiveRecognitionSnapshot>[];
    final live = LiveRecognition(
      infer: (_, _) async =>
          hypothesis(++calls == 1 ? ' Gusto ko kumayim' : ' Gusto ko kumain'),
      cancelInference: () {},
      onUpdate: updates.add,
    );
    live.add(audio(3));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(updates.last.provisional, ' Gusto ko kumayim');
    live.add(audio(3));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(updates.last.stable + updates.last.provisional, ' Gusto ko kumain');
    await live.close();
  });

  test(
    'slow preview pauses further inference but retains its last text',
    () async {
      var calls = 0;
      final updates = <LiveRecognitionSnapshot>[];
      final live = LiveRecognition(
        infer: (_, _) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return hypothesis(' Oo oo');
        },
        maxProcessingTime: const Duration(milliseconds: 1),
        cancelInference: () {},
        onUpdate: updates.add,
      );
      live.add(audio(3));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(updates.last.provisional, ' Oo oo');
      expect(updates.last.notice, contains('slow'));
      live.add(audio(6));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(calls, 1);
      await live.close();
    },
  );

  test('exact silence does not call the model', () async {
    var calls = 0;
    final live = LiveRecognition(
      infer: (_, _) async {
        calls++;
        return hypothesis('invented');
      },
      cancelInference: () {},
      onUpdate: (_) {},
    );
    live.add(RecordingChunk(Float32List(48000), 16000));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 0);
    await live.close();
  });
}
