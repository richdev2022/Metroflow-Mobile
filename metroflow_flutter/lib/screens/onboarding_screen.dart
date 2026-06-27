import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  children: [
                    _OnboardingPage1(),
                    _OnboardingPage2(),
                    _OnboardingPage3(),
                  ],
                ),
              ),
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Dot(isActive: _currentPage == 0),
                      const SizedBox(width: 8),
                      _Dot(isActive: _currentPage == 1),
                      const SizedBox(width: 8),
                      _Dot(isActive: _currentPage == 2),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_currentPage < 2) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          await ref.read(authProvider.notifier).completeOnboarding();
                          if (context.mounted) context.go('/login');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _currentPage < 2 ? AppColors.primaryDark : AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _currentPage < 2 ? 'Next' : 'Get Started',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (_currentPage == 2) const SizedBox(height: 16),
                  if (_currentPage == 2)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account? ",
                            style: TextStyle(fontSize: 14, color: Colors.grey)),
                        GestureDetector(
                          onTap: () async {
                            await ref.read(authProvider.notifier).completeOnboarding();
                            if (context.mounted) context.go('/register');
                          },
                          child: const Text('Sign Up',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                        ),
                      ],
                    ),
                  const SizedBox(height: 24),
                ],
              ),
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

class _OnboardingPage1 extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryBg,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.business_center, size: 48, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          const Text('Metricorex',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 32),
          const Text(
            'Run Your Entire Business on One Platform',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Stop juggling five different tools. Manage your projects, automate your payroll, and handle business banking in a single, unified workspace.',
            style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage2 extends StatelessWidget {
  final features = [
    {
      'icon': Icons.trending_up_outlined,
      'title': 'Goal-Oriented Tasks',
      'desc': 'Link every task and sprint to high-level Company KPIs.'
    },
    {
      'icon': Icons.calendar_today_outlined,
      'title': 'Sprint Planning',
      'desc': 'Organize work into focused sprints with clear deliverables.'
    },
    {
      'icon': Icons.lightbulb_outlined,
      'title': 'Ideas Portal',
      'desc': 'Capture innovation from your frontline team.'
    },
    {
      'icon': Icons.access_time_outlined,
      'title': 'Activity Logs',
      'desc': 'A transparent audit trail of every action.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.people, size: 48, color: AppColors.success),
          ),
          const SizedBox(height: 8),
          const Text('Metricorex',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 16),
          const Text(
            'Intelligent Project Management',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ...features.map((f) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.colors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(f['icon'] as IconData, size: 24, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f['title'] as String,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text(f['desc'] as String,
                            style: const TextStyle(fontSize: 14, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _OnboardingPage3 extends StatelessWidget {
  final features = [
    {
      'icon': Icons.payments_outlined,
      'title': 'One-Click Payroll',
      'desc': 'Run payroll for your entire team in seconds.'
    },
    {
      'icon': Icons.credit_card_outlined,
      'title': 'Multi-Currency Support',
      'desc': 'Pay employees in NGN or USD.'
    },
    {
      'icon': Icons.emoji_events_outlined,
      'title': 'Performance Bonuses',
      'desc': 'Reward high performers instantly.'
    },
    {
      'icon': Icons.notifications_outlined,
      'title': 'Automated Notifications',
      'desc': 'Instant email alerts for payments.'
    },
    {
      'icon': Icons.account_balance_wallet_outlined,
      'title': 'Business Wallets',
      'desc': 'Get a dedicated NUBAN account for your business.'
    },
    {
      'icon': Icons.shield_outlined,
      'title': 'Bank-Grade Security',
      'desc': '2FA (OTP via Email/SMS) for all transactions.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
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
          const Text('Metricorex',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 16),
          const Text('Automated HR & Payroll',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          const Text('Everything You Need to Run Your Business',
              style: TextStyle(fontSize: 15, color: AppColors.primary, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
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
                        Text(f['title'] as String,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(f['desc'] as String,
                            style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
