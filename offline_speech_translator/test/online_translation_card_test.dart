import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/features/translation/data/online_translation_settings.dart';
import 'package:offline_speech_translator/features/translation/presentation/online_translation_card.dart';

void main() {
  testWidgets('key entry is obscured, cleared after save, and removable', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      OnlineTranslationSettings.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        OnlineTranslationSettings.channel,
        null,
      ),
    );
    bool configured = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: OnlineTranslationCard(
                settings: OnlineTranslationSettings(),
                configured: configured,
                onChanged: () => setState(() => configured = !configured),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, true);
    await tester.enterText(find.byType(TextField), 'sk-example-not-a-real-key');
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'saveKey');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('Remove key'), findsOneWidget);
    await tester.tap(find.text('Remove key'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'removeKey');
    expect(find.text('Remove key'), findsNothing);
  });
}
