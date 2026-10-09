import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/translation/application/translation_controller.dart';
import 'package:offline_speech_translator/features/translation/domain/translation.dart';

class PendingTranslation {
  PendingTranslation(this.text, this.source, this.target);
  final String text;
  final TranslationLanguage source, target;
  final result = Completer<String>();
}

class FakeTranslator implements TranslationService {
  final requests = <PendingTranslation>[];
  Completer<void>? cancellation;
  @override
  Future<void> cancel() async => cancellation?.future;
  @override
  Future<String> translate(
    String text,
    TranslationLanguage source,
    TranslationLanguage target,
  ) {
    final request = PendingTranslation(text, source, target);
    requests.add(request);
    return request.result.future;
  }
}

class FakeVoice implements SpeechOutput {
  final spoken = <(String, TranslationLanguage)>[];
  bool available = true;
  int stops = 0;
  Completer<bool>? discovery;
  Completer<void>? playback;
  @override
  Future<bool> supports(TranslationLanguage language) async =>
      discovery == null ? available : discovery!.future;
  @override
  Future<void> speak(String text, TranslationLanguage language) async {
    spoken.add((text, language));
    await playback?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeTranslator translator;
  late FakeVoice voice;
  late TranslationController controller;
  setUp(() {
    translator = FakeTranslator();
    voice = FakeVoice();
    controller = TranslationController(translator: translator, voice: voice);
  });
  tearDown(() => controller.dispose());

  for (final source in TranslationLanguage.values) {
    test(
      'final ${source.label} text uses the selected pair and target voice',
      () async {
        controller.selectSource(source);
        final epoch = await controller.beginRecording();
        expect(translator.requests, isEmpty);
        expect(controller.recording, isTrue);
        final work = controller.acceptFinal(epoch, '  Final text  ');
        await flush();
        final request = translator.requests.single;
        expect(request.text, 'Final text');
        expect(request.source, source);
        expect(request.target, source.other);
        request.result.complete('Translated text');
        await work;
        await controller.play();
        expect(voice.spoken.single, ('Translated text', source.other));
        expect(controller.translating, isFalse);
        expect(controller.playing, isFalse);
        expect(controller.transcript, 'Final text');
      },
    );
  }

  test(
    'duplicate translate and duplicate finalization do not queue work',
    () async {
      final epoch = await controller.beginRecording();
      final first = controller.acceptFinal(epoch, 'Salamat');
      await flush();
      await controller.acceptFinal(epoch, 'Earlier provisional text');
      await controller.translate();
      expect(translator.requests, hasLength(1));
      translator.requests.single.result.complete('Salamat');
      await first;
    },
  );

  test(
    'direction change clears source and ignores old output/errors',
    () async {
      controller.edit('Kumusta?');
      final first = controller.translate();
      await flush();
      controller.selectSource(TranslationLanguage.cebuano);
      expect(controller.transcript, isEmpty);
      expect(controller.translating, isFalse);
      controller.edit('Asa si Maria?');
      final second = controller.translate();
      await flush();
      translator.requests[1].result.complete('Nasaan si Maria?');
      await second;
      translator.requests[0].result.completeError(StateError('old failure'));
      await first;
      expect(controller.translated, 'Nasaan si Maria?');
      expect(controller.error, isNull);
      expect(translator.requests[1].source.modelCode, 'ceb_Latn');
      expect(translator.requests[1].target.modelCode, 'tgl_Latn');
    },
  );

  test(
    'new recording invalidates translation and waits for resource release',
    () async {
      controller.edit('Old text');
      final old = controller.translate();
      await flush();
      translator.cancellation = Completer<void>();
      var recordingReady = false;
      final start = controller.beginRecording().then((value) {
        recordingReady = true;
        return value;
      });
      await flush();
      expect(recordingReady, isFalse);
      translator.requests.single.result.complete('Stale output');
      await old;
      expect(controller.translated, isEmpty);
      expect(controller.transcript, isEmpty);
      translator.cancellation!.complete();
      await start;
      expect(recordingReady, isTrue);
    },
  );

  test('language selection is frozen throughout a recording', () async {
    final epoch = await controller.beginRecording();
    controller.selectSource(TranslationLanguage.cebuano);
    expect(controller.source, TranslationLanguage.tagalog);
    controller.cancelRecording();
    await controller.acceptFinal(epoch, 'Late final result');
    expect(controller.transcript, isEmpty);
    expect(translator.requests, isEmpty);
  });

  test(
    'editing invalidates output; failures preserve source and allow retry',
    () async {
      controller.edit('Hindi ako pupunta sa Mayo 12.');
      final first = controller.translate();
      await flush();
      translator.requests.last.result.completeError(
        StateError('model unavailable'),
      );
      await first;
      expect(controller.error, contains('model unavailable'));
      expect(controller.transcript, 'Hindi ako pupunta sa Mayo 12.');
      final retry = controller.translate();
      await flush();
      translator.requests.last.result.complete('Dili ko moadto sa Mayo 12.');
      await retry;
      expect(controller.error, isNull);
      controller.edit('Hindi ako pupunta sa Mayo 13.');
      expect(controller.translated, isEmpty);
      expect(controller.transcript, endsWith('13.'));
      controller.edit('');
      await controller.translate();
      expect(translator.requests, hasLength(2));
    },
  );

  test('silence and empty final results never translate', () async {
    final epoch = await controller.beginRecording();
    await controller.acceptFinal(epoch, '   ');
    expect(controller.recording, isFalse);
    expect(controller.translating, isFalse);
    expect(translator.requests, isEmpty);
  });

  test(
    'unsupported target voice is reported without speaking source text',
    () async {
      voice.available = false;
      controller.edit('Hello');
      final work = controller.translate();
      await flush();
      translator.requests.single.result.complete('Kumusta');
      await work;
      await controller.play();
      expect(voice.spoken, isEmpty);
      expect(controller.voiceNotice, contains('offline Bisaya voice'));
      expect(controller.translated, 'Kumusta');
    },
  );

  test('stop during voice discovery prevents later playback', () async {
    controller.edit('Hello');
    final work = controller.translate();
    await flush();
    translator.requests.single.result.complete('Kumusta');
    await work;
    voice.discovery = Completer<bool>();
    final play = controller.play();
    await controller.stopPlayback();
    voice.discovery!.complete(true);
    await play;
    expect(voice.spoken, isEmpty);
    expect(controller.playing, isFalse);
  });

  test(
    'playback state lasts until utterance completion; swap invalidates it',
    () async {
      controller.edit('Salamat');
      final work = controller.translate();
      await flush();
      translator.requests.single.result.complete('Salamat');
      await work;
      voice.playback = Completer<void>();
      final play = controller.play();
      await flush();
      expect(controller.playing, isTrue);
      controller.selectSource(TranslationLanguage.cebuano);
      voice.playback!.complete();
      await play;
      expect(controller.playing, isFalse);
      expect(controller.translated, isEmpty);
    },
  );
}
