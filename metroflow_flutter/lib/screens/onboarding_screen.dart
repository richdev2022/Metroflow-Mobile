import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

/// Revamped onboarding: a single, coherent 4-slide flow.
///
/// 1. All your work in one place — tasks, projects, team
/// 2. Meet, call & chat — video meetings, calls, team chat
/// 3. Payroll & money moves — salaries, transfers, wallet & virtual accounts
/// 4. Built for growing businesses — KYC, security, insights
///
/// "Seen" is persisted exactly like before: `completeOnboarding()` on the
/// auth provider, then route to /login (Skip) or /register (Sign Up).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.initialPage = 0});

  /// Optional starting slide (used by the legacy OnboardingScreen1/2/3
  /// shims so they land on their original slide).
  final int initialPage;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  PageController? _pageController;
  int _currentPage = 0;
  static const int _pageCount = 4;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage.clamp(0, _pageCount - 1);
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    await ref.read(authProvider.notifier).completeOnboarding();
    if (context.mounted) context.go('/login');
  }

  Future<void> _completeAndRegister() async {
    await ref.read(authProvider.notifier).completeOnboarding();
    if (context.mounted) context.go('/register');
  }

  void _next() {
    if (_currentPage < _pageCount - 1) {
      _pageController?.nextPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final isLast = _currentPage == _pageCount - 1;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: small brand mark + Skip.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Metricorex',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _completeOnboarding,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            // Slides.
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pageCount,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  return _SlidePage(
                    page: _slides[index],
                    controller: _pageController!,
                    index: index,
                    active: index == _currentPage,
                  );
                },
              ),
            ),
            // Dots + CTA.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                children: [
                  _DotsIndicator(count: _pageCount, current: _currentPage),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: isLast
                              ? const [Color(0xFF2563EB), Color(0xFF7C3AED)]
                              : const [Color(0xFF2563EB), Color(0xFF3B82F6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.30),
                            offset: const Offset(0, 8),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _next,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 17),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  isLast ? 'Get Started' : 'Next',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  isLast
                                      ? Icons.rocket_launch_rounded
                                      : Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 2,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                      GestureDetector(
                        onTap: _completeAndRegister,
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide model + data
// ---------------------------------------------------------------------------

class _SlideData {
  final IconData icon;
  final List<Color> gradient;
  final List<IconData> miniIcons;
  final String title;
  final String subtitle;
  final List<(IconData, String)> bullets;

  const _SlideData({
    required this.icon,
    required this.gradient,
    required this.miniIcons,
    required this.title,
    required this.subtitle,
    required this.bullets,
  });
}

const List<_SlideData> _slides = [
  _SlideData(
    icon: Icons.grid_view_rounded,
    gradient: [Color(0xFF2563EB), Color(0xFF7C3AED)],
    miniIcons: [Icons.checklist_rounded, Icons.folder_shared_rounded, Icons.groups_rounded],
    title: 'All your work in one place',
    subtitle:
        'Stop juggling five different tools. Organize tasks, projects and your whole team in a single workspace.',
    bullets: [
      (Icons.task_alt_rounded, 'Tasks & projects'),
      (Icons.folder_open_rounded, 'Epics, ideas & backlog'),
      (Icons.groups_rounded, 'One shared team workspace'),
    ],
  ),
  _SlideData(
    icon: Icons.video_chat_rounded,
    gradient: [Color(0xFF0891B2), Color(0xFF2563EB)],
    miniIcons: [Icons.videocam_rounded, Icons.call_rounded, Icons.chat_rounded],
    title: 'Meet, call & chat',
    subtitle:
        'Video meetings, quick calls and team chat — with your work right there in the conversation.',
    bullets: [
      (Icons.videocam_rounded, 'Video meetings & calls'),
      (Icons.chat_rounded, 'Direct & group team chat'),
      (Icons.notifications_active_rounded, 'Never miss a ping'),
    ],
  ),
  _SlideData(
    icon: Icons.account_balance_wallet_rounded,
    gradient: [Color(0xFF7C3AED), Color(0xFFDB2777)],
    miniIcons: [Icons.payments_rounded, Icons.swap_horiz_rounded, Icons.account_balance_rounded],
    title: 'Payroll & money moves',
    subtitle:
        'Run payroll in seconds, send local & international transfers and manage business wallets in one place.',
    bullets: [
      (Icons.payments_rounded, 'One-click salary payouts'),
      (Icons.swap_horiz_rounded, 'Single & bulk transfers'),
      (Icons.account_balance_rounded, 'Wallets & virtual accounts'),
    ],
  ),
  _SlideData(
    icon: Icons.shield_rounded,
    gradient: [Color(0xFF2563EB), Color(0xFF059669)],
    miniIcons: [Icons.verified_user_rounded, Icons.insights_rounded, Icons.lock_rounded],
    title: 'Built for growing businesses',
    subtitle:
        'KYC-verified payments, bank-grade security and insight into how your team performs — ready as you scale.',
    bullets: [
      (Icons.verified_user_rounded, 'KYC & secure transactions'),
      (Icons.insights_rounded, 'Performance insights'),
      (Icons.lock_rounded, 'OTP & PIN protection'),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Slide page (parallax illustration + animated content)
// ---------------------------------------------------------------------------

class _SlidePage extends StatelessWidget {
  final _SlideData page;
  final PageController controller;
  final int index;
  final bool active;

  const _SlidePage({
    required this.page,
    required this.controller,
    required this.index,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      opacity: active ? 1.0 : 0.55,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Parallax illustration block.
            AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                double offset = 0;
                if (controller.hasClients && controller.position.haveDimensions) {
                  offset = (controller.page ?? 0) - index;
                }
                return Transform.translate(
                  offset: Offset(offset * -36, 0),
                  child: Transform.scale(
                    scale: (1 - offset.abs().clamp(0.0, 0.35)).toDouble(),
                    child: child,
                  ),
                );
              },
              child: _IllustrationBlock(page: page),
            ),
            const SizedBox(height: 34),
            // Title + subtitle (slide up when page becomes active).
            AnimatedSlide(
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              offset: active ? Offset.zero : const Offset(0, 0.05),
              child: Column(
                children: [
                  Text(
                    page.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: colors.text,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    page.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Feature bullets.
            ...page.bullets.map((bullet) {
              final (icon, label) = bullet;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                width: 300,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: page.gradient),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 16, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Big gradient tile with the slide icon + floating mini chips.
class _IllustrationBlock extends StatelessWidget {
  final _SlideData page;

  const _IllustrationBlock({required this.page});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 216,
      height: 216,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main gradient tile.
          Container(
            width: 176,
            height: 176,
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(44),
              gradient: LinearGradient(
                colors: page.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: page.gradient.last.withValues(alpha: 0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Icon(page.icon, size: 76, color: Colors.white),
          ),
          // Floating mini chips.
          _MiniChip(
            icon: page.miniIcons[0],
            colors: page.gradient,
            right: 0,
            top: 12,
          ),
          _MiniChip(
            icon: page.miniIcons[1],
            colors: page.gradient,
            left: 0,
            top: 84,
          ),
          _MiniChip(
            icon: page.miniIcons[2],
            colors: page.gradient,
            right: 14,
            bottom: 4,
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final List<Color> colors;
  final double? left;
  final double? right;
  final double? top;
  final double? bottom;

  const _MiniChip({
    required this.icon,
    required this.colors,
    this.left,
    this.right,
    this.top,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.colors;
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: theme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: theme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: colors.first),
      ),
    );
  }
}

/// Animated dots indicator: active dot stretches into a pill.
class _DotsIndicator extends StatelessWidget {
  final int count;
  final int current;

  const _DotsIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: active ? 26 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                  )
                : null,
            color: active ? null : colors.borderVariant,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}
