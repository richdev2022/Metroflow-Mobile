import 'package:flutter/material.dart';
import 'onboarding_screen.dart';

/// Legacy standalone onboarding screen — redesigned flow shim (slide 2).
class OnboardingScreen2 extends StatelessWidget {
  const OnboardingScreen2({super.key});

  @override
  Widget build(BuildContext context) => const OnboardingScreen(initialPage: 1);
}
