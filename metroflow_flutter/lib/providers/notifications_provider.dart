import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
import 'auth_provider.dart';

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
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void _addNotification(AppNotification notification) {
    final updatedNotifications = [notification, ...state.notifications];
    final updatedUnreadCount = state.unreadCount + (notification.isRead ? 0 : 1);
    state = state.copyWith(
      notifications: updatedNotifications,
      unreadCount: updatedUnreadCount,
    );
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
