import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class OnboardingScreen2 extends StatelessWidget {
  const OnboardingScreen2({super.key});

  @override
  Widget build(BuildContext context) {
    final features = [
      {'icon': Icons.trending_up_outlined, 'title': 'Goal-Oriented Tasks', 'desc': 'Link every task and sprint to high-level Company KPIs.'},
      {'icon': Icons.calendar_today_outlined, 'title': 'Sprint Planning', 'desc': 'Organize work into focused sprints with clear deliverables.'},
      {'icon': Icons.lightbulb_outlined, 'title': 'Ideas Portal', 'desc': 'Capture innovation from your frontline team.'},
      {'icon': Icons.access_time_outlined, 'title': 'Activity Logs', 'desc': 'A transparent audit trail of every action.'},
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
                      color: AppColors.successBg,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.people, size: 48, color: AppColors.success),
                  ),
                  const SizedBox(height: 8),
                  const Text('Metricorex', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary)),
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
                                Text(f['title'] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                Text(f['desc'] as String, style: const TextStyle(fontSize: 14, color: Colors.grey)),
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
                  _Dot(isActive: true),
                  SizedBox(width: 8),
                  _Dot(isActive: false),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/onboarding3'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Next', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
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
