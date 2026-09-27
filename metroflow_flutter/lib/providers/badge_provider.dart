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
