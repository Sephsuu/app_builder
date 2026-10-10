import 'package:flutter/services.dart';

class OnlineTranslationSettings {
  static const channel = MethodChannel('sulti/online_translation_settings');
  Future<bool> configured() async =>
      await channel.invokeMethod<bool>('configured') ?? false;
  Future<bool> isOnline() async =>
      await channel.invokeMethod<bool>('isOnline') ?? false;
  Future<String?> readKey() => channel.invokeMethod<String>('readKey');
  Future<void> saveKey(String key) =>
      channel.invokeMethod<void>('saveKey', key.trim());
  Future<void> removeKey() => channel.invokeMethod<void>('removeKey');
}
