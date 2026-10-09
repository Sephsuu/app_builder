import '../domain/translation.dart';

// Speech transcripts often start in lowercase. NLLB is sensitive to the casing
// of its first word. Apply sentence casing only to the model input, keeping the
// recognized text, internal capitalization, punctuation and line breaks intact.
// Do not infer question marks, rewrite words, or alter mixed-case names.
String prepareTranslationInput(String text, TranslationLanguage source) {
  if (source != TranslationLanguage.tagalog) return text;
  final firstWord = RegExp(
    r'''^(\s*["'“‘(]*)([a-z]+(?:-[a-z]+)*)(?=\s|[.,?!:;)"”’]|$)''',
  ).firstMatch(text);
  if (firstWord == null) return text;
  final start = firstWord.group(1)!.length;
  return text.replaceRange(start, start + 1, text[start].toUpperCase());
}
