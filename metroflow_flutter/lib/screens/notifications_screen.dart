import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/notifications_provider.dart';
import '../models/notification.dart';
import '../theme/app_theme.dart';

/// Deep-link map for in-app notification taps.
///
/// The backend stores web-style actionUrls ("/wallet", "/calls/{code}",
/// "/meetings/{code}", "/subscriptions", "/invoices", "/bills",
/// "/savings"). Mobile uses the `/main/...` shell, so every tap is routed
/// by (a) the notification type first, then (b) the stored actionUrl —
/// falling back to the dashboard when the target screen does not exist on
/// mobile. Mirrors the push-tap routing in PushNotificationService.
void _navigateForNotification(BuildContext context, AppNotification notification) {
  final actionUrl = notification.actionUrl ?? '';
  final type = notification.type.toLowerCase();

  String target;
  if (type == 'chat' || type == 'chat_message' || actionUrl.startsWith('/chat')) {
    target = '/main/chat';
  } else if (type == 'call' ||
      type == 'missed_call' ||
      type == 'incoming_call' ||
      actionUrl.startsWith('/calls')) {
    target = '/main/calls';
  } else if (type == 'meeting' || actionUrl.startsWith('/meetings')) {
    target = '/main/meetings';
  } else if (type == 'task' || type == 'assignment' || actionUrl.startsWith('/tasks')) {
    target = '/main/board';
  } else if (type == 'invoice' || actionUrl.startsWith('/invoices')) {
    target = '/main/invoices';
  } else if (actionUrl.startsWith('/subscriptions')) {
    target = '/main/subscriptions';
  } else if (type == 'credit' ||
      type == 'debit' ||
      type == 'reversal' ||
      type == 'transfer' ||
      type == 'transaction' ||
      actionUrl.startsWith('/wallet') ||
      actionUrl.startsWith('/transactions') ||
      actionUrl.startsWith('/transfers')) {
    // Wallet money movement (credits, debits, reversals) — the transfers
    // screen is the mobile transaction history.
    target = '/main/transfers';
  } else {
    // Bills, savings and any other web-only destinations land on the
    // dashboard instead of doing nothing.
    target = '/main';
  }

  try {
    GoRouter.of(context).go(target);
  } catch (e) {
    debugPrint('Notification navigation failed: $e');
  }
}

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
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 56,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Couldn\'t load notifications',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ref.read(notificationsProvider.notifier).fetchNotifications();
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
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
                  onTap: () {
                    // Tapping a notification: mark it read and deep-link to
                    // the relevant screen (chat, calls, meetings, wallet…).
                    if (!notification.isRead) {
                      ref.read(notificationsProvider.notifier).markAsRead(notification.id);
                    }
                    _navigateForNotification(context, notification);
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
  final VoidCallback? onTap;

  const _NotificationCard({
    required this.notification,
    required this.onMarkAsRead,
    required this.onAction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final isUnread = !notification.isRead;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUnread ? colors.primary.withValues(alpha: 0.05) : colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
      ),
      ),
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
