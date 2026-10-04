import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
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

  Offset _clamp(Offset pos) {
    final size = MediaQuery.of(context).size;
    final maxX = size.width - _bubbleSize - _edgeMargin;
    final maxY = size.height - _bubbleSize - _edgeMargin;
    return Offset(
      pos.dx.clamp(_edgeMargin, maxX < _edgeMargin ? _edgeMargin : maxX),
      pos.dy.clamp(_edgeMargin, maxY < _edgeMargin ? _edgeMargin : maxY),
    );
  }

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
    // push (not go) so the bubble's host screen stays in the stack.
    GoRouter.of(context).push('/main/metric-ai');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final isAuthenticated = ref.watch(authProvider).isAuthenticated;

    return ValueListenableBuilder<String>(
      valueListenable: appCurrentRouteNotifier,
      builder: (context, route, _) {
        if (!isAuthenticated || _hidden) return const SizedBox.shrink();

        final position = _clamp(_pos ??
            Offset(
              MediaQuery.of(context).size.width - _bubbleSize - 16,
              MediaQuery.of(context).size.height - _bubbleSize - 118,
            ));

        return Positioned(
          left: position.dx,
          top: position.dy,
          width: _bubbleSize,
          height: _bubbleSize,
          child: GestureDetector(
            onPanStart: (_) => _dragging = true,
            onPanUpdate: (details) {
              setState(() {
                _pos = _clamp(_pos! + details.delta);
              });
            },
            onPanEnd: (_) {
              _dragging = false;
              if (_pos != null) _persistPosition(_pos!);
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
                    'assets/images/appIcon.png',
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
