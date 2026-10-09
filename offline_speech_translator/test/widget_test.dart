import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:offline_speech_translator/main.dart';

void main() {
  testWidgets('Salin landing assets load and Start opens recording', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SultiApp());
    await tester.pumpAndSettle();
    expect(find.text('Bawat wika, iisang diwa'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Enter Tagalog text'), findsOneWidget);
    expect(find.byTooltip('Start recording'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
  });
}
