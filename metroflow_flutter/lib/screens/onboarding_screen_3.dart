import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class OnboardingScreen3 extends ConsumerWidget {
  const OnboardingScreen3({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final features = [
      {'icon': Icons.payments_outlined, 'title': 'One-Click Payroll', 'desc': 'Run payroll for your entire team in seconds.'},
      {'icon': Icons.credit_card_outlined, 'title': 'Multi-Currency Support', 'desc': 'Pay employees in NGN or USD.'},
      {'icon': Icons.emoji_events_outlined, 'title': 'Performance Bonuses', 'desc': 'Reward high performers instantly.'},
      {'icon': Icons.notifications_outlined, 'title': 'Automated Notifications', 'desc': 'Instant email alerts for payments.'},
      {'icon': Icons.account_balance_wallet_outlined, 'title': 'Business Wallets', 'desc': 'Get a dedicated NUBAN account for your business.'},
      {'icon': Icons.shield_outlined, 'title': 'Bank-Grade Security', 'desc': '2FA (OTP via Email/SMS) for all transactions.'},
    ];

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.account_balance_wallet, size: 48, color: AppColors.warning),
                  ),
                  const SizedBox(height: 8),
                  const Text('Metroflow', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  const SizedBox(height: 16),
                  const Text('Automated HR & Payroll', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  const Text('Everything You Need to Run Your Business', style: TextStyle(fontSize: 15, color: AppColors.primary, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  ...features.map((f) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.colors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.colors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(f['icon'] as IconData?, size: 20, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f['title'] as String, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                Text(f['desc'] as String, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Dot(isActive: false),
                  SizedBox(width: 8),
                  _Dot(isActive: false),
                  SizedBox(width: 8),
                  _Dot(isActive: true),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await ref.read(authProvider.notifier).completeOnboarding();
                    if (context.mounted) context.go('/login');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Get Started', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? ", style: TextStyle(fontSize: 14, color: Colors.grey)),
                  GestureDetector(
                    onTap: () async {
                      await ref.read(authProvider.notifier).completeOnboarding();
                      if (context.mounted) context.go('/register');
                    },
                    child: const Text('Sign Up', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool isActive;
  const _Dot({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary : AppTheme.colors.border,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
