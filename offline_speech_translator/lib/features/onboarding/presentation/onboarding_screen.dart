import 'package:flutter/material.dart';
import '../../speech/presentation/conversation_widgets.dart';
import '../../speech/presentation/salin_components.dart';
import '../../speech/presentation/salin_landing_screen.dart';
import '../../translation/domain/translation.dart';
import '../../../theme/salin_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});
  final Future<void> Function() onComplete;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = -1;
  bool _recorded = false;
  bool _translated = false;
  bool _saving = false;
  String? _error;
  TranslationLanguage _source = TranslationLanguage.tagalog;
  String get _original => _source == TranslationLanguage.tagalog
      ? 'Kumain ka na ba?'
      : 'Nakaon ka na?';
  String get _output => _source == TranslationLanguage.tagalog
      ? 'Nakaon ka na?'
      : 'Kumain ka na ba?';

  Future<void> _complete() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onComplete();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save your welcome preferences. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step < 0) {
      return SalinLandingScreen(onStart: () => setState(() => _step = 0));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving) setState(() => _step--);
      },
      child: Scaffold(
        backgroundColor: _step == 1 ? SalinTheme.yellow : Colors.white,
        appBar: AppBar(
          backgroundColor: _step == 1 ? SalinTheme.yellow : Colors.white,
          leading: IconButton(
            tooltip: 'Previous onboarding step',
            onPressed: _saving ? null : () => setState(() => _step--),
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text(
            'A quick introduction',
            style: TextStyle(fontSize: 16),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                children: [
                  const SizedBox(height: 20),
                  SalinSteps(current: _step + 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          [
                            'Record voice',
                            'Choose & translate',
                            'Listen & keep talking',
                          ][_step],
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Interactive example · no microphone recording',
                          style: TextStyle(
                            fontSize: 12,
                            color: SalinTheme.muted,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_step == 0) ...[
                          const Text(
                            'Tap the microphone to reveal a sample. In a conversation, tap it to record, then Stop when you finish speaking.',
                            style: TextStyle(height: 1.6),
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: MicrophoneButton(
                              enabled: true,
                              onPressed: () => setState(() => _recorded = true),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_recorded)
                            TranslationTextPanel(
                              title: 'Original · ${_source.label}',
                              text: _original,
                              placeholder: '',
                            ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _recorded
                                ? () => setState(() => _step = 1)
                                : null,
                            child: const Text('Continue'),
                          ),
                        ],
                        if (_step == 1) ...[
                          LanguageSelection(
                            source: _source,
                            enabled: true,
                            onSource: (value) => setState(() {
                              _source = value;
                              _translated = false;
                            }),
                            onTarget: (value) => setState(() {
                              _source = value.other;
                              _translated = false;
                            }),
                            onSwap: () => setState(() {
                              _source = _source.other;
                              _translated = false;
                            }),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _original,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Swap languages to switch speakers. The translator will turn finalized speech into the other language on your device.',
                            style: TextStyle(height: 1.6),
                          ),
                          const SizedBox(height: 32),
                          FilledButton(
                            onPressed: () => setState(() => _translated = true),
                            child: const Text('Translate example'),
                          ),
                          if (_translated) ...[
                            const SizedBox(height: 20),
                            TranslationTextPanel(
                              title: 'Translation · ${_source.other.label}',
                              text: _output,
                              placeholder: '',
                              accent: true,
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: () => setState(() => _step = 2),
                              child: const Text('Continue'),
                            ),
                          ],
                        ],
                        if (_step == 2) ...[
                          TranslationTextPanel(
                            title: 'Original · ${_source.label}',
                            text: _original,
                            placeholder: '',
                          ),
                          const SizedBox(height: 12),
                          TranslationTextPanel(
                            title: 'Translation · ${_source.other.label}',
                            text: _output,
                            placeholder: '',
                            accent: true,
                            actions: const [
                              TextButton(
                                onPressed: null,
                                child: Text('Play translation'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'In the translator, playback uses an installed offline voice. Keep talking on one screen; your completed turns stay in conversation history.',
                            style: TextStyle(height: 1.6),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Speech and translation models need a one-time setup. After installation, processing stays on your device.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: SalinTheme.muted,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_error != null) ...[
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          FilledButton(
                            onPressed: _saving ? null : _complete,
                            child: Text(
                              _saving ? 'Saving…' : 'Start Translating',
                            ),
                          ),
                          if (_saving)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: LinearProgressIndicator(),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
