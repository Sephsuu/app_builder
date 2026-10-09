import 'package:flutter_test/flutter_test.dart';
import 'package:offline_speech_translator/main.dart';

void main() {
  testWidgets('shows the local Tagalog speech screen', (tester) async {
    await tester.pumpWidget(const SultiApp());

    expect(find.text('Sulti'), findsOneWidget);
    expect(find.text('Tagalog'), findsOneWidget);
    expect(find.text('Bisaya'), findsOneWidget);
  });
}
