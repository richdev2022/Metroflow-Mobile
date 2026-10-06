import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../services/api.dart' show navigatorKey;
import '../theme/app_theme.dart';

/// Current app route, kept fresh by the GoRouter redirect in main.dart so
/// globally-mounted widgets (this bubble) can react to navigation without a
/// NavigatorObserver.
final ValueNotifier<String> appCurrentRouteNotifier =
    ValueNotifier<String>('');

/// Routes where the floating "Ask MetricAi" bubble stays hidden: the
/// MetricAi screen itself, every pre-auth screen and the KYC/profile gates
/// (web parity: AskMetricAiWidget hides on call-room routes; here the
/// incoming-call overlay renders above the bubble anyway).
const Set<String> _metricAiBubbleHiddenRoutes = <String>{
  '/',
  '/login',
  '/register',
  '/forgot-password',
  '/verify-otp',
  '/verify-reset-otp',
  '/reset-password',
  '/onboarding1',
  '/kyc-prompt',
  '/kyc-initiate',
  '/kyc-otp',
  '/complete-profile',
};

const String _posKey = 'metric_ai_fab_pos';
const double _bubbleSize = 52;
const double _edgeMargin = 12;

/// Floating, DRAGGABLE "Ask MetricAi" bubble — mounted once above every
/// screen (in the MaterialApp builder stack), like the web's
/// AskMetricAiWidget. Tap opens the MetricAi chat; press-and-drag moves it
/// anywhere on screen and the position persists across sessions.
class MetricAiFloatingBubble extends ConsumerStatefulWidget {
  const MetricAiFloatingBubble({super.key});

  @override
  ConsumerState<MetricAiFloatingBubble> createState() =>
      _MetricAiFloatingBubbleState();
}

class _MetricAiFloatingBubbleState
    extends ConsumerState<MetricAiFloatingBubble> {
  Offset? _pos; // null = default corner (bottom-right, above the tab bar)
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _restorePosition();
  }

  Future<void> _restorePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble('${_posKey}_x');
      final y = prefs.getDouble('${_posKey}_y');
      if (x != null && y != null && mounted) {
        setState(() => _pos = Offset(x, y));
      }
    } catch (_) {
      // Corrupted position — keep the default corner.
    }
  }

  Future<void> _persistPosition(Offset pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('${_posKey}_x', pos.dx);
      await prefs.setDouble('${_posKey}_y', pos.dy);
    } catch (_) {}
  }

  /// Default corner (bottom-right, above the tab bar) used when the user
  /// has never dragged the bubble.
  Offset _defaultPosition(Size size) => Offset(
        size.width - _bubbleSize - 16,
        size.height - _bubbleSize - 118,
      );

  Offset _clamp(Offset pos) {
    final size = MediaQuery.of(context).size;
    final maxX = size.width - _bubbleSize - _edgeMargin;
    final maxY = size.height - _bubbleSize - _edgeMargin;
    return Offset(
      pos.dx.clamp(_edgeMargin, maxX < _edgeMargin ? _edgeMargin : maxX),
      pos.dy.clamp(_edgeMargin, maxY < _edgeMargin ? _edgeMargin : maxY),
    );
  }

  Offset get _effectivePos =>
      _pos ?? _defaultPosition(MediaQuery.of(context).size);

  bool get _hidden {
    if (!ref.read(authProvider).isAuthenticated) return true;
    final route = appCurrentRouteNotifier.value;
    if (_metricAiBubbleHiddenRoutes.contains(route)) return true;
    if (route.startsWith('/main/metric-ai')) return true;
    return false;
  }

  void _openMetricAi() {
    final route = appCurrentRouteNotifier.value;
    if (route.startsWith('/main/metric-ai')) return;
    // CLICK FIX: this bubble is mounted in the MaterialApp.builder stack,
    // whose BuildContext sits ABOVE the Router widget — GoRouter.of(context)
    // threw "No GoRouter found in context" on every tap, so the bubble
    // rendered fine but clicks silently did nothing. The navigator key's
    // context lives BELOW the router's InheritedGoRouter, so resolving the
    // GoRouter through it always works.
    final navContext = navigatorKey.currentContext;
    final router = navContext != null
        ? GoRouter.maybeOf(navContext)
        : GoRouter.maybeOf(context);
    // push (not go) so the bubble's host screen stays in the stack.
    router?.push('/main/metric-ai');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final isAuthenticated = ref.watch(authProvider).isAuthenticated;

    return ValueListenableBuilder<String>(
      valueListenable: appCurrentRouteNotifier,
      builder: (context, route, _) {
        if (!isAuthenticated || _hidden) return const SizedBox.shrink();

        final position = _clamp(_effectivePos);

        return Positioned(
          left: position.dx,
          top: position.dy,
          width: _bubbleSize,
          height: _bubbleSize,
          child: GestureDetector(
            // DRAG FIX: seeding _pos here — the first drag used to crash on
            // "_pos!" (null until the user had ever dragged), which could
            // leave _dragging stuck true and permanently dead taps.
            onPanStart: (_) {
              setState(() {
                _pos = _effectivePos;
                _dragging = true;
              });
            },
            onPanUpdate: (details) {
              if (!_dragging) return;
              setState(() {
                _pos = _clamp((_pos ?? _effectivePos) + details.delta);
              });
            },
            onPanEnd: (_) {
              _dragging = false;
              if (_pos != null) _persistPosition(_pos!);
            },
            onPanCancel: () {
              if (mounted) setState(() => _dragging = false);
            },
            onTap: _dragging ? null : _openMetricAi,
            child: Tooltip(
              message: 'Ask MetricAi — drag to move',
              waitDuration: const Duration(milliseconds: 600),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4F46E5), Color(0xFF2563EB)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(5),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surface,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Image.asset(
                    // WHITE-MATTE FIX: appIcon.png is an RGB PNG with the
                    // mark baked onto an opaque white canvas (no alpha), so
                    // a white square showed inside the themed disc in dark
                    // mode. logo-mark.png is the identical mark with a
                    // transparent background.
                    'assets/images/logo-mark.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
