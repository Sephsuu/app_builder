import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:offline_speech_translator/main.dart';
import 'package:offline_speech_translator/features/onboarding/data/onboarding_store.dart';

class MemoryOnboardingStore implements OnboardingStore {
  bool completed = false;
  bool failRead = false;
  bool failWrite = false;
  @override
  Future<bool> isCompleted() async {
    if (failRead) throw StateError('read failed');
    return completed;
  }

  @override
  Future<void> complete() async {
    if (failWrite) throw StateError('write failed');
    completed = true;
  }
}

Future<void> onboardingNext(WidgetTester tester, Finder control) async {
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'welcome, interactive example and completion skip on next launch',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryOnboardingStore();
      Widget app() => SultiApp(
        onboardingStore: store,
        translatorBuilder: (_) =>
            const Scaffold(body: Text('Conversation translator')),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsNWidgets(2));
      await onboardingNext(tester, find.text('Get started'));
      expect(find.text('Record voice'), findsOneWidget);
      await onboardingNext(tester, find.byTooltip('Start recording'));
      expect(find.text('Kumain ka na ba?'), findsOneWidget);
      await onboardingNext(tester, find.text('Continue'));
      await onboardingNext(
        tester,
        find.byTooltip('Swap languages and clear text'),
      );
      expect(find.text('Nakaon ka na?'), findsOneWidget);
      await onboardingNext(tester, find.text('Translate example'));
      await onboardingNext(tester, find.text('Continue'));
      await onboardingNext(tester, find.text('Start Translating'));
      expect(store.completed, isTrue);
      expect(find.text('Conversation translator'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsNothing);
      expect(find.text('Conversation translator'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preference read failure can be retried', (tester) async {
    final store = MemoryOnboardingStore()..failRead = true;
    await tester.pumpWidget(SultiApp(onboardingStore: store));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not read your welcome preferences.'),
      findsOneWidget,
    );
    store.failRead = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets(
    'failed completion write stays in onboarding until retry succeeds',
    (tester) async {
      final store = MemoryOnboardingStore()..failWrite = true;
      await tester.pumpWidget(
        SultiApp(
          onboardingStore: store,
          translatorBuilder: (_) => const Scaffold(body: Text('Translator')),
        ),
      );
      await tester.pumpAndSettle();
      await onboardingNext(tester, find.text('Get started'));
      await onboardingNext(tester, find.byTooltip('Start recording'));
      await onboardingNext(tester, find.text('Continue'));
      await onboardingNext(tester, find.text('Translate example'));
      await onboardingNext(tester, find.text('Continue'));
      await onboardingNext(tester, find.text('Start Translating'));
      expect(store.completed, isFalse);
      expect(find.text('Translator'), findsNothing);
      store.failWrite = false;
      await onboardingNext(tester, find.text('Start Translating'));
      expect(find.text('Translator'), findsOneWidget);
    },
  );
}
