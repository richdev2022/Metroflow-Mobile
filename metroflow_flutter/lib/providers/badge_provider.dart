import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global unread-chat count shown as a badge on the bottom-nav Chat tab.
/// - Incremented on `chat:new-message-notification` socket pushes
/// - Re-synced from the conversations API by ChatScreen after each load
final StateProvider<int> chatUnreadProvider = StateProvider<int>((ref) => 0);

/// New meeting-invite dot for the bottom-nav Meetings tab.
/// Incremented when a "meeting" notification arrives; cleared when the
/// Meetings tab/screen is opened.
final StateProvider<int> meetingsUnreadProvider = StateProvider<int>((ref) => 0);
