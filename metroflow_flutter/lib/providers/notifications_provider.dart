import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/notification.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_feedback.dart';
import '../widgets/inapp_banner.dart';
import 'auth_provider.dart';
import 'badge_provider.dart';

class NotificationsState {
  final List<AppNotification> notifications;
  final bool isLoading;
  final String? error;
  final int unreadCount;

  NotificationsState({
    required this.notifications,
    this.isLoading = false,
    this.error,
    required this.unreadCount,
  });

  NotificationsState copyWith({
    List<AppNotification>? notifications,
    bool? isLoading,
    String? error,
    int? unreadCount,
  }) {
    return NotificationsState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

final notificationsProvider = NotifierProvider<NotificationsNotifier, NotificationsState>(NotificationsNotifier.new);

class NotificationsNotifier extends Notifier<NotificationsState> {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();

  @override
  NotificationsState build() {
    // Listen for new notifications from socket
    _socketService.onNotificationNew = (data) {
      try {
        final notification = AppNotification.fromJson(Map<String, dynamic>.from(data));
        _addNotification(notification);
      } catch (e) {
        debugPrint('Error handling new notification: $e');
      }
    };

    // Listen to auth state changes
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.isAuthenticated && (previous?.isAuthenticated != true)) {
        fetchNotifications();
      }
    });

    // Also fetch notifications immediately if already authenticated
    final authState = ref.read(authProvider);
    if (authState.isAuthenticated) {
      fetchNotifications();
    }

    return NotificationsState(
      notifications: [],
      unreadCount: 0,
    );
  }

  Future<void> fetchNotifications() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _apiService.getNotifications();
      final data = response.data;
      if (data['success'] == true) {
        final notificationsData = data['data']['notifications'] as List;
        final notifications = notificationsData
            .map((n) => AppNotification.fromJson(Map<String, dynamic>.from(n)))
            .toList();
        final unreadCount = notifications.where((n) => !n.isRead).length;
        state = state.copyWith(
          notifications: notifications,
          unreadCount: unreadCount,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false, error: 'Failed to fetch notifications');
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      // Show the SERVER's message (e.g. "Your subscription has expired…"),
      // never the raw DioException dump — users cannot act on that.
      state = state.copyWith(
        isLoading: false,
        error: ApiService.extractErrorMessage(e),
      );
    }
  }

  void _addNotification(AppNotification notification) {
    final updatedNotifications = [notification, ...state.notifications];
    final updatedUnreadCount = state.unreadCount + (notification.isRead ? 0 : 1);
    state = state.copyWith(
      notifications: updatedNotifications,
      unreadCount: updatedUnreadCount,
    );

    if (notification.isRead) return;

    // In-app pop for new notifications: sound + sliding banner.
    // Chat messages have their own dedicated banner in main.dart and calls
    // ring via the IncomingCallDialog, so skip both here to avoid
    // double alerts.
    final type = notification.type.toLowerCase();
    if (type != 'chat' && type != 'call') {
      AppFeedback.playPushNotificationSound();
      final icon = _iconForType(type);
      final accent = _colorForType(type);
      InAppBanner.show(
        title: notification.title,
        message: notification.message,
        icon: icon,
        accentColor: accent,
        onTap: () {
          if (type == 'meeting') {
            ref.read(meetingsUnreadProvider.notifier).clear();
          }
          navigateToAction(notification.actionUrl);
        },
      );
    }

    // Meetings tab dot: a fresh meeting invite lights the badge up
    if (type == 'meeting') {
      ref.read(meetingsUnreadProvider.notifier).increment();
    }
  }

  /// Route to a sensible screen for the notification. Only in-app
  /// "/main/..." locations are routable on mobile; anything else (web-only
  /// urls like "/calls/<code>") falls back to the notifications screen.
  void navigateToAction(String? actionUrl) {
    final target = (actionUrl != null && actionUrl.startsWith('/main/'))
        ? actionUrl
        : '/main/notifications';
    final context = navigatorKey.currentContext;
    if (context == null) return;
    try {
      GoRouter.of(context).go(target);
    } catch (e) {
      debugPrint('Notification navigation failed: $e');
    }
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'meeting':
        return Icons.calendar_month_rounded;
      case 'call':
        return Icons.videocam_rounded;
      case 'task':
        return Icons.check_circle_outline_rounded;
      case 'credit':
        return Icons.south_west_rounded;
      case 'debit':
        return Icons.north_east_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  static Color? _colorForType(String type) {
    switch (type) {
      case 'meeting':
        return AppColors.primary;
      case 'call':
        return AppColors.warning;
      case 'credit':
        return AppColors.success;
      case 'debit':
        return AppColors.error;
      default:
        return null;
    }
  }

  Future<void> markAsRead(String id) async {
    try {
      await _apiService.markNotificationAsRead(id);
      final updatedNotifications = state.notifications.map((n) {
        if (n.id == id) {
          return n.copyWith(isRead: true);
        }
        return n;
      }).toList();
      final updatedUnreadCount = updatedNotifications.where((n) => !n.isRead).length;
      state = state.copyWith(
        notifications: updatedNotifications,
        unreadCount: updatedUnreadCount,
      );
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      await _apiService.markAllNotificationsAsRead();
      final updatedNotifications = state.notifications.map((n) => n.copyWith(isRead: true)).toList();
      state = state.copyWith(
        notifications: updatedNotifications,
        unreadCount: 0,
      );
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
    }
  }

  Future<void> takeAction(String id, String action) async {
    try {
      final response = await _apiService.takeNotificationAction(id, action);
      final data = response.data;
      if (data['success'] == true) {
        final updatedNotification = AppNotification.fromJson(Map<String, dynamic>.from(data['data']));
        final updatedNotifications = state.notifications.map((n) {
          if (n.id == id) {
            return updatedNotification;
          }
          return n;
        }).toList();
        final updatedUnreadCount = updatedNotifications.where((n) => !n.isRead).length;
        state = state.copyWith(
          notifications: updatedNotifications,
          unreadCount: updatedUnreadCount,
        );
      }
    } catch (e) {
      debugPrint('Error taking notification action: $e');
    }
  }
}
