import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme/salin_theme.dart';

class SalinLandingScreen extends StatelessWidget {
  const SalinLandingScreen({super.key, required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SalinTheme.yellow,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.min(constraints.maxWidth, 440.0);
            // Short and landscape displays scroll without shrinking tap targets.
            final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final height = math.max(
              constraints.maxHeight,
              620.0 + (textScale - 1).clamp(0, 3) * 140,
            );
            final artworkHeight = math.min(height * .27, width * .64);
            return SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Column(
                    children: [
                      const Spacer(flex: 3),
                      Image.asset(
                        'assets/LANDPAGElogo.png',
                        width: width * .83,
                        height: width * .83 * 275 / 393,
                        fit: BoxFit.contain,
                        semanticLabel: 'Salin',
                      ),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Bawat wika, iisang diwa',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.5,
                              ),
                        ),
                      ),
                      const Spacer(flex: 3),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: onStart,
                            child: const Text('Start'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        height: artworkHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: SvgPicture.asset(
                                  'assets/AFRO.svg',
                                  height: artworkHeight,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.bottomLeft,
                                  excludeFromSemantics: true,
                                ),
                              ),
                              const SizedBox(width: 22),
                              Expanded(
                                child: SvgPicture.asset(
                                  'assets/BABAE.svg',
                                  height: artworkHeight,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.bottomRight,
                                  excludeFromSemantics: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
