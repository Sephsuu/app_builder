// Developer-only real-device regression probe. Never use as the app entry point
// in a distributed APK. Build with -t tools/tagalog_translation_probe.dart, then
// restore the normal lib/main.dart build after reading the report.
// Pass --dart-define=RAW_INPUT=true to compare the raw native-input baseline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:offline_speech_translator/features/translation/data/local_translation_service.dart';
import 'package:offline_speech_translator/features/translation/data/translation_input.dart';
import 'package:offline_speech_translator/features/translation/domain/translation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Translation regression check'))),
    ),
  );
  unawaited(probe());
}

Future<void> probe() async {
  const rawInput = bool.fromEnvironment('RAW_INPUT');
  final service = LocalTranslationService();
  final rows = <Map<String, Object?>>[];
  final directory = Directory(
    '/data/user/0/com.example.offline_speech_translator/files/evaluation',
  );
  await directory.create(recursive: true);
  final file = File('${directory.path}/tagalog-translation-result.json');
  for (final input in [
    'saan tayo pupunta mamaya',
    'Saan tayo pupunta mamaya',
    'Saan tayo pupunta mamaya?',
    'Kumain ka na ba?',
    'Pakibigay kay Juan ang 3 libro bukas.',
  ]) {
    final timer = Stopwatch()..start();
    final row = <String, Object?>{
      'input': input,
      'model_input': rawInput
          ? input
          : prepareTranslationInput(input, TranslationLanguage.tagalog),
    };
    try {
      row['output'] = rawInput
          ? await LocalTranslationService.channel.invokeMethod<String>(
              'translate',
              {'text': input, 'source': 'tgl_Latn', 'target': 'ceb_Latn'},
            )
          : await service.translate(
              input,
              TranslationLanguage.tagalog,
              TranslationLanguage.cebuano,
            );
    } catch (error) {
      row['error'] = '$error';
    }
    row['elapsed_ms'] = timer.elapsedMilliseconds;
    rows.add(row);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Actual Android inference; not a human-reviewed quality score',
        'raw_input': rawInput,
        'complete': rows.length == 5,
        'results': rows,
      }),
    );
  }
  await service.cancel();
}
