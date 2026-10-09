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
    'direction change selects a separate draft and ignores old output/errors',
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
    'both direction drafts and completed outputs survive repeated swaps',
    () async {
      controller.edit('Nasaan si Maria?');
      final work = controller.translate();
      await flush();
      translator.requests.single.result.complete('Asa si Maria?');
      await work;
      controller.selectSource(TranslationLanguage.cebuano);
      expect(controller.transcript, isEmpty);
      controller.edit('Dili ko moadto.');
      controller.selectSource(TranslationLanguage.tagalog);
      expect(controller.transcript, 'Nasaan si Maria?');
      expect(controller.translated, 'Asa si Maria?');
      expect(controller.restoredDraft, isTrue);
      await controller.play();
      expect(voice.spoken.single.$2, TranslationLanguage.cebuano);
      controller.selectSource(TranslationLanguage.cebuano);
      expect(controller.transcript, 'Dili ko moadto.');
      expect(controller.translated, isEmpty);
      expect(translator.requests, hasLength(1));
    },
  );

  test(
    'swap away and back never accepts an earlier asynchronous result',
    () async {
      controller.edit('Salamat');
      final work = controller.translate();
      await flush();
      controller.selectSource(TranslationLanguage.cebuano);
      controller.selectSource(TranslationLanguage.tagalog);
      translator.requests.single.result.complete('Obsolete output');
      await work;
      expect(controller.transcript, 'Salamat');
      expect(controller.translated, isEmpty);
      expect(controller.history, isEmpty);
      expect(controller.translating, isFalse);
    },
  );

  test(
    'review mode accepts only final text and waits for explicit translation',
    () async {
      final epoch = await controller.beginRecording();
      await controller.acceptFinal(
        epoch,
        'Raw source',
        translateAutomatically: false,
      );
      expect(controller.transcript, 'Raw source');
      expect(controller.recording, isFalse);
      expect(translator.requests, isEmpty);
      controller.edit('Reviewed source');
      final work = controller.translate();
      await flush();
      expect(translator.requests.single.text, 'Reviewed source');
      translator.requests.single.result.complete('Reviewed result');
      await work;
    },
  );

  test('cancelled or empty recordings restore the previous draft', () async {
    controller.edit('Keep this');
    await controller.beginRecording();
    controller.cancelRecording();
    expect(controller.transcript, 'Keep this');
    final epoch = await controller.beginRecording();
    await controller.acceptFinal(epoch, '   ');
    expect(controller.transcript, 'Keep this');
    expect(translator.requests, isEmpty);
  });

  test(
    'failed cancellation restores source and a later recording can retry',
    () async {
      controller.edit('Keep this');
      translator.cancellation = Completer<void>();
      final start = controller.beginRecording();
      final expectation = expectLater(start, throwsStateError);
      translator.cancellation!.completeError(StateError('cancel failed'));
      await expectation;
      expect(controller.recording, isFalse);
      expect(controller.transcript, 'Keep this');
      translator.cancellation = null;
      await controller.beginRecording();
      expect(controller.recording, isTrue);
    },
  );

  test(
    'clear affects only selected draft and retains completed history',
    () async {
      controller.edit('Salamat');
      final work = controller.translate();
      await flush();
      translator.requests.single.result.complete('Salamat');
      await work;
      controller.selectSource(TranslationLanguage.cebuano);
      controller.edit('Asa ka?');
      controller.clear();
      controller.selectSource(TranslationLanguage.tagalog);
      expect(controller.translated, 'Salamat');
      controller.selectSource(TranslationLanguage.cebuano);
      expect(controller.transcript, isEmpty);
      expect(controller.history, hasLength(1));
    },
  );

  test('saving unchanged source preserves the valid translation', () async {
    controller.edit('Salamat');
    final work = controller.translate();
    await flush();
    translator.requests.single.result.complete('Salamat');
    await work;
    controller.edit(' Salamat ');
    expect(controller.translated, 'Salamat');
    expect(controller.history, hasLength(1));
  });

  test(
    'independent lines translate serially and publish one complete turn',
    () async {
      controller.edit('Nasaan si Maria?\r\n\r\nSalamat.');
      final work = controller.translate(separateLines: true);
      await flush();
      expect(translator.requests.single.text, 'Nasaan si Maria?');
      translator.requests.single.result.complete('Asa si Maria?');
      await flush();
      expect(controller.translated, isEmpty);
      expect(controller.history, isEmpty);
      expect(translator.requests.last.text, 'Salamat.');
      translator.requests.last.result.complete('Salamat.');
      await work;
      expect(controller.translated, 'Asa si Maria?\n\nSalamat.');
      expect(
        controller.history.single.original,
        'Nasaan si Maria?\r\n\r\nSalamat.',
      );
    },
  );

  test(
    'line failure preserves full source and rejects partial output',
    () async {
      controller.edit('First\nSecond');
      final work = controller.translate(separateLines: true);
      await flush();
      translator.requests.first.result.complete('First output');
      await flush();
      translator.requests.last.result.completeError(StateError('Timeout'));
      await work;
      expect(controller.transcript, 'First\nSecond');
      expect(controller.translated, isEmpty);
      expect(controller.history, isEmpty);
      expect(controller.error, contains('Timeout'));
    },
  );

  test(
    'direction switch cancels a line batch before starting its next line',
    () async {
      controller.edit('First\nSecond');
      final work = controller.translate(separateLines: true);
      await flush();
      controller.selectSource(TranslationLanguage.cebuano);
      translator.requests.single.result.complete('Stale');
      await work;
      expect(translator.requests, hasLength(1));
      expect(controller.history, isEmpty);
      controller.selectSource(TranslationLanguage.tagalog);
      expect(controller.transcript, 'First\nSecond');
      expect(controller.translated, isEmpty);
    },
  );

  test('default translation retains context across lines', () async {
    controller.edit('First\nSecond');
    final work = controller.translate();
    await flush();
    expect(translator.requests.single.text, 'First\nSecond');
    translator.requests.single.result.complete('Full output');
    await work;
    expect(controller.translated, 'Full output');
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
