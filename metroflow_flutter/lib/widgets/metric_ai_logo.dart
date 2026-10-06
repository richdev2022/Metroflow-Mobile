import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The MetricAi logo inside a circle with a subtle glow that blends indigo
/// (#4F46E5) and blue (#2563EB). Used for the pinned MetricAi entry in the
/// chat list, the MetricAi screen header and every assistant bubble.
///
/// NOTE: deliberately STATIC. An earlier version pulsed via an
/// AnimationController that repeated forever — and because one instance is
/// mounted in every assistant bubble, a loaded history spawned N+1 infinite
/// 60fps animations that continuously invalidated frames inside the
/// ListView. That constant repaint churn made the chat appear to "scroll
/// loop" on its own. A static glow keeps the exact same look with zero
/// per-frame work.
class MetricAiGlowLogo extends StatelessWidget {
  /// Radius of the logo circle.
  final double radius;

  /// Scales the box-shadow strength (0 = none, 1 = default).
  final double glowStrength;

  const MetricAiGlowLogo({
    super.key,
    this.radius = 24,
    this.glowStrength = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final double size = radius * 2;
    // Static midpoint of the old indigo->blue pulse.
    final glowColor = Color.lerp(const Color(0xFF4F46E5), const Color(0xFF2563EB), 0.5)!;
    final blur = 20.0 * glowStrength;
    final spread = 1.75 * glowStrength;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Theme-aware disc: hardcoded white glared in dark mode (this widget
        // sits in the app bar, the chat-list tile and EVERY assistant bubble).
        // Light keeps the classic white disc; dark uses the surface color.
        color: AppTheme.colors.surface,
        boxShadow: glowStrength <= 0
            ? null
            : [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.40),
                  blurRadius: blur,
                  spreadRadius: spread,
                ),
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.18),
                  blurRadius: blur * 2,
                  spreadRadius: spread,
                ),
              ],
      ),
      padding: EdgeInsets.all(size * 0.08),
      child: ClipOval(
        // WHITE-MATTE FIX: this used to render 'assets/images/appIcon.png',
        // a 1024x1024 RGB PNG with NO alpha channel — the mark is baked onto
        // an opaque white canvas, so a white square always showed inside the
        // disc no matter the theme (glaring in dark mode). 'logo-mark.png'
        // is the same blue-purple mark with a real transparent background
        // (already used by auth/onboarding/main screens), so the theme-aware
        // disc above finally shows through. BoxFit.contain keeps the full
        // mark visible inside the circle no matter its aspect ratio.
        child: Image.asset(
          'assets/images/logo-mark.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
