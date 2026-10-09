import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/speech/presentation/conversation_widgets.dart';
import 'package:offline_speech_translator/features/speech/presentation/speech_home_screen.dart';
import 'package:offline_speech_translator/theme/salin_theme.dart';
import 'translation_screen_test.dart' show ScreenSpeech;
import 'package:offline_speech_translator/features/translation/domain/translation.dart';
import 'translation_controller_test.dart' show FakeTranslator, FakeVoice;

class WaveformSpeech extends ScreenSpeech {
  final levels = StreamController<double>.broadcast();
  int starts = 0;
  int cancellations = 0;
  bool denied = false;
  @override
  Stream<double> get audioLevels => levels.stream;
  @override
  Future<void> startRecording({
    String language = 'tl',
    bool preferAccuracy = false,
    bool livePreview = true,
    bool noiseSuppression = false,
    bool cebuano = false,
  }) async {
    if (denied) throw StateError('Microphone permission denied');
    starts++;
    await super.startRecording(
      language: language,
      preferAccuracy: preferAccuracy,
      livePreview: livePreview,
      noiseSuppression: noiseSuppression,
      cebuano: cebuano,
    );
  }

  @override
  Future<void> cancelTranscription() {
    cancellations++;
    return super.cancelTranscription();
  }

  @override
  Future<void> dispose() async {
    await levels.close();
    await super.dispose();
  }
}

void main() {
  testWidgets(
    'real level events grow the waveform; interruption removes it and stops capture',
    (tester) async {
      final speech = WaveformSpeech();
      await tester.pumpWidget(
        MaterialApp(
          theme: SalinTheme.light,
          home: SpeechHomeScreen(
            speech: speech,
            translator: FakeTranslator(),
            voice: FakeVoice(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AudioWaveform), findsNothing);
      await tester.tap(find.byTooltip('Start recording'));
      await tester.pump();
      expect(find.byType(AudioWaveform), findsOneWidget);
      speech.levels.add(.002);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final quiet = tester
          .widget<AudioWaveform>(find.byType(AudioWaveform))
          .levels
          .last;
      speech.levels.add(.2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final loud = tester
          .widget<AudioWaveform>(find.byType(AudioWaveform))
          .levels
          .last;
      expect(loud, greaterThan(quiet));
      final dropdowns = tester
          .widgetList<DropdownButtonFormField<TranslationLanguage>>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is DropdownButtonFormField<TranslationLanguage>,
            ),
          );
      expect(dropdowns, hasLength(2));
      expect(dropdowns.every((d) => d.onChanged == null), isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(speech.cancellations, greaterThan(0));
      expect(find.byType(AudioWaveform), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
  testWidgets('permission denial returns to idle with an actionable error', (
    tester,
  ) async {
    final speech = WaveformSpeech()..denied = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: SalinTheme.light,
        home: SpeechHomeScreen(
          speech: speech,
          translator: FakeTranslator(),
          voice: FakeVoice(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Start recording'));
    await tester.pumpAndSettle();
    expect(find.byType(AudioWaveform), findsNothing);
    expect(
      find.text(
        'Microphone access is needed. Allow it in Android Settings, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Start recording'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
