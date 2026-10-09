import 'package:flutter/material.dart';
import '../../../theme/salin_theme.dart';
import '../../translation/domain/translation.dart';

class LanguageSelection extends StatelessWidget {
  const LanguageSelection({
    super.key,
    required this.source,
    required this.enabled,
    required this.onSource,
    required this.onTarget,
    required this.onSwap,
  });
  final TranslationLanguage source;
  final bool enabled;
  final ValueChanged<TranslationLanguage> onSource;
  final ValueChanged<TranslationLanguage> onTarget;
  final VoidCallback onSwap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: _selector('From', source, onSource)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: IconButton(
          tooltip: 'Swap languages and clear text',
          onPressed: enabled ? onSwap : null,
          icon: const Icon(Icons.swap_horiz_rounded),
        ),
      ),
      Expanded(child: _selector('To', source.other, onTarget)),
    ],
  );

  Widget _selector(
    String label,
    TranslationLanguage value,
    ValueChanged<TranslationLanguage> onChanged,
  ) {
    return DropdownButtonFormField<TranslationLanguage>(
      key: ValueKey('$label:${value.name}'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      items: TranslationLanguage.values
          .map(
            (language) => DropdownMenuItem(
              value: language,
              child: Text(language.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: enabled
          ? (language) {
              if (language != null) onChanged(language);
            }
          : null,
    );
  }
}

class MicrophoneButton extends StatelessWidget {
  const MicrophoneButton({
    super.key,
    required this.enabled,
    required this.onPressed,
  });
  final bool enabled;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 92,
    height: 92,
    child: IconButton.filled(
      tooltip: 'Start recording',
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(
        backgroundColor: SalinTheme.yellow,
        foregroundColor: Colors.black,
        disabledBackgroundColor: const Color(0xFFE8E8E8),
        disabledForegroundColor: SalinTheme.muted,
      ),
      icon: const Icon(Icons.mic_none_rounded, size: 44),
    ),
  );
}

class AudioWaveform extends StatelessWidget {
  const AudioWaveform({super.key, required this.levels});
  final List<double> levels;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Microphone audio level',
    child: ExcludeSemantics(
      child: SizedBox(
        height: 64,
        width: double.infinity,
        child: TweenAnimationBuilder<List<double>>(
          tween: _LevelsTween(
            begin: List.filled(levels.length, 0),
            end: levels,
          ),
          duration: const Duration(milliseconds: 90),
          builder: (context, values, child) =>
              CustomPaint(painter: AudioWaveformPainter(values)),
        ),
      ),
    ),
  );
}

class _LevelsTween extends Tween<List<double>> {
  _LevelsTween({required super.begin, required super.end});
  @override
  List<double> lerp(double t) => List.generate(
    end!.length,
    (i) => (i < begin!.length ? begin![i] : 0) * (1 - t) + end![i] * t,
  );
}

class AudioWaveformPainter extends CustomPainter {
  const AudioWaveformPainter(this.levels);
  final List<double> levels;
  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final spacing = size.width / levels.length;
    final paint = Paint()..color = SalinTheme.ink;
    for (var i = 0; i < levels.length; i++) {
      final height = 2 + levels[i].clamp(0.0, 1.0) * (size.height - 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset((i + .5) * spacing, size.height / 2),
            width: spacing * .45,
            height: height,
          ),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(AudioWaveformPainter oldDelegate) =>
      oldDelegate.levels != levels;
}

class ProcessingIndicator extends StatelessWidget {
  const ProcessingIndicator({
    super.key,
    required this.label,
    this.processing = false,
    this.progress,
  });
  final String label;
  final bool processing;
  final double? progress;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        if (processing) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(value: progress, strokeWidth: 2),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: SalinTheme.muted,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class TranslationTextPanel extends StatelessWidget {
  const TranslationTextPanel({
    super.key,
    required this.title,
    required this.text,
    required this.placeholder,
    this.accent = false,
    this.actions = const [],
    this.child,
  });
  final String title;
  final String text;
  final String placeholder;
  final bool accent;
  final List<Widget> actions;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: accent ? const Color(0xFFFFF7DD) : const Color(0xFFF5F5F2),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: SalinTheme.muted),
        ),
        const SizedBox(height: 12),
        if (child != null)
          child!
        else if (text.isNotEmpty)
          SelectableText(
            text,
            key: PageStorageKey('panel:$title'),
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          )
        else
          Text(
            placeholder,
            style: const TextStyle(
              fontSize: 17,
              color: SalinTheme.muted,
              height: 1.45,
            ),
          ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ],
    ),
  );
}

class ConversationHistoryItem extends StatelessWidget {
  const ConversationHistoryItem({
    super.key,
    required this.entry,
    this.onPlay,
    this.onCopy,
    this.playing = false,
  });
  final ConversationEntry entry;
  final VoidCallback? onPlay;
  final VoidCallback? onCopy;
  final bool playing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${entry.source.label} → ${entry.target.label}',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: SalinTheme.muted),
              ),
            ),
            IconButton(
              tooltip: playing
                  ? 'Stop history playback'
                  : 'Play previous translation',
              onPressed: onPlay,
              icon: Icon(
                playing ? Icons.stop_rounded : Icons.volume_up_outlined,
              ),
            ),
            IconButton(
              tooltip: 'Copy previous translation',
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 20),
            ),
          ],
        ),
        Text(
          entry.original,
          style: const TextStyle(
            fontSize: 15,
            color: SalinTheme.muted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          entry.translated,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1, color: Color(0xFFE7E7E2)),
      ],
    ),
  );
}
