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
  final String? phoneNumber;
  /// SERVER-COMPUTED ownership (businesses.owner_id match). The registrant's
  /// role string is 'admin' — the same role invited admins get — so this flag
  /// is the ONLY reliable signal for gating business-profile editing. Invited
  /// members (admins included) must never edit business identity.
  final bool isOwner;

  const UserProfile({
    this.name = '',
    this.email = '',
    this.avatarUrl,
    this.role,
    this.phoneNumber,
    this.isOwner = false,
  });

  bool get hasAvatar => (avatarUrl ?? '').trim().isNotEmpty;

  UserProfile copyWith({
    String? name,
    String? email,
    String? avatarUrl,
    String? role,
    String? phoneNumber,
    bool? isOwner,
    bool clearAvatar = false,
    bool clearPhone = false,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
      role: role ?? this.role,
      phoneNumber:
          clearPhone ? null : (phoneNumber ?? this.phoneNumber),
      isOwner: isOwner ?? this.isOwner,
    );
  }
}

const String _kName = 'user_profile_name';
const String _kEmail = 'user_profile_email';
const String _kAvatar = 'user_profile_avatar';
const String _kRole = 'user_profile_role';
const String _kPhone = 'user_profile_phone';
const String _kIsOwner = 'user_profile_is_owner';

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
        phoneNumber: prefs.getString(_kPhone),
        isOwner: prefs.getBool(_kIsOwner) ?? false,
      );
    } catch (e) {
      debugPrint('UserProfile.hydrate failed: $e');
    }
  }

  /// Adopt the `profile` object returned by GET /settings (the caller's own
  /// user row: name, email, avatarUrl, role, phone, server-computed isOwner).
  void adoptServerProfile(Map<String, dynamic>? profile) {
    if (profile == null) return;
    final name = (profile['name'] ?? '').toString();
    final email = (profile['email'] ?? '').toString();
    final avatarUrl = (profile['avatarUrl'] ?? profile['avatar_url'])?.toString();
    final role = (profile['role'] ?? '').toString();
    final phone =
        (profile['phoneNumber'] ?? profile['phone_number'] ?? '')?.toString();
    final isOwnerFlag = profile['isOwner'];
    final wasOwner = state.isOwner;
    state = state.copyWith(
      name: name,
      email: email,
      avatarUrl: (avatarUrl == null || avatarUrl.isEmpty) ? null : avatarUrl,
      role: role.isEmpty ? null : role,
      phoneNumber: (phone == null || phone.isEmpty) ? null : phone,
      clearPhone: phone == null || phone.isEmpty,
      // Only trust the flag when the server actually sent it — otherwise
      // keep whatever we had (avoids flipping the owner to member view when
      // an older backend omits the field).
      isOwner: isOwnerFlag is bool ? isOwnerFlag : wasOwner,
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

  /// Wipe the cached profile (logout) — clears the persisted keys too so a
  /// different account signing in on this device never inherits the previous
  /// user's identity (name/email/phone/avatar/owner flag).
  Future<void> reset() async {
    state = const UserProfile();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in [_kName, _kEmail, _kAvatar, _kRole, _kPhone]) {
        await prefs.remove(k);
      }
      await prefs.setBool(_kIsOwner, false);
    } catch (e) {
      debugPrint('UserProfile reset failed: $e');
    }
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
      final phone = state.phoneNumber;
      if (phone == null || phone.isEmpty) {
        await prefs.remove(_kPhone);
      } else {
        await prefs.setString(_kPhone, phone);
      }
      await prefs.setBool(_kIsOwner, state.isOwner);
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
