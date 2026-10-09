import '../../translation/data/translation_input.dart';
import '../../translation/domain/translation.dart';

class TranscriptChange {
  const TranscriptChange(this.before, this.after, this.reason);
  final String before, after, reason;
}

/// Lightweight offline cleanup, not a grammar model or an ASR confidence score.
/// Only formatting is automatic. Word replacements always require review.
class TagalogTranscriptReview {
  TagalogTranscriptReview._(
    this.raw,
    this.cleaned,
    this.suggested,
    this.formatting,
    this.suggestions,
  );
  final String raw, cleaned, suggested;
  final List<TranscriptChange> formatting, suggestions;

  static const _spellings = {
    'puponta': 'pupunta',
    'mamya': 'mamaya',
    'salmat': 'salamat',
    'kaialngan': 'kailangan',
    'kelangan': 'kailangan',
    'kamusta': 'kumusta',
  };

  factory TagalogTranscriptReview.analyze(String raw) {
    final formatting = <TranscriptChange>[];
    var cleaned = raw.trim().replaceAll(RegExp(r'[\t ]+'), ' ');
    if (cleaned != raw) {
      formatting.add(TranscriptChange(raw, cleaned, 'Spacing'));
    }
    final cased = prepareTranslationInput(cleaned, TranslationLanguage.tagalog);
    if (cased != cleaned) {
      formatting.add(
        TranscriptChange(cleaned, cased, 'Sentence capitalization'),
      );
    }
    cleaned = cased;
    final suggestions = <TranscriptChange>[];
    // Limit matching to whole alphabetic words. Preserve mixed-case identifiers,
    // names, numbers, hyphenated words and apostrophe forms. Nothing is removed.
    final suggested = cleaned.replaceAllMapped(
      RegExp(r"(?<![\w'’-])[A-Za-z]+(?![\w'’-])"),
      (match) {
        final word = match.group(0)!;
        final lower = word.toLowerCase();
        final replacement = _spellings[lower];
        if (replacement == null || (word != lower && match.start != 0)) {
          return word;
        }
        if (word != lower &&
            word != '${word[0]}${word.substring(1).toLowerCase()}') {
          return word;
        }
        final corrected = word == lower
            ? replacement
            : '${replacement[0].toUpperCase()}${replacement.substring(1)}';
        suggestions.add(
          TranscriptChange(
            word,
            corrected,
            'Possible spelling — confirm the intended word',
          ),
        );
        return corrected;
      },
    );
    return TagalogTranscriptReview._(
      raw,
      cleaned,
      suggested,
      List.unmodifiable(formatting),
      List.unmodifiable(suggestions),
    );
  }
}
