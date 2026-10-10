import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import 'modern_ui.dart';

/// Web-parity transaction-limits card (Wallet.tsx `WalletLimitCard`): an
/// amber panel showing the account tier's INFLOW (funding) and OUTFLOW
/// (transfer) limits with live daily head-room — shown on the wallet screen
/// and the home dashboard so users always see what their tier allows BEFORE
/// money moves.
///
/// Data shape = GET /wallet/limits → data (see [ApiService.getWalletLimits]).
class TransactionLimitsCard extends StatefulWidget {
  final VoidCallback? onUpgrade;

  const TransactionLimitsCard({super.key, this.onUpgrade});

  @override
  State<TransactionLimitsCard> createState() => _TransactionLimitsCardState();
}

class _TransactionLimitsCardState extends State<TransactionLimitsCard> {
  Map<String, dynamic>? _limits;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService().getWalletLimits();
      if (!mounted) return;
      setState(() {
        _limits = data;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  static String _symbol(String? currency) {
    switch ((currency ?? 'NGN').toUpperCase()) {
      case 'NGN':
        return '₦';
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return '$currency ';
    }
  }

  static String _fmt(dynamic value, String symbol) {
    final n = double.tryParse(value?.toString() ?? '') ?? 0;
    final text = n.round().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '$symbol$text';
  }

  Map<String, dynamic>? _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  @override
  Widget build(BuildContext context) {
    // Self-sufficient theming: resolves the app palette directly so every
    // call site can stay `const TransactionLimitsCard()`.
    final colors = AppTheme.colors;
    if (!_loaded) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.warning.withValues(alpha: 0.18)),
        ),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: colors.warning),
          ),
        ),
      );
    }

    final limits = _map(_limits?['limits']);
    final single = limits?['singleTransactionLimit'];
    // Hide entirely when the tier has no limits configured (web parity).
    if (single == null ||
        single.toString() == '' ||
        (double.tryParse(single.toString()) ?? 0) <= 0) {
      return const SizedBox.shrink();
    }

    final isRegistered = _limits?['isRegistered'] == true;
    final tierLabel = isRegistered ? 'Registered Business' : 'Non-Registered Business';
    final currency = _limits?['currency']?.toString() ?? 'NGN';
    final symbol = _symbol(currency);
    final inflow = _map(_limits?['inflow']);
    final remainingToday = inflow?['remainingToday'];
    final daily = limits?['dailyLimit'];
    final registeredLimits = _map(_limits?['registeredLimits']);
    final registeredSingle = registeredLimits?['singleTransactionLimit'];
    final upgradeHint = !isRegistered &&
        registeredSingle != null &&
        (double.tryParse(registeredSingle.toString()) ?? 0) > 0;

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 14, color: colors.textSecondary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12, color: colors.textSecondary, height: 1.3)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                        height: 1.3)),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.warning.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TintedCircleIcon(
                icon: Icons.speed_rounded,
                tint: colors.warning,
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Transaction limits — $tierLabel',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // INFLOW (funding)
          row(Icons.trending_up_rounded, 'Inflow · funding per transaction',
              _fmt(single, symbol)),
          if (daily != null)
            row(
                Icons.trending_up_rounded,
                'Inflow · daily limit',
                _fmt(daily, symbol) +
                    (remainingToday != null
                        ? ' · ${_fmt(remainingToday, symbol)} left today'
                        : '')),
          // OUTFLOW (transfers)
          row(Icons.trending_down_rounded, 'Outflow · transfer per transaction',
              '${_fmt(single, symbol)} (same tier)'),
          if (upgradeHint) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: widget.onUpgrade,
              child: Text(
                'Upgrade to a Registered Business to unlock up to ${_fmt(registeredSingle, symbol)} per transaction — limits apply to both funding and transfers. Tap to upgrade.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: colors.textSecondary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
