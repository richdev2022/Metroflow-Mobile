import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

/// Branded splash: indigo → violet gradient, animated logo (scale + fade
/// with easeOutBack), a letter-spacing wordmark reveal, the product tagline
/// and a soft loading indicator.
///
/// The auth-check + navigation logic below is intentionally untouched — it
/// waits for authProvider to leave its loading state (min 800ms so the brand
/// animation plays), then routes to /main, /login or /onboarding1.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _hasNavigated = false;
  late final AnimationController _introController;

  // Logo: scale 0.6 -> 1.0 with a playful overshoot + fade in.
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  // Wordmark: letter-spacing tightens as it fades in.
  late final Animation<double> _wordmarkOpacity;
  late final Animation<double> _letterSpacing;

  // Tagline + loader arrive last.
  late final Animation<double> _taglineOpacity;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    Future.microtask(_navigateToNext);

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );

    final curved = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutBack,
    );

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(curved);
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _wordmarkOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.25, 0.62, curve: Curves.easeOut),
      ),
    );
    _letterSpacing = Tween<double>(begin: 9.0, end: 2.5).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.25, 0.80, curve: Curves.easeOutCubic),
      ),
    );

    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.5, 0.85, curve: Curves.easeOut),
      ),
    );

    // Soft repeating pulse for the loading dots.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    _introController.forward();
  }

  @override
  void dispose() {
    _introController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _navigateToNext() async {
    final startedAt = DateTime.now();
    while (mounted && ref.read(authProvider).isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final elapsed = DateTime.now().difference(startedAt);
    final remainingSplashTime = const Duration(milliseconds: 800) - elapsed;
    if (remainingSplashTime > Duration.zero) {
      await Future.delayed(remainingSplashTime);
    }

    if (!mounted) return;
    if (_hasNavigated) return;
    _hasNavigated = true;

    final authState = ref.read(authProvider);

    if (authState.isAuthenticated) {
      // The router redirect will handle KYC check
      context.go('/main');
    } else if (authState.hasSeenOnboarding) {
      context.go('/login');
    } else {
      context.go('/onboarding1');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF2563EB), // indigo primary
              Color(0xFF4F46E5),
              Color(0xFF7C3AED), // violet
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Decorative soft circles.
            Positioned(
              right: -70,
              top: -70,
              child: _SoftCircle(size: 220, alpha: 0.10),
            ),
            Positioned(
              left: -60,
              bottom: 90,
              child: _SoftCircle(size: 180, alpha: 0.08),
            ),
            Positioned(
              right: 40,
              bottom: -50,
              child: _SoftCircle(size: 140, alpha: 0.07),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated logo — the SQUARE white shield mark. The wide
                  // wordmark (Logo-white.png, 1024x273) is NOT usable here:
                  // BoxFit.cover inside a square crops it to a blank sliver.
                  FadeTransition(
                    opacity: _logoOpacity,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        width: 122,
                        height: 122,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          color: Colors.white.withValues(alpha: 0.10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.28),
                              blurRadius: 34,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Image.asset(
                            'assets/images/logo-mark-white.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  // Wordmark with animated letter spacing.
                  FadeTransition(
                    opacity: _wordmarkOpacity,
                    child: AnimatedBuilder(
                      animation: _letterSpacing,
                      builder: (context, child) {
                        return Text(
                          'METRICOREX',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: _letterSpacing.value,
                            height: 1.1,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Tagline.
                  FadeTransition(
                    opacity: _taglineOpacity,
                    child: Text(
                      'Run your entire business in one place',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ),
                  const SizedBox(height: 56),
                  // Loading dots.
                  FadeTransition(
                    opacity: _taglineOpacity,
                    child: _PulsingDots(controller: _pulseController),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftCircle extends StatelessWidget {
  final double size;
  final double alpha;

  const _SoftCircle({required this.size, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }
}

/// Three dots fading in sequence — a lightweight branded loader.
class _PulsingDots extends StatelessWidget {
  final AnimationController controller;

  const _PulsingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final offset = (controller.value * 2 - index * 0.35).clamp(0.0, 1.0);
            final opacity = 0.25 + 0.65 * (1.0 - (offset - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
