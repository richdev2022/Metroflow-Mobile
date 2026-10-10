import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// MAINTENANCE GATE (web parity with client/components/MaintenanceGate.tsx).
///
/// Polls the PUBLIC, unauthenticated `GET /public/app-config` endpoint:
///   { success: true, data: { maintenance_mode: bool, announcement: {...} } }
///
/// When `maintenance_mode` is ON the overlay replaces the ENTIRE app —
/// including the login screen — so nobody can sign in during a maintenance
/// window, exactly like the web's full-screen blocker. Polling runs every
/// 60s and on every app resume; the admin flipping the switch off lets
/// users back in automatically.
///
/// Fail-open: any fetch error keeps the app usable (same contract as web).
///
/// Entry points that also trigger a check:
///   - MaterialApp start (main.dart) and app resume (overlay lifecycle).
///   - Login / Google sign-in submit (login_screen.dart) — belt & braces
///     so a stale 60s window never lets a login through.
///   - Dio onError hook (api.dart) — a 503 MAINTENANCE_MODE from ANY call
///     (including POST /auth/login itself) flips the gate immediately.
/// ---------------------------------------------------------------------------
final ValueNotifier<bool> maintenanceModeNotifier = ValueNotifier<bool>(false);

/// Last announcement from /public/app-config (drives the in-app banner).
final ValueNotifier<Map<String, dynamic>?> appAnnouncementNotifier =
    ValueNotifier<Map<String, dynamic>?>(null);

class MaintenanceGate {
  MaintenanceGate._();

  static const Duration pollInterval = Duration(minutes: 1);
  static Timer? _timer;
  static bool _checking = false;

  /// Fetches the app config and updates the notifiers. Returns the live
  /// maintenance flag. Never throws (fail-open).
  static Future<bool> checkNow() async {
    if (_checking) return maintenanceModeNotifier.value;
    _checking = true;
    try {
      final response = await ApiService()
          .getPublicAppConfig()
          .timeout(const Duration(seconds: 12));
      final data = response.data;
      // Tolerant parse (web parity): accept both nested data.maintenance_mode
      // and a flat top-level maintenance_mode.
      Map? cfg;
      if (data is Map) {
        if (data['data'] is Map) {
          cfg = Map.castFrom(data['data'] as Map);
        } else {
          cfg = Map.castFrom(data);
        }
      }
      final on = cfg?['maintenance_mode'] == true ||
          cfg?['maintenance_mode']?.toString().toLowerCase() == 'true' ||
          cfg?['maintenance_mode']?.toString() == 'on';
      maintenanceModeNotifier.value = on;

      final announcement = cfg?['announcement'];
      appAnnouncementNotifier.value =
          announcement is Map ? Map<String, dynamic>.from(announcement) : null;
      return on;
    } catch (_) {
      // Fail-open: never trap users behind a network blip.
      return maintenanceModeNotifier.value;
    } finally {
      _checking = false;
    }
  }

  /// Immediately flip the gate ON (used by the dio 503 MAINTENANCE_MODE hook).
  static void setOn() {
    maintenanceModeNotifier.value = true;
  }

  static void startPolling() {
    _timer ??= Timer.periodic(pollInterval, (_) => checkNow());
  }

  static void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Mounted ONCE as the TOP-most child of the MaterialApp.builder stack
/// (above the incoming-call overlay): while maintenance is ON it covers the
/// whole app — every screen, every dialog, including login.
class MaintenanceGateOverlay extends StatefulWidget {
  const MaintenanceGateOverlay({super.key});

  @override
  State<MaintenanceGateOverlay> createState() => _MaintenanceGateOverlayState();
}

class _MaintenanceGateOverlayState extends State<MaintenanceGateOverlay>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initial check + periodic polling (60s, web parity).
    MaintenanceGate.checkNow();
    MaintenanceGate.startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check the moment the user comes back (web re-checks on focus).
      MaintenanceGate.checkNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: maintenanceModeNotifier,
      builder: (context, maintenance, _) {
        if (!maintenance) return const SizedBox.shrink();
        return const MaintenanceScreen();
      },
    );
  }
}

/// Full-screen branded blocker — mobile mirror of the web MaintenanceScreen
/// (dark backdrop, logo, pulsing wrench, "We'll be back soon").
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0B0F1A),
        elevation: 0,
        child: Stack(
          children: [
            // Ambient glow behind the content (mirrors the web blur blob).
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 420,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    width: 420,
                    height: 420,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.20),
                          blurRadius: 120,
                          spreadRadius: 40,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          // WHITE-MATTE FIX: appIcon.png is an RGB PNG with
                          // the mark baked onto an opaque white canvas (no
                          // alpha) — a white tile glared on this dark screen.
                          // logo-mark.png is the identical mark with a
                          // transparent background.
                          'assets/images/logo-mark.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.05),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: const Icon(
                          Icons.build_rounded,
                          size: 40,
                          color: Color(0xFF60A5FA),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "We'll be back soon",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Metricorex is undergoing scheduled maintenance to '
                        'make things better for you. Please check back in a '
                        'little while — the app will refresh automatically '
                        "once we're done.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 14.5,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _PulsingDot(),
                          const SizedBox(width: 8),
                          Text(
                            'Monitoring status — '
                            "you'll be let back in automatically",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.40),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          color: Color(0xFF3B82F6),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// ANNOUNCEMENT BANNER (web parity with AnnouncementTicker.tsx) — a slim,
/// dismissible strip fed by the same /public/app-config announcement. The
/// dismissal is remembered per announcement id.
/// ---------------------------------------------------------------------------
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({super.key});

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  static const String _dismissedKey = 'announcement_dismissed_id';
  String? _dismissedId;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _dismissedId = prefs.getString(_dismissedKey));
    } catch (_) {}
  }

  Future<void> _dismiss(String? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id != null && id.isNotEmpty) {
        await prefs.setString(_dismissedKey, id);
      }
    } catch (_) {}
    // No stable id — suppress for this session only.
    appAnnouncementNotifier.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: appAnnouncementNotifier,
      builder: (context, announcement, _) {
        if (announcement == null) return const SizedBox.shrink();
        final message =
            (announcement['message'] ?? announcement['text'] ?? '').toString();
        if (message.trim().isEmpty) return const SizedBox.shrink();
        final id = (announcement['id'] ?? '').toString();
        // Already dismissed by the user? Stay hidden.
        if (id.isNotEmpty && _dismissedId == id) {
          return const SizedBox.shrink();
        }

        return _AnnouncementStrip(
          message: message,
          colors: colors,
          onDismiss: () => _dismiss(id.isNotEmpty ? id : null),
        );
      },
    );
  }
}

class _AnnouncementStrip extends StatelessWidget {
  final String message;
  final ThemeColors colors;
  final VoidCallback onDismiss;

  const _AnnouncementStrip({
    required this.message,
    required this.colors,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2563EB),
      elevation: 0,
      child: SafeArea(
        bottom: false,
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              const Icon(Icons.campaign_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close_rounded,
                      color: Colors.white70, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
