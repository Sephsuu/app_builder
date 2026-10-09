enum TranslationLanguage {
  tagalog('Tagalog', 'tgl_Latn', 'tl'),
  cebuano('Bisaya', 'ceb_Latn', 'ceb');

  const TranslationLanguage(this.label, this.modelCode, this.voiceCode);
  final String label;
  final String modelCode;
  final String voiceCode;
  TranslationLanguage get other => this == tagalog ? cebuano : tagalog;
}

abstract interface class TranslationService {
  Future<String> translate(
    String text,
    TranslationLanguage source,
    TranslationLanguage target,
  );

  /// Cancels inference and waits for native resources to be released.
  Future<void> cancel();
}

abstract interface class SpeechOutput {
  Future<bool> supports(TranslationLanguage language);

  /// Resolves on completion (or stop), not when the utterance is merely queued.
  Future<void> speak(String text, TranslationLanguage language);
  Future<void> stop();
}

/// A completed turn is immutable; changing speakers never reinterprets it.
class ConversationEntry {
  const ConversationEntry({
    required this.id,
    required this.source,
    required this.target,
    required this.original,
    required this.translated,
    required this.createdAt,
  });
  final int id;
  final TranslationLanguage source;
  final TranslationLanguage target;
  final String original;
  final String translated;
  final DateTime createdAt;
}
