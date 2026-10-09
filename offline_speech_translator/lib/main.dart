import 'package:flutter/material.dart';

import 'features/onboarding/presentation/onboarding_gate.dart';
import 'features/onboarding/data/onboarding_store.dart';
import 'theme/salin_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SultiApp());
}

// Retain the app class used by existing integrations; Salin is the UI brand.
class SultiApp extends StatelessWidget {
  const SultiApp({super.key, this.onboardingStore, this.translatorBuilder});
  final OnboardingStore? onboardingStore;
  final WidgetBuilder? translatorBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salin',
      debugShowCheckedModeBanner: false,
      theme: SalinTheme.light,
      home: OnboardingGate(
        store: onboardingStore,
        translatorBuilder: translatorBuilder,
      ),
    );
  }
}
