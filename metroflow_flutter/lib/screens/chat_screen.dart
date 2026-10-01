import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/api.dart';
import '../services/app_badge_service.dart';
import '../services/socket_service.dart';
import '../models/conversation.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';
import '../providers/auth_provider.dart';
import '../providers/badge_provider.dart';
import '../widgets/modern_ui.dart';
import '../widgets/metric_ai_logo.dart';
import 'chat_detail_screen.dart';

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
  List<User> _teamMembers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  late final void Function(dynamic) _conversationCreatedHandler;

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
    _socket.onConversationCreated = _conversationCreatedHandler;
  }

  @override
  void dispose() {
    if (_socket.onConversationCreated == _conversationCreatedHandler) {
      _socket.onConversationCreated = null;
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
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
      }
    } catch (e) {
      Logger.error('Error loading conversations: $e');
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
        setState(() {
          _teamMembers = data
              .whereType<Map>()
              .map((json) => User.fromJson(Map<String, dynamic>.from(json)))
              .toList();
        });
      }
    } catch (e) {
      Logger.error('Error loading team members: $e');
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
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadConversations,
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
                                itemCount: filtered.length + 1,
                                separatorBuilder: (context, index) => const SizedBox(height: 4),
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return _MetricAiEntry(colors: colors);
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

  const _ConversationTile({
    required this.conversation,
    required this.name,
    required this.timeLabel,
    required this.hasUnread,
    this.unreadCount = 0,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPreview = (conversation.lastMessage ?? '').isNotEmpty;
    final preview = conversation.lastMessage ?? 'No messages yet';
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
                      child: Text(
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
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final List<String> _selectedMemberIds = [];
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createConversation() async {
    if (_selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one member')),
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      final type = _selectedMemberIds.length == 1 ? 'direct' : 'group';
      final response = await _api.createConversation({
        if (type == 'group' && _nameController.text.isNotEmpty) 'name': _nameController.text,
        'type': type,
        'participant_ids': _selectedMemberIds,
      });
      if (response.data['success'] == true) {
        final responseData = response.data['data'];
        if (responseData is! Map) {
          throw const FormatException('Invalid conversation response');
        }
        final conversation = Conversation.fromJson(Map<String, dynamic>.from(responseData));
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
    final availableMembers = widget.teamMembers.where((m) => m.id != widget.currentUserId).toList();
    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Text('New Conversation'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (availableMembers.length > 1)
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name (optional)',
                    hintText: 'e.g. Project Team',
                  ),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select Participants:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableMembers.length,
                  itemBuilder: (context, index) {
                    final member = availableMembers[index];
                    final isSelected = _selectedMemberIds.contains(member.id);
                    return CheckboxListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      title: Text(
                        member.name,
                        style: TextStyle(color: colors.text),
                      ),
                      subtitle: Text(
                        member.email,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedMemberIds.add(member.id);
                          } else {
                            _selectedMemberIds.remove(member.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
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
