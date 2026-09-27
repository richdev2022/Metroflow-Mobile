import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart' show navigatorKey;
import '../theme/app_theme.dart';

/// Global in-app notification banner (slides in from the top, tap to act).
/// Rendered through the root navigator overlay so it appears on any screen.
class InAppBanner {
  InAppBanner._();

  static final Map<int, Timer> _dismissTimers = {};
  static int _nextId = 0;

  static void show({
    required String title,
    String? message,
    IconData icon = Icons.notifications_active_rounded,
    Color? accentColor,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    final navigator = navigatorKey.currentState;
    final context = navigatorKey.currentContext;
    if (navigator == null || context == null) return;

    final colors = AppTheme.colors;
    final accent = accentColor ?? colors.primary;
    final id = _nextId++;

    final OverlayState overlay;
    try {
      overlay = Overlay.of(navigator.context, rootOverlay: true);
    } catch (_) {
      // No overlay available yet — fail silently.
      return;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _BannerView(
        title: title,
        message: message,
        icon: icon,
        accent: accent,
        colors: colors,
        onDismiss: () {
          _dismissTimers.remove(id)?.cancel();
          if (entry.mounted) entry.remove();
        },
        onTap: onTap,
      ),
    );

    overlay.insert(entry);
    _dismissTimers[id] = Timer(duration, () {
      _dismissTimers.remove(id);
      if (entry.mounted) entry.remove();
    });
  }
}

class _BannerView extends StatefulWidget {
  final String title;
  final String? message;
  final IconData icon;
  final Color accent;
  final ThemeColors colors;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  const _BannerView({
    required this.title,
    required this.icon,
    required this.accent,
    required this.colors,
    required this.onDismiss,
    this.message,
    this.onTap,
  });

  @override
  State<_BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<_BannerView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    widget.onTap?.call();
    await _close();
  }

  Future<void> _close() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _handleTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: widget.colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: widget.colors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, color: widget.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: widget.colors.text,
                          ),
                        ),
                        if (widget.message != null && widget.message!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.message!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.colors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _close,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 18, color: widget.colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
