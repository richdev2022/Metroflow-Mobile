import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api.dart';

/// Current user's display profile (name / avatar / role) shared by the
/// dashboard greeting chip, the profile/settings screen and chat.
///
/// Kept separate from [authProvider] (which owns session concerns) so the UI
/// can refresh the picture/name right after an upload without touching the
/// auth state machine. Values are cached in SharedPreferences so the very
/// first frames after a cold start already show the picture/initials; the
/// server copy (GET /settings → `profile`) is adopted whenever a screen
/// loads it.
class UserProfile {
  final String name;
  final String email;
  final String? avatarUrl;
  final String? role;

  const UserProfile({
    this.name = '',
    this.email = '',
    this.avatarUrl,
    this.role,
  });

  bool get hasAvatar => (avatarUrl ?? '').trim().isNotEmpty;

  UserProfile copyWith({
    String? name,
    String? email,
    String? avatarUrl,
    String? role,
    bool clearAvatar = false,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
      role: role ?? this.role,
    );
  }
}

const String _kName = 'user_profile_name';
const String _kEmail = 'user_profile_email';
const String _kAvatar = 'user_profile_avatar';
const String _kRole = 'user_profile_role';

class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    // Start from the local cache; [hydrate] pulls fresh values from storage
    // and [adoptServerProfile] syncs from GET /settings.
    return const UserProfile();
  }

  Future<void> hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = UserProfile(
        name: prefs.getString(_kName) ?? '',
        email: prefs.getString(_kEmail) ?? '',
        avatarUrl: prefs.getString(_kAvatar),
        role: prefs.getString(_kRole),
      );
    } catch (e) {
      debugPrint('UserProfile.hydrate failed: $e');
    }
  }

  /// Adopt the `profile` object returned by GET /settings (the caller's own
  /// user row: name, email, avatarUrl, role).
  void adoptServerProfile(Map<String, dynamic>? profile) {
    if (profile == null) return;
    final name = (profile['name'] ?? '').toString();
    final email = (profile['email'] ?? '').toString();
    final avatarUrl = (profile['avatarUrl'] ?? profile['avatar_url'])?.toString();
    final role = (profile['role'] ?? '').toString();
    state = state.copyWith(
      name: name,
      email: email,
      avatarUrl: (avatarUrl == null || avatarUrl.isEmpty) ? null : avatarUrl,
      role: role.isEmpty ? null : role,
    );
    _persist();
  }

  /// Update just the avatar (after a successful upload).
  void setAvatar(String? url) {
    final normalized = (url == null || url.trim().isEmpty) ? null : url.trim();
    state = state.copyWith(avatarUrl: normalized, clearAvatar: normalized == null);
    _persist();
  }

  /// Update just the display name (after a name edit).
  void setName(String name) {
    state = state.copyWith(name: name.trim());
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kName, state.name);
      await prefs.setString(_kEmail, state.email);
      final avatar = state.avatarUrl;
      if (avatar == null || avatar.isEmpty) {
        await prefs.remove(_kAvatar);
      } else {
        await prefs.setString(_kAvatar, avatar);
      }
      final role = state.role;
      if (role == null || role.isEmpty) {
        await prefs.remove(_kRole);
      } else {
        await prefs.setString(_kRole, role);
      }
    } catch (e) {
      debugPrint('UserProfile persist failed: $e');
    }
  }

  /// Convenience: fetch the user's own profile from the server and adopt it.
  Future<void> refreshFromServer() async {
    try {
      final response = await ApiService().getSettings();
      final data = response.data;
      if (data is Map && data['profile'] is Map) {
        adoptServerProfile(Map<String, dynamic>.from(data['profile'] as Map));
      }
    } catch (e) {
      debugPrint('UserProfile.refreshFromServer failed: $e');
    }
  }
}

final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile>(UserProfileNotifier.new);
