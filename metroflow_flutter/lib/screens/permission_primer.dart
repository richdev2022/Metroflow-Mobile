import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api.dart';

/// ---------------------------------------------------------------------------
/// First-login permissions primer (beautiful, never blocking).
///
/// Shown ONCE after the first successful login (flag persisted in
/// SharedPreferences as `permission_primer_shown`). A polished bottom sheet
/// (brand indigo #2563EB) explains why the app needs:
///   - Notifications  — incoming-call rings & chat alerts
///   - Camera         — video calls & meetings
///   - Microphone     — audio in calls & voice notes
///   - Photos/Storage — avatars & attachments
///
/// Each row has its own "Allow" button that triggers ONLY that OS prompt so
/// the user stays in control; "Skip for now" closes the sheet. The app is
/// fully usable regardless of the outcome — nothing here can block usage.
/// ---------------------------------------------------------------------------
class PermissionPrimer {
  PermissionPrimer._();

  static const String _shownKey = 'permission_primer_shown';
  static const Color brand = Color(0xFF2563EB);

  /// Call right after a successful login. Shows the sheet at most once per
  /// install. Never throws, never blocks navigation.
  static Future<void> maybeShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_shownKey) == true) return;
      await prefs.setBool(_shownKey, true);

      // Give the post-login navigation a beat to settle so the sheet
      // attaches to the (now mounted) root navigator context.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black54,
        builder: (_) => const _PermissionPrimerSheet(),
      );
    } catch (e) {
      debugPrint('PermissionPrimer.maybeShow failed: $e');
    }
  }
}

enum _PrimerStatus { waiting, granted, denied }

class _PermissionPrimerSheet extends StatefulWidget {
  const _PermissionPrimerSheet();

  @override
  State<_PermissionPrimerSheet> createState() => _PermissionPrimerSheetState();
}

class _PermissionPrimerSheetState extends State<_PermissionPrimerSheet> {
  _PrimerStatus _notifications = _PrimerStatus.waiting;
  _PrimerStatus _camera = _PrimerStatus.waiting;
  _PrimerStatus _microphone = _PrimerStatus.waiting;
  _PrimerStatus _photos = _PrimerStatus.waiting;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _readCurrentStatuses();
  }

  Future<void> _readCurrentStatuses() async {
    try {
      final notif = await Permission.notification.isGranted;
      final cam = await Permission.camera.isGranted;
      final mic = await Permission.microphone.isGranted;
      final photos =
          await Permission.photos.isGranted || await Permission.storage.isGranted;
      if (!mounted) return;
      setState(() {
        if (notif) _notifications = _PrimerStatus.granted;
        if (cam) _camera = _PrimerStatus.granted;
        if (mic) _microphone = _PrimerStatus.granted;
        if (photos) _photos = _PrimerStatus.granted;
      });
    } catch (_) {}
  }

  Future<void> _request(_PrimerRow row) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (row) {
        case _PrimerRow.notifications:
          final result = await Permission.notification.request();
          if (!mounted) return;
          setState(() =>
              _notifications = result.isGranted ? _PrimerStatus.granted : _PrimerStatus.denied);
          break;
        case _PrimerRow.camera:
          final result = await Permission.camera.request();
          if (!mounted) return;
          setState(() => _camera = result.isGranted ? _PrimerStatus.granted : _PrimerStatus.denied);
          break;
        case _PrimerRow.microphone:
          final result = await Permission.microphone.request();
          if (!mounted) return;
          setState(() =>
              _microphone = result.isGranted ? _PrimerStatus.granted : _PrimerStatus.denied);
          break;
        case _PrimerRow.photos:
          // Photos (Android 13+/iOS 14+) with the legacy storage fallback —
          // at least one granted counts.
          final photos = await Permission.photos.request();
          var granted = photos.isGranted;
          if (!granted) {
            try {
              final storage = await Permission.storage.request();
              granted = storage.isGranted;
            } catch (_) {}
          }
          if (!mounted) return;
          setState(() => _photos = granted ? _PrimerStatus.granted : _PrimerStatus.denied);
          break;
      }
    } catch (e) {
      debugPrint('Permission request failed: $e');
      if (mounted) {
        setState(() {
          switch (row) {
            case _PrimerRow.notifications:
              _notifications = _PrimerStatus.denied;
              break;
            case _PrimerRow.camera:
              _camera = _PrimerStatus.denied;
              break;
            case _PrimerRow.microphone:
              _microphone = _PrimerStatus.denied;
              break;
            case _PrimerRow.photos:
              _photos = _PrimerStatus.denied;
              break;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int get _grantedCount =>
      [_notifications, _camera, _microphone, _photos]
          .where((s) => s == _PrimerStatus.granted)
          .length;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [PermissionPrimer.brand, Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: PermissionPrimer.brand.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 18),
              const Text(
                'Unlock the full experience',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Allow these permissions so calls ring, meetings run and files share smoothly. You can change them anytime in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 20),
              _PrimerTile(
                icon: Icons.notifications_active_rounded,
                iconColor: PermissionPrimer.brand,
                title: 'Notifications',
                description: 'Incoming-call rings and chat alerts — even when the app is closed.',
                status: _notifications,
                busy: _busy,
                onAllow: () => _request(_PrimerRow.notifications),
              ),
              const SizedBox(height: 12),
              _PrimerTile(
                icon: Icons.videocam_rounded,
                iconColor: const Color(0xFF059669),
                title: 'Camera',
                description: 'Video calls and meetings.',
                status: _camera,
                busy: _busy,
                onAllow: () => _request(_PrimerRow.camera),
              ),
              const SizedBox(height: 12),
              _PrimerTile(
                icon: Icons.mic_rounded,
                iconColor: const Color(0xFFD97706),
                title: 'Microphone',
                description: 'Your voice in calls, meetings and voice notes.',
                status: _microphone,
                busy: _busy,
                onAllow: () => _request(_PrimerRow.microphone),
              ),
              const SizedBox(height: 12),
              _PrimerTile(
                icon: Icons.photo_library_outlined,
                iconColor: const Color(0xFF7C3AED),
                title: 'Photos & storage',
                description: 'Avatars and file attachments you share.',
                status: _photos,
                busy: _busy,
                onAllow: () => _request(_PrimerRow.photos),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [PermissionPrimer.brand, Color(0xFF3B82F6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: PermissionPrimer.brand.withValues(alpha: 0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _grantedCount == 4
                          ? 'All set — continue'
                          : 'Continue ($_grantedCount of 4 allowed)',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF94A3B8)),
                child: const Text(
                  'Skip for now',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PrimerRow { notifications, camera, microphone, photos }

class _PrimerTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final _PrimerStatus status;
  final bool busy;
  final VoidCallback onAllow;

  const _PrimerTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.status,
    required this.busy,
    required this.onAllow,
  });

  @override
  Widget build(BuildContext context) {
    final granted = status == _PrimerStatus.granted;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: granted ? iconColor.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: granted ? iconColor.withValues(alpha: 0.35) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (granted)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 26)
          else
            SizedBox(
              height: 40,
              child: TextButton(
                onPressed: busy ? null : onAllow,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: PermissionPrimer.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Allow',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
