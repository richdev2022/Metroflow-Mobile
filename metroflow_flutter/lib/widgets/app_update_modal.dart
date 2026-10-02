import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../models/app_update.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

/// "A new version is available" modal.
///
/// Visual language mirrors [UpgradeDialog]: rounded 24 card, brand-gradient
/// hero, white (or dark-surface) body, gradient pill CTA. The widget itself
/// is dumb UI — behaviour (dismiss persistence, store launch, forced mode)
/// lives in AppUpdateService, which wires the callbacks.
class AppUpdateModal extends StatelessWidget {
  const AppUpdateModal({
    super.key,
    required this.info,
    required this.onUpdate,
    this.onLater,
    this.showLater = true,
  });

  final AppUpdateInfo info;

  /// Opens the store page. Returns true when a store page was opened.
  final Future<bool> Function() onUpdate;

  /// Postpones this release (optional updates only). Null for forced ones.
  final VoidCallback? onLater;

  final bool showLater;

  String get _storeName {
    try {
      if (Platform.isIOS) return 'the App Store';
    } catch (_) {}
    return 'Google Play';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bodyColor = isDark ? const Color(0xFF16213A) : Colors.white;
    final primaryText = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
    final secondaryText = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final chipBg = isDark ? Colors.white12 : const Color(0xFFEFF6FF);
    final notesBg = isDark ? const Color(0xFF0F1A2E) : const Color(0xFFF8FAFC);

    final required = info.updateRequired;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          color: bodyColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---------------- Hero ----------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary,
                      AppColors.primaryDark,
                      Color(0xFF7C3AED),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'MetriCorex',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: required
                                ? const Color(0x59EF4444)
                                : Colors.white24,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                required
                                    ? Icons.priority_high
                                    : Icons.rocket_launch_outlined,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                required ? 'UPDATE REQUIRED' : 'NEW VERSION',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        required ? Icons.system_security_update_good : Icons.system_update_alt,
                        size: 30,
                        color: required ? const Color(0xFFFCA5A5) : const Color(0xFFFCD34D),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      required
                          ? 'Update required to continue'
                          : 'A new version is available',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      required
                          ? 'Version ${info.latestLabel} is required to keep using '
                              'MetriCorex securely. Please update now.'
                          : 'MetriCorex ${info.latestLabel} brings improvements '
                              'and fixes. Update for the best experience.',
                      style: const TextStyle(
                        color: Color(0xE6E0E7FF),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),

              // ---------------- Body ----------------
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Version chips
                      Row(
                        children: [
                          _versionChip(
                            label: 'INSTALLED',
                            value: info.currentLabel,
                            background: chipBg,
                            accent: secondaryText,
                            valueColor: primaryText,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.arrow_forward,
                                size: 16, color: Color(0xFF94A3B8)),
                          ),
                          _versionChip(
                            label: 'LATEST',
                            value:
                                '${info.latestLabel} (build ${info.latestVersionCode})',
                            background: chipBg,
                            accent: AppColors.primary,
                            valueColor: AppColors.primaryDark,
                          ),
                        ],
                      ),
                      if (info.releaseNotes != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          "WHAT'S NEW",
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: notesBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white10
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Text(
                            info.releaseNotes!,
                            style: TextStyle(
                              color: primaryText,
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _UpdateButton(onUpdate: onUpdate, storeName: _storeName),
                      if (showLater && onLater != null) ...[
                        const SizedBox(height: 6),
                        Center(
                          child: TextButton(
                            onPressed: onLater,
                            child: Text(
                              'Remind me later',
                              style: TextStyle(
                                color: secondaryText,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _versionChip({
    required String label,
    required String value,
    required Color background,
    required Color accent,
    required Color valueColor,
  }) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateButton extends StatefulWidget {
  const _UpdateButton({required this.onUpdate, required this.storeName});

  final Future<bool> Function() onUpdate;
  final String storeName;

  @override
  State<_UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<_UpdateButton> {
  bool _launching = false;

  Future<void> _handleTap() async {
    if (_launching) return;
    setState(() => _launching = true);
    try {
      final opened = await widget.onUpdate();
      if (!opened && mounted) {
        AppToast.show(
          "Couldn't open ${widget.storeName}. Please open it and search for "
          'MetriCorex to update.',
          type: AppToastType.error,
          isLong: true,
        );
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFF7C3AED)],
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x592563EB),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _launching ? null : _handleTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          child: _launching
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Opening store…',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Update now',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward, size: 17, color: Colors.white),
                  ],
                ),
        ),
      ),
    );
  }
}
