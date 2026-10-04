import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Custom-painted Google "G" logo (4 brand colors) used inside the Google
/// sign-in button. Designed for small sizes (18x18).
class GoogleLogoPainter extends CustomPainter {
  const GoogleLogoPainter();

  static const Color blue = Color(0xFF4285F4);
  static const Color red = Color(0xFFEA4335);
  static const Color yellow = Color(0xFFFBBC05);
  static const Color green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final double side = math.min(size.width, size.height);
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double stroke = side * 0.17;
    final Rect ring = Rect.fromCircle(center: center, radius: (side - stroke) / 2);

    Paint strokePaint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Top-left quadrant (9 → 12 o'clock): red.
    canvas.drawArc(ring, -math.pi, math.pi / 2, false, strokePaint(red));
    // Bottom-left quadrant (6 → 9 o'clock): yellow.
    canvas.drawArc(ring, math.pi / 2, math.pi / 2, false, strokePaint(yellow));
    // Bottom-right quadrant (just below 3 o'clock → 6 o'clock): green,
    // trimmed to leave the "mouth" of the G open below the crossbar.
    canvas.drawArc(
        ring, math.pi / 7, math.pi / 2 - math.pi / 7, false, strokePaint(green));
    // Right side (12 → 3 o'clock): blue.
    canvas.drawArc(ring, -math.pi / 2, math.pi / 2, false, strokePaint(blue));
    // Blue crossbar from the center out to the right edge of the ring.
    canvas.drawRect(
      Rect.fromLTWH(center.dx, center.dy - stroke / 2, ring.right - center.dx, stroke),
      Paint()..color = blue,
    );
  }

  @override
  bool shouldRepaint(covariant GoogleLogoPainter oldDelegate) => false;
}

/// "OR" divider used between the primary auth button and the Google button.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, this.label = 'OR'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Row(
      children: [
        Expanded(child: Divider(color: colors.border, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(child: Divider(color: colors.border, thickness: 1)),
      ],
    );
  }
}

/// Full-width outlined "Continue with Google" button with a small
/// CustomPaint'ed Google "G" logo.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.label = 'Continue with Google',
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF3C4043),
          backgroundColor: Colors.white,
          disabledForegroundColor: const Color(0xFF3C4043).withValues(alpha: 0.45),
          side: BorderSide(color: colors.border, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: GoogleLogoPainter.blue,
                ),
              )
            else
              const CustomPaint(
                size: Size(18, 18),
                painter: GoogleLogoPainter(),
              ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3C4043),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
