import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api.dart';
import '../services/biometrics.dart';
import '../services/google_auth_service.dart';
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
    );
  }
}

// Global variable to hold the auth notifier instance (set in main.dart)
AuthNotifier? authNotifierInstance;

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  Timer? _idleTimer;
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final SocketService _socketService = SocketService();
  final GoogleAuthService _googleAuthService = GoogleAuthService();

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
        logout();
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
      final biometricsEnabled = await BiometricService.isEnabled();
      final hasSeenOnboarding = await _storageService.getHasSeenOnboarding();

      final isTokenValid = token != null;

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
      final userName = data['user']?['name'] ?? email;

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

      // Same session persistence path as password login.
      await _storageService.setToken(token.toString());
      if (userId != null) await _storageService.setUserId(userId);
      if (businessId != null) await _storageService.setBusinessId(businessId);
      await _storageService.setUserName(userName);
      await _storageService.setAvatarUrl(avatarUrl);
      await _storageService.setAuthProvider(authProvider);
      await _storageService.setRequiresPasswordSetup(requiresPasswordSetup);

      // Save biometrics credentials if enabled (same as password login).
      if (state.biometricsEnabled && userId != null && businessId != null) {
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
      );
      resetIdleTimer();

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
      final userName = data['user']?['name'] ?? email;

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

  Future<void> logout({bool disableBiometrics = false}) async {
    try {
      _idleTimer?.cancel();
      clearMeCache();

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
        await BiometricService.disableBiometrics();
        await BiometricService.resetPromptStatus();
        await storage.clearBiometricsCredentials();
      }
      
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

  Future<BiometricResult> enableBiometricsWithResult() async {
    try {
      final result = await BiometricService.enableBiometricsWithResult();
      if (result.success) {
        // Save current credentials for biometrics login
        final token = state.token;
        final userId = state.userId;
        final businessId = state.businessId;
        final userName = state.userName;
        if (token != null && userId != null && businessId != null && userName != null) {
          await _storageService.setBiometricsCredentials(
            token: token,
            userId: userId,
            businessId: businessId,
            userName: userName,
          );
        }
        state = state.copyWith(biometricsEnabled: true);
      }
      resetIdleTimer();
      return result;
    } catch (e) {
      debugPrint('Enable biometrics failed: $e');
      return BiometricResult(success: false, error: 'Failed to enable biometric login');
    }
  }

  Future<void> disableBiometrics() async {
    try {
      await BiometricService.disableBiometrics();
      await BiometricService.resetPromptStatus();
      await _storageService.clearBiometricsCredentials();
      state = state.copyWith(biometricsEnabled: false);
      resetIdleTimer();
    } catch (e) {
      debugPrint('Disable biometrics failed: $e');
    }
  }

  Future<bool> loginWithBiometrics() async {
    try {
      final authResult = await BiometricService.authenticate('Sign in to your account');
      if (authResult.success) {
        final credentials = await _storageService.getBiometricsCredentials();
        if (credentials != null) {
          final token = credentials['token']!;
          final userId = credentials['userId']!;
          final businessId = credentials['businessId']!;
          final userName = credentials['userName']!;

          // Restore all credentials
          await Future.wait([
            _storageService.setToken(token),
            _storageService.setUserId(userId),
            _storageService.setBusinessId(businessId),
            _storageService.setUserName(userName),
          ]);

          // Connect socket
          _socketService.connect(userId, businessId, token: token);

          state = state.copyWith(
            token: token,
            userId: userId,
            businessId: businessId,
            userName: userName,
            isAuthenticated: true,
          );
          resetIdleTimer();
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Biometric login failed: $e');
      return false;
    }
  }

  Future<bool> checkBiometricsAvailable() async {
    return await BiometricService.isAvailable();
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
