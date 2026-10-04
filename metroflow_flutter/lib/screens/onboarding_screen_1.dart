import 'package:flutter/material.dart';
import 'onboarding_screen.dart';

/// Legacy standalone onboarding screen — redesigned flow shim (slide 1).
class OnboardingScreen1 extends StatelessWidget {
  const OnboardingScreen1({super.key});

  @override
  Widget build(BuildContext context) => const OnboardingScreen(initialPage: 0);
}
