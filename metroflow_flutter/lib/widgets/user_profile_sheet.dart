import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../screens/chat_detail_screen.dart';
import '../services/api.dart';
import '../models/conversation.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/logger.dart';
import 'avatar_with_initials.dart';
import 'modern_ui.dart';

/// One chat member (parsed straight from the conversation `participants`
/// list, which the backend enriches with the user's name/email/avatarUrl).
class ChatUserProfile {
  final String userId;
  final String name;
  final String email;
  final String? avatarUrl;
  final String? role;

  const ChatUserProfile({
    required this.userId,
    required this.name,
    this.email = '',
    this.avatarUrl,
    this.role,
  });

  String get displayName => name.trim().isEmpty ? 'Team member' : name.trim();

  /// Title-cased role label (admin/owner/member…), null when unknown.
  String? get roleLabel {
    final raw = (role ?? '').trim();
    if (raw.isEmpty) return null;
    if (raw.length <= 1) return null;
    return raw[0].toUpperCase() + raw.substring(1);
  }
}

/// Reusable profile sheet: large avatar (picture or initials), full name,
/// email and role — plus an optional scrollable member list for groups.
///
/// Opened by tapping a member's avatar/name in chat (list tiles, detail
/// header, group sender bubbles).
///
/// GROUP EXTRAS (when [conversationId] is provided):
/// - member rows (except yourself) are TAPPABLE → creates/opens a direct
///   chat with that member (backend returns the existing hydrated
///   conversation for duplicates);
/// - an "Add member" row → multi-select picker of the business's users →
///   POST /chat/conversations/:id/participants → roster refresh;
/// - an "Invite link" row → GET /chat/conversations/:id/invite →
///   copy / share / reset (rotate).
class UserProfileSheet {
  UserProfileSheet._();

  static Future<void> show(
    BuildContext context, {
    required ChatUserProfile profile,
    List<ChatUserProfile> members = const <ChatUserProfile>[],
    String? conversationName,
    String? conversationId,
    bool? isGroup,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ProfileSheetBody(
        parentContext: context,
        profile: profile,
        members: members,
        conversationName: conversationName,
        conversationId: conversationId,
        isGroup: isGroup ?? members.length > 2,
      ),
    );
  }
}

class _ProfileSheetBody extends StatefulWidget {
  /// The context the sheet was opened FROM (chat screen) — used to push the
  /// direct-chat screen on the ROOT navigator after the sheet closes.
  final BuildContext parentContext;
  final ChatUserProfile profile;
  final List<ChatUserProfile> members;
  final String? conversationName;
  final String? conversationId;
  final bool isGroup;

  const _ProfileSheetBody({
    required this.parentContext,
    required this.profile,
    required this.members,
    this.conversationName,
    this.conversationId,
    required this.isGroup,
  });

  @override
  State<_ProfileSheetBody> createState() => _ProfileSheetBodyState();
}

class _ProfileSheetBodyState extends State<_ProfileSheetBody> {
  final ApiService _api = ApiService();
  late List<ChatUserProfile> _members;
  String? _currentUserId;
  // Invite link state (group view only).
  String? _inviteUrl;
  bool _inviteLoading = false;
  String? _inviteError;
  bool _rotatingInvite = false;

  bool get _hasConversation => (widget.conversationId ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _members = List<ChatUserProfile>.from(widget.members);
    _loadCurrentUser();
    if (widget.isGroup && _hasConversation) {
      _refreshParticipants();
      _loadInvite();
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final userId = await StorageService().getUserId();
      if (mounted) setState(() => _currentUserId = userId);
    } catch (_) {}
  }

  /// Re-pulls the participant roster so a freshly-added member (or a member
  /// added from ANOTHER device) shows up without re-opening the sheet.
  Future<void> _refreshParticipants() async {
    if (!_hasConversation) return;
    try {
      final response =
          await _api.getConversationParticipants(widget.conversationId!);
      final data = response.data is Map ? response.data['data'] : null;
      final rows = data is Map && data['participants'] is List
          ? data['participants'] as List
          : const <dynamic>[];
      final roster = rows
          .whereType<Map>()
          .map((raw) {
            final map = Map<String, dynamic>.from(raw);
            final userId = (map['userId'] ?? map['user_id'] ?? '').toString();
            final name = (map['name'] ?? '').toString().trim();
            final email = (map['email'] ?? '').toString().trim();
            return ChatUserProfile(
              userId: userId,
              name: name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Member'),
              email: email,
              avatarUrl: map['avatarUrl']?.toString(),
              role: map['role']?.toString(),
            );
          })
          .where((m) => m.userId.isNotEmpty)
          .toList();
      if (!mounted || roster.isEmpty) return;
      setState(() => _members = roster);
    } catch (e) {
      // Non-fatal: the seeded member list stays.
      Logger.error('Profile sheet roster refresh failed: $e');
    }
  }

  Future<void> _loadInvite() async {
    if (!_hasConversation) return;
    setState(() {
      _inviteLoading = true;
      _inviteError = null;
    });
    try {
      final response = await _api.getChatInvite(widget.conversationId!);
      final data = response.data is Map ? response.data['data'] : null;
      final url = data is Map ? (data['inviteUrl'] ?? '').toString() : '';
      if (!mounted) return;
      setState(() {
        _inviteUrl = url.isEmpty ? null : url;
        _inviteLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inviteError = ApiService.extractErrorMessage(e);
        _inviteLoading = false;
      });
    }
  }

  Future<void> _rotateInvite() async {
    if (!_hasConversation || _rotatingInvite) return;
    setState(() => _rotatingInvite = true);
    try {
      final response = await _api.rotateChatInvite(widget.conversationId!);
      final data = response.data is Map ? response.data['data'] : null;
      final url = data is Map ? (data['inviteUrl'] ?? '').toString() : '';
      if (!mounted) return;
      setState(() {
        _inviteUrl = url.isEmpty ? _inviteUrl : url;
        _rotatingInvite = false;
      });
      AppToast.show('New link created — the old one no longer works');
    } catch (e) {
      if (!mounted) return;
      setState(() => _rotatingInvite = false);
      AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
    }
  }

  void _confirmRotateInvite() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset invite link?'),
        content: const Text(
            'A new link will be created and the current one will stop working immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _rotateInvite();
            },
            child: Text('Reset',
                style: TextStyle(color: AppTheme.colors.error)),
          ),
        ],
      ),
    );
  }

  /// Tap on ANOTHER member's row → create/open a direct chat. The backend
  /// returns the fully-hydrated existing conversation for duplicates, so the
  /// response is fed straight into the chat detail screen.
  Future<void> _openDirectChat(ChatUserProfile member) async {
    if (!_hasConversation) return;
    if (member.userId.isEmpty || member.userId == _currentUserId) return;
    try {
      final response = await _api.createConversation(<String, dynamic>{
        'type': 'direct',
        'participantIds': <String>[member.userId],
        'participant_ids': <String>[member.userId],
      });
      if (response.data['success'] != true) return;
      final responseData = response.data['data'];
      if (responseData is! Map) return;
      final conversation =
          Conversation.fromJson(Map<String, dynamic>.from(responseData));
      final rootNav = Navigator.of(widget.parentContext, rootNavigator: true);
      Navigator.of(context, rootNavigator: true).pop(); // close the sheet
      await rootNav.push(
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(conversation: conversation),
        ),
      );
    } catch (e) {
      Logger.error('Open direct chat failed: $e');
      if (mounted) {
        AppToast.show(
          ApiService.extractErrorMessage(e),
          type: AppToastType.error,
        );
      }
    }
  }

  /// "Add member" row → multi-select picker of the business's users (the same
  /// team endpoint the New-Conversation dialog uses) → POST participants.
  void _showAddMemberSheet() {
    if (!_hasConversation) return;
    final existingIds = _members.map((m) => m.userId).toSet();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _AddMemberPicker(
        existingIds: existingIds,
        onConfirm: (userIds) => _addParticipants(userIds),
      ),
    );
  }

  Future<void> _addParticipants(List<String> userIds) async {
    if (userIds.isEmpty || !_hasConversation) return;
    try {
      final response =
          await _api.addChatParticipants(widget.conversationId!, userIds);
      if (response.data['success'] != true) {
        throw const FormatException('Could not add members');
      }
      final data = response.data is Map ? response.data['data'] : null;
      final added = data is Map && data['added'] is List
          ? (data['added'] as List).length
          : userIds.length;
      if (mounted) {
        AppToast.show(
          '$added member${added == 1 ? '' : 's'} added',
          type: AppToastType.success,
        );
      }
      await _refreshParticipants();
    } catch (e) {
      Logger.error('addChatParticipants failed: $e');
      if (mounted) {
        AppToast.show(
          ApiService.extractErrorMessage(e),
          type: AppToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final showGroupSection = widget.isGroup;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: colors.borderVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _profileHeader(colors),
                    const SizedBox(height: 18),
                    _infoCard(colors),
                    if (showGroupSection) ...[
                      const SizedBox(height: 18),
                      Text(
                        'MEMBERS (${_members.length})',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._members.map((member) => _memberRow(colors, member)),
                      if (_hasConversation) ...[
                        const SizedBox(height: 6),
                        _addMemberRow(colors),
                        const SizedBox(height: 4),
                        _inviteLinkRow(colors),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileHeader(ThemeColors colors) {
    final profile = widget.profile;
    final roleLabel = profile.roleLabel;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [colors.primary, const Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AvatarWithInitials(name: profile.displayName, imageUrl: profile.avatarUrl, radius: 44),
        ),
        const SizedBox(height: 14),
        Text(
          profile.displayName,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: colors.text,
          ),
        ),
        if (profile.email.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            profile.email.trim(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              color: colors.textSecondary,
            ),
          ),
        ],
        if (roleLabel != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.work_outline_rounded, size: 13, color: colors.primary),
                const SizedBox(width: 5),
                Text(
                  roleLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _infoCard(ThemeColors colors) {
    final profile = widget.profile;
    return ModernCard(
      radius: 18,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          if (profile.email.trim().isNotEmpty)
            _infoRow(
              colors,
              Icons.alternate_email_rounded,
              'Email',
              profile.email.trim(),
            ),
          if (profile.roleLabel != null)
            _infoRow(
              colors,
              Icons.badge_outlined,
              'Role',
              profile.roleLabel!,
            ),
          if (profile.email.trim().isEmpty && profile.roleLabel == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'This member has not shared profile details yet.',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: colors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(ThemeColors colors, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          TintedCircleIcon(icon: icon, tint: colors.primary, size: 34, iconSize: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(ThemeColors colors, ChatUserProfile member) {
    final roleLabel = member.roleLabel;
    // Self rows are NOT tappable (you can't DM yourself); everyone else's
    // opens a direct chat with a chevron affordance.
    final isSelf = member.userId.isNotEmpty && member.userId == _currentUserId;
    final tappable = !isSelf && member.userId.isNotEmpty && _hasConversation;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AvatarWithInitials(name: member.displayName, imageUrl: member.avatarUrl, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSelf ? '${member.displayName} (you)' : member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                if (member.email.trim().isNotEmpty)
                  Text(
                    member.email.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (roleLabel != null)
            Text(
              roleLabel,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          if (tappable) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: colors.textSecondary),
          ],
        ],
      ),
    );

    if (!tappable) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openDirectChat(member),
      child: row,
    );
  }

  /// "Add member" row — visible to ANY member of the group (the backend
  /// allows every participant to add business users).
  Widget _addMemberRow(ThemeColors colors) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _showAddMemberSheet,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_add_alt_1_rounded,
                  size: 18, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Add member',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }

  /// "Invite link" row — join URL (mono, ellipsized) + Copy + Share and a
  /// subtle Reset action that rotates the code.
  Widget _inviteLinkRow(ThemeColors colors) {
    final url = _inviteUrl;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Invite link',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              if (_inviteLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: colors.primary),
                )
              else if (_inviteError != null)
                InkWell(
                  onTap: _loadInvite,
                  child: Text(
                    'Retry',
                    style: TextStyle(fontSize: 12, color: colors.error),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            url ?? _inviteError ?? 'Not available yet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontFamily: 'monospace',
              color: url != null ? colors.text : colors.textSecondary,
            ),
          ),
          if (url != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _InviteActionChip(
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  colors: colors,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    AppToast.show('Link copied', type: AppToastType.success);
                  },
                ),
                const SizedBox(width: 8),
                _InviteActionChip(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  colors: colors,
                  onTap: () async {
                    try {
                      await SharePlus.instance.share(ShareParams(
                        title: widget.conversationName ?? 'Metricorex group',
                        text:
                            '${widget.conversationName ?? 'Our group'} on Metricorex — join: $url',
                      ));
                    } catch (_) {
                      // Best-effort; clipboard fallback below.
                      await Clipboard.setData(ClipboardData(text: url));
                      AppToast.show('Link copied', type: AppToastType.success);
                    }
                  },
                ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: _rotatingInvite ? null : _confirmRotateInvite,
                  child: _rotatingInvite
                      ? SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: colors.error),
                        )
                      : Text(
                          'Reset',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.error,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Add-member picker (group sheet)
// =============================================================================

/// Multi-select list of the business's users (GET /team — the same source the
/// New-Conversation dialog in chat_screen uses). Confirm returns the selected
/// user ids through [onConfirm] (the sheet stays open until the parent closes
/// it after the API call — kept simple: the picker pops itself immediately
/// and the parent toasts + refreshes).
class _AddMemberPicker extends StatefulWidget {
  final Set<String> existingIds;
  final Future<void> Function(List<String> userIds) onConfirm;

  const _AddMemberPicker({
    required this.existingIds,
    required this.onConfirm,
  });

  @override
  State<_AddMemberPicker> createState() => _AddMemberPickerState();
}

class _AddMemberPickerState extends State<_AddMemberPicker> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  List<ChatUserProfile> _candidates = [];
  bool _loading = true;
  String? _loadError;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTeam() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response = await _api.getTeam();
      if (response.data['success'] != true) {
        throw const FormatException('Could not load teammates');
      }
      final data = response.data['data'] is List
          ? response.data['data'] as List
          : const <dynamic>[];
      final members = <ChatUserProfile>[];
      for (final row in data) {
        if (row is! Map) continue;
        try {
          final map = Map<String, dynamic>.from(row);
          final userId =
              (map['id'] ?? map['userId'] ?? map['user_id'] ?? '').toString();
          if (userId.isEmpty || widget.existingIds.contains(userId)) continue;
          final name = (map['name'] ?? '').toString().trim();
          final email = (map['email'] ?? '').toString().trim();
          members.add(ChatUserProfile(
            userId: userId,
            name: name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Member'),
            email: email,
            avatarUrl: (map['avatarUrl'] ?? map['avatar_url'])?.toString(),
            role: map['role']?.toString(),
          ));
        } catch (_) {
          // Skip malformed rows — same tolerant parse as the create dialog.
        }
      }
      if (!mounted) return;
      setState(() {
        _candidates = members;
        _loading = false;
      });
    } catch (e) {
      Logger.error('Add-member picker: load team failed: $e');
      if (!mounted) return;
      setState(() {
        _loadError = ApiService.extractErrorMessage(e);
        _loading = false;
      });
    }
  }

  List<ChatUserProfile> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _candidates;
    return _candidates
        .where((m) =>
            m.displayName.toLowerCase().contains(query) ||
            m.email.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty) return;
    final ids = _selected.toList();
    Navigator.of(context).pop();
    await widget.onConfirm(ids);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final filtered = _filtered;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: colors.borderVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Add members',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: colors.text,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: colors.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search teammates',
                  hintStyle: TextStyle(color: colors.textSecondary),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 20, color: colors.textSecondary),
                  filled: true,
                  fillColor: colors.surfaceVariant,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Flexible(
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child:
                            CircularProgressIndicator(color: colors.primary),
                      ),
                    )
                  : _loadError != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13, color: colors.error),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _loadTeam,
                                icon: const Icon(Icons.refresh_rounded,
                                    size: 18),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Everyone in your workspace is already here',
                                style: TextStyle(
                                    fontSize: 13.5, color: colors.textSecondary),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final member = filtered[index];
                                final selected =
                                    _selected.contains(member.userId);
                                return InkWell(
                                  onTap: () => setState(() {
                                    if (selected) {
                                      _selected.remove(member.userId);
                                    } else {
                                      _selected.add(member.userId);
                                    }
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    child: Row(
                                      children: [
                                        AvatarWithInitials(
                                          name: member.displayName,
                                          imageUrl: member.avatarUrl,
                                          radius: 19,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                member.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: colors.text,
                                                ),
                                              ),
                                              if (member.email.trim().isNotEmpty)
                                                Text(
                                                  member.email.trim(),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: colors.textSecondary,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          selected
                                              ? Icons.check_box_rounded
                                              : Icons.check_box_outline_blank_rounded,
                                          size: 22,
                                          color: selected
                                              ? colors.primary
                                              : colors.textSecondary,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    disabledBackgroundColor:
                        colors.textSecondary.withValues(alpha: 0.3),
                  ),
                  onPressed: _selected.isEmpty ? null : _confirm,
                  child: Text(
                    'Add ${_selected.isEmpty ? '' : _selected.length} '
                    'member${_selected.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One pill action on the invite-link row (Copy / Share).
class _InviteActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeColors colors;
  final Future<void> Function() onTap;

  const _InviteActionChip({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        // Fire-and-forget — the chips toast their own outcome.
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.primary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
