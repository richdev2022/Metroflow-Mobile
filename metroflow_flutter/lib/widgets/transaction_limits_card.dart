import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import 'modern_ui.dart';

/// Web-parity transaction-limits card (Wallet.tsx `WalletLimitCard`): an
/// amber panel showing the account tier's INFLOW (funding) and OUTFLOW
/// (transfer) limits with live daily head-room.
///
/// Data shape = GET /wallet/limits → data (see [ApiService.getWalletLimits]).
///
/// Surfaces:
///   • inline card (legacy — kept for embedders) via [TransactionLimitsCard]
///   • modal popup via [showTransactionLimitsModal], used by the home
///     dashboard (post-login), the wallet screen and the payroll screen.
///     Each surface pops the modal at most ONCE per app session — see
///     [TransactionLimitsSession] — and the modal silently no-ops when the
///     tier has no limits configured.

/// Per-session "already popped" flags. Static so they survive route changes
/// and are reset on a fresh login (auth provider calls [reset]).
class TransactionLimitsSession {
  static bool loginShown = false;
  static bool walletShown = false;
  static bool payrollShown = false;

  static void reset() {
    loginShown = false;
    walletShown = false;
    payrollShown = false;
  }
}

/// Pops the transaction-limits modal (once per session per surface). The
/// modal fetches GET /wallet/limits itself and auto-dismisses when the tier
/// has no limits configured, so callers never need to pre-check.
///
/// Choosing "Upgrade Now" pops the dialog with 'upgrade' and (by default)
/// pushes /business-kyc-upgrade on the caller's context.
Future<void> showTransactionLimitsModal(
  BuildContext context, {
  bool navigateOnUpgrade = true,
}) async {
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    builder: (dialogContext) => const _TransactionLimitsModal(),
  );
  if (result == 'upgrade' && navigateOnUpgrade && context.mounted) {
    await context.push('/business-kyc-upgrade');
  }
}

class _TransactionLimitsModal extends StatefulWidget {
  const _TransactionLimitsModal();

  @override
  State<_TransactionLimitsModal> createState() =>
      _TransactionLimitsModalState();
}

class _TransactionLimitsModalState extends State<_TransactionLimitsModal> {
  Map<String, dynamic>? _limits;
  bool _loaded = false;
  bool _autoClosed = false;

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
      // Network hiccup — never trap the user in a modal; just close it.
      Navigator.of(context).pop();
    }
  }

  /// The tier has nothing configured — auto-close so the modal never shows
  /// an empty shell (same predicate as the inline card's hidden state).
  bool get _hasContent {
    final limits = _limits?['limits'];
    final single = limits is Map ? limits['singleTransactionLimit'] : null;
    final value = double.tryParse(single?.toString() ?? '') ?? 0;
    return single != null && single.toString() != '' && value > 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded && !_hasContent && !_autoClosed) {
      _autoClosed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.colors.warning.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: !_loaded
            ? const Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            : !_hasContent
                ? const SizedBox(height: 10, width: 10)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LimitsPanel(
                        limits: _limits!,
                        rounded: false,
                      ),
                      const SizedBox(height: 16),
                      // -------------------------------------------- CTAs
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop('upgrade');
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.colors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.rocket_launch_rounded, size: 17),
                          label: const Text(
                            'Upgrade Now',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop('skip'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.colors.textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text(
                            'Skip for now — I\'ll do it later',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// Inline card wrapper (legacy embed point — wallet/home used to render this
/// directly; the modal is the primary surface now).
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

    final limits = _limits?['limits'];
    final single = limits is Map ? limits['singleTransactionLimit'] : null;
    // Hide entirely when the tier has no limits configured (web parity).
    if (single == null ||
        single.toString() == '' ||
        (double.tryParse(single.toString()) ?? 0) <= 0) {
      return const SizedBox.shrink();
    }

    return _LimitsPanel(limits: _limits!, onUpgrade: widget.onUpgrade);
  }
}

/// Shared visual body: amber panel with the tier's inflow/outflow limits,
/// daily head-room and (when applicable) the registered-tier upgrade hint.
class _LimitsPanel extends StatelessWidget {
  final Map<String, dynamic> limits;

  /// Rounded container (inline card). The modal draws its own container, so
  /// it passes false.
  final bool rounded;
  final VoidCallback? onUpgrade;

  const _LimitsPanel({required this.limits, this.rounded = true, this.onUpgrade});

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
    final colors = AppTheme.colors;
    final limitsMap = _map(limits['limits']);
    final single = limitsMap?['singleTransactionLimit'];
    final isRegistered = limits['isRegistered'] == true;
    final tierLabel = isRegistered ? 'Registered Business' : 'Non-Registered Business';
    final currency = limits['currency']?.toString() ?? 'NGN';
    final symbol = _symbol(currency);
    final inflow = _map(limits['inflow']);
    final remainingToday = inflow?['remainingToday'];
    final daily = limitsMap?['dailyLimit'];
    final registeredLimits = _map(limits['registeredLimits']);
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

    final body = Column(
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
          if (onUpgrade != null)
            GestureDetector(
              onTap: onUpgrade,
              child: Text(
                'Upgrade to a Registered Business to unlock up to ${_fmt(registeredSingle, symbol)} per transaction — limits apply to both funding and transfers. Tap to upgrade.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: colors.textSecondary,
                  decoration: TextDecoration.underline,
                ),
              ),
            )
          else
            Text(
              'Upgrade to a Registered Business to unlock up to ${_fmt(registeredSingle, symbol)} per transaction — limits apply to both funding and transfers.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: colors.textSecondary,
              ),
            ),
        ],
      ],
    );

    if (!rounded) return body;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.warning.withValues(alpha: 0.25)),
      ),
      child: body,
    );
  }
}
