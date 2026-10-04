import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api.dart';
import '../models/kyc_status.dart';
import 'auth_provider.dart';

class KycState {
  final KycStatus? status;
  final bool isLoading;
  final String? error;

  KycState({
    this.status,
    this.isLoading = false,
    this.error,
  });

  KycState copyWith({
    KycStatus? status,
    bool? isLoading,
    String? error,
  }) {
    return KycState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

final kycProvider = NotifierProvider<KycNotifier, KycState>(KycNotifier.new);

class KycNotifier extends Notifier<KycState> {
  final ApiService _apiService = ApiService();

  @override
  KycState build() {
    // Listen to auth provider changes
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.isAuthenticated && next.token != null) {
        Future.microtask(() => fetchKycStatus());
      } else if (previous?.isAuthenticated == true && !next.isAuthenticated) {
        // Reset KYC state if logged out
        Future.microtask(() => state = KycState());
      }
    });
    
    // Schedule a microtask to check auth state after initial build
    Future.microtask(() {
      try {
        final authState = ref.read(authProvider);
        if (authState.isAuthenticated && authState.token != null) {
          fetchKycStatus();
        }
      } catch (e) {
        // Ignore if provider isn't initialized yet
        debugPrint('KYC provider: auth not yet initialized: $e');
      }
    });
    
    return KycState();
  }

  Future<void> fetchKycStatus() async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final response = await _apiService.getKycStatus();
      final data = response.data;
      final kycStatus = KycStatus.fromJson(data);
      state = state.copyWith(status: kycStatus, isLoading: false);
    } catch (e) {
      debugPrint('Fetch KYC status failed: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}
