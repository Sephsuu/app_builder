import 'package:flutter/material.dart';
import '../data/online_translation_settings.dart';

class OnlineTranslationCard extends StatefulWidget {
  const OnlineTranslationCard({
    super.key,
    required this.settings,
    required this.configured,
    required this.onChanged,
    this.enabled = true,
  });
  final OnlineTranslationSettings settings;
  final bool configured;
  final VoidCallback onChanged;
  final bool enabled;
  @override
  State<OnlineTranslationCard> createState() => _OnlineTranslationCardState();
}

class _OnlineTranslationCardState extends State<OnlineTranslationCard> {
  final _key = TextEditingController();
  bool _saving = false;
  String? _notice;
  Future<void> _save({bool remove = false}) async {
    if (!remove &&
        (!_key.text.trim().startsWith('sk-') ||
            _key.text.trim().length < 20 ||
            RegExp(r'\s').hasMatch(_key.text.trim()))) {
      setState(() => _notice = 'Enter a valid OpenAI API key.');
      return;
    }
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      if (remove) {
        await widget.settings.removeKey();
      } else {
        await widget.settings.saveKey(_key.text);
      }
      if (!mounted) return;
      _key.clear();
      widget.onChanged();
      setState(
        () => _notice = remove
            ? 'Key removed. Offline translation is active.'
            : 'Key saved. It will be checked on your next translation.',
      );
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'Could not save settings. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OpenAI translation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            widget.configured
                ? 'Automatic: OpenAI online, local model offline.'
                : 'Add your own key to translate with OpenAI when connected.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Enabling this sends finalized or edited text to OpenAI. Audio stays on your device. API usage is billed to your OpenAI account. Install the offline model for fallback.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            enabled: widget.enabled && !_saving,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: widget.configured
                  ? 'Replacement API key'
                  : 'OpenAI API key',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: widget.enabled && !_saving ? () => _save() : null,
                child: const Text('Save key'),
              ),
              if (widget.configured)
                TextButton(
                  onPressed: widget.enabled && !_saving
                      ? () => _save(remove: true)
                      : null,
                  child: const Text('Remove key'),
                ),
            ],
          ),
          if (_notice != null) Text(_notice!),
          const Text(
            'Your key is encrypted on this Android device and excluded from backups.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
