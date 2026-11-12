import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update.dart';
import '../utils/app_toast.dart';
import '../widgets/app_update_modal.dart';
import 'api.dart';

/// In-app update checker — SIMPLE flow (2026-11).
///
/// The admin publishes a release with a store URL or a custom link and flips
/// the "new release available" toggle. Users get a modal instantly:
///   - required updates  -> non-dismissable, only "Update now"
///   - optional updates  -> "Not now" skips it, but the prompt returns on the
///                          user's next login; tapping "Update now" records
///                          the release as handled so it stops nagging
///
/// "Instantly" is delivered by checking on login, on app start, on every
/// foreground resume and on a 60-second poll while the app is open.
///
/// Robustness rules (by design, all silent for automatic checks):
///   - any network/parse failure => no prompt (the app keeps working)
///   - endpoint missing (old backend) => 404 => no prompt
///   - web builds and non-phone platforms => no-op
///   - one prompt at a time; required updates ignore every dismissal
class AppUpdateService {
  AppUpdateService._() {
    // Lifecycle listener: fires the check on every foreground resume, so an
    // admin flipping the toggle reaches a backgrounded app the moment the
    // user returns to it. (AppLifecycleListener self-registers on creation.)
    AppLifecycleListener(
      onResume: () {
        _resumed = true;
        checkAndPrompt(source: 'resume');
      },
      onStateChange: (state) => _resumed = state == AppLifecycleState.resumed,
    );
  }
  static final AppUpdateService instance = AppUpdateService._();

  /// SharedPreferences key holding the release the user SKIPPED. Cleared on
  /// the next login so the prompt returns, per the product flow.
  static const String _skippedPrefKey = 'app_update.skipped_release';

  /// Release the user already tapped "Update now" for (optional updates) —
  /// never auto-prompted again.
  static const String _handledPrefKey = 'app_update.handled_release';

  static const Duration _httpTimeout = Duration(seconds: 8);

  /// Poll cadence while the app is foregrounded — how quickly an admin's
  /// "new release available" flip reaches an open app.
  static const Duration _pollInterval = Duration(seconds: 60);

  Timer? _pollTimer;
  bool _resumed = true;
  bool _dialogOpen = false;

  Dio _client() =>
      Dio(BaseOptions(connectTimeout: _httpTimeout, receiveTimeout: _httpTimeout));

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Starts the 60-second foreground poll + lifecycle hooks. Safe to call
  /// multiple times.
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_resumed && !_dialogOpen) {
        checkAndPrompt(source: 'poll');
      }
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Automatic check (login / app start / resume / poll). Never throws,
  /// never toasts.
  Future<void> checkAndPrompt({String source = 'auto'}) async {
    if (kIsWeb) return;
    try {
      final info = await checkForUpdate();
      if (info == null || !info.updateAvailable) return;

      // Required update: always surface, ignore dismissals and dedupe.
      if (info.updateRequired) {
        debugPrint('[AppUpdate] required update -> prompting ($source)');
        _show(info);
        return;
      }

      if (_dialogOpen) return;
      if (await handledRelease() == info.trackingKey) {
        debugPrint('[AppUpdate] ${info.trackingKey} already handled — skipping');
        return;
      }
      if (await skippedRelease() == info.trackingKey) {
        debugPrint(
            '[AppUpdate] ${info.trackingKey} previously skipped until next login');
        return;
      }
      debugPrint('[AppUpdate] update available -> prompting ($source)');
      _show(info);
    } catch (e) {
      // Belt & braces — the whole path is already failure-tolerant.
      debugPrint('[AppUpdate] checkAndPrompt ignored error: $e');
    }
  }

  /// Manual check (Settings row). Always gives feedback and, when an update
  /// exists, always shows the modal — even if the user dismissed it before.
  Future<void> checkManually() async {
    if (kIsWeb) return;
    final info = await checkForUpdate();
    if (info == null) {
      AppToast.show(
        'Could not check for updates. Check your connection and try again.',
        type: AppToastType.error,
      );
      return;
    }
    if (!info.updateAvailable) {
      AppToast.show("You're on the latest version (${info.currentLabel}).");
      return;
    }
    _show(info);
  }

  /// Fetches + parses the update payload. Returns null on ANY failure
  /// (offline, timeout, old backend, malformed body) — callers treat that as
  /// "no information", which automatic callers translate to "stay silent".
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (kIsWeb) return null;
    try {
      final platform = Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
              ? 'android'
              : null;
      if (platform == null) return null;

      final pkg = await PackageInfo.fromPlatform();
      final res = await _client().get<dynamic>(
        '$apiBaseUrl/public/app-updates/check',
        queryParameters: {
          'platform': platform,
          // Which app this is — the backend keeps Personal and Business
          // releases apart so each app is prompted only for itself.
          'app': pkg.packageName.endsWith('.personal') ? 'personal' : 'business',
          'current_version_code': pkg.buildNumber,
          'current_version_name': pkg.version,
        },
      );

      final body = res.data;
      final payload = body is Map ? body['data'] : null;
      if (payload is! Map) return null;

      return AppUpdateInfo.fromApi(
        payload,
        platform: platform,
        appType: pkg.packageName.endsWith('.personal')
            ? 'personal'
            : 'business',
        currentVersionCode: int.tryParse(pkg.buildNumber),
        currentVersionName: pkg.version,
      );
    } catch (e) {
      debugPrint('[AppUpdate] check failed (silently ignored): $e');
      return null;
    }
  }

  /// Opens the admin-configured download URL (store listing or custom link).
  /// Fallbacks: Android market:// deep link + https Play page; iOS iTunes
  /// lookup by bundle id. Returns false when every candidate fails (the UI
  /// then shows guidance).
  Future<bool> openDownload(AppUpdateInfo info) async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final candidates = <String>[
        if (info.downloadUrl != null && info.downloadUrl!.trim().isNotEmpty)
          info.downloadUrl!.trim(),
        if (Platform.isAndroid) ...[
          'market://details?id=${pkg.packageName}',
          'https://play.google.com/store/apps/details?id=${pkg.packageName}',
        ],
      ];
      if (Platform.isIOS) {
        final resolved = await _iosStoreUrl(pkg.packageName);
        if (resolved != null) candidates.add(resolved);
      }

      for (final raw in candidates) {
        final uri = Uri.tryParse(raw);
        if (uri == null) continue;
        try {
          if (await canLaunchUrl(uri)) {
            final launched = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
            if (launched) return true;
          }
        } catch (e) {
          debugPrint('[AppUpdate] launch failed for $raw: $e');
          // try the next candidate
        }
      }
    } catch (e) {
      debugPrint('[AppUpdate] openDownload failed: $e');
    }
    return false;
  }

  /// Convenience alias kept for older call sites.
  Future<bool> openStore(AppUpdateInfo info) => openDownload(info);

  Future<String?> skippedRelease() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_skippedPrefKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> rememberSkipped(String trackingKey) async {
    try {
      await (await SharedPreferences.getInstance())
          .setString(_skippedPrefKey, trackingKey);
    } catch (_) {
      // persistence is best-effort; worst case the user is re-prompted once
    }
  }

  Future<String?> handledRelease() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_handledPrefKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> rememberHandled(String trackingKey) async {
    try {
      await (await SharedPreferences.getInstance())
          .setString(_handledPrefKey, trackingKey);
    } catch (_) {
      // best-effort; worst case the user is prompted once more
    }
  }

  /// Called on every fresh LOGIN: a skipped release prompts again from the
  /// next session, exactly as the product flow specifies.
  Future<void> clearSessionDismissals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_skippedPrefKey);
      await prefs.remove(_handledPrefKey);
    } catch (_) {
      // ignore — the prompt simply returns a session early
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _show(AppUpdateInfo info) {
    if (_dialogOpen) return;
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('[AppUpdate] no navigator context yet — prompt skipped');
      return;
    }
    _dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: !info.updateRequired,
      builder: (dialogContext) => PopScope(
        // Required updates cannot be backed out of.
        canPop: !info.updateRequired,
        child: AppUpdateModal(
          info: info,
          showLater: !info.updateRequired,
          onUpdate: () async {
            final opened = await openDownload(info);
            // Optional updates: tapping "Update now" ends the nagging for
            // this release. Required ones keep blocking until updated.
            if (!info.updateRequired) {
              await rememberHandled(info.trackingKey);
            }
            return opened;
          },
          onLater: () {
            if (!info.updateRequired) {
              rememberSkipped(info.trackingKey);
            }
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          },
        ),
      ),
    ).whenComplete(() => _dialogOpen = false);
  }

  /// Resolves the live App Store page for [bundleId] via Apple's public
  /// iTunes Lookup API. Returns null when the app isn't published (yet) or
  /// the lookup fails — the modal then only relies on the admin-set URL.
  Future<String?> _iosStoreUrl(String bundleId) async {
    try {
      final res = await _client().get<dynamic>(
        'https://itunes.apple.com/lookup',
        queryParameters: {'bundleId': bundleId, 'country': 'us'},
      );
      final body = res.data;
      final results = body is Map ? body['results'] : null;
      if (results is List && results.isNotEmpty && results.first is Map) {
        final url = (results.first as Map)['trackViewUrl'];
        if (url is String && url.startsWith('https://')) return url;
      }
    } catch (_) {
      // not published / offline — fall through
    }
    return null;
  }
}
