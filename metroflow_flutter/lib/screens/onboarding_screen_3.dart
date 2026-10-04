import 'package:flutter/material.dart';
import 'onboarding_screen.dart';

/// Legacy standalone onboarding screen — redesigned flow shim (slide 3).
class OnboardingScreen3 extends StatelessWidget {
  const OnboardingScreen3({super.key});

  @override
  Widget build(BuildContext context) => const OnboardingScreen(initialPage: 2);
}
