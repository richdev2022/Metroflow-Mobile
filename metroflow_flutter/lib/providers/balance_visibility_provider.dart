import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BALANCE HIDE/SHOW (privacy toggle)
/// ----------------------------------
/// A single app-wide switch that masks every balance surface (dashboard hero
/// strip, wallet cards, home "Your money" section) behind dots (••••••) until
/// the user taps the eye icon. Persisted in SharedPreferences so the choice
/// survives app restarts, and exposed as a Riverpod Notifier so every screen
/// watching it re-masks instantly when toggled.
///
/// Usage in a screen:
///   final balanceHidden = ref.watch(balanceVisibilityProvider);
///   Text(balanceHidden ? '••••••' : _formatCurrency(amount));
///   IconButton(
///     icon: Icon(balanceHidden ? Icons.visibility_off : Icons.visibility),
///     onPressed: () => ref.read(balanceVisibilityProvider.notifier).toggle(),
///   );

const String _kBalanceHidden = 'balance_hidden_v1';

class BalanceVisibilityNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Optimistic default (visible); hydrate() loads the persisted choice.
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_kBalanceHidden);
      if (stored != null && stored != state) {
        state = stored;
      }
    } catch (e) {
      debugPrint('BalanceVisibility load failed: $e');
    }
  }

  Future<void> toggle() async {
    final next = !state;
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kBalanceHidden, next);
    } catch (e) {
      debugPrint('BalanceVisibility persist failed: $e');
    }
  }

  /// Mask helper — turns any formatted amount into uniform dots that keep a
  /// similar width footprint without revealing the value.
  static String mask() => '••••••';
}

final balanceVisibilityProvider =
    NotifierProvider<BalanceVisibilityNotifier, bool>(
  BalanceVisibilityNotifier.new,
);
