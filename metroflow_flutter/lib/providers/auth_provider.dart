import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api.dart';
import '../services/biometrics.dart';
import '../services/google_auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/socket_service.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? token;
  final String? userId;
  final String? businessId;
  final String? userName;
  final String? avatarUrl;
  final bool requiresPasswordSetup;
  final String? authProvider;
  final bool? hasPassword;
  final bool biometricsEnabled;
  final bool hasSeenOnboarding;
  final bool skippedKyc;
  /// SSO onboarding gate: false while the business profile (real name,
  /// industry, phone, logo) is still incomplete — clients route those users
  /// to the profile-completion screen before the dashboard. Null = unknown.
  final bool? profileCompleted;

  AuthState({
    required this.isAuthenticated,
    required this.isLoading,
    this.token,
    this.userId,
    this.businessId,
    this.userName,
    this.avatarUrl,
    this.requiresPasswordSetup = false,
    this.authProvider,
    this.hasPassword,
    required this.biometricsEnabled,
    required this.hasSeenOnboarding,
    this.skippedKyc = false,
    this.profileCompleted,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? token,
    String? userId,
    String? businessId,
    String? userName,
    String? avatarUrl,
    bool? requiresPasswordSetup,
    String? authProvider,
    bool? hasPassword,
    bool? biometricsEnabled,
    bool? hasSeenOnboarding,
    bool? skippedKyc,
    bool? profileCompleted,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      token: token ?? this.token,
      userId: userId ?? this.userId,
      businessId: businessId ?? this.businessId,
      userName: userName ?? this.userName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      requiresPasswordSetup: requiresPasswordSetup ?? this.requiresPasswordSetup,
      authProvider: authProvider ?? this.authProvider,
      hasPassword: hasPassword ?? this.hasPassword,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      hasSeenOnboarding: hasSeenOnboarding ?? this.hasSeenOnboarding,
      skippedKyc: skippedKyc ?? this.skippedKyc,
      profileCompleted: profileCompleted ?? this.profileCompleted,
    );
  }
}

// Global variable to hold the auth notifier instance (set in main.dart)
AuthNotifier? authNotifierInstance;

/// Result of the SERVER-BACKED biometric login flow.
/// [revoked] is true when the backend no longer recognises this device's
/// biometric credential (401/403) — the caller should fall back to password
/// login; the local enrollment has been wiped in that case.
class BiometricLoginResult {
  final bool success;
  final bool revoked;
  final String? error;

  const BiometricLoginResult({
    required this.success,
    this.revoked = false,
    this.error,
  });
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  Timer? _idleTimer;
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final SocketService _socketService = SocketService();
  final GoogleAuthService _googleAuthService = GoogleAuthService();

  /// One-shot flag armed by [logout] when the FCM device registration was
  /// deliberately KEPT (security/idle/session-expiry logouts pass
  /// `unregisterDevice: false`). main.dart's auth-state listener consumes it
  /// via [consumeKeepDeviceRegistration] so IT also skips its unregister —
  /// without this, the listener re-killed the registration the logout just
  /// decided to preserve.
  bool _keepDeviceRegistration = false;

  /// Returns — and clears — the one-shot keep-registration flag for the
  /// logout that just flipped isAuthenticated.
  bool consumeKeepDeviceRegistration() {
    final keep = _keepDeviceRegistration;
    _keepDeviceRegistration = false;
    return keep;
  }

  // In-memory cache of the GET /auth/me profile (see getMe()).
  Map<String, dynamic>? _meCache;
  DateTime? _meCacheAt;
  static const Duration _meCacheTtl = Duration(minutes: 5);

  @override
  AuthState build() {
    // Set global instance
    authNotifierInstance = this;
    checkAuth();
    return AuthState(
      isAuthenticated: false,
      isLoading: true,
      biometricsEnabled: false,
      hasSeenOnboarding: false,
    );
  }

  void resetIdleTimer() {
    _idleTimer?.cancel();
    if (state.isAuthenticated) {
      _idleTimer = Timer(const Duration(minutes: 5), () {
        // AUTOMATIC security logout — keep the FCM device registration so
        // push keeps working for the next session on this device.
        logout(unregisterDevice: false);
      });
    }
  }

  Future<void> checkAuth() async {
    try {
      final token = await _storageService.getToken();
      final userId = await _storageService.getUserId();
      final businessId = await _storageService.getBusinessId();
      final userName = await _storageService.getUserName();
      final avatarUrl = await _storageService.getAvatarUrl();
      final requiresPasswordSetup = await _storageService.getRequiresPasswordSetup();
      final authProvider = await _storageService.getAuthProvider();
      final hasPassword = await _storageService.getHasPassword();
      final biometricsEnabled = await BiometricService.isEnabled(userId);
      final hasSeenOnboarding = await _storageService.getHasSeenOnboarding();

      var isTokenValid = token != null;

      // SERVER-SIDE SESSION VALIDATION. HISTORY: this used to trust the mere
      // EXISTENCE of a stored token. The backend keeps sessions in the
      // user_sessions table with a sliding idle window — once the row is
      // gone (idle expiry, server-side cleanup) every REST call 403s and the
      // socket silently drops to GUEST: no calls, no live chat, no push
      // registration, raw DioExceptions on the notifications tab — while the
      // app still LOOKED logged in. Now a dead session is detected here and
      // the user is routed to login (fail-open on network errors so an
      // offline launch never logs anyone out).
      if (isTokenValid) {
        final verdict = await _apiService.validateSession();
        if (verdict == ApiService.sessionExpired) {
          debugPrint('checkAuth: stored session rejected by server — clearing it');
          await _storageService.clearSession();
          isTokenValid = false;
        }
      }

      // Connect socket if authenticated
      if (isTokenValid && userId != null && businessId != null) {
        _socketService.connect(userId, businessId, token: token);
      }

      state = state.copyWith(
        token: isTokenValid ? token : null,
        userId: isTokenValid ? userId : null,
        businessId: isTokenValid ? businessId : null,
        userName: isTokenValid ? userName : null,
        avatarUrl: isTokenValid ? avatarUrl : null,
        requiresPasswordSetup: isTokenValid ? requiresPasswordSetup : false,
        authProvider: isTokenValid ? authProvider : null,
        hasPassword: isTokenValid ? hasPassword : null,
        biometricsEnabled: biometricsEnabled,
        hasSeenOnboarding: hasSeenOnboarding,
        isAuthenticated: isTokenValid,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Auth check failed: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> login(String email, String password) async {
    try {
      final response = await _apiService.login(email, password);
      final data = response.data;
      
      if (data['requiresOtp'] == true) {
        throw Exception('OTP required');
      }
      
      final token = data['token'];
      final userId = data['userId'] ?? data['user']?['id'];
      final businessId = data['businessId'] ?? data['business']?['id'];
      // Backend returns the profile name top-level on every login method —
      // greet the user by NAME, never by their email address.
      final userName = (data['name'] ?? data['user']?['name'] ?? email)
          .toString();

      // ACCOUNT-SWITCH BIOMETRIC WIPE (user requirement): biometrics are per
      // ACCOUNT — when a different account signs in on this device, the
      // previous account's enrollment is cleared COMPLETELY (server revoke +
      // per-device token + per-account flag + prompt memory) BEFORE the new
      // session is persisted (the revoke call still rides the old token).
      // The enrollment is one-per-device, so a new account never starts with
      // biometrics enabled and gets the activation prompt on the login
      // screen instead.
      final newUserId = userId?.toString();
      final previousUserId = await _resolveEnrolledUserId();
      if (newUserId != null &&
          newUserId.isNotEmpty &&
          previousUserId != null &&
          previousUserId.isNotEmpty &&
          previousUserId != newUserId) {
        await _wipeBiometricsForAccountSwitch(previousUserId);
      }

      await Future.wait([
        _storageService.setToken(token),
        _storageService.setUserId(userId),
        _storageService.setBusinessId(businessId),
        _storageService.setUserName(userName),
      ]);

      // PER-ACCOUNT biometrics: the switch belongs to the account that just
      // logged in — a NEW account starts with biometrics OFF (and gets the
      // activation prompt on the login screen), it never inherits the
      // previous account's opt-in.
      final biometricsForAccount = await BiometricService.isEnabled(userId);

      // Save biometrics credentials if enabled
      if (biometricsForAccount) {
        await _storageService.setBiometricsCredentials(
          token: token,
          userId: userId,
          businessId: businessId,
          userName: userName,
        );
      }

      // Connect socket
      if (userId != null && businessId != null) {
        _socketService.connect(userId, businessId, token: token);
      }

      state = state.copyWith(
        token: token,
        userId: userId,
        businessId: businessId,
        userName: userName,
        isAuthenticated: true,
        biometricsEnabled: biometricsForAccount,
      );
      resetIdleTimer();

      // Keep the server-backed biometric enrollment fresh for this device
      // (enroll revokes+reissues the per-device token). Best-effort.
      unawaited(_reenrollBiometricsIfNeeded());
    } on DioException catch (e) {
      final backendMessage = e.response?.data?['message'] ?? e.response?.data?['error'] ?? e.message ?? 'An error occurred';
      throw Exception(backendMessage);
    } catch (e) {
      rethrow;
    }
  }

  /// Signs in with Google, exchanges the Google ID token for an app session
  /// via POST /auth/google, then persists the session exactly like password
  /// login does (token/userId/businessId/userName + biometrics credentials,
  /// socket connect, idle timer).
  ///
  /// Returns `false` when the user cancelled the Google flow (not an error).
  /// Throws a friendly [Exception] on failure.
  Future<bool> loginWithGoogle() async {
    String? idToken;
    try {
      idToken = await _googleAuthService.signIn();
    } catch (e) {
      // GoogleAuthService already maps errors to friendly messages.
      rethrow;
    }

    if (idToken == null) {
      // User cancelled the account picker — not an error.
      return false;
    }

    try {
      final response = await _apiService.googleAuth(idToken);
      final data = response.data;

      final token = data['token'];
      if (token == null || (token is String && token.isEmpty)) {
        throw Exception('Google sign-in failed: no session token returned');
      }

      final user = data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : <String, dynamic>{};
      final userId = (data['userId'] ?? user['id'])?.toString();
      final businessId = data['businessId']?.toString();
      final userName = user['name']?.toString() ?? '';
      final avatarUrl = user['avatarUrl']?.toString();
      final authProvider =
          (user['authProvider']?.toString().isNotEmpty ?? false)
              ? user['authProvider'].toString()
              : 'google';
      final requiresPasswordSetup = data['requiresPasswordSetup'] == true;
      // SSO onboarding gate — server says whether the business profile is
      // complete (real name, industry, phone, logo).
      final profileCompleted = data['profileCompleted'] == true;

      // ACCOUNT-SWITCH BIOMETRIC WIPE — same contract as password login:
      // a different Google account signing in wipes the previous account's
      // enrollment completely before the new session is persisted.
      final previousUserId = await _resolveEnrolledUserId();
      if (userId != null &&
          userId.isNotEmpty &&
          previousUserId != null &&
          previousUserId.isNotEmpty &&
          previousUserId != userId) {
        await _wipeBiometricsForAccountSwitch(previousUserId);
      }

      // Same session persistence path as password login.
      await _storageService.setToken(token.toString());
      if (userId != null) await _storageService.setUserId(userId);
      if (businessId != null) await _storageService.setBusinessId(businessId);
      await _storageService.setUserName(userName);
      await _storageService.setAvatarUrl(avatarUrl);
      await _storageService.setAuthProvider(authProvider);
      await _storageService.setRequiresPasswordSetup(requiresPasswordSetup);
      await _storageService.setProfileCompleted(profileCompleted);

      // PER-ACCOUNT biometrics (same contract as password login): read the
      // flag for the account that just signed in — never inherit the
      // previous account's switch.
      final biometricsForAccount = await BiometricService.isEnabled(userId);

      // Save biometrics credentials if enabled (same as password login).
      if (biometricsForAccount && userId != null && businessId != null) {
        await _storageService.setBiometricsCredentials(
          token: token.toString(),
          userId: userId,
          businessId: businessId,
          userName: userName,
        );
      }

      // Connect socket
      if (userId != null && businessId != null) {
        _socketService.connect(userId, businessId, token: token);
      }

      state = state.copyWith(
        token: token.toString(),
        userId: userId,
        businessId: businessId,
        userName: userName,
        avatarUrl: avatarUrl,
        authProvider: authProvider,
        requiresPasswordSetup: requiresPasswordSetup,
        isAuthenticated: true,
        biometricsEnabled: biometricsForAccount,
        profileCompleted: profileCompleted,
      );
      resetIdleTimer();

      // Keep the server-backed biometric enrollment fresh for this device.
      unawaited(_reenrollBiometricsIfNeeded());

      // Non-blocking, one-time hint to create a password from Settings.
      await maybeSuggestPasswordSetup();
      return true;
    } on DioException catch (e) {
      final backendMessage = e.response?.data?['message'] ??
          e.response?.data?['error'] ??
          e.message ??
          'Google sign-in failed';
      throw Exception(backendMessage);
    }
  }

  /// Fetches the current user profile from GET /auth/me. The result is
  /// cached in memory for [meCacheTtl] and mirrored into AuthState
  /// ([hasPassword] / [authProvider] getters) and persistent storage.
  Future<Map<String, dynamic>?> getMe({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _meCache != null &&
        _meCacheAt != null &&
        DateTime.now().difference(_meCacheAt!) < _meCacheTtl) {
      return _meCache;
    }
    if (state.token == null) return null;

    try {
      final response = await _apiService.getMe();
      final data = response.data;
      if (data is Map && data['success'] == true && data['data'] is Map) {
        _meCache = Map<String, dynamic>.from(data['data'] as Map);
        _meCacheAt = DateTime.now();

        final dynamic hasPassword = _meCache!['hasPassword'];
        final dynamic authProvider = _meCache!['authProvider'];
        final dynamic avatarUrl = _meCache!['avatarUrl'];

        // Keep lightweight persistent copies for offline display.
        if (authProvider is String && authProvider.isNotEmpty) {
          await _storageService.setAuthProvider(authProvider);
        }
        if (hasPassword is bool) {
          await _storageService.setHasPassword(hasPassword);
        }
        if (_meCache!.containsKey('avatarUrl')) {
          await _storageService.setAvatarUrl(avatarUrl is String ? avatarUrl : null);
        }

        state = state.copyWith(
          hasPassword: hasPassword is bool ? hasPassword : null,
          authProvider: authProvider is String && authProvider.isNotEmpty
              ? authProvider
              : null,
          avatarUrl: avatarUrl is String && avatarUrl.isNotEmpty ? avatarUrl : null,
        );
        return _meCache;
      }
      return null;
    } catch (e) {
      debugPrint('getMe failed: $e');
      return null;
    }
  }

  /// True when the account has a local password (null = unknown until
  /// GET /auth/me succeeds). Backed by [getMe] caching.
  bool? get hasPassword => state.hasPassword;

  /// Auth provider for the signed-in account: 'google' or 'email'.
  String? get authProvider => state.authProvider;

  /// Clears the cached /auth/me profile (used on logout).
  void clearMeCache() {
    _meCache = null;
    _meCacheAt = null;
  }

  /// Sets an initial password for SSO-only (Google) accounts.
  Future<void> setPassword(String password) async {
    try {
      final response = await _apiService.setPassword(password);
      final data = response.data;
      if (data is Map && data['success'] == false) {
        throw Exception(data['message']?.toString() ?? 'Failed to set password');
      }
      state = state.copyWith(hasPassword: true, requiresPasswordSetup: false);
      await _storageService.setHasPassword(true);
      await _storageService.setRequiresPasswordSetup(false);
      _meCache?['hasPassword'] = true;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['code'] == 'PASSWORD_ALREADY_SET') {
        throw Exception(
            'A password is already set for this account. Use "Change password" instead.');
      }
      final backendMessage = data?['message'] ??
          data?['error'] ??
          e.message ??
          'Failed to set password';
      throw Exception(backendMessage);
    }
  }

  /// Changes the password for accounts that already have one.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    try {
      final response = await _apiService.changePassword(currentPassword, newPassword);
      final data = response.data;
      if (data is Map && data['success'] == false) {
        throw Exception(data['message']?.toString() ?? 'Failed to change password');
      }
      state = state.copyWith(hasPassword: true);
      await _storageService.setHasPassword(true);
      _meCache?['hasPassword'] = true;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['code'] == 'NO_PASSWORD_SET') {
        throw Exception(
            'No password is set for this account yet. Use "Create password" instead.');
      }
      final backendMessage = data?['message'] ??
          data?['error'] ??
          e.message ??
          'Failed to change password';
      throw Exception(backendMessage);
    }
  }

  /// One-time, non-blocking snackbar suggesting the user create a password
  /// (for Google accounts signed in without one). Never blocks the flow and
  /// never throws — fires after navigation has had a moment to settle.
  Future<void> maybeSuggestPasswordSetup() async {
    try {
      if (!state.requiresPasswordSetup) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('passwordSetupPromptShown') == true) return;
      await prefs.setBool('passwordSetupPromptShown', true);

      Future.delayed(const Duration(milliseconds: 1200), () {
        final context = navigatorKey.currentContext;
        if (context == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Add a password in Settings \u2192 Sign-in & Security to also sign in with your email.',
            ),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Later',
              onPressed: () {},
            ),
          ),
        );
      });
    } catch (e) {
      debugPrint('Failed to suggest password setup: $e');
    }
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    try {
      final response = await _apiService.register(data);
      final responseData = response.data;
      
      if (responseData['requiresOtp'] == true) {
        return {'requiresOtp': true, 'email': data['adminEmail']};
      }
      
      final token = responseData['token'];
      final userId = responseData['userId'];
      final businessId = responseData['businessId'];
      final userName = data['adminName'];

      if (token != null) {
        await Future.wait([
          _storageService.setToken(token),
          _storageService.setUserId(userId),
          _storageService.setBusinessId(businessId),
          _storageService.setUserName(userName),
        ]);

        // Save biometrics credentials if enabled
        if (state.biometricsEnabled) {
          await _storageService.setBiometricsCredentials(
            token: token,
            userId: userId,
            businessId: businessId,
            userName: userName,
          );
        }

        // Connect socket
        if (userId != null && businessId != null) {
          _socketService.connect(userId, businessId, token: token);
        }

        state = state.copyWith(
          token: token,
          userId: userId,
          businessId: businessId,
          userName: userName,
          isAuthenticated: true,
        );
        resetIdleTimer();
      }

      return {'requiresOtp': false};
    } on DioException catch (e) {
      final backendMessage = e.response?.data?['message'] ?? e.response?.data?['error'] ?? e.message ?? 'An error occurred';
      throw Exception(backendMessage);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> verifyOtp(String email, String otpCode) async {
    try {
      final response = await _apiService.verifyOtp(email, otpCode);
      final data = response.data;
      
      final token = data['token'];
      final userId = data['userId'] ?? data['user']?['id'];
      final businessId = data['businessId'] ?? data['businessId'] ?? data['user']?['businessId'];
      final userName = (data['name'] ?? data['user']?['name'] ?? email)
          .toString();

      if (token != null) {
        await Future.wait([
          _storageService.setToken(token),
          _storageService.setUserId(userId),
          _storageService.setBusinessId(businessId),
          _storageService.setUserName(userName),
        ]);

        // Save biometrics credentials if enabled
        if (state.biometricsEnabled) {
          await _storageService.setBiometricsCredentials(
            token: token,
            userId: userId,
            businessId: businessId,
            userName: userName,
          );
        }

        // Connect socket
        if (userId != null && businessId != null) {
          _socketService.connect(userId, businessId, token: token);
        }

        state = state.copyWith(
          token: token,
          userId: userId,
          businessId: businessId,
          userName: userName,
          isAuthenticated: true,
        );
        resetIdleTimer();
      }
    } on DioException catch (e) {
      final backendMessage = e.response?.data?['message'] ?? e.response?.data?['error'] ?? e.message ?? 'An error occurred';
      throw Exception(backendMessage);
    } catch (e) {
      rethrow;
    }
  }

  /// Resolves the account that owns the CURRENT device biometric
  /// enrollment: the legacy credentials copy records the userId that
  /// enrolled; when absent, fall back to the persisted session userId.
  Future<String?> _resolveEnrolledUserId() async {
    try {
      final creds = await _storageService.getBiometricsCredentials();
      final credsUserId = creds?['userId']?.toString();
      if (credsUserId != null && credsUserId.isNotEmpty) return credsUserId;
    } catch (_) {}
    try {
      return await _storageService.getUserId();
    } catch (_) {
      return null;
    }
  }

  /// ACCOUNT-SWITCH WIPE (user requirement): when a DIFFERENT account signs
  /// in on this device, the previous account's biometric enrollment is
  /// cleared COMPLETELY — server-side revoke, per-device token, per-account
  /// opt-in flag and prompt memory — because the enrollment (one per
  /// device) belongs to exactly one account and must never leak into
  /// another user's session.
  Future<void> _wipeBiometricsForAccountSwitch(String previousUserId) async {
    try {
      debugPrint(
          'Account switch detected — wiping biometric enrollment of $previousUserId');
      final deviceId = await _storageService.getBiometricDeviceId();
      try {
        await _apiService.biometricRevoke(deviceId: deviceId);
      } catch (e) {
        // Best-effort: offline / stale session — the local wipe still
        // guarantees the old account can never biometric-login here.
        debugPrint('Account-switch biometric revoke skipped: $e');
      }
      if (deviceId != null && deviceId.isNotEmpty) {
        await _storageService.clearBiometricToken(deviceId);
      }
      await _storageService.setBiometricsEnabledForAccount(
          previousUserId, false);
      await _storageService.setBiometricsPromptShownForAccount(
          previousUserId, false);
      await BiometricService.disableBiometrics();
      await BiometricService.resetPromptStatusFor(previousUserId);
      await _storageService.clearBiometricsCredentials();
    } catch (e) {
      debugPrint('Account-switch biometric wipe failed: $e');
    }
  }

  /// [unregisterDevice] — pass FALSE for AUTOMATIC logouts (5-minute idle
  /// security logout, session expiry): the FCM device registration is kept
  /// so push (call rings, chat alerts) keeps working until the next login.
  /// Explicit user logouts keep the default (true) and unregister.
  Future<void> logout({bool disableBiometrics = false, bool unregisterDevice = true}) async {
    try {
      _idleTimer?.cancel();
      clearMeCache();

      if (unregisterDevice) {
        // Best-effort: remove this device's FCM token from the backend so push
        // (call rings, chat alerts) stops for the signed-out user.
        try {
          await PushNotificationService.instance.unregisterCurrentDevice();
        } catch (e) {
          debugPrint('FCM unregister skipped: $e');
        }
      }

      // Sign out of the Google account picker too so the next Google
      // sign-in re-opens the account chooser (best effort, never blocks).
      await _googleAuthService.signOut();

      // Disconnect socket
      _socketService.disconnect();
      
      final hasSeenOnboarding = state.hasSeenOnboarding;
      bool newBiometricsEnabled = state.biometricsEnabled;
      
      // Clear everything except hasSeenOnboarding
      final storage = StorageService();
      await storage.clearAll();
      
      // If we should disable biometrics, also clear biometric credentials and disable it
      if (disableBiometrics) {
        newBiometricsEnabled = false;
        await _revokeBiometricEnrollment();
      }
      
      // Arm the one-shot keep-registration flag immediately BEFORE the state
      // flip: main.dart's auth listener reads it for THIS logout only (when
      // the registration was kept, the listener must not unregister either).
      _keepDeviceRegistration = !unregisterDevice;
      state = AuthState(
        isAuthenticated: false,
        isLoading: false,
        biometricsEnabled: newBiometricsEnabled,
        hasSeenOnboarding: hasSeenOnboarding,
      );
    } catch (e) {
      debugPrint('Logout failed: $e');
    }
  }

  Future<bool> enableBiometrics() async {
    final result = await enableBiometricsWithResult();
    return result.success;
  }

  /// Enables biometric unlock SERVER-SIDE:
  /// 1. local_auth prompt (device-credential fallback enabled);
  /// 2. POST /auth/biometric/enroll with a stable per-device UUID;
  /// 3. the returned one-time biometric_token goes into secure storage,
  ///    keyed per device.
  Future<BiometricResult> enableBiometricsWithResult() async {
    try {
      final sessionToken = state.token ?? await _storageService.getToken();
      if (sessionToken == null || sessionToken.isEmpty) {
        return const BiometricResult(
          success: false,
          error: 'Sign in with your password first to enable biometric unlock.',
        );
      }

      // Device capability: biometrics OR device PIN/pattern fallback.
      final canAuth = await BiometricService.canAuthenticate();
      if (!canAuth) {
        await _storageService.setBiometricsEnabled(false);
        final hasHardware = await BiometricService.hasHardware();
        return BiometricResult(
          success: false,
          error: hasHardware
              ? 'Please set up fingerprint or face recognition in your device settings first.'
              : 'This device does not support biometric or device-credential unlock.',
        );
      }

      final authResult = await BiometricService.authenticate('Enable biometric unlock');
      if (!authResult.success) {
        debugPrint('Biometric authentication failed during enable: ${authResult.error}');
        return authResult;
      }

      final deviceId = await _storageService.getOrCreateBiometricDeviceId();
      final response = await _apiService.biometricEnroll(
        deviceId: deviceId,
        deviceName: BiometricService.deviceName(),
        platform: BiometricService.platformName(),
      );
      final data = response.data;
      String? biometricToken;
      if (data is Map && data['success'] == true && data['data'] is Map) {
        biometricToken = data['data']['biometric_token']?.toString();
      }
      if (biometricToken == null || biometricToken.isEmpty) {
        return BiometricResult(
          success: false,
          error: ApiService.extractResponseMessage(data) ?? 'Failed to enable biometric unlock',
        );
      }

      await _storageService.setBiometricToken(deviceId, biometricToken);

      // Keep the legacy credential copy so the display name survives logout
      // (biometric login has no password prompt to derive it from).
      final userId = state.userId ?? await _storageService.getUserId() ?? '';
      final businessId = state.businessId ?? await _storageService.getBusinessId() ?? '';
      final userName = state.userName ?? await _storageService.getUserName() ?? userId;
      await _storageService.setBiometricsCredentials(
        token: sessionToken,
        userId: userId,
        businessId: businessId,
        userName: userName,
      );

      // PER-ACCOUNT opt-in: the switch is written for the signed-in account
      // (legacy device-wide flag mirrored for old code paths).
      if (userId.isNotEmpty) {
        await _storageService.setBiometricsEnabledForAccount(userId, true);
      } else {
        await _storageService.setBiometricsEnabled(true);
      }
      state = state.copyWith(biometricsEnabled: true);
      if (userId.isNotEmpty) {
        await BiometricService.markPromptAsShown(userId);
      }
      debugPrint('Biometric unlock enabled successfully');
      resetIdleTimer();
      return const BiometricResult(success: true);
    } on DioException catch (e) {
      return BiometricResult(
        success: false,
        error: ApiService.extractErrorMessage(e),
      );
    } catch (e) {
      debugPrint('Failed to enable biometrics: $e');
      return const BiometricResult(success: false, error: 'Failed to enable biometric login');
    }
  }

  Future<void> disableBiometrics() async {
    try {
      await _revokeBiometricEnrollment();
      // PER-ACCOUNT: flip the switch off for the signed-in account only.
      final userId = state.userId ?? await _storageService.getUserId();
      if (userId != null && userId.isNotEmpty) {
        await _storageService.setBiometricsEnabledForAccount(userId, false);
      }
      state = state.copyWith(biometricsEnabled: false);
      resetIdleTimer();
    } catch (e) {
      debugPrint('Disable biometrics failed: $e');
    }
  }

  /// Full wipe of the biometric unlock: backend revoke (best-effort, needs a
  /// live session) + secure-storage token + legacy credentials + flag.
  Future<void> _revokeBiometricEnrollment() async {
    try {
      final deviceId = await _storageService.getBiometricDeviceId();
      try {
        await _apiService.biometricRevoke(deviceId: deviceId);
      } catch (e) {
        // Revocation is best-effort: offline / session already gone.
        debugPrint('Biometric revoke skipped: $e');
      }
      if (deviceId != null && deviceId.isNotEmpty) {
        await _storageService.clearBiometricToken(deviceId);
      }
      // PER-ACCOUNT: clear the opt-in for the account being wiped.
      final flaggedUserId = state.userId ?? await _storageService.getUserId();
      if (flaggedUserId != null && flaggedUserId.isNotEmpty) {
        await _storageService.setBiometricsEnabledForAccount(flaggedUserId, false);
      }
      await BiometricService.disableBiometrics();
      if (flaggedUserId != null) {
        await BiometricService.resetPromptStatusFor(flaggedUserId);
      }
      await _storageService.clearBiometricsCredentials();
    } catch (e) {
      debugPrint('Failed to revoke biometric enrollment: $e');
    }
  }

  /// Local wipe ONLY (no network, no flag change) — used when the backend
  /// answers 401/403 or the token is missing, i.e. the stored credential is
  /// no longer usable. Keeps `biometricsEnabled == true` so the next
  /// password/Google login silently re-enrolls this device.
  Future<void> _clearBiometricTokenOnly() async {
    try {
      final deviceId = await _storageService.getBiometricDeviceId();
      if (deviceId != null && deviceId.isNotEmpty) {
        await _storageService.clearBiometricToken(deviceId);
      }
    } catch (e) {
      debugPrint('Failed to clear biometric token: $e');
    }
  }

  /// Silent re-enroll after a successful password/Google login so the
  /// per-device biometric token always matches a live enrollment. Runs only
  /// when biometrics are enabled AND no token is stored (missing/empty) —
  /// a live enrollment stays untouched. Never throws; failures simply leave
  /// the state as-is — the next biometric login falls back to password
  /// sign-in and the login screen's status check catches stale tokens.
  Future<void> _reenrollBiometricsIfNeeded() async {
    try {
      if (!state.biometricsEnabled) return;
      final token = state.token ?? await _storageService.getToken();
      if (token == null || token.isEmpty) return;
      if (!await BiometricService.canAuthenticate()) return;

      final deviceId = await _storageService.getOrCreateBiometricDeviceId();
      final existing = await _storageService.getBiometricToken(deviceId);
      // Re-enroll ONLY when the stored token is missing or empty — otherwise
      // the (already valid) enrollment is kept as-is.
      if (existing != null && existing.isNotEmpty) return;

      final response = await _apiService.biometricEnroll(
        deviceId: deviceId,
        deviceName: BiometricService.deviceName(),
        platform: BiometricService.platformName(),
      );
      final data = response.data;
      String? biometricToken;
      if (data is Map && data['success'] == true && data['data'] is Map) {
        biometricToken = data['data']['biometric_token']?.toString();
      }
      if (biometricToken != null && biometricToken.isNotEmpty) {
        await _storageService.setBiometricToken(deviceId, biometricToken);
      }
    } catch (e) {
      debugPrint('Biometric re-enroll skipped: $e');
    }
  }

  /// SERVER-BACKED biometric login:
  /// 1. local_auth prompt (device PIN/pattern fallback allowed);
  /// 2. POST /auth/biometric/login with the stored biometric_token + device_id;
  /// 3. bootstrap the session exactly like password login (token storage,
  ///    socket, idle timer) on success; wipe the local enrollment on 401.
  Future<BiometricLoginResult> loginWithBiometrics() async {
    try {
      final authResult = await BiometricService.authenticate('Sign in to your account');
      if (!authResult.success) {
        return BiometricLoginResult(success: false, error: authResult.error);
      }

      final deviceId = await _storageService.getBiometricDeviceId();
      final biometricToken = (deviceId == null || deviceId.isEmpty)
          ? null
          : await _storageService.getBiometricToken(deviceId);
      if (deviceId == null || deviceId.isEmpty || biometricToken == null || biometricToken.isEmpty) {
        // Token gone locally — clear ONLY the token and keep the flag so the
        // next password/Google login silently re-enrolls.
        await _clearBiometricTokenOnly();
        return const BiometricLoginResult(
          success: false,
          revoked: true,
          error: 'Biometric unlock needs to be re-verified — please sign in once with your password.',
        );
      }

      try {
        final response = await _apiService.biometricLogin(
          biometricToken: biometricToken,
          deviceId: deviceId,
          deviceName: BiometricService.deviceName(),
        );
        final data = response.data;
        if (data is Map && data['success'] == true) {
          final token = data['token']?.toString() ?? '';
          final userId = data['userId']?.toString() ?? '';
          final businessId = data['businessId']?.toString() ?? '';
          if (token.isEmpty || userId.isEmpty || businessId.isEmpty) {
            return const BiometricLoginResult(
              success: false,
              error: 'Biometric sign-in returned an incomplete session. Please use your password.',
            );
          }
          // Display name: restore from the legacy credential copy (cleared
          // on logout) or the persisted user name; refreshed by /auth/me.
          final creds = await _storageService.getBiometricsCredentials();
          final userName = creds?['userName'] ?? await _storageService.getUserName() ?? userId;

          await Future.wait([
            _storageService.setToken(token),
            _storageService.setUserId(userId),
            _storageService.setBusinessId(businessId),
            _storageService.setUserName(userName),
          ]);

          _socketService.connect(userId, businessId, token: token);

          state = state.copyWith(
            token: token,
            userId: userId,
            businessId: businessId,
            userName: userName,
            isAuthenticated: true,
            // PER-ACCOUNT: sync the switch with the account the token belongs
            // to (the enrollment maps to exactly one account).
            biometricsEnabled: await BiometricService.isEnabled(userId),
          );
          resetIdleTimer();
          unawaited(getMe());
          return const BiometricLoginResult(success: true);
        }
        return BiometricLoginResult(
          success: false,
          error: ApiService.extractResponseMessage(data) ?? 'Biometric sign-in failed',
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 401 || status == 403) {
          // Credential rejected server-side — clear ONLY the stored token
          // (biometricsEnabled stays true so the next password/Google login
          // silently re-enrolls this device) and ask for the password.
          await _clearBiometricTokenOnly();
          return const BiometricLoginResult(
            success: false,
            revoked: true,
            error: 'Biometric unlock needs to be re-verified — please sign in once with your password.',
          );
        }
        return BiometricLoginResult(success: false, error: ApiService.extractErrorMessage(e));
      }
    } catch (e) {
      debugPrint('Biometric login failed: $e');
      return const BiometricLoginResult(success: false, error: 'An error occurred during biometric authentication');
    }
  }

  Future<bool> checkBiometricsAvailable() async {
    return await BiometricService.isAvailable();
  }

  /// Clears the SSO profile-completion gate after the business profile was
  /// successfully submitted (POST /settings/business/complete).
  Future<void> markProfileCompleted() async {
    try {
      await _storageService.setProfileCompleted(true);
      state = state.copyWith(profileCompleted: true);
    } catch (e) {
      debugPrint('Failed to mark profile completed: $e');
    }
  }

  Future<void> completeOnboarding() async {
    try {
      await _storageService.setHasSeenOnboarding(true);
      state = state.copyWith(hasSeenOnboarding: true);
      resetIdleTimer();
    } catch (e) {
      debugPrint('Failed to complete onboarding: $e');
    }
  }

  Future<void> skipKyc() async {
    try {
      state = state.copyWith(skippedKyc: true);
    } catch (e) {
      debugPrint('Failed to skip KYC: $e');
    }
  }

  Future<void> setAuthState({
    required String? token,
    required String? userId,
    required String? businessId,
    required bool isAuthenticated,
  }) async {
    try {
      final futures = <Future<void>>[];
      if (token != null) futures.add(_storageService.setToken(token));
      if (userId != null) futures.add(_storageService.setUserId(userId));
      if (businessId != null) futures.add(_storageService.setBusinessId(businessId));
      await Future.wait(futures);

      // Save biometrics credentials if enabled and all data is present
      if (state.biometricsEnabled && token != null && userId != null && businessId != null) {
        final userName = state.userName ?? userId;
        await _storageService.setBiometricsCredentials(
          token: token,
          userId: userId,
          businessId: businessId,
          userName: userName,
        );
      }

      // Connect socket if authenticated
      if (isAuthenticated && userId != null && businessId != null) {
        _socketService.connect(userId, businessId, token: token);
      }

      state = state.copyWith(
        token: token,
        userId: userId,
        businessId: businessId,
        isAuthenticated: isAuthenticated,
      );
      resetIdleTimer();
    } catch (e) {
      debugPrint('Failed to set auth state: $e');
    }
  }
}
