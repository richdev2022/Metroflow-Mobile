import 'package:flutter/material.dart';

import '../services/captions_service.dart';

/// Live captions overlay for the call/meeting screen.
///
/// Sits at the bottom of the room, just above the control dock, and shows the
/// most recent caption segments (speaker name + text) with an automatic fade
/// after ~6s. Purely presentational — segment lifecycle (room filtering,
/// interim replacement, pruning, opacity) lives in [CaptionsController].
///
/// Provider-agnostic by design: captions arrive over the app's own socket
/// connection, so this overlay never references (or knows about) the media
/// provider powering the room.
class CaptionsOverlay extends StatelessWidget {
  final CaptionsController controller;

  /// Distance from the bottom of the screen — keep the block clear of the
  /// control dock (dock ≈ 110dp incl. safe area + margins).
  final double bottom;

  const CaptionsOverlay({
    super.key,
    required this.controller,
    this.bottom = 124,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final entries = controller.entries;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in entries)
                  _CaptionRow(
                    key: ValueKey(entry.key),
                    segment: entry.segment,
                    opacity: controller.opacityFor(entry.segment),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CaptionRow extends StatelessWidget {
  final CaptionSegment segment;
  final double opacity;

  const _CaptionRow({
    super.key,
    required this.segment,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // Fade/slide-in on entry; the controller's prune + opacityFor handle
      // the fade-out (rows disappear once fully faded).
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, entry, child) {
        return Opacity(
          opacity: (entry * opacity).clamp(0.0, 1.0),
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              segment.speakerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF60A5FA),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              segment.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
