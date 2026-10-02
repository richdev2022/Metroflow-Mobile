import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';

/// A step in the guided app tour.
///
/// Steps with an [anchorKey] spotlight that widget (dim everything else and
/// punch a rounded hole around it). Steps without an anchor render as a
/// centred card — useful for conceptual intros that have no single widget to
/// point at.
class TourStep {
  const TourStep({
    this.anchorKey,
    required this.icon,
    required this.title,
    required this.body,
    this.radius = 16,
  });

  final GlobalKey? anchorKey;
  final IconData icon;
  final String title;
  final String body;
  final double radius;
}

/// Show the guided tour as a transparent full-screen route.
///
/// Persists completion to StorageService and pops itself when finished or
/// skipped. Safe to call unconditionally — [maybeShow] only shows it the
/// first time.
Future<void> showAppTour(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => AppTourOverlay(steps: buildDefaultTourSteps()),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
    ),
  );
}

/// Shows the tour only when it has never been completed on this device.
Future<void> maybeShowAppTour(BuildContext context) async {
  try {
    final seen = await StorageService().getHasSeenAppTour();
    if (seen) return;
    if (!context.mounted) return;
    await showAppTour(context);
  } catch (_) {
    // Never block the app because of the tour.
  }
}

/// Registry of named widget anchors the tour can spotlight. Screens register
/// their GlobalKeys in initState; the tour resolves them at show time, so a
/// missing/hidden anchor gracefully degrades to a centred card.
class AppTourAnchors {
  static final Map<String, GlobalKey> _keys = {};

  static void register(String name, GlobalKey key) => _keys[name] = key;
  static GlobalKey? get(String name) => _keys[name];
}

/// The default tour script — anchored steps highlight real dashboard regions;
/// centred steps introduce cross-cutting features.
List<TourStep> buildDefaultTourSteps() => [
      const TourStep(
        icon: Icons.waving_hand_rounded,
        title: 'Welcome to Metricorex \u{1F44B}',
        body:
            "Quick tour \u{2014} 60 seconds, promise. We'll point out the important bits so you can find everything fast. Skip any time.",
      ),
      TourStep(
        anchorKey: AppTourAnchors.get('dashboard-hero'),
        icon: Icons.space_dashboard_rounded,
        title: 'Your dashboard',
        body:
            'This is mission control \u{2014} your greeting, mini stats and everything that needs your attention today.',
      ),
      TourStep(
        anchorKey: AppTourAnchors.get('dashboard-quick-actions'),
        icon: Icons.bolt_rounded,
        title: 'Quick actions',
        body:
            'Create tasks, start meetings, raise invoices, share payment links and add products \u{2014} work and money, one tap away.',
      ),
      TourStep(
        anchorKey: AppTourAnchors.get('dashboard-tasks'),
        icon: Icons.checklist_rounded,
        title: 'My tasks',
        body:
            'Your open tasks live here. Tap one to see details, chat on it, or mark it done. Everything your team assigned you shows up automatically.',
      ),
      const TourStep(
        icon: Icons.menu_rounded,
        title: 'Everything lives in More',
        body:
            'Tap More in the bottom bar (or the \u{2630} menu) for the full toolbox \u{2014} grouped into Work & Team, Money, Get Paid, MetricAi and App so nothing gets lost.',
      ),
      const TourStep(
        icon: Icons.account_balance_wallet_rounded,
        title: 'Wallet & transfers',
        body:
            'Your balance sits right on the home screen. Fund your wallet, manage virtual accounts, send single or bulk transfers and run payroll \u{2014} all under Money.',
      ),
      const TourStep(
        icon: Icons.smart_toy_rounded,
        title: 'Meet MetricAi',
        body:
            'Your built-in AI assistant. Ask questions, analyse images and videos, generate documents and get smart summaries \u{2014} find it in the menu.',
      ),
      const TourStep(
        icon: Icons.celebration_rounded,
        title: "You're all set! \u{1F389}",
        body:
            "That's the tour. Tap around \u{2014} everything is built to be obvious. Need it again? Settings \u{2192} Take the app tour.",
      ),
    ];

class AppTourOverlay extends StatefulWidget {
  const AppTourOverlay({super.key, required this.steps});

  final List<TourStep> steps;

  @override
  State<AppTourOverlay> createState() => _AppTourOverlayState();
}

class _AppTourOverlayState extends State<AppTourOverlay> {
  int _index = 0;

  TourStep get _step => widget.steps[_index];
  bool get _isLast => _index == widget.steps.length - 1;

  Rect? _anchorRect() {
    final key = _step.anchorKey;
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    // Off-screen anchors degrade to a centred card.
    if (rect.width <= 0 || rect.height <= 0) return null;
    return rect;
  }

  Future<void> _finish() async {
    try {
      await StorageService().setHasSeenAppTour(true);
    } catch (_) {}
    if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    setState(() => _index += 1);
  }

  void _back() {
    if (_index > 0) setState(() => _index -= 1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final rect = _anchorRect();
    final size = MediaQuery.of(context).size;
    final cardWidth = size.width * 0.86;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dim layer with a punched hole around the anchor (if any).
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(
                rect: rect,
                radius: _step.radius,
                dimColor: colors.surface.withValues(alpha: 0.82),
              ),
            ),
          ),

          // Skip — top right.
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Skip tour',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),

          // Tooltip card — anchored below/above the hole, or centred.
          _buildCard(colors, rect, cardWidth, size),
        ],
      ),
    );
  }

  Widget _buildCard(dynamic colors, Rect? rect, double cardWidth, Size size) {
    const estimatedCardHeight = 250.0;
    final prefersTop = rect != null && (size.height - rect.bottom) < estimatedCardHeight + 24;

    final card = _TourCard(
      step: _step,
      index: _index,
      total: widget.steps.length,
      isLast: _isLast,
      canGoBack: _index > 0,
      onNext: _next,
      onBack: _back,
      onSkip: _finish,
    );

    if (rect == null) {
      return Center(child: SizedBox(width: cardWidth, child: card));
    }

    // Position next to the anchor, clamped to the screen.
    final left = ((rect.left + rect.width / 2) - cardWidth / 2).clamp(12.0, size.width - cardWidth - 12.0);
    final top = prefersTop
        ? (rect.top - estimatedCardHeight - 16).clamp(60.0, size.height - estimatedCardHeight - 24.0)
        : (rect.bottom + 16).clamp(60.0, size.height - estimatedCardHeight - 24.0);

    return Positioned(left: left, top: top, child: SizedBox(width: cardWidth, child: card));
  }
}

/// Dims the whole screen except a rounded hole around [rect].
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.rect, required this.radius, required this.dimColor});

  final Rect? rect;
  final double radius;
  final Color dimColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dimColor;

    if (rect == null) {
      canvas.drawPaint(paint);
      return;
    }

    final hole = RRect.fromRectAndRadius(
      rect!.inflate(10),
      Radius.circular(radius),
    );

    // Punch a transparent hole through the dim layer.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawPaint(paint);
    canvas.drawRRect(hole, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // Glow ring around the spotlight.
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF8B5CF6),
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.dimColor != dimColor || oldDelegate.radius != radius;
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.index,
    required this.total,
    required this.isLast,
    required this.canGoBack,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final TourStep step;
  final int index;
  final int total;
  final bool isLast;
  final bool canGoBack;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [colors.primary, colors.primary.withValues(alpha: 0.7)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(step.icon, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  step.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            step.body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: isDark ? Colors.white.withValues(alpha: 0.82) : Colors.black87,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Progress dots
              Expanded(
                child: Row(
                  children: List.generate(total, (i) {
                    final active = i == index;
                    final passed = i < index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.only(right: 5),
                      height: 6,
                      width: active ? 20 : 6,
                      decoration: BoxDecoration(
                        color: active
                            ? colors.primary
                            : passed
                                ? colors.primary.withValues(alpha: 0.45)
                                : (isDark ? Colors.white24 : Colors.black12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
              if (canGoBack)
                TextButton(
                  onPressed: onBack,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: isDark ? Colors.white70 : Colors.black54,
                  ),
                  child: const Text('Back'),
                ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(isLast ? 'Done' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
