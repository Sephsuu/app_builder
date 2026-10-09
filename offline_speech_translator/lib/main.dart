import 'package:flutter/material.dart';

import 'features/speech/presentation/salin_landing_screen.dart';
import 'theme/salin_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SultiApp());
}

// Retain the app class used by existing integrations; Salin is the UI brand.
class SultiApp extends StatelessWidget {
  const SultiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salin',
      debugShowCheckedModeBanner: false,
      theme: SalinTheme.light,
      home: const SalinLandingScreen(),
    );
  }
}
