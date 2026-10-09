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
  final List<ConversationEntry> _history = [];
  List<ConversationEntry> get history => List.unmodifiable(_history);
  int? playingEntryId;
  int _generation = 0;
  int _playbackGeneration = 0;
  bool _disposed = false;
  Future<void> _settling = Future.value();

  void _invalidate() {
    ++_generation;
    ++_playbackGeneration;
    translated = '';
    error = null;
    voiceNotice = null;
    translating = false;
    playing = false;
    playingEntryId = null;
    _settling = Future.wait([translator.cancel(), voice.stop()]).then((_) {});
    // Keep asynchronous cancellation failures observed even when no new operation
    // is started. A new recording still awaits the original failing future.
    unawaited(_settling.catchError((Object _) {}));
  }

  void selectSource(TranslationLanguage value) {
    if (recording || value == source) return;
    _invalidate();
    source = value;
    transcript = ''; // Never reinterpret a transcript in the other language.
    notifyListeners();
  }

  Future<int> beginRecording() async {
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
        notifyListeners();
      }
      rethrow;
    }
    return generation;
  }

  void cancelRecording() {
    _invalidate();
    recording = false;
    transcript = '';
    notifyListeners();
  }

  Future<void> acceptFinal(int generation, String text) async {
    if (!_current(generation) || !recording) return;
    recording = false;
    transcript = text.trim();
    notifyListeners();
    if (transcript.isNotEmpty) await translate();
  }

  void edit(String text) {
    if (recording) return;
    _invalidate();
    transcript = text.trim();
    notifyListeners();
  }

  Future<void> translate() async {
    if (_disposed || recording || translating || transcript.isEmpty) return;
    final generation = ++_generation;
    final input = transcript;
    final from = source;
    final to = target;
    translated = '';
    error = null;
    voiceNotice = null;
    translating = true;
    playing = false;
    notifyListeners();
    try {
      await voice.stop();
      await _settling;
      if (!_current(generation)) return;
      final result = await translator.translate(input, from, to);
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
