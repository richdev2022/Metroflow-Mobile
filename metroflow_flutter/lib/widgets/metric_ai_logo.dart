import 'package:flutter/material.dart';

/// The MetricAi logo inside a circle with a subtle animated glow pulse that
/// lerps between indigo (#4F46E5) and blue (#2563EB). Used for the pinned
/// MetricAi entry in the chat list and the MetricAi screen header.
class MetricAiGlowLogo extends StatefulWidget {
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
  State<MetricAiGlowLogo> createState() => _MetricAiGlowLogoState();
}

class _MetricAiGlowLogoState extends State<MetricAiGlowLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.radius * 2;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final glowColor =
            Color.lerp(const Color(0xFF4F46E5), const Color(0xFF2563EB), t)!;
        final blur = (10.0 + 10.0 * t) * widget.glowStrength;
        final spread = (1.0 + 1.5 * t) * widget.glowStrength;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: widget.glowStrength <= 0
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
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}
