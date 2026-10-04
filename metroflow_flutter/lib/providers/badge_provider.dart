import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_badge_service.dart';

/// Global unread-chat count shown as a badge on the bottom-nav Chat tab.
/// - Incremented on `chat:new-message-notification` socket pushes
/// - Re-synced from the conversations API by ChatScreen after each load
///
/// (Riverpod 3 removed StateProvider from the main export — Notifier is
/// the supported primitive here, same as the other providers in this app.)
class ChatUnreadNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value < 0 ? 0 : value;

  void increment() => state = state + 1;

  void clear() => state = 0;
}

final chatUnreadProvider =
    NotifierProvider<ChatUnreadNotifier, int>(ChatUnreadNotifier.new);

/// New meeting-invite dot for the bottom-nav Meetings tab.
/// Incremented when a "meeting" notification arrives; cleared when the
/// Meetings tab/screen is opened.
class MeetingsUnreadNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state = state + 1;

  void clear() => state = 0;
}

final meetingsUnreadProvider =
    NotifierProvider<MeetingsUnreadNotifier, int>(MeetingsUnreadNotifier.new);

/// ---------------------------------------------------------------------------
/// Launcher-icon badge (Facebook-style app icon count).
///
/// Total = unread chats (chatUnreadProvider) + unread notifications
/// (notificationsProvider.unreadCount). main.dart listens to both providers
/// and calls [update]; push handlers set the exact server-computed total;
/// the badge is also refreshed on app resume and cleared on sign-out.
///
/// Delegates to [AppBadgeService] (MethodChannel -> ShortcutBadger) which
/// covers more launchers (Samsung, Xiaomi, Oppo/OnePlus, Huawei...) than the
/// previous app_badge_plus implementation and persists the counter so a
/// cold start restores it. Every call is best-effort.
/// ---------------------------------------------------------------------------
class LauncherBadge {
  LauncherBadge._();

  static Future<void> update(int count) async {
    try {
      final total = count < 0 ? 0 : count;
      await AppBadgeService.instance.addUnread(exact: total);
    } catch (e) {
      debugPrint('LauncherBadge.update failed (unsupported launcher?): $e');
    }
  }

  static Future<void> clear() async {
    try {
      await AppBadgeService.instance.clear();
    } catch (e) {
      debugPrint('LauncherBadge.clear failed: $e');
    }
  }
}
