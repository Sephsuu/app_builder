import 'package:flutter/material.dart';

import 'features/speech/presentation/speech_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SultiApp());
}

class SultiApp extends StatelessWidget {
  const SultiApp({super.key});

  static const _ink = Color(0xFF182C2A);
  static const _teal = Color(0xFF187C70);
  static const _paper = Color(0xFFF5F7F4);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _teal,
      brightness: Brightness.light,
      surface: _paper,
    );

    return MaterialApp(
      title: 'Sulti',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _paper,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: _paper,
          foregroundColor: _ink,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFE6ECE8)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE1E8E3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE1E8E3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _teal, width: 1.5),
          ),
        ),
      ),
      home: const SpeechHomeScreen(),
    );
  }
}
