import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

/// Revamped onboarding: a tight 5-slide flow with real imagery that
/// summarizes the whole business platform.
///
/// 1. All your work in one place — tasks, projects, team
/// 2. Meet, call & chat — video meetings, calls, team chat
/// 3. Payroll & money moves — salaries, transfers, wallet & virtual accounts
/// 4. Get paid, every way — payment links, smart invoices, storefront,
///    recurring billing
/// 5. Smarter. Safer. — MetricAi copilot, credit packs, KYC/OTP/PIN security
///
/// Real photos (from the website's brand library) sit inside layered 3D
/// cards; every slide gradient stays inside the indigo→violet brand family.
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
  // BUGFIX: was hardcoded to 7 while _slides holds only 5 entries — swiping
  // past slide 5 threw RangeError inside PageView.builder -> grey/blank page
  // (users could only escape via Skip). Derive from the list instead.
  static const int _pageCount = _slides.length;

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
                  // Square shield mark — the wide wordmark gets cropped to a
                  // sliver by BoxFit.cover inside a 28x28 square.
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: Image.asset(
                      'assets/images/logo-mark.png',
                      width: 26,
                      height: 26,
                      fit: BoxFit.contain,
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
  /// Real brand photography (site poster library) shown in the 3D card.
  final String? photo;

  const _SlideData({
    required this.icon,
    required this.gradient,
    required this.miniIcons,
    required this.title,
    required this.subtitle,
    required this.bullets,
    this.photo,
  });
}

// Gradients stay inside the Metricorex indigo→violet family so the whole
// flow reads as one brand (the old cyan/pink/green mix felt off-brand).
const List<_SlideData> _slides = [
  _SlideData(
    icon: Icons.grid_view_rounded,
    gradient: [Color(0xFF2563EB), Color(0xFF4F46E5)],
    miniIcons: [Icons.checklist_rounded, Icons.folder_shared_rounded, Icons.groups_rounded],
    photo: 'assets/images/onboarding/work.jpg',
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
    gradient: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
    miniIcons: [Icons.videocam_rounded, Icons.call_rounded, Icons.chat_rounded],
    photo: 'assets/images/onboarding/meet.jpg',
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
    gradient: [Color(0xFF7C3AED), Color(0xFF2563EB)],
    miniIcons: [Icons.payments_rounded, Icons.swap_horiz_rounded, Icons.account_balance_rounded],
    photo: 'assets/images/onboarding/money.jpg',
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
    icon: Icons.storefront_rounded,
    gradient: [Color(0xFF0EA5E9), Color(0xFF4F46E5)],
    miniIcons: [Icons.link_rounded, Icons.receipt_long_rounded, Icons.autorenew_rounded],
    photo: 'assets/images/onboarding/growth.jpg',
    title: 'Get paid, every way',
    subtitle:
        'Payment links, smart invoices, your own storefront and recurring billing — money lands in your wallet the moment clients pay.',
    bullets: [
      (Icons.link_rounded, 'Payment links & smart invoices'),
      (Icons.storefront_rounded, 'Your own storefront'),
      (Icons.autorenew_rounded, 'Recurring billing on autopilot'),
    ],
  ),
  _SlideData(
    icon: Icons.auto_awesome_rounded,
    gradient: [Color(0xFF4F46E5), Color(0xFF2563EB)],
    miniIcons: [Icons.chat_bubble_rounded, Icons.verified_user_rounded, Icons.bolt_rounded],
    photo: 'assets/images/onboarding/ai.jpg',
    title: 'Smarter. Safer.',
    subtitle:
        'MetricAi drafts ideas, summarises meetings into action items and answers your questions — while KYC, OTP and PIN protection keep every kobo safe.',
    bullets: [
      (Icons.summarize_rounded, 'AI meeting notes & insights'),
      (Icons.bolt_rounded, 'MetricAi credit packs'),
      (Icons.verified_user_rounded, 'KYC, OTP & PIN protection'),
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

/// Layered 3D photo card: real brand photography inside a rounded frame with
/// a gradient wash, floating glass chips on top for depth, and a soft
/// two-layer shadow that lifts the whole card off the background.
class _IllustrationBlock extends StatelessWidget {
  final _SlideData page;

  const _IllustrationBlock({required this.page});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 216,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Back glow plate (3D depth).
          Positioned(
            left: 26,
            right: 26,
            top: 34,
            bottom: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                gradient: LinearGradient(
                  colors: [
                    page.gradient.first.withValues(alpha: 0.22),
                    page.gradient.last.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Main photo card.
          Container(
            width: 260,
            height: 184,
            margin: const EdgeInsets.only(left: 20, right: 20, top: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                colors: page.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: page.gradient.last.withValues(alpha: 0.38),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (page.photo != null)
                    Image.asset(
                      page.photo!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        page.icon,
                        size: 72,
                        color: Colors.white,
                      ),
                    )
                  else
                    Icon(page.icon, size: 72, color: Colors.white),
                  // Brand gradient wash keeps photos consistent + readable.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          page.gradient.first.withValues(alpha: 0.25),
                          Colors.transparent,
                          page.gradient.last.withValues(alpha: 0.45),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                  // Slide icon badge in the corner.
                  Positioned(
                    right: 14,
                    top: 14,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(page.icon, size: 22, color: page.gradient.first),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Floating glass chips (depth + dynamic feel).
          _MiniChip(
            icon: page.miniIcons[0],
            colors: page.gradient,
            right: 0,
            top: 6,
          ),
          _MiniChip(
            icon: page.miniIcons[1],
            colors: page.gradient,
            left: 0,
            top: 88,
          ),
          _MiniChip(
            icon: page.miniIcons[2],
            colors: page.gradient,
            right: 22,
            bottom: -6,
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
