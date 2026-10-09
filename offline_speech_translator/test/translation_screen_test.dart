import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';
import 'package:offline_speech_translator/features/speech/data/local_whisper_speech_service.dart';
import 'package:offline_speech_translator/features/speech/presentation/speech_home_screen.dart';
import 'package:offline_speech_translator/features/translation/domain/translation.dart';
import 'package:offline_speech_translator/theme/salin_theme.dart';
import 'package:offline_speech_translator/features/speech/presentation/conversation_widgets.dart';
import 'translation_controller_test.dart' show FakeTranslator, FakeVoice;

class ScreenSpeech extends LocalWhisperSpeechService {
  late final result = Completer<WhisperResult>();
  String? capturedLanguage;
  bool? capturedNoiseSetting;
  int releases = 0;
  int finishes = 0;
  bool cebuanoInstalled = false;
  bool? capturedCebuano;
  @override
  Future<File?> findCebuanoModel() async =>
      cebuanoInstalled ? File('/ggml-cebuano-small-q5_1.bin') : null;
  bool baseInstalled = false;
  bool? capturedAccuracySetting;
  @override
  Future<File?> findInstalledModel({bool preferAccuracy = false}) async =>
      preferAccuracy
      ? (baseInstalled ? File('/ggml-base-q5_1.bin') : null)
      : File('/ggml-tiny-q5_1.bin');
  @override
  Future<void> startRecording({
    String language = 'tl',
    bool preferAccuracy = false,
    bool livePreview = true,
    bool noiseSuppression = false,
    bool cebuano = false,
  }) async {
    capturedLanguage = language;
    capturedCebuano = cebuano;
    capturedAccuracySetting = preferAccuracy;
    capturedNoiseSetting = noiseSuppression;
  }

  @override
  Future<WhisperResult> stopRecordingAndTranscribe() {
    finishes++;
    return result.future;
  }

  @override
  void releaseModel() {
    releases++;
  }
}

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 250,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> showResult(WidgetTester tester) async {
  final panel = find.byWidgetPredicate(
    (widget) => widget is TranslationTextPanel && widget.accent,
  );
  if (tester.widget<TranslationTextPanel>(panel).text.isNotEmpty) return;
  await reveal(tester, find.text('Translate source text'));
  await tester.tap(find.text('Translate source text'));
  await tester.pump();
}

Future<void> showSource(WidgetTester tester, String language) async {
  await reveal(tester, find.text('Original · $language'), delta: -250);
}

void main() {
  late ScreenSpeech speech;
  late FakeTranslator translator;
  late FakeVoice voice;
  setUp(() {
    speech = ScreenSpeech();
    translator = FakeTranslator();
    voice = FakeVoice();
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: SalinTheme.light,
        home: SpeechHomeScreen(
          speech: speech,
          translator: translator,
          voice: voice,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'installed Cebuano model enables voice and translates the final Cebuano source',
    (tester) async {
      speech.cebuanoInstalled = true;
      await open(tester);
      await reveal(tester, find.byTooltip('Swap languages and clear text'));
      await tester.tap(find.byTooltip('Swap languages and clear text'));
      await tester.pumpAndSettle();
      final microphone = find.byIcon(Icons.mic_none_rounded);
      await reveal(tester, microphone);
      await tester.tap(microphone);
      await tester.pump();
      expect(speech.capturedLanguage, 'ceb');
      expect(speech.capturedCebuano, isTrue);
      expect(translator.requests, isEmpty);
      await reveal(tester, find.text('Stop'));
      await tester.tap(find.text('Stop'));
      await tester.pump();
      speech.result.complete(
        const WhisperResult(
          text: 'Asa si Maria?',
          segments: [],
          language: 'tl',
          languageProbability: -1,
          systemInfo: 'test',
          processingTime: Duration.zero,
        ),
      );
      await tester.pump();
      expect(translator.requests.single.source, TranslationLanguage.cebuano);
      expect(translator.requests.single.target, TranslationLanguage.tagalog);
      expect(translator.requests.single.text, 'Asa si Maria?');
      translator.requests.single.result.complete('Saan si Maria?');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Finish translates only the final transcript and plays output', (
    tester,
  ) async {
    await open(tester);
    final microphone = find.byIcon(Icons.mic_none_rounded);
    await reveal(tester, microphone);
    await tester.tap(microphone);
    await tester.pump();
    expect(speech.capturedLanguage, 'tl');
    expect(speech.capturedNoiseSetting, isFalse);
    expect(translator.requests, isEmpty);
    final finish = find.text('Stop');
    await reveal(tester, finish);
    await tester.tap(finish);
    await tester.pump();
    expect(speech.finishes, 1);
    expect(translator.requests, isEmpty);
    speech.result.complete(
      const WhisperResult(
        text: '  Nasaan si Maria?  ',
        language: 'tl',
        languageProbability: -1,
        segments: [],
        processingTime: Duration.zero,
        systemInfo: 'test',
      ),
    );
    await tester.pump();
    expect(translator.requests.single.text, 'Nasaan si Maria?');
    expect(speech.releases, 1);
    translator.requests.single.result.complete('Asa si Maria?');
    await tester.pumpAndSettle();
    await showResult(tester);
    expect(translator.requests, hasLength(1));
    final play = find.text('Play translation');
    await reveal(tester, play);
    await tester.tap(play);
    await tester.pump();
    expect(voice.spoken.single, ('Asa si Maria?', TranslationLanguage.cebuano));
    await showSource(tester, 'Tagalog');
    expect(find.text('Nasaan si Maria?'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Installed Base is selected for final recognition; user can choose Tiny',
    (tester) async {
      speech.baseInstalled = true;
      await open(tester);
      await tester.tap(find.byTooltip('Speech and offline settings'));
      await tester.pumpAndSettle();
      final choice = find.widgetWithText(
        SwitchListTile,
        'Refine with Whisper Base',
      );
      await reveal(tester, choice);
      expect(tester.widget<SwitchListTile>(choice).value, isTrue);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(choice).value, isFalse);
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byIcon(Icons.mic_none_rounded));
      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pump();
      expect(speech.capturedAccuracySetting, isFalse);
    },
  );

  testWidgets('Cebuano text can translate, retry, edit and play Tagalog', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Swap languages and clear text'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.mic_none_rounded),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Enter Bisaya text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Asa si Maria sa Mayo 12?');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await showResult(tester);
    expect(translator.requests.single.source, TranslationLanguage.cebuano);
    translator.requests.single.result.completeError(
      StateError('temporary failure'),
    );
    await tester.pumpAndSettle();
    await showSource(tester, 'Bisaya');
    expect(find.text('Asa si Maria sa Mayo 12?'), findsWidgets);
    await reveal(tester, find.text('Retry translation'));
    await tester.tap(find.text('Retry translation'));
    await tester.pump();
    translator.requests.last.result.complete('Nasaan si Maria sa Mayo 12?');
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Play translation'));
    await tester.tap(find.text('Play translation'));
    await tester.pump();
    expect(voice.spoken.single.$2, TranslationLanguage.tagalog);
    await reveal(tester, find.byTooltip('Edit transcription'), delta: -250);
    await tester.tap(find.byTooltip('Edit transcription'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Dili ko moadto.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TranslationTextPanel>(
            find.byWidgetPredicate(
              (w) => w is TranslationTextPanel && w.accent,
            ),
          )
          .text,
      isEmpty,
    );
    // The previous completed turn remains in conversation history.
    await showResult(tester);
    expect(translator.requests.last.text, 'Dili ko moadto.');
    translator.requests.last.result.complete('Hindi ako pupunta.');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
