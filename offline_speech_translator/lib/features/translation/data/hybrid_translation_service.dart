import 'package:flutter/foundation.dart';
import '../domain/translation.dart';
import 'local_translation_service.dart';

class HybridTranslationService implements TranslationService {
  HybridTranslationService({
    required this.offline,
    required this.online,
    required this.isOnline,
    required this.configured,
  });
  final TranslationService offline;
  final TranslationService online;
  final Future<bool> Function() isOnline;
  final Future<bool> Function() configured;
  final status = ValueNotifier<String>('Offline translation');
  int _generation = 0;

  @override
  Future<String> translate(
    String text,
    TranslationLanguage source,
    TranslationLanguage target,
  ) async {
    if (text.trim().isEmpty || text.length > 8000 || source == target) {
      throw ArgumentError(
        'Choose different languages and enter 1–8000 characters.',
      );
    }
    final generation = ++_generation;
    void checkCurrent() {
      if (generation != _generation) {
        throw const TranslationFailure('Translation cancelled.');
      }
    }

    String? fallbackReason;
    bool useOnline = false;
    try {
      useOnline =
          await configured().timeout(const Duration(seconds: 2)) &&
          await isOnline().timeout(const Duration(seconds: 2));
    } catch (_) {
      fallbackReason = 'Online settings unavailable.';
    }
    checkCurrent();
    if (useOnline) {
      status.value = 'Translating with OpenAI…';
      try {
        final result = await online.translate(text, source, target);
        checkCurrent();
        if (result.trim().isEmpty) {
          throw const TranslationFailure('OpenAI returned no translation.');
        }
        status.value = 'Translated with OpenAI';
        return result;
      } catch (error) {
        checkCurrent();
        fallbackReason = error is TranslationFailure
            ? error.message
            : 'OpenAI is unavailable.';
      }
    }
    checkCurrent();
    status.value =
        '${fallbackReason == null ? '' : '$fallbackReason '}Using offline translation…';
    try {
      final result = await offline.translate(text, source, target);
      checkCurrent();
      status.value =
          '${fallbackReason == null ? '' : '$fallbackReason '}Translated offline';
      return result;
    } catch (_) {
      checkCurrent();
      status.value = 'Translation unavailable';
      throw const TranslationFailure(
        'Offline translation could not finish. Check the offline model in settings, or connect to the internet with a working OpenAI key.',
      );
    }
  }

  @override
  Future<void> cancel() async {
    ++_generation;
    await Future.wait([online.cancel(), offline.cancel()]);
  }
}
