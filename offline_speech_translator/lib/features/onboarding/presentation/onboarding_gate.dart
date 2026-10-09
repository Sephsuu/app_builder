import 'package:flutter/material.dart';
import '../data/onboarding_store.dart';
import '../../speech/presentation/speech_home_screen.dart';
import 'onboarding_screen.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, this.store, this.translatorBuilder});
  final OnboardingStore? store;
  final WidgetBuilder? translatorBuilder;
  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late final _store = widget.store ?? PreferencesOnboardingStore();
  bool? _completed;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final completed = await _store.isCompleted();
      if (mounted) setState(() => _completed = completed);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not read your welcome preferences.');
      }
    }
  }

  Future<void> _complete() async {
    await _store.complete();
    if (mounted) setState(() => _completed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_completed == true) {
      return widget.translatorBuilder?.call(context) ??
          const SpeechHomeScreen();
    }
    if (_completed == false) return OnboardingScreen(onComplete: _complete);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _error == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Salin',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 20),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Opening Salin',
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
        ),
      ),
    );
  }
}
