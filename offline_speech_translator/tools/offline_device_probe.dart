// Developer-only native smoke test. Build explicitly with -t tools/offline_device_probe.dart.
// Never included as the application entry point. No network requests are made.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:offline_speech_translator/features/translation/data/local_translation_service.dart';
import 'package:offline_speech_translator/features/translation/domain/translation.dart';

const root =
    '/data/user/0/com.example.offline_speech_translator/files/evaluation';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Offline native verification'))),
    ),
  );
  unawaited(probe());
}

Future<void> probe() async {
  final report = <String, Object?>{
    'platform': Platform.operatingSystem,
    'voices': <String, Object?>{},
  };
  final translation = LocalTranslationService();
  final voice = DeviceSpeechOutput();
  try {
    for (final language in TranslationLanguage.values) {
      (report['voices'] as Map<String, Object?>)[language.voiceCode] =
          await voice.supports(language);
    }
    report['installed'] = await translation.isInstalled();
    final results = <Map<String, Object?>>[];
    report['translations'] = results;
    for (final pair in [
      (TranslationLanguage.tagalog, 'Kumusta ka?'),
      (TranslationLanguage.cebuano, 'Asa si Maria?'),
      (TranslationLanguage.tagalog, 'Hindi ako pupunta sa Mayo 12.'),
      (TranslationLanguage.cebuano, 'Dili ko gusto og kape.'),
    ]) {
      final clock = Stopwatch()..start();
      final output = await translation.translate(
        pair.$2,
        pair.$1,
        pair.$1.other,
      );
      results.add({
        'source': pair.$1.modelCode,
        'target': pair.$1.other.modelCode,
        'input': pair.$2,
        'output': output,
        'elapsed_ms': clock.elapsedMilliseconds,
      });
    }
    final pending = translation
        .translate(
          List.filled(20, 'Nasaan si Maria?').join(' '),
          TranslationLanguage.tagalog,
          TranslationLanguage.cebuano,
        )
        .then<String>(
          (_) => 'unexpected completion',
          onError: (_) => 'cancelled',
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final cancellationClock = Stopwatch()..start();
    await translation.cancel();
    report['cancellation'] = {
      'outcome': await pending,
      'fence_ms': cancellationClock.elapsedMilliseconds,
      'retry_output': await translation.translate(
        'Asa si Maria?',
        TranslationLanguage.cebuano,
        TranslationLanguage.tagalog,
      ),
    };
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
  } finally {
    await translation.cancel();
    await voice.stop();
    await Directory(root).create(recursive: true);
    await File(
      '$root/offline-native-result.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  }
}
