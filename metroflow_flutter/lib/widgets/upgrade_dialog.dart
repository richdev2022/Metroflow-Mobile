import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';

/// Show the plan-upgrade dialog from anywhere (dio interceptor included).
/// Mirrors the web app's UpgradePromptProvider modal.
void showUpgradeDialog({String? feature}) {
  final context = navigatorKey.currentContext;
  if (context == null) return;
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => UpgradeDialog(feature: feature),
  );
}

class UpgradeDialog extends StatelessWidget {
  final String? feature;

  const UpgradeDialog({super.key, this.feature});

  @override
  Widget build(BuildContext context) {
    final title = feature != null && feature!.isNotEmpty
        ? 'Unlock $feature'
        : 'Unlock the full power of MetriCorex';

    const benefits = [
      'Unlimited access to every premium feature',
      'Advanced analytics and reporting tools',
      'Priority support from our team',
      'Cancel or change plans anytime',
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gradient hero
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary,
                      AppColors.primaryDark,
                      Color(0xFF7C3AED),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'MetriCorex',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'PRO FEATURE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.workspace_premium,
                          size: 30, color: Color(0xFFFCD34D)),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "This feature isn't part of your current plan. Upgrade to unlock it instantly.",
                      style: TextStyle(
                        color: Color(0xE6E0E7FF),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),

              // Benefits
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Column(
                  children: benefits
                      .map(
                        (benefit) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                margin: const EdgeInsets.only(top: 1),
                                decoration: const BoxDecoration(
                                  color: AppColors.successBg,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check,
                                    size: 12, color: AppColors.success),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  benefit,
                                  style: const TextStyle(
                                    color: Color(0xFF1E293B),
                                    fontSize: 13.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),

              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, Color(0xFF7C3AED)],
                          ),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            const BoxShadow(
                              color: Color(0x592563EB),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            // Deep-link to the recommended tier: the
                            // subscription screen reads ?plan= and highlights
                            // + scrolls to the matching plan card.
                            GoRouter.of(context).go('/main/subscription?plan=pro');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Upgrade now',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward,
                                  size: 17, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Maybe later',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
