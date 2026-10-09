import 'package:flutter/material.dart';

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
