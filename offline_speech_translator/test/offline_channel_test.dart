import 'package:flutter/services.dart';
import 'package:offline_speech_translator/features/speech/data/local_whisper_speech_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/translation/data/local_translation_service.dart';
import 'package:offline_speech_translator/features/translation/domain/translation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  test(
    'Cebuano cannot use a stock checkpoint and cancelled import remains uninstalled',
    () async {
      const channel = MethodChannel('sulti/cebuano_model');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'import' ? false : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final speech = LocalWhisperSpeechService();
      expect(await speech.findCebuanoModel(), isNull);
      expect(await speech.importCebuanoModel(), isFalse);
      await expectLater(
        speech.startRecording(language: 'ceb'),
        throwsStateError,
      );
      await speech.dispose();
    },
  );

  test(
    'native translation receives actual text and both exact NLLB codes',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(LocalTranslationService.channel, (
        call,
      ) async {
        calls.add(call);
        return 'model result';
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          LocalTranslationService.channel,
          null,
        ),
      );
      final translator = LocalTranslationService();
      for (final source in TranslationLanguage.values) {
        await translator.translate('Maria: 12, hindi!', source, source.other);
        expect(calls.last.arguments, {
          'text': 'Maria: 12, hindi!',
          'source': source.modelCode,
          'target': source.other.modelCode,
        });
      }
      await expectLater(
        translator.translate(
          '',
          TranslationLanguage.tagalog,
          TranslationLanguage.cebuano,
        ),
        throwsArgumentError,
      );
      await expectLater(
        translator.translate(
          'text',
          TranslationLanguage.tagalog,
          TranslationLanguage.tagalog,
        ),
        throwsArgumentError,
      );
      expect(calls, hasLength(2));
    },
  );

  test(
    'playback selects only the target voice code and translation text',
    () async {
      const channel = MethodChannel('sulti/offline_voice');
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'supports' ? true : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final voice = DeviceSpeechOutput();
      for (final language in TranslationLanguage.values) {
        expect(await voice.supports(language), isTrue);
        expect(calls.last.arguments, language.voiceCode);
        await voice.speak('Translated output', language);
        expect(calls.last.arguments, {
          'text': 'Translated output',
          'language': language.voiceCode,
        });
      }
      await voice.stop();
      expect(calls.last.method, 'stop');
    },
  );
}
