import 'dart:async';
import 'package:flutter/foundation.dart';
import '../domain/translation.dart';

/// Owns finalized text only. Live ASR hypotheses never enter this controller.
class TranslationController extends ChangeNotifier {
  TranslationController({required this.translator, required this.voice});
  final TranslationService translator;
  final SpeechOutput voice;
  TranslationLanguage source = TranslationLanguage.tagalog;
  TranslationLanguage get target => source.other;
  String transcript = '';
  String translated = '';
  String? error;
  String? voiceNotice;
  bool translating = false;
  bool playing = false;
  bool recording = false;
  bool restoredDraft = false;
  final Map<TranslationLanguage, _Draft> _drafts = {};
  _Draft? _beforeRecording;
  final List<ConversationEntry> _history = [];
  List<ConversationEntry> get history => List.unmodifiable(_history);
  int? playingEntryId;
  int _generation = 0;
  int _playbackGeneration = 0;
  bool _disposed = false;
  Future<void> _settling = Future.value();

  _Draft get _draft => _Draft(transcript, translated, error);

  void _restore(_Draft? draft) {
    transcript = draft?.transcript ?? '';
    translated = draft?.translated ?? '';
    error = draft?.error;
    restoredDraft = transcript.isNotEmpty;
  }

  void _invalidate() {
    ++_generation;
    ++_playbackGeneration;
    translated = '';
    error = null;
    voiceNotice = null;
    translating = false;
    playing = false;
    playingEntryId = null;
    restoredDraft = false;
    _settling = Future.wait([translator.cancel(), voice.stop()]).then((_) {});
    // Keep asynchronous cancellation failures observed even when no new operation
    // is started. A new recording still awaits the original failing future.
    unawaited(_settling.catchError((Object _) {}));
  }

  void selectSource(TranslationLanguage value) {
    if (_disposed || recording || value == source) return;
    _drafts[source] = _draft;
    _invalidate();
    source = value;
    // Each language owns its text. Switching never reinterprets the old input
    // or automatically restarts cancelled translation work.
    _restore(_drafts[value]);
    notifyListeners();
  }

  Future<int> beginRecording() async {
    if (_disposed || recording) {
      throw StateError('Recording is already active.');
    }
    _beforeRecording = _draft;
    _invalidate();
    transcript = '';
    recording = true;
    final generation = _generation;
    notifyListeners();
    try {
      await _settling;
    } catch (_) {
      if (_current(generation)) {
        recording = false;
        _restore(_beforeRecording);
        _beforeRecording = null;
        notifyListeners();
      }
      rethrow;
    }
    return generation;
  }

  void cancelRecording() {
    if (_disposed || !recording) return;
    _invalidate();
    recording = false;
    _restore(_beforeRecording);
    _beforeRecording = null;
    notifyListeners();
  }

  Future<void> acceptFinal(
    int generation,
    String text, {
    bool translateAutomatically = true,
    bool separateLines = false,
  }) async {
    if (!_current(generation) || !recording) return;
    recording = false;
    transcript = text.trim();
    if (transcript.isEmpty) _restore(_beforeRecording);
    _beforeRecording = null;
    notifyListeners();
    if (text.trim().isNotEmpty && translateAutomatically) {
      await translate(separateLines: separateLines);
    }
  }

  /// Explicitly clears only the selected direction; completed history survives.
  void clear() {
    if (_disposed || recording) return;
    _invalidate();
    transcript = '';
    _drafts.remove(source);
    notifyListeners();
  }

  void edit(String text) {
    if (_disposed || recording || text.trim() == transcript) return;
    _invalidate();
    transcript = text.trim();
    notifyListeners();
  }

  Future<void> translate({bool separateLines = false}) async {
    if (_disposed || recording || translating || transcript.isEmpty) return;
    final generation = ++_generation;
    final input = transcript;
    final from = source;
    final to = target;
    ++_playbackGeneration;
    translated = '';
    error = null;
    voiceNotice = null;
    translating = true;
    playing = false;
    playingEntryId = null;
    restoredDraft = false;
    notifyListeners();
    try {
      await voice.stop();
      await _settling;
      if (!_current(generation)) return;
      final String result;
      if (separateLines) {
        if (input.length > 8000) {
          throw ArgumentError(
            'Enter a shorter passage (at most 8000 characters). No text was truncated.',
          );
        }
        final lines = input.split(RegExp(r'\r\n|[\n\r]'));
        final outputs = <String>[];
        for (final line in lines) {
          if (!_current(generation)) return;
          if (line.trim().isEmpty) {
            outputs.add('');
            continue;
          }
          final output = await translator.translate(line.trim(), from, to);
          if (!_current(generation)) return;
          if (output.trim().isEmpty) {
            throw StateError(
              'A line could not be translated. Edit the source and retry.',
            );
          }
          outputs.add(output.trim());
        }
        // Commit only after every line succeeds. A cancelled or failed batch
        // never publishes an incomplete translation or history entry.
        result = outputs.join('\n');
      } else {
        result = await translator.translate(input, from, to);
      }
      if (!_current(generation)) return;
      if (result.trim().isEmpty) {
        throw StateError('No translation was generated.');
      }
      translated = result.trim();
      _history.add(
        ConversationEntry(
          id: _generation,
          source: from,
          target: to,
          original: input,
          translated: translated,
          createdAt: DateTime.now(),
        ),
      );
    } catch (failure) {
      if (_current(generation)) error = '$failure';
    } finally {
      if (_current(generation)) {
        translating = false;
        notifyListeners();
      }
    }
  }

  Future<void> play({ConversationEntry? entry}) async {
    final output = entry?.translated ?? translated;
    final language = entry?.target ?? target;
    if (output.isEmpty || translating || recording || playing || _disposed) {
      return;
    }
    final generation = _generation;
    final playback = ++_playbackGeneration;
    playing = true;
    playingEntryId = entry?.id;
    voiceNotice = null;
    notifyListeners();
    try {
      // A previous direction may still be releasing native playback resources.
      await _settling;
      if (!_current(generation) || playback != _playbackGeneration) return;
      final supported = await voice.supports(language);
      if (!_current(generation) || playback != _playbackGeneration) return;
      if (!supported) {
        voiceNotice =
            'No installed offline ${language.label} voice is available.';
        return;
      }
      await voice.speak(output, language);
    } catch (failure) {
      if (_current(generation) && playback == _playbackGeneration) {
        voiceNotice = 'Playback unavailable: $failure';
      }
    } finally {
      if (_current(generation) && playback == _playbackGeneration) {
        playing = false;
        playingEntryId = null;
        notifyListeners();
      }
    }
  }

  Future<void> stopPlayback() async {
    final playback = ++_playbackGeneration;
    playing = false;
    playingEntryId = null;
    if (!_disposed) notifyListeners();
    try {
      await voice.stop();
    } catch (failure) {
      if (!_disposed && playback == _playbackGeneration) {
        voiceNotice = 'Could not stop playback: $failure';
        notifyListeners();
      }
    }
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _invalidate();
    super.dispose();
  }
}

class _Draft {
  const _Draft(this.transcript, this.translated, this.error);
  final String transcript;
  final String translated;
  final String? error;
}
