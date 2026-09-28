import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// Launcher-icon badge (WhatsApp-style app icon count).
///
/// Total = unread chats (chatUnreadProvider) + unread notifications
/// (notificationsProvider.unreadCount). main.dart listens to both providers
/// and calls [update]; the badge is also refreshed on app resume and cleared
/// when the user signs out.
///
/// Everything is wrapped in try/catch: launchers/platforms that don't support
/// badges must never crash the app (app_badge_plus is a no-op there anyway).
/// ---------------------------------------------------------------------------
class LauncherBadge {
  LauncherBadge._();

  static Future<void> update(int count) async {
    try {
      final total = count < 0 ? 0 : count;
      if (total == 0) {
        await AppBadgePlus.removeBadge();
      } else {
        await AppBadgePlus.updateBadge(total);
      }
    } catch (e) {
      debugPrint('LauncherBadge.update failed (unsupported launcher?): $e');
    }
  }

  static Future<void> clear() => update(0);
}
