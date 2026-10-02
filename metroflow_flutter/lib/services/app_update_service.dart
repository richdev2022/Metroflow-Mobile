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

/// In-app update checker.
///
/// Flow: on login and on app start the app asks the backend whether a newer
/// release exists (`GET /api/public/app-updates/check`). When one does, a
/// polished modal is shown:
///   - required updates  -> non-dismissable, only "Update now"
///   - optional updates  -> "Remind me later" persists the dismissed version
///                          code so the same release never nags twice
///
/// Robustness rules (by design, all silent for automatic checks):
///   - any network/parse failure => no prompt (the app keeps working)
///   - endpoint missing (old backend) => 404 => no prompt
///   - web builds and non-phone platforms => no-op
///   - one prompt at a time; one check prompt per version per session;
///     required updates ignore every dismissal
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// SharedPreferences key holding the last OPTIONAL release the user
  /// postponed. Required updates never read this.
  static const String _dismissedPrefKey = 'app_update.dismissed_version_code';

  static const Duration _httpTimeout = Duration(seconds: 8);

  /// Version code already prompted in this app session — prevents the login
  /// hook and the startup hook from double-prompting the same release.
  int? _promptedThisSession;

  bool _dialogOpen = false;

  Dio _client() =>
      Dio(BaseOptions(connectTimeout: _httpTimeout, receiveTimeout: _httpTimeout));

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Automatic check (login / app start). Never throws, never toasts.
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

      if (_dialogOpen || _promptedThisSession == info.latestVersionCode) return;
      if (await dismissedVersionCode() == info.latestVersionCode) {
        debugPrint('[AppUpdate] v${info.latestVersionCode} previously dismissed — skipping');
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
        currentVersionCode: int.tryParse(pkg.buildNumber),
        currentVersionName: pkg.version,
      );
    } catch (e) {
      debugPrint('[AppUpdate] check failed (silently ignored): $e');
      return null;
    }
  }

  /// Opens the right store page for the running platform. Priority:
  ///   1. store_url published with the release (admin-controlled)
   ///  2. Android: market:// deep link, then the https Play fallback
  ///   3. iOS: iTunes lookup by bundle id -> human trackViewUrl
  /// Returns false when every candidate fails (UI then shows guidance).
  Future<bool> openStore(AppUpdateInfo info) async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final candidates = <String>[
        if (info.storeUrl != null && info.storeUrl!.trim().isNotEmpty)
          info.storeUrl!.trim(),
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
      debugPrint('[AppUpdate] openStore failed: $e');
    }
    return false;
  }

  Future<int?> dismissedVersionCode() async {
    try {
      return (await SharedPreferences.getInstance()).getInt(_dismissedPrefKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> rememberDismissed(int versionCode) async {
    try {
      await (await SharedPreferences.getInstance())
          .setInt(_dismissedPrefKey, versionCode);
    } catch (_) {
      // persistence is best-effort; worst case the user is re-prompted once
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
    _promptedThisSession = info.latestVersionCode;
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
          onUpdate: () => openStore(info),
          onLater: () {
            rememberDismissed(info.latestVersionCode);
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
