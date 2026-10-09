import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/speech/data/speech_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'concurrent stop callers wait for native cleanup before a new capture',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const methods = MethodChannel('whisper_cpp_flutter/recorder');
      const events = MethodChannel('whisper_cpp_flutter/audio');
      var stopped = Completer<void>();
      var stops = 0;
      messenger.setMockMethodCallHandler(events, (_) async => null);
      messenger.setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'requestPermission') return true;
        if (call.method == 'stop') {
          stops++;
          await stopped.future;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(methods, null);
        messenger.setMockMethodCallHandler(events, null);
      });
      final capture = MicrophoneCapture();
      final stream = await capture.start();
      final subscription = stream.listen((_) {});
      final first = capture.stop();
      final second = capture.stop();
      var secondFinished = false;
      unawaited(second.then((_) => secondFinished = true));
      await Future<void>.delayed(Duration.zero);
      expect(stops, 1);
      expect(secondFinished, isFalse);
      stopped.complete();
      await Future.wait([first, second]);
      await subscription.cancel();
      stopped = Completer<void>();
      final next = (await capture.start()).listen((_) {});
      final finish = capture.stop();
      stopped.complete();
      await finish;
      await next.cancel();
      expect(stops, 2);
    },
  );
}
