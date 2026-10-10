import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/speech/presentation/salin_landing_screen.dart';
import 'package:offline_speech_translator/features/speech/presentation/speech_home_screen.dart';
import 'package:offline_speech_translator/theme/salin_theme.dart';

import 'translation_controller_test.dart' show FakeTranslator, FakeVoice;
import 'translation_screen_test.dart' show ScreenSpeech, reveal, showResult;

const _captureScreenshots = bool.fromEnvironment('SALIN_SCREENSHOTS');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Load the real bundled fonts for visual inspection as well as layout tests.
    for (final font in {
      'Inter': 'Inter',
      'Plus Jakarta Sans': 'PlusJakartaSans',
    }.entries) {
      await (FontLoader(
        font.key,
      )..addFont(rootBundle.load('assets/fonts/${font.value}.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(430, 932),
    const Size(844, 390),
  ]) {
    testWidgets(
      'landing and translation flow fit ${size.width}×${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundaryKey = GlobalKey();
        Widget app(Widget home) => MaterialApp(
          theme: SalinTheme.light,
          home: RepaintBoundary(key: boundaryKey, child: home),
        );
        Future<void> screenshot(String name) async {
          expect(tester.takeException(), isNull);
          if (!_captureScreenshots || size != const Size(390, 844)) return;
          await tester.runAsync(() async {
            for (final path in [
              'assets/LANDPAGElogo.png',
              'assets/tagalogHeader.png',
            ]) {
              await precacheImage(
                AssetImage(path),
                boundaryKey.currentContext!,
              );
            }
          });
          await tester.pumpAndSettle();
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('build/salin-ui/$name.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }

        await tester.pumpWidget(app(SalinLandingScreen(onStart: () {})));
        await tester.pumpAndSettle();
        await screenshot('landing');
        await reveal(tester, find.text('Start'));
        expect(find.text('Start').hitTestable(), findsOneWidget);

        final translator = FakeTranslator();
        final voice = FakeVoice();
        await tester.pumpWidget(
          app(
            SpeechHomeScreen(
              speech: ScreenSpeech(),
              translator: translator,
              voice: voice,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await screenshot('capture-empty');
        await reveal(tester, find.text('Enter Tagalog text'));
        await tester.tap(find.text('Enter Tagalog text'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'Kumain ka na ba?\nSaan ka pupunta?\nMahal kita.',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, 1200),
        );
        await tester.pumpAndSettle();
        await screenshot('capture-text');
        await reveal(tester, find.text('Translate source text'));
        await tester.tap(find.text('Translate source text'));
        await tester.pump();
        expect(translator.requests, hasLength(1));
        translator.requests.single.result.complete(
          'Nakaon ka na?\nAsa ka paingon?\nGihigugma tika.',
        );
        await tester.pumpAndSettle();
        await screenshot('result');
        await reveal(tester, find.text('Translate Again'));
        await tester.tap(find.text('Translate Again'));
        await tester.pumpAndSettle();
        expect(find.text('Stop'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Speech and translation settings'));
        await tester.pumpAndSettle();
        await screenshot('settings');
        await reveal(tester, find.text('Refine with Whisper Base'));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'large text stays usable and a new recording cancels pending translation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final translator = FakeTranslator();
      await tester.pumpWidget(
        MaterialApp(
          theme: SalinTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SpeechHomeScreen(
            speech: ScreenSpeech(),
            translator: translator,
            voice: FakeVoice(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Enter Tagalog text'));
      await tester.tap(find.text('Enter Tagalog text'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Salamat.');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await showResult(tester);
      // Starting the next turn cancels the unfinished translation.
      await tester.ensureVisible(find.byTooltip('Start recording'));
      await tester.pump();
      await tester.tap(find.byTooltip('Start recording'));
      await tester.pumpAndSettle();
      translator.requests.single.result.complete('Stale result');
      await tester.pumpAndSettle();
      expect(find.text('Stale result'), findsNothing);
      expect(find.text('Stop'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
