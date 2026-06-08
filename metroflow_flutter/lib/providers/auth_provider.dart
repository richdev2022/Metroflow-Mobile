import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../services/api.dart';
import '../services/biometrics.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? token;
  final String? userId;
  final String? businessId;
  final String? userName;
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
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      hasSeenOnboarding: hasSeenOnboarding ?? this.hasSeenOnboarding,
      skippedKyc: skippedKyc ?? this.skippedKyc,
    );
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  Timer? _idleTimer;
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  @override
  AuthState build() {
    _checkAuth();
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

  Future<void> _checkAuth() async {
    try {
      final token = await _storageService.getToken();
      final userId = await _storageService.getUserId();
      final businessId = await _storageService.getBusinessId();
      final userName = await _storageService.getUserName();
      final biometricsEnabled = await BiometricService.isEnabled();
      final hasSeenOnboarding = await _storageService.getHasSeenOnboarding();

      state = state.copyWith(
        token: token,
        userId: userId,
        businessId: businessId,
        userName: userName,
        biometricsEnabled: biometricsEnabled,
        hasSeenOnboarding: hasSeenOnboarding,
        isAuthenticated: token != null,
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

  Future<void> logout() async {
    try {
      _idleTimer?.cancel();
      
      // Keep biometrics enabled and last route on logout
      final biometricsEnabled = state.biometricsEnabled;
      final hasSeenOnboarding = state.hasSeenOnboarding;
      
      // Clear everything except biometricsEnabled and hasSeenOnboarding
      final storage = StorageService();
      await storage.clearAll();
      
      state = AuthState(
        isAuthenticated: false,
        isLoading: false,
        biometricsEnabled: biometricsEnabled,
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

          // Restore the credentials to storage
          await Future.wait([
            _storageService.setToken(token),
            _storageService.setUserId(userId),
            _storageService.setBusinessId(businessId),
            _storageService.setUserName(userName),
          ]);

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
