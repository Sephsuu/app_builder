import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/speech/data/speech_capture.dart';
import 'package:offline_speech_translator/features/speech/domain/audio_validation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unsupported suppression falls back to the original recording contract',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const noise = MethodChannel('sulti/noise_capture');
      const original = MethodChannel('whisper_cpp_flutter/recorder');
      final calls = <MethodCall>[];
      for (final name in ['sulti/noise_audio', 'whisper_cpp_flutter/audio']) {
        final channel = MethodChannel(name);
        messenger.setMockMethodCallHandler(channel, (_) async => null);
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      messenger.setMockMethodCallHandler(noise, (_) async => false);
      messenger.setMockMethodCallHandler(original, (call) async {
        calls.add(call);
        return call.method == 'requestPermission' ? true : null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(noise, null);
        messenger.setMockMethodCallHandler(original, null);
      });
      final capture = NoiseSuppressedCapture();
      expect(await capture.requestPermission(), isTrue);
      final stream = await capture.start();
      final subscription = stream.listen((_) {});
      expect(capture.suppressionActive, isFalse);
      expect(calls.last.method, 'start');
      expect(calls.last.arguments, {
        'sampleRate': 16000,
        'chunkMilliseconds': 100,
      });
      await capture.stop();
      await subscription.cancel();
      expect(calls.last.method, 'stop');
    },
  );
  test(
    'noise-path decoding preserves quiet speech, pauses and sample boundaries',
    () {
      final samples = Float32List.fromList([0, .000001, -.000001, .9, -1, 0]);
      final buffer = Uint8List(samples.length * 4 + 1);
      final bytes = ByteData.sublistView(buffer, 1);
      for (var i = 0; i < samples.length; i++) {
        bytes.setFloat32(i * 4, samples[i], Endian.little);
      }
      final chunk = decodeFloatPcm(Uint8List.sublistView(buffer, 1));
      expect(chunk.sampleRate, 16000);
      expect(chunk.samples, samples);
      validateAudio(chunk.samples);
    },
  );
  test('bad channel buffers never reach Whisper', () {
    for (final buffer in [
      Uint8List(3),
      'text',
      Float32List.fromList([double.nan]).buffer.asUint8List(),
      Float32List.fromList([1.1]).buffer.asUint8List(),
    ]) {
      expect(() => decodeFloatPcm(buffer), throwsFormatException);
    }
  });
  test(
    'diagnostics retain noisy/quiet input without gating or a confidence score',
    () {
      for (final gain in [.00001, .05, .3]) {
        final samples = List.generate(16000, (i) => gain * sin(i / 20));
        final original = List<double>.from(samples);
        final diagnostics = AudioDiagnostics()..add(samples);
        validateAudio(samples);
        expect(samples, original);
        expect(diagnostics.notice, isNull);
        expect(diagnostics.samples, 16000);
      }
      final overloaded = AudioDiagnostics()..add(List.filled(1600, 1));
      expect(overloaded.fullScaleFraction, 1);
      expect(overloaded.notice, contains('full scale'));
    },
  );
}
