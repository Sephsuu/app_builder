import 'package:flutter/material.dart';
import '../../../theme/salin_theme.dart';

class SalinSteps extends StatelessWidget {
  const SalinSteps({super.key, required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step $current of 3',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(
                height: 10,
                width: double.infinity,
                child: ColoredBox(color: Colors.black),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(3, (index) {
                  final number = index + 1;
                  final filled = number <= current;
                  return Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? Colors.black : Colors.white,
                      border: Border.all(color: Colors.black, width: 3),
                    ),
                    child: Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: filled ? Colors.white : Colors.black,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SalinLanguageHeading extends StatelessWidget {
  const SalinLanguageHeading({super.key, required this.language});
  final String language;

  @override
  Widget build(BuildContext context) {
    if (language == 'Tagalog') {
      // The original 433×240 PNG has artwork at (38,70)–(396,200).
      // Clip transparent padding in layout, keeping the PNG bytes intact.
      return Semantics(
        header: true,
        label: language,
        child: ExcludeSemantics(
          child: SizedBox(
            width: 142,
            height: 52,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: 172,
                maxHeight: 96,
                child: Transform.translate(
                  offset: const Offset(-15, -28),
                  child: Image.asset(
                    'assets/tagalogHeader.png',
                    width: 172,
                    height: 96,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      header: true,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          language,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
      ),
    );
  }
}

/// Decorative reference waveform, not a microphone-level measurement.
class SalinWaveform extends StatelessWidget {
  const SalinWaveform({super.key});
  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      height: 106,
      width: double.infinity,
      child: CustomPaint(painter: _WaveformPainter()),
    ),
  );
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter();
  @override
  void paint(Canvas canvas, Size size) {
    const points = <Offset>[
      Offset(0, .57),
      Offset(.05, .55),
      Offset(.10, .23),
      Offset(.15, .85),
      Offset(.19, .26),
      Offset(.23, .56),
      Offset(.27, .49),
      Offset(.34, .05),
      Offset(.41, .87),
      Offset(.46, .40),
      Offset(.49, .53),
      Offset(.55, .45),
      Offset(.63, 0),
      Offset(.74, .83),
      Offset(.78, .19),
      Offset(.84, .80),
      Offset(.89, .53),
      Offset(1, .55),
      Offset(1, .61),
      Offset(.89, .65),
      Offset(.84, .98),
      Offset(.78, .69),
      Offset(.74, .97),
      Offset(.63, .28),
      Offset(.55, 1),
      Offset(.49, .61),
      Offset(.46, .91),
      Offset(.41, .30),
      Offset(.34, 1),
      Offset(.27, .68),
      Offset(.23, .96),
      Offset(.19, .64),
      Offset(.15, .97),
      Offset(.10, .65),
      Offset(0, .64),
    ];
    final path = Path()..moveTo(0, size.height * .57);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = SalinTheme.yellow
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) => false;
}
