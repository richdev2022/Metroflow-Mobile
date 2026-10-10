import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api.dart';
import 'app_toast.dart';

/// Tier-1 KYC gate shared by EVERY finance entry point — main_screen tabs +
/// drawer/More-sheet tiles and the dashboard's quick actions / "Get Paid" hub
/// / money row.
///
/// ONBOARDING CHANGE: KYC is no longer part of signup/login (a fresh account
/// lands straight on the dashboard), so this gate is the single place that
/// DEMANDS identity verification — right before the user actually uses a
/// financial feature (wallet, transfers, payroll, payment links, invoices,
/// store, subscriptions).
///
/// Semantics mirror the backend's `checkKycStatus` middleware EXACTLY:
/// verified = BVN **OR** NIN. The old client-side AND logic locked
/// BVN-only users out of features the server already allowed.
class KycGate {
  /// Guards against double concurrent checks (rapid double-taps).
  static bool _checking = false;

  /// Returns `true` when the user may use a finance feature. When nothing is
  /// verified yet, routes to `/kyc-prompt` (the BVN/NIN collection flow) and
  /// returns `false`. On network failure it fails CLOSED with a toast — the
  /// backend re-checks every money endpoint anyway (403 KYC_REQUIRED).
  static Future<bool> canUseFinance(BuildContext context) async {
    if (_checking) return false;
    _checking = true;
    try {
      final response = await ApiService().getKycStatus();
      if (!context.mounted) return false;

      final data = response.data;
      final root = data is Map ? data : <String, dynamic>{};
      final user = root['user'] is Map ? root['user'] as Map : null;

      final bvnVerified = user?['bvnStatus'] == 'verified' ||
          user?['bvn_status'] == 'verified' ||
          root['bvn_verified'] == true;
      final ninVerified = user?['ninStatus'] == 'verified' ||
          user?['nin_status'] == 'verified' ||
          root['nin_verified'] == true;

      // EITHER identity document unlocks finance features (backend parity).
      if (bvnVerified || ninVerified) return true;

      // Nothing verified yet — collect BVN/NIN via the KYC journey.
      context.go('/kyc-prompt');
      return false;
    } catch (_) {
      if (context.mounted) {
        AppToast.show('Unable to confirm KYC status. Please try again.');
      }
      return false;
    } finally {
      _checking = false;
    }
  }
}
