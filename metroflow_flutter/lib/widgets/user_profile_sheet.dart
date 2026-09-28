import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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
class UserProfileSheet {
  UserProfileSheet._();

  static Future<void> show(
    BuildContext context, {
    required ChatUserProfile profile,
    List<ChatUserProfile> members = const <ChatUserProfile>[],
    String? conversationName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ProfileSheetBody(
        profile: profile,
        members: members,
        conversationName: conversationName,
      ),
    );
  }
}

class _ProfileSheetBody extends StatelessWidget {
  final ChatUserProfile profile;
  final List<ChatUserProfile> members;
  final String? conversationName;

  const _ProfileSheetBody({
    required this.profile,
    required this.members,
    this.conversationName,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    // Groups carry more than two members (caller passes the full roster).
    final isGroup = members.length > 2;

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
                    if (isGroup && members.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'MEMBERS (${members.length})',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...members.map((member) => _memberRow(colors, member)),
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
    return Padding(
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
                  member.displayName,
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
        ],
      ),
    );
  }
}
