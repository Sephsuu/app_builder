import 'package:flutter/services.dart';
import '../domain/translation.dart';

class LocalTranslationService implements TranslationService {
  static const channel = MethodChannel('sulti/offline_translation');
  static const downloads = EventChannel('sulti/model_download');
  Stream<double> get downloadProgress => downloads.receiveBroadcastStream().map(
    (event) => (event as num).toDouble(),
  );

  Future<bool> isInstalled() async =>
      await channel.invokeMethod<bool>('isInstalled') ?? false;
  Future<void> install() => channel.invokeMethod<void>('install');

  @override
  Future<String> translate(
    String text,
    TranslationLanguage source,
    TranslationLanguage target,
  ) async {
    if (source == target) {
      throw ArgumentError('Select two different languages.');
    }
    if (text.trim().isEmpty) throw ArgumentError('Enter text to translate.');
    try {
      return await channel.invokeMethod<String>('translate', {
            'text': text,
            'source': source.modelCode,
            'target': target.modelCode,
          }) ??
          '';
    } on PlatformException catch (error) {
      throw TranslationFailure(
        error.message ?? 'Offline translation failed. Please retry.',
      );
    } on MissingPluginException {
      throw const TranslationFailure(
        'Offline translation currently requires Android.',
      );
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Other platform templates can still display and edit text.
    }
  }
}

class TranslationFailure implements Exception {
  const TranslationFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class DeviceSpeechOutput implements SpeechOutput {
  static const _channel = MethodChannel('sulti/offline_voice');
  @override
  Future<bool> supports(TranslationLanguage language) async =>
      await _channel.invokeMethod<bool>('supports', language.voiceCode) ??
      false;
  @override
  Future<void> speak(String text, TranslationLanguage language) =>
      _channel.invokeMethod<void>('speak', {
        'text': text,
        'language': language.voiceCode,
      });
  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // No playback exists on platforms without this Android implementation.
    }
  }
}
