import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/speech/application/live_recognition.dart';
import 'package:offline_speech_translator/features/speech/presentation/live_caption_card.dart';

void main() {
  testWidgets(
    'captions preserve repeated words and revise the provisional tail',
    (tester) async {
      Widget view(String text) => MaterialApp(
        home: Scaffold(
          body: LiveCaptionCard(
            snapshot: LiveRecognitionSnapshot(
              stable: 'Oo oo. ',
              provisional: text,
            ),
            finalizing: false,
          ),
        ),
      );
      await tester.pumpWidget(view('Gusto ko kumayim'));
      await tester.pumpWidget(view('Gusto ko kumain'));
      final text = tester.widget<Text>(
        find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
      );
      expect(text.textSpan!.toPlainText(), 'Oo oo. Gusto ko kumain');
      expect(tester.takeException(), isNull);
    },
  );
}
