import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_navigateToNext);
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
