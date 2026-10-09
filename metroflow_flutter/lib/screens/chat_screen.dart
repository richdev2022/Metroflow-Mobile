import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/api.dart';
import '../services/app_badge_service.dart';
import '../services/socket_service.dart';
import '../models/conversation.dart';
import '../widgets/chat_status.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../utils/app_timezone.dart';
import '../utils/app_toast.dart';
import '../utils/logger.dart';
import '../providers/auth_provider.dart';
import '../providers/badge_provider.dart';
import '../widgets/modern_ui.dart';
import '../widgets/metric_ai_logo.dart';
import '../widgets/avatar_with_initials.dart';
import 'chat_detail_screen.dart';

/// Pretty preview for a conversation's last message when the latest row is a
/// CALL LOG system message (a JSON blob in `content`). Raw JSON must never
/// leak into the chat list — format it as "📞 Voice call · 1m 5s" etc., the
/// same shape the backend preview formatter produces.
String? _formatLastMessagePreview(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (!trimmed.startsWith('{') || !trimmed.contains('callType')) return trimmed.isEmpty ? null : trimmed;
  try {
    final meta = jsonDecode(trimmed);
    if (meta is! Map || meta['callType'] is! String) return trimmed;
    final isVideo = meta['callType'] == 'video';
    final icon = isVideo ? '📹' : '📞';
    final label = isVideo ? 'Video call' : 'Voice call';
    final status = String(meta['status'] ?? '').toLowerCase();
    final duration = int.tryParse('${meta['durationSeconds'] ?? 0}') ?? 0;
    String detail;
    if (status == 'missed') {
      detail = ' · Missed';
    } else if (status == 'declined') {
      detail = ' · Declined';
    } else if (status == 'cancelled' || status == 'canceled') {
      detail = ' · Cancelled';
    } else if (duration > 0) {
      final m = duration ~/ 60;
      final s = duration % 60;
      detail = ' · ${m}m ${s}s';
    } else {
      detail = '';
    }
    return '$icon $label$detail';
  } catch (_) {
    return trimmed;
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();
  final TextEditingController _searchController = TextEditingController();
  List<Conversation> _conversations = [];
  // Invited (guest) contacts — people brought in by email who have not
  // registered yet. Rendered in the list with an "Invited" badge.
  List<Map<String, dynamic>> _guestContacts = [];
  /// Bumped whenever a status is created/deleted so the ChatStatusRail refetches.
  int _statusRefreshKey = 0;
  List<User> _teamMembers = [];
  bool _isLoading = true;
  String? _loadError;
  String _searchQuery = '';
  late final void Function(dynamic) _conversationCreatedHandler;

  // WhatsApp-style typing presence (chat:typing-updated → user room):
  // conversationId -> display name of the peer who is typing. Each entry
  // auto-clears 4s after its last update, so a lost `isTyping: false` (old
  // emitter, dropped packet, app kill) can never leave a stuck indicator.
  final Map<String, String> _typingNames = {};
  final Map<String, Timer> _typingTimers = {};
  late final void Function(dynamic) _typingUpdatedHandler;
  late final void Function(dynamic) _messageCreatedHandler;

  /// ChatDetailScreen owns the SAME onMessageCreated socket slot while it is
  /// open (single-slot handlers) and nulls it on dispose — re-attach our
  /// handlers whenever we come back so the list keeps live-updating.
  void _registerSocketHandlers() {
    _socket.onConversationCreated = _conversationCreatedHandler;
    _socket.onMessageCreated = _messageCreatedHandler;
  }

  void _handleMessageCreated(dynamic data) {
    if (!mounted) return;
    if (data is! Map) return;
    final conversationId = data['conversationId']?.toString() ??
        data['conversation_id']?.toString() ?? '';
    if (conversationId.isEmpty) return;
    final index = _conversations.indexWhere((item) => item.id == conversationId);
    if (index == -1) return; // unknown conversation — full refetch will pick it up
    // Derive the same preview the backend lastMessage CASE produces.
    final deleted = data['deletedForEveryone'] == true || data['deleted_for_everyone'] == true;
    final content = (data['content'] ?? '').toString().trim();
    final attachmentType = (data['attachmentType'] ?? data['attachment_type'] ?? '').toString();
    final attachmentUrl = data['attachmentUrl'] ?? data['attachment_url'];
    final attachmentName = (data['attachmentName'] ?? data['attachment_name'] ?? '').toString();
    String preview;
    if (deleted) {
      preview = 'This message was deleted';
    } else if (content.isNotEmpty) {
      preview = content;
    } else if (attachmentType == 'image') {
      preview = '📷 Photo';
    } else if (attachmentType == 'video') {
      preview = '🎬 Video';
    } else if (attachmentType == 'audio') {
      preview = '🎤 Voice note';
    } else if (attachmentType == 'sticker') {
      preview = 'Sticker';
    } else if (attachmentType == 'gif') {
      preview = 'GIF';
    } else if (attachmentUrl != null) {
      preview = attachmentName.isNotEmpty ? '📎 $attachmentName' : '📎 Attachment';
    } else {
      preview = 'Message';
    }
    final currentUserId = ref.read(authProvider).userId;
    final senderId = (data['senderId'] ?? data['sender_id'] ?? '').toString();
    setState(() {
      final conv = _conversations[index];
      final fromOther = senderId.isNotEmpty && senderId != currentUserId;
      final lastAt = DateTime.tryParse((data['createdAt'] ?? data['created_at'] ?? '').toString())?.toLocal();
      _conversations[index] = Conversation(
        id: conv.id,
        name: conv.name,
        type: conv.type,
        createdBy: conv.createdBy,
        createdAt: conv.createdAt,
        updatedAt: DateTime.now(),
        participants: conv.participants,
        lastMessage: preview,
        lastMessageAt: lastAt ?? conv.lastMessageAt,
        lastMessageSenderId: senderId.isNotEmpty ? senderId : conv.lastMessageSenderId,
        unreadCount: fromOther ? conv.unreadCount + 1 : conv.unreadCount,
        isGroupFlag: conv.isGroupFlag,
        displayName: conv.displayName,
        displayAvatarUrl: conv.displayAvatarUrl,
        otherUserLastSeenAt: conv.otherUserLastSeenAt,
        otherUserPresenceStatus: conv.otherUserPresenceStatus,
      );
      // Most-recent-first, like the server ordering.
      final updated = _conversations.removeAt(index);
      _conversations.insert(0, updated);
      // Keep the launcher badge in sync while the hub is open.
      final totalUnread = _conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
      ref.read(chatUnreadProvider.notifier).set(totalUnread);
    });
  }

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _loadTeamMembers();
    // Opening the chat hub means the user is catching up — clear the
    // Facebook-style launcher badge (per-conversation dots stay in-app).
    AppBadgeService.instance.clear();
    _conversationCreatedHandler = (data) {
      if (!mounted) return;
      if (data is! Map) return;
      final conversation = Conversation.fromJson(Map<String, dynamic>.from(data));
      setState(() {
        final index = _conversations.indexWhere((item) => item.id == conversation.id);
        if (index == -1) {
          _conversations.insert(0, conversation);
        } else {
          _conversations[index] = conversation;
        }
      });
    };
    _messageCreatedHandler = _handleMessageCreated;
    _registerSocketHandlers();
    // Typing presence — same pattern as the other chat listeners: assign a
    // stored handler here and unregister the exact instance in dispose.
    _typingUpdatedHandler = _handleTypingUpdated;
    _socket.onChatTypingUpdated = _typingUpdatedHandler;
    // Deep link from a chat push tap: open the exact conversation once the
    // list arrives (see ChatDetailScreen.pendingOpenConversationId, set by
    // the push notification tap handler).
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingDeepLink());
  }

  /// Deep-link consumption, in priority order:
  /// 1. [ChatDetailScreen.pendingChatJoinCode] — group invite
  ///    (metricorex://chat/join/<code> or a chat_invite push tap): POST
  ///    /chat/join/<code> then open the returned (fully-hydrated) group.
  /// 2. [ChatDetailScreen.pendingOpenConversationId] — chat push tap: open
  ///    the exact conversation once the list arrives.
  void _consumePendingDeepLink() {
    final joinCode = ChatDetailScreen.pendingChatJoinCode;
    if (joinCode != null && joinCode.isNotEmpty) {
      if (_isLoading) {
        // List still loading — retry shortly (same pattern as below).
        Future.delayed(const Duration(milliseconds: 400), _consumePendingDeepLink);
        return;
      }
      ChatDetailScreen.pendingChatJoinCode = null;
      _joinByInviteCode(joinCode);
      return;
    }
    final pendingId = ChatDetailScreen.pendingOpenConversationId;
    if (pendingId == null || pendingId.isEmpty) return;
    if (_isLoading) {
      // List still loading — retry shortly.
      Future.delayed(const Duration(milliseconds: 400), _consumePendingDeepLink);
      return;
    }
    ChatDetailScreen.pendingOpenConversationId = null;
    final match = _conversations.where((c) => c.id == pendingId).toList();
    if (!mounted || match.isEmpty) return; // unknown/stale conversation — list view is fine
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatDetailScreen(conversation: match.first)),
    ).then((_) {
      _registerSocketHandlers();
      _loadConversations();
    });
  }

  /// POST /chat/join/<code> (silent) → navigate into the returned group.
  /// Failures surface the server message (invalid/expired link,
  /// wrong-workspace, …) as an error toast — the list view stays.
  Future<void> _joinByInviteCode(String code) async {
    try {
      final response = await _api.joinChatByInvite(code);
      if (response.data['success'] != true) {
        throw FormatException(
            (response.data['error'] ?? 'Couldn\'t join this group').toString());
      }
      final responseData = response.data['data'];
      if (responseData is! Map) {
        throw const FormatException('Invalid join response');
      }
      final conversation =
          Conversation.fromJson(Map<String, dynamic>.from(responseData));
      if (!mounted) return;
      // Refresh the list in the background so the joined group appears
      // behind the pushed detail screen.
      unawaited(_loadConversations());
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatDetailScreen(conversation: conversation)),
      ).then((_) {
        _registerSocketHandlers();
        _loadConversations();
      });
    } catch (e) {
      Logger.error('joinChatByInvite failed: $e');
      if (mounted) {
        AppToast.show(
          e is FormatException && e.message.isNotEmpty
              ? e.message
              : ApiService.extractErrorMessage(e),
          type: AppToastType.error,
        );
      }
    }
  }

  @override
  void dispose() {
    if (_socket.onConversationCreated == _conversationCreatedHandler) {
      _socket.onConversationCreated = null;
    }
    if (_socket.onMessageCreated == _messageCreatedHandler) {
      _socket.onMessageCreated = null;
    }
    if (_socket.onChatTypingUpdated == _typingUpdatedHandler) {
      _socket.onChatTypingUpdated = null;
    }
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _searchController.dispose();
    super.dispose();
  }

  /// `chat:typing-updated` → { conversationId, userId, name, isTyping, ts }.
  /// Own events are skipped (the server excludes the emitter's user room,
  /// but the guard also covers local echoes / same-account multi-device).
  void _handleTypingUpdated(dynamic data) {
    if (!mounted || data is! Map) return;
    final payload = Map<String, dynamic>.from(data);
    final conversationId = (payload['conversationId'] ?? '').toString();
    if (conversationId.isEmpty) return;
    final senderId = (payload['userId'] ?? payload['user_id'] ?? '').toString();
    final currentUserId = ref.read(authProvider).userId;
    if (senderId.isNotEmpty && senderId == currentUserId) return;

    final isTyping = payload['isTyping'] == true;
    if (!isTyping) {
      _clearTyping(conversationId);
      return;
    }

    final name = (payload['name'] ?? payload['userName'] ?? 'Someone').toString();
    _typingTimers[conversationId]?.cancel();
    setState(() => _typingNames[conversationId] = name);
    // Auto-clear 4s after the LAST update (WhatsApp behaviour — typing
    // indicators are ephemeral and must never stick).
    _typingTimers[conversationId] = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _typingNames.remove(conversationId));
      _typingTimers.remove(conversationId);
    });
  }

  void _clearTyping(String conversationId) {
    if (!_typingNames.containsKey(conversationId)) return;
    _typingTimers.remove(conversationId)?.cancel();
    if (mounted) {
      setState(() => _typingNames.remove(conversationId));
    }
  }

  /// Tile subtitle for a conversation with an active typing flag:
  /// direct chats show "typing…", groups "`<First name>` is typing…".
  String? _typingLabelFor(Conversation conversation) {
    final name = _typingNames[conversation.id];
    if (name == null) return null;
    final isGroup = conversation.type == 'group';
    if (!isGroup) return 'typing…';
    final firstName = name.trim().split(RegExp(r'\s+')).first;
    return '$firstName is typing…';
  }

  Future<void> _loadGuestContacts() async {
    try {
      final res = await _api.getChatGuestContacts();
      final data = res.data is Map ? res.data['data'] : null;
      final contacts = data is Map && data['contacts'] is List ? data['contacts'] as List : const [];
      if (!mounted) return;
      setState(() {
        _guestContacts = contacts
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      // Non-fatal — the invited strip simply stays hidden.
    }
  }

  /// Bump the status rail's refresh key (pull-to-refresh + after composing).
  Future<void> _refreshStatuses() async {
    if (!mounted) return;
    setState(() => _statusRefreshKey++);
  }

  Future<void> _loadConversations() async {
    setState(() => _loadError = null);
    try {
      final response = await _api.getConversations();
      if (response.data['success'] == true) {
        if (!mounted) return;
        final responseData = response.data['data'];
        final data = responseData is Map && responseData['conversations'] is List
            ? responseData['conversations'] as List
            : responseData is List
                ? responseData
                : <dynamic>[];
        setState(() {
          _conversations = data
              .whereType<Map>()
              .map((json) => Conversation.fromJson(Map<String, dynamic>.from(json)))
              .toList();
        });
        // Re-sync the bottom-nav chat badge with server truth
        final totalUnread = _conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
        ref.read(chatUnreadProvider.notifier).set(totalUnread);
        // Invited (guest) contacts ride along — a failure is non-fatal.
        _loadGuestContacts();
      } else {
        if (!mounted) return;
        setState(() => _loadError = 'Couldn\'t load conversations');
      }
    } catch (e) {
      Logger.error('Error loading conversations: $e');
      // Surface the failure — a silent empty list made users think their
      // chats disappeared (or showed stale socket-only rows as "No messages
      // yet") whenever the request failed.
      if (!mounted) return;
      setState(() => _loadError = ApiService.extractErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadTeamMembers() async {
    try {
      final response = await _api.getTeam();
      if (response.data['success'] == true) {
        if (!mounted) return;
        final data = response.data['data'] is List ? response.data['data'] as List : <dynamic>[];
        // Per-row tolerant parse: ONE malformed row must never blank the
        // whole participant picker again (the old all-or-nothing .map left
        // the New-Conversation dialog empty whenever any row failed).
        final members = <User>[];
        for (final row in data) {
          if (row is! Map) continue;
          try {
            members.add(User.fromJson(Map<String, dynamic>.from(row)));
          } catch (rowError) {
            Logger.error('Skipping malformed team member row: $rowError');
          }
        }
        if (!mounted) return;
        setState(() => _teamMembers = members);
      }
    } catch (e) {
      Logger.error('Error loading team members: $e');
      if (!mounted) return;
      // Surface the failure instead of leaving a silently-empty picker.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t load teammates: ${ApiService.extractErrorMessage(e)}')),
      );
    }
  }

  Future<void> _showCreateConversationDialog() async {
    final authState = ref.read(authProvider);
    showDialog(
      context: context,
      builder: (context) => _CreateConversationDialog(
        teamMembers: _teamMembers,
        currentUserId: authState.userId,
        onCreated: (conversation) {
          _loadConversations();
        },
      ),
    );
  }

  List<Conversation> get _filteredConversations {
    if (_searchQuery.trim().isEmpty) return _conversations;
    final query = _searchQuery.trim().toLowerCase();
    final currentUserId = ref.read(authProvider).userId;
    return _conversations.where((conversation) {
      final name = conversation.displayTitle(currentUserId).toLowerCase();
      final preview = (conversation.lastMessage ?? '').toLowerCase();
      return name.contains(query) || preview.contains(query);
    }).toList();
  }

  bool _hasUnread(Conversation conversation, String? currentUserId) {
    if (currentUserId == null || currentUserId.isEmpty) return false;
    final lastAt = conversation.lastMessageAt;
    if (lastAt == null) return false;
    ConversationParticipant? mine;
    for (final participant in conversation.participants) {
      if (participant.userId == currentUserId) {
        mine = participant;
        break;
      }
    }
    if (mine == null) return false;
    final lastRead = mine.lastReadAt;
    return lastRead == null || lastAt.isAfter(lastRead);
  }

  String _timeLabel(DateTime time) {
    final tz = AppTimezone.instance;
    final now = tz.todayKey();
    final messageDay = tz.dateKeyIn(time);
    if (messageDay == now) {
      return tz.formatTime(time);
    }
    if (messageDay.year == now.year) {
      return tz.formatDateShort(time);
    }
    return tz.formatDate(time);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final authState = ref.watch(authProvider);
    final currentUserId = authState.userId;
    final filtered = _filteredConversations;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: colors.text,
                      ),
                    ),
                  ),
                  if (_conversations.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primaryBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_conversations.length} chats',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ModernSearchField(
                controller: _searchController,
                hintText: 'Search conversations...',
                onChanged: (value) => setState(() => _searchQuery = value),
                onClear: _searchQuery.isEmpty
                    ? null
                    : () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
              ),
            ),
            const SizedBox(height: 8),
            // WHATSAPP-STYLE STATUS RAIL — 24h stories above the chat list.
            // Hidden entirely when the workspace has no active statuses AND
            // loading failed (best-effort surface, chat always works).
            ChatStatusRail(refreshKey: _statusRefreshKey),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([_loadConversations(), _refreshStatuses()]);
                },
                color: colors.primary,
                child: _isLoading
                    ? ListView(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        children: const [
                          SkeletonCard(),
                          SkeletonCard(),
                          SkeletonCard(),
                          SkeletonCard(),
                        ],
                      )
                    : _loadError != null
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
                            children: [
                              _MetricAiEntry(colors: colors),
                              const SizedBox(height: 40),
                              EmptyState(
                                icon: Icons.wifi_off_rounded,
                                title: 'Couldn\'t load conversations',
                                subtitle: _loadError!,
                                actionLabel: 'Retry',
                                onAction: _loadConversations,
                              ),
                            ],
                          )
                        : _conversations.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
                            children: [
                              // Pinned MetricAi entry — visible even with
                              // zero conversations.
                              _MetricAiEntry(colors: colors),
                              const SizedBox(height: 40),
                              EmptyState(
                                icon: Icons.chat_bubble_outline_rounded,
                                title: 'No conversations yet',
                                subtitle: 'Start messaging your team to see conversations here.',
                                actionLabel: 'New Chat',
                                onAction: _showCreateConversationDialog,
                              ),
                            ],
                          )
                        : filtered.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 40),
                                  EmptyState(
                                    icon: Icons.search_off_rounded,
                                    title: 'No matches found',
                                    subtitle:
                                        'Nothing matches "$_searchQuery". Try a different search.',
                                    tint: colors.warning,
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
                                // +1 = the pinned MetricAi entry at the top.
                                // +1 = pinned MetricAi entry, +N = invited
                                // (guest) contacts waiting for registration.
                                itemCount: filtered.length + 1 + _guestContacts.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 4),
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return _MetricAiEntry(colors: colors);
                                  }
                                  final guestIndex = index - 1 - filtered.length;
                                  if (guestIndex >= 0 && guestIndex < _guestContacts.length) {
                                    final guest = _guestContacts[guestIndex];
                                    final email = (guest['email'] ?? '').toString();
                                    return Dismissible(
                                      key: ValueKey('guest-${guest['id']}'),
                                      direction: DismissDirection.endToStart,
                                      background: Container(
                                        alignment: Alignment.centerRight,
                                        padding: const EdgeInsets.only(right: 20),
                                        color: AppColors.error.withValues(alpha: 0.15),
                                        child: const Icon(Icons.delete_outline_rounded,
                                            color: AppColors.error),
                                      ),
                                      onDismissed: (_) async {
                                        setState(() => _guestContacts.removeAt(guestIndex));
                                        try {
                                          await _api.deleteChatGuestContact(
                                              guest['id']?.toString() ?? '');
                                        } catch (_) {}
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: colors.surface,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: colors.border),
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor:
                                                  colors.surfaceVariant,
                                              child: Icon(Icons.person_add_alt_rounded,
                                                  size: 18,
                                                  color: colors.textSecondary),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(email,
                                                            maxLines: 1,
                                                            overflow: TextOverflow
                                                                .ellipsis,
                                                            style: TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: colors
                                                                    .text)),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 6,
                                                            vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                              0xFFFEF3C7),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(999),
                                                        ),
                                                        child: const Text(
                                                            'Invited',
                                                            style: TextStyle(
                                                                fontSize: 9.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: Color(
                                                                    0xFF92400E))),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                      'Waiting for them to join Metricorex',
                                                      style: TextStyle(
                                                          fontSize: 11.5,
                                                          color: colors
                                                              .textSecondary)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                  final conversation = filtered[index - 1];
                                  // Real display name: backend displayName ->
                                  // other participant's name -> group name.
                                  // NEVER show "Direct Chat" placeholders.
                                  final name = conversation.displayTitle(currentUserId);
                                  final hasUnread = conversation.unreadCount > 0 ||
                                      _hasUnread(conversation, currentUserId);
                                  return _ConversationTile(
                                    conversation: conversation,
                                    name: name,
                                    timeLabel: conversation.lastMessageAt != null
                                        ? _timeLabel(conversation.lastMessageAt!)
                                        : null,
                                    hasUnread: hasUnread,
                                    unreadCount: conversation.unreadCount,
                                    colors: colors,
                                    typingLabel: _typingLabelFor(conversation),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ChatDetailScreen(conversation: conversation),
                                        ),
                                      ).then((_) => _loadConversations());
                                    },
                                  );
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: ModernFab(
        icon: Icons.add_comment_outlined,
        label: 'New Chat',
        onPressed: _showCreateConversationDialog,
      ),
    );
  }
}

/// Pinned first entry of the chat list: the MetricAi assistant with its
/// glowing animated logo (indigo -> blue pulse). Opens the MetricAi screen.
class _MetricAiEntry extends StatelessWidget {
  final ThemeColors colors;

  const _MetricAiEntry({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      onTap: () => GoRouter.of(context).push('/main/metric-ai'),
      child: Row(
        children: [
          const MetricAiGlowLogo(radius: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'MetricAi',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF2563EB)],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'AI',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Your AI assistant',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final String name;
  final String? timeLabel;
  final bool hasUnread;
  final int unreadCount;
  final ThemeColors colors;
  final VoidCallback onTap;

  /// "typing…" / "`<Name>` is typing…" while the peer's typing flag is on —
  /// replaces the last-message preview (WhatsApp behaviour).
  final String? typingLabel;

  const _ConversationTile({
    required this.conversation,
    required this.name,
    required this.timeLabel,
    required this.hasUnread,
    this.unreadCount = 0,
    required this.colors,
    required this.onTap,
    this.typingLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasPreview = (conversation.lastMessage ?? '').isNotEmpty;
    final preview = _formatLastMessagePreview(conversation.lastMessage) ?? 'No messages yet';
    final isGroup = conversation.type == 'group';

    return ModernCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      color: hasUnread ? colors.primaryBg : null,
      borderColor: hasUnread ? colors.primary.withValues(alpha: 0.25) : null,
      onTap: onTap,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AvatarInitials(name: name, radius: 23),
              if (isGroup)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.border),
                    ),
                    child: Icon(Icons.group_rounded,
                        size: 11, color: colors.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ),
                    if (timeLabel != null)
                      Text(
                        timeLabel!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w500,
                          color: hasUnread ? colors.primary : colors.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      // Typing indicator replaces the preview while active —
                      // subtle pulsing "…" in the primary color (WhatsApp
                      // style), animated so it reads as "live presence".
                      child: (typingLabel != null && typingLabel!.isNotEmpty)
                          ? _TypingText(label: typingLabel!, accent: colors.primary)
                          : Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.3,
                                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                                fontStyle: hasPreview ? FontStyle.normal : FontStyle.italic,
                                color: hasUnread ? colors.text.withValues(alpha: 0.85) : colors.textSecondary,
                              ),
                            ),
                    ),
                    if (hasUnread) ...[
                      const SizedBox(width: 8),
                      Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colors.primary, colors.primaryDark],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : (unreadCount > 0 ? '$unreadCount' : 'New'),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "`<label>`" with a gently pulsing trailing "…" — the animated typing
/// indicator used in conversation tiles (subtle fade loop, ~1.4s cycle).
class _TypingText extends StatefulWidget {
  final String label;
  final Color accent;

  const _TypingText({required this.label, required this.accent});

  @override
  State<_TypingText> createState() => _TypingTextState();
}

class _TypingTextState extends State<_TypingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Text(
        widget.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          height: 1.3,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
          color: widget.accent,
        ),
      ),
    );
  }
}

/// "New Chat" flow — mirrors the web app's New Conversation dialog
/// (client/pages/Chat.tsx): the user FIRST picks the conversation type
/// (Direct Message vs Group Chat), groups get a name field, and both types
/// pick participants from a searchable team list. The payload uses the
/// camelCase `participantIds` key the backend reads — the old mobile dialog
/// sent `participant_ids`, which the backend ignored, so every new chat
/// contained only the creator (and the direct-dedupe path crashed with a
/// 500 before the backend normalization fix).
class _CreateConversationDialog extends StatefulWidget {
  final List<User> teamMembers;
  final String? currentUserId;
  final Function(Conversation) onCreated;

  const _CreateConversationDialog({
    required this.teamMembers,
    required this.currentUserId,
    required this.onCreated,
  });

  @override
  State<_CreateConversationDialog> createState() => _CreateConversationDialogState();
}

class _CreateConversationDialogState extends State<_CreateConversationDialog> {
  final ApiService _api = ApiService();
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  String _type = 'direct';
  final List<String> _selectedMemberIds = [];
  bool _isCreating = false;

  // ---- Add anyone by email: the search field doubles as an email resolver.
  // Typing a full email that matches NO teammate triggers a debounced lookup:
  // registered members select for a normal DM, unknown emails offer Invite
  // (guest contact + invite email, "Invited" badge in the chat list).
  Timer? _lookupDebounce;
  Map<String, dynamic>? _emailLookup;
  bool _lookupLoading = false;
  bool _inviting = false;

  bool get _searchLooksLikeEmail =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
          .hasMatch(_searchController.text.trim().toLowerCase());

  void _onSearchChanged(String value) {
    setState(() {});
    _lookupDebounce?.cancel();
    _emailLookup = null;
    if (!_searchLooksLikeEmail) return;
    _lookupDebounce = Timer(const Duration(milliseconds: 400), _lookupEmail);
  }

  Future<void> _lookupEmail() async {
    final email = _searchController.text.trim().toLowerCase();
    setState(() => _lookupLoading = true);
    try {
      final res = await _api.lookupChatContact(email);
      final data = res.data is Map ? res.data['data'] : null;
      if (!mounted) return;
      setState(() => _emailLookup = data is Map ? Map<String, dynamic>.from(data) : null);
    } catch (_) {
      if (mounted) setState(() => _emailLookup = null);
    } finally {
      if (mounted) setState(() => _lookupLoading = false);
    }
  }

  Future<void> _inviteGuest() async {
    final email = _searchController.text.trim().toLowerCase();
    if (_inviting) return;
    setState(() => _inviting = true);
    try {
      final res = await _api.inviteChatContact(email);
      final ok = res.data is Map && res.data['success'] == true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ok
                ? (res.data['message']?.toString() ?? 'Invitation sent')
                : ApiService.extractErrorMessage(res))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.extractErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<User> get _availableMembers =>
      widget.teamMembers.where((m) => m.id != widget.currentUserId).toList();

  List<User> get _filteredMembers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _availableMembers;
    return _availableMembers
        .where((m) =>
            m.name.toLowerCase().contains(query) ||
            m.email.toLowerCase().contains(query))
        .toList();
  }

  void _toggleMember(String id) {
    setState(() {
      if (_type == 'direct') {
        // Direct chat: exactly ONE participant — re-tap selects the other
        // person (radio behaviour, like the web Select + single-pick flow).
        _selectedMemberIds
          ..clear()
          ..add(id);
      } else {
        if (_selectedMemberIds.contains(id)) {
          _selectedMemberIds.remove(id);
        } else {
          _selectedMemberIds.add(id);
        }
      }
    });
  }

  Future<void> _createConversation() async {
    if (_selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_type == 'direct'
              ? 'Please select a teammate to chat with'
              : 'Please select at least one participant'),
        ),
      );
      return;
    }
    if (_type == 'group' && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please give your group a name')),
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      final response = await _api.createConversation({
        if (_type == 'group') 'name': _nameController.text.trim(),
        'type': _type,
        // camelCase matches the backend contract (snake_case kept for older
        // deployed backends that were taught the other spelling).
        'participantIds': _selectedMemberIds,
        'participant_ids': _selectedMemberIds,
      });
      if (response.data['success'] == true) {
        final responseData = response.data['data'];
        if (responseData is! Map) {
          throw const FormatException('Invalid conversation response');
        }
        Conversation conversation =
            Conversation.fromJson(Map<String, dynamic>.from(responseData));
        widget.onCreated(conversation);
        if (mounted) {
          final navigator = Navigator.of(context, rootNavigator: true);
          navigator.pop();
          // Refresh the list after returning from the pushed chat detail.
          // (Routed through the parent's onCreated callback which calls
          // _loadConversations() on the owning screen state.)
          navigator
              .push(
                MaterialPageRoute(
                  builder: (context) => ChatDetailScreen(conversation: conversation),
                ),
              )
              .then((_) => widget.onCreated(conversation));
        }
      }
    } catch (e) {
      Logger.error('Error creating conversation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final availableMembers = _availableMembers;
    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Text('New Conversation'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Step 1: conversation type (web parity: the Type Select) --
            Text(
              'Type',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TypeCard(
                    icon: Icons.person_outline_rounded,
                    label: 'Direct Message',
                    selected: _type == 'direct',
                    colors: colors,
                    onTap: () => setState(() {
                      _type = 'direct';
                      // Switching to direct keeps at most one selection.
                      if (_selectedMemberIds.length > 1) {
                        _selectedMemberIds.removeRange(1, _selectedMemberIds.length);
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TypeCard(
                    icon: Icons.group_outlined,
                    label: 'Group Chat',
                    selected: _type == 'group',
                    colors: colors,
                    onTap: () => setState(() => _type = 'group'),
                  ),
                ),
              ],
            ),
            // -- Step 2: group name (group only, required) --
            if (_type == 'group') ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Group Name',
                  hintText: 'e.g. Project Team',
                ),
              ),
            ],
            const SizedBox(height: 14),
            // -- Step 3: participants (searchable, chips for selection) --
            Row(
              children: [
                Text(
                  _type == 'direct' ? 'Select teammate' : 'Select participants',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
                const Spacer(),
                if (_selectedMemberIds.isNotEmpty)
                  Text(
                    _type == 'direct'
                        ? '1 selected'
                        : '${_selectedMemberIds.length} selected',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_selectedMemberIds.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in _selectedMemberIds)
                    _ParticipantChip(
                      member: _availableMembers.where((m) => m.id == id).firstOrNull,
                      colors: colors,
                      onRemove: () => setState(() => _selectedMemberIds.remove(id)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: colors.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search team members or add by email...',
                hintStyle: TextStyle(color: colors.textSecondary, fontSize: 13.5),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 20, color: colors.textSecondary),
                isDense: true,
                filled: true,
                fillColor: colors.surfaceVariant,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            // Email lookup row — appears when the search text is an email
            // that did not match any teammate.
            if (_searchLooksLikeEmail) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _lookupLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : _emailLookup == null
                        ? Text('Checking…',
                            style: TextStyle(fontSize: 12.5, color: colors.textSecondary))
                        : (_emailLookup!['registered'] == true
                            ? Builder(builder: (context) {
                                final lookupName =
                                    (_emailLookup?['name'] ?? 'user').toString();
                                return Row(children: [
                                Expanded(
                                  child: Text(
                                    'Registered: $lookupName',
                                    style: TextStyle(fontSize: 12.5, color: colors.text),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _toggleMember(
                                      _emailLookup!['userId']?.toString() ?? ''),
                                  icon: const Icon(Icons.add_rounded, size: 14),
                                  label: const Text('Select',
                                      style: TextStyle(fontSize: 12.5)),
                                  style: TextButton.styleFrom(
                                      foregroundColor: colors.primary,
                                      minimumSize: const Size(0, 30),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8)),
                                ),
                              ]);
                              })
                            : Row(children: [
                                Expanded(
                                  child: Text(
                                    _emailLookup!['invited'] == true
                                        ? 'Already invited — see the Invited badge in your chat list.'
                                        : 'Not on Metricorex yet — guest',
                                    style: TextStyle(
                                        fontSize: 12.5, color: colors.textSecondary),
                                  ),
                                ),
                                if (_emailLookup!['invited'] != true)
                                  TextButton.icon(
                                    onPressed: _inviting ? null : _inviteGuest,
                                    icon: _inviting
                                        ? const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(Icons.send_rounded, size: 13),
                                    label: const Text('Invite',
                                        style: TextStyle(fontSize: 12.5)),
                                    style: TextButton.styleFrom(
                                        foregroundColor: colors.primary,
                                        minimumSize: const Size(0, 30),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8)),
                                  ),
                              ])
              ),
            ),
            ],
            const SizedBox(height: 8),
            Flexible(
              child: availableMembers.isEmpty
                  // Empty state — the picker used to render a silent blank
                  // box here when the team list failed to load or only the
                  // current user exists. Actual explanation + where to go.
                  ? Container(
                      height: 200,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.group_add_rounded, size: 44, color: colors.textSecondary),
                          const SizedBox(height: 12),
                          Text(
                            'No teammates to chat with yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: colors.text),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Invite your team from the More → Team screen, then start a conversation here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12.5, height: 1.4, color: colors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : SizedBox(
                      height: 200,
                      child: _filteredMembers.isEmpty
                          ? Center(
                              child: Text(
                                'No team members found.',
                                style: TextStyle(
                                    fontSize: 13, color: colors.textSecondary),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredMembers.length,
                              itemBuilder: (context, index) {
                                final member = _filteredMembers[index];
                                final isSelected =
                                    _selectedMemberIds.contains(member.id);
                                return _ParticipantTile(
                                  member: member,
                                  isSelected: isSelected,
                                  colors: colors,
                                  onTap: () => _toggleMember(member.id),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isCreating ? null : _createConversation,
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

/// Type chooser card: "Direct Message" vs "Group Chat" (web Type Select).
class _TypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final ThemeColors colors;
  final VoidCallback onTap;

  const _TypeCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? colors.primaryBg : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: selected ? colors.primary : colors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? colors.primary : colors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selected-participant chip with a remove button (web Badge + X pattern).
class _ParticipantChip extends StatelessWidget {
  final User? member;
  final ThemeColors colors;
  final VoidCallback onRemove;

  const _ParticipantChip({
    required this.member,
    required this.colors,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: colors.primaryBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            member?.name ?? 'Member',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(Icons.close_rounded, size: 13, color: colors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Searchable participant row with a check indicator (web CommandItem).
class _ParticipantTile extends StatelessWidget {
  final User member;
  final bool isSelected;
  final ThemeColors colors;
  final VoidCallback onTap;

  const _ParticipantTile({
    required this.member,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            AvatarWithInitials(name: member.name, radius: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  Text(
                    member.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? colors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected ? colors.primary : colors.borderVariant,
                  width: 1.6,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
