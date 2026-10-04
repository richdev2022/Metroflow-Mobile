import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Facebook-style unread badge on the launcher icon.
///
/// - Android: MethodChannel -> ShortcutBadger in MainActivity.kt (covers
///   Samsung, Xiaomi/HyperOS, Oppo/OnePlus, Huawei and most stock launchers).
/// - iOS:     app_badge_plus -> UIApplication.applicationIconBadgeNumber
///   (the same badge the OS shows for APNs `badge` payloads).
/// Every call is best-effort: launchers without badge support simply no-op
/// and the stored counter keeps working for the next supported device.
class AppBadgeService {
  AppBadgeService._internal();
  static final AppBadgeService instance = AppBadgeService._internal();

  static const MethodChannel _channel = MethodChannel('metricorex/app_badge');
  static const String _kUnreadCountKey = 'app_badge_unread_count';

  int _unread = 0;
  int get unread => _unread;

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  Future<SharedPreferences> get _prefs async =>
      SharedPreferences.getInstance();

  /// Restore the last known count at app start.
  Future<void> initialize() async {
    if (!_supported) return;
    try {
      final prefs = await _prefs;
      _unread = prefs.getInt(_kUnreadCountKey) ?? 0;
      if (_unread > 0) {
        await _setLauncherBadge(_unread);
      }
    } catch (_) {}
  }

  /// Add [delta] unread messages (or set an exact count when the push payload
  /// carries the server-computed unread number).
  Future<void> addUnread({int delta = 1, int? exact}) async {
    if (!_supported) return;
    try {
      final prefs = await _prefs;
      _unread = exact != null
          ? (exact < 0 ? 0 : exact)
          : _unread + delta;
      await prefs.setInt(_kUnreadCountKey, _unread);
      await _setLauncherBadge(_unread);
    } catch (_) {}
  }

  /// Chats opened / conversations read — badge goes back to zero.
  Future<void> clear() async {
    if (!_supported) return;
    try {
      _unread = 0;
      final prefs = await _prefs;
      await prefs.setInt(_kUnreadCountKey, 0);
      await _setLauncherBadge(0);
    } catch (_) {}
  }

  Future<void> _setLauncherBadge(int count) async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('setBadge', {'count': count});
      } else if (Platform.isIOS) {
        // updateBadge(0) clears the badge.
        await AppBadgePlus.updateBadge(count);
      }
    } on MissingPluginException {
      // Badge channel unavailable (e.g. hot restart) — ignore.
    } catch (_) {}
  }
}
