import 'package:shared_preferences/shared_preferences.dart';

abstract interface class OnboardingStore {
  Future<bool> isCompleted();
  Future<void> complete();
}

class PreferencesOnboardingStore implements OnboardingStore {
  PreferencesOnboardingStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  static const completionKey = 'salin.onboarding.completed.v1';

  @override
  Future<bool> isCompleted() async =>
      await _preferences.getBool(completionKey) ?? false;
  @override
  Future<void> complete() => _preferences.setBool(completionKey, true);
}
