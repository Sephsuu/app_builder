import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/main.dart';
import 'package:offline_speech_translator/features/speech/presentation/speech_home_screen.dart';
import 'translation_controller_test.dart' show FakeTranslator, FakeVoice;
import 'translation_screen_test.dart' show ScreenSpeech;

void main() {
  testWidgets('landing assets open the main translator and back returns home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SultiApp(
        translatorBuilder: (_) => SpeechHomeScreen(
          speech: ScreenSpeech(),
          translator: FakeTranslator(),
          voice: FakeVoice(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.bySemanticsLabel('Salin'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
    expect(find.text('Bawat wika, iisang diwa'), findsOneWidget);

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.text('From'), findsOneWidget);
    expect(find.text('A conversation, in both languages'), findsOneWidget);
    expect(find.byTooltip('Back to landing page'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);

    await tester.tap(find.byTooltip('Speech and translation settings'));
    await tester.pumpAndSettle();
    expect(find.text('Speech & translation setup'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to translator'));
    await tester.pumpAndSettle();
    expect(find.text('Speech & translation setup'), findsNothing);
    expect(find.byTooltip('Back to landing page'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to landing page'));
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Bawat wika, iisang diwa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
