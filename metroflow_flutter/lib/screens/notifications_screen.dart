import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/notifications_provider.dart';
import '../models/notification.dart';
import '../theme/app_theme.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).fetchNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final colors = AppTheme.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: const Text('Notifications'),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () {
                ref.read(notificationsProvider.notifier).markAllAsRead();
              },
              child: const Text('Mark all as read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(notificationsProvider.notifier).fetchNotifications();
        },
        child: Builder(
          builder: (context) {
            if (state.isLoading && state.notifications.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(state.error!),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        ref.read(notificationsProvider.notifier).fetchNotifications();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            if (state.notifications.isEmpty) {
              return const Center(child: Text('No notifications yet'));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.notifications.length,
              itemBuilder: (context, index) {
                final notification = state.notifications[index];
                return _NotificationCard(
                  notification: notification,
                  onMarkAsRead: () {
                    ref.read(notificationsProvider.notifier).markAsRead(notification.id);
                  },
                  onAction: (action) {
                    ref.read(notificationsProvider.notifier).takeAction(notification.id, action);
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onMarkAsRead;
  final Function(String) onAction;

  const _NotificationCard({
    required this.notification,
    required this.onMarkAsRead,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final isUnread = !notification.isRead;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUnread ? colors.primary.withValues(alpha: 0.05) : colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _getIconColor(notification.type),
                  shape: BoxShape.circle,
                ),
                child: Icon(_getIcon(notification.type), color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isUnread ? FontWeight.bold : FontWeight.w500,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatDate(notification.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          if (isUnread || notification.isActionable) const SizedBox(height: 12),
          Row(
            children: [
              if (isUnread)
                TextButton(
                  onPressed: onMarkAsRead,
                  child: const Text('Mark as read'),
                ),
              if (notification.isActionable && notification.actionType != null) ...[
                const Spacer(),
                if (notification.actionType == 'accept_call' || notification.actionType == 'decline_call') ...[
                  OutlinedButton(
                    onPressed: () => onAction('decline'),
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => onAction('accept'),
                    child: const Text('Accept'),
                  ),
                ] else if (notification.actionUrl != null)
                  ElevatedButton(
                    onPressed: () => onAction('view'),
                    child: const Text('View'),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'meeting':
        return Icons.calendar_today;
      case 'task':
        return Icons.task_alt;
      case 'chat':
        return Icons.chat;
      case 'call':
        return Icons.call;
      case 'credit':
        return Icons.attach_money;
      case 'debit':
        return Icons.money_off;
      default:
        return Icons.notifications;
    }
  }

  Color _getIconColor(String type) {
    switch (type) {
      case 'meeting':
        return AppColors.primary;
      case 'task':
        return Colors.blue;
      case 'chat':
        return Colors.green;
      case 'call':
        return Colors.orange;
      case 'credit':
        return AppColors.success;
      case 'debit':
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }
}
