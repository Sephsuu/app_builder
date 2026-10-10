import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';
import 'package:offline_speech_translator/features/speech/data/local_whisper_speech_service.dart';
import 'package:offline_speech_translator/features/speech/presentation/speech_home_screen.dart';
import 'package:offline_speech_translator/features/translation/domain/translation.dart';
import 'package:offline_speech_translator/theme/salin_theme.dart';
import 'package:offline_speech_translator/features/speech/presentation/conversation_widgets.dart';
import 'translation_controller_test.dart' show FakeTranslator, FakeVoice;

class ScreenSpeech extends LocalWhisperSpeechService {
  late Completer<WhisperResult> result = Completer<WhisperResult>();
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

  Future<void> enter(WidgetTester tester, String language, String text) async {
    await reveal(tester, find.text('Enter $language text'));
    await tester.tap(find.text('Enter $language text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  Future<void> swap(WidgetTester tester) async {
    await reveal(tester, find.byTooltip('Swap languages'), delta: -250);
    await tester.tap(find.byTooltip('Swap languages'));
    await tester.pumpAndSettle();
  }

  Future<void> recordText(WidgetTester tester, String text) async {
    speech.result = Completer<WhisperResult>();
    await tester.scrollUntilVisible(
      find.byTooltip('Start recording'),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byTooltip('Start recording'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Start recording'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();
    speech.result.complete(
      WhisperResult(
        text: text,
        language: 'tl',
        languageProbability: -1,
        segments: [],
        processingTime: Duration.zero,
        systemInfo: 'test',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'consecutive speech turns discard stale translations and accept new transcripts',
    (tester) async {
      await open(tester);
      await recordText(tester, 'Nasaan si Maria?');
      final first = translator.requests.single;
      await recordText(tester, 'Saan tayo pupunta mamaya?');
      expect(translator.requests, hasLength(2));
      first.result.complete('stale translation');
      translator.requests.last.result.complete('Asa ta moadto unya?');
      await tester.pumpAndSettle();
      expect(find.text('stale translation'), findsNothing);
      await recordText(tester, 'Maraming salamat.');
      expect(translator.requests.last.text, 'Maraming salamat.');
      translator.requests.last.result.complete('Daghang salamat.');
      await tester.pumpAndSettle();
      expect(speech.finishes, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Tagalog suggestions require approval and tracker can restore raw words',
    (tester) async {
      await open(tester);
      await recordText(tester, 'saan tayo puponta mamya');
      expect(translator.requests, isEmpty);
      await reveal(tester, find.text('Use suggested wording'));
      await tester.tap(find.text('Use suggested wording'));
      await tester.pump();
      expect(translator.requests.single.text, 'Saan tayo pupunta mamaya');
      translator.requests.single.result.complete('Asa ta moadto unya?');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Restore recognized text'), delta: -250);
      await tester.tap(find.text('Restore recognized text'));
      await tester.pumpAndSettle();
      await showResult(tester);
      expect(translator.requests.last.text, 'saan tayo puponta mamya');
      translator.requests.last.result.complete('Restored wording translation');
      await tester.pumpAndSettle();
      await swap(tester);
      expect(find.text('Tagalog transcript check'), findsNothing);
      await swap(tester);
      expect(find.text('Tagalog transcript check'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keeping recognized wording does not apply suggested word replacements',
    (tester) async {
      await open(tester);
      await recordText(tester, 'saan tayo puponta mamya');
      await reveal(tester, find.text('Keep recognized wording'));
      await tester.tap(find.text('Keep recognized wording'));
      await tester.pump();
      expect(translator.requests.single.text, 'Saan tayo puponta mamya');
      translator.requests.single.result.complete('Output');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'swapping retains independent drafts and clear affects only current direction',
    (tester) async {
      await open(tester);
      await enter(tester, 'Tagalog', 'Nasaan si Maria?');
      await swap(tester);
      await enter(tester, 'Bisaya', 'Dili ko moadto.');
      await swap(tester);
      expect(find.text('Nasaan si Maria?'), findsOneWidget);
      expect(find.text('Dili ko moadto.'), findsNothing);
      await reveal(tester, find.byTooltip('Clear current turn'));
      await tester.tap(find.byTooltip('Clear current turn'));
      await tester.pumpAndSettle();
      expect(find.text('Nasaan si Maria?'), findsNothing);
      await swap(tester);
      expect(find.text('Dili ko moadto.'), findsOneWidget);
      expect(translator.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('review mode holds final speech for editing before translation', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Speech and translation settings'));
    await tester.pumpAndSettle();
    final review = find.widgetWithText(
      SwitchListTile,
      'Review before translating',
    );
    await reveal(tester, review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close settings'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byTooltip('Start recording'), delta: -250);
    await tester.tap(find.byTooltip('Start recording'));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.swap_horiz_rounded),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Stop'));
    await tester.pump();
    speech.result.complete(
      const WhisperResult(
        text: 'Nasaan si Mario?',
        language: 'tl',
        languageProbability: -1,
        segments: [],
        processingTime: Duration.zero,
        systemInfo: 'test',
      ),
    );
    await tester.pumpAndSettle();
    expect(translator.requests, isEmpty);
    expect(
      find.text('Review your source text, then translate.'),
      findsOneWidget,
    );
    final steps = tester.widget<ConversationSteps>(
      find.byType(ConversationSteps),
    );
    expect(steps.hasSource, isTrue);
    expect(steps.hasTranslation, isFalse);
    await reveal(tester, find.byTooltip('Edit transcription'));
    await tester.tap(find.byTooltip('Edit transcription'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Nasaan si Maria?');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await showResult(tester);
    expect(translator.requests.single.text, 'Nasaan si Maria?');
    translator.requests.single.result.complete('Asa si Maria?');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ConversationSteps>(find.byType(ConversationSteps))
          .hasTranslation,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancel new recording restores source and saved result; copy uses displayed text',
    (tester) async {
      final copied = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await open(tester);
      await enter(tester, 'Tagalog', 'Salamat.');
      await showResult(tester);
      translator.requests.single.result.complete('Daghang salamat.');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Translate Again'));
      await tester.tap(find.text('Translate Again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Saved translation · Bisaya'), findsOneWidget);
      await reveal(tester, find.byTooltip('Copy transcription'), delta: -250);
      await tester.tap(find.byTooltip('Copy transcription'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byTooltip('Copy translation').first);
      await tester.tap(find.byTooltip('Copy translation').first);
      await tester.pumpAndSettle();
      expect(copied, ['Salamat.', 'Daghang salamat.']);
      expect(translator.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'installed Cebuano model enables voice and translates the final Cebuano source',
    (tester) async {
      speech.cebuanoInstalled = true;
      await open(tester);
      await reveal(tester, find.byTooltip('Swap languages'));
      await tester.tap(find.byTooltip('Swap languages'));
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
      await tester.tap(find.byTooltip('Speech and translation settings'));
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
    await tester.tap(find.byTooltip('Swap languages'));
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
