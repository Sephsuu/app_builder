import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/translation/application/translation_controller.dart';
import 'package:offline_speech_translator/features/translation/domain/translation.dart';
import 'translation_controller_test.dart' show FakeTranslator, FakeVoice, flush;

void main() {
  test(
    'history retains completed language pairs and plays old turns in their own language',
    () async {
      final translator = FakeTranslator();
      final voice = FakeVoice();
      final controller = TranslationController(
        translator: translator,
        voice: voice,
      );
      addTearDown(controller.dispose);
      controller.edit('Salamat.');
      final first = controller.translate();
      await flush();
      translator.requests.single.result.complete('Salamat.');
      await first;
      final turn = controller.history.single;
      controller.selectSource(TranslationLanguage.cebuano);
      controller.edit('Asa ka?');
      final second = controller.translate();
      await flush();
      translator.requests.last.result.complete('Nasaan ka?');
      await second;
      expect(controller.history, hasLength(2));
      expect(controller.history.first.target, TranslationLanguage.cebuano);
      expect(controller.history.last.target, TranslationLanguage.tagalog);
      await controller.play(entry: turn);
      expect(voice.spoken.single, ('Salamat.', TranslationLanguage.cebuano));
      expect(controller.translated, 'Nasaan ka?');
      await controller.beginRecording();
      expect(controller.history, hasLength(2));
    },
  );
  test('failures and stale cancelled outputs never become history', () async {
    final translator = FakeTranslator();
    final controller = TranslationController(
      translator: translator,
      voice: FakeVoice(),
    );
    addTearDown(controller.dispose);
    controller.edit('one');
    final failed = controller.translate();
    await flush();
    translator.requests.last.result.completeError(StateError('failure'));
    await failed;
    expect(controller.history, isEmpty);
    final stale = controller.translate();
    await flush();
    controller.edit('two');
    translator.requests.last.result.complete('old output');
    await stale;
    expect(controller.history, isEmpty);
  });
}
