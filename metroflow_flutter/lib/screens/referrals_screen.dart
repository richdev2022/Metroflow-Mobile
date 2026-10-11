import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

/// Refer & Earn — the user's referral code, stats and referred users.
///
/// Mirrors the web /referrals page: share code/link, watch referred users
/// subscribe, and see the bonus land in the Metricorex wallet
/// (amount configured by admins via GET /referrals/public-config data).
class ReferralsScreen extends ConsumerStatefulWidget {
  const ReferralsScreen({super.key});

  @override
  ConsumerState<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends ConsumerState<ReferralsScreen> {
  final ApiService _api = ApiService();

  bool _loading = true;
  String? _referralCode;
  String? _referralLink;
  bool _referralEnabled = true;
  num _bonusAmount = 0;
  String _bonusCurrency = 'NGN';
  int _totalReferred = 0;
  int _subscribed = 0;
  num _totalEarned = 0;
  List<Map<String, dynamic>> _referred = [];
  bool? _hasReferrer;

  String get _bonusText => _formatMoney(_bonusAmount, _bonusCurrency);

  String _formatMoney(num amount, String currency) {
    final symbol = switch (currency) {
      'NGN' => '₦',
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '$currency ',
    };
    final value = amount is int ? amount.toString() : amount.toStringAsFixed(2);
    return '$symbol$value';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await _api.getReferralInfo();
      final data = (response.data['data'] ?? {}) as Map;
      if (!mounted) return;
      setState(() {
        _referralCode = data['referralCode']?.toString();
        _referralLink = data['referralLink']?.toString();
        _hasReferrer = data['hasReferrer'] == true;
        final config = (data['config'] ?? {}) as Map;
        _referralEnabled = config['enabled'] == true;
        _bonusAmount = (config['amount'] as num?) ?? 0;
        _bonusCurrency = (config['currency'] ?? 'NGN').toString();
        final stats = (data['stats'] ?? {}) as Map;
        _totalReferred = (stats['totalReferred'] as num?)?.toInt() ?? 0;
        _subscribed = (stats['subscribed'] as num?)?.toInt() ?? 0;
        _totalEarned = (stats['totalEarned'] as num?) ?? 0;
        _referred = ((data['referred'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.show('Could not load referrals', type: AppToastType.error);
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    AppToast.show('$label copied', type: AppToastType.success);
  }

  Future<void> _share() async {
    final link = _referralLink;
    if (link == null || link.isEmpty) return;
    await SharePlus.instance.share(ShareParams(
      text:
          'Join me on Metricorex — operations, meetings, chat, payroll and MetricAi in one platform. Use my referral link: $link',
      title: 'Metricorex — Refer & Earn',
    ));
  }

  Future<void> _claimCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Have a referral code?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'If someone referred you, enter their code so they get credited when you subscribe.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'e.g. K7M2PQ9X',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim().toUpperCase()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.claimReferralCode(code);
      if (!mounted) return;
      AppToast.show('Referral code applied', type: AppToastType.success);
      await _load();
    } catch (_) {
      if (!mounted) return;
      AppToast.show("That code couldn't be applied", type: AppToastType.error);
    }
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '—';
    final d = DateTime.tryParse(value);
    if (d == null) return '—';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: const Text('Refer & Earn', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // ---- Code + link card ----
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR REFERRAL CODE',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _referralCode ?? '—',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 3,
                                ),
                              ),
                            ),
                            _pillButton(
                              icon: Icons.copy_rounded,
                              label: 'Copy',
                              onTap: () =>
                                  _copy(_referralCode ?? '', 'Referral code'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'REFERRAL LINK',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _referralLink ?? '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _roundIcon(Icons.share_rounded, _share),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.emoji_events_rounded,
                                    color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _referralEnabled
                                          ? '$_bonusText per referral'
                                          : 'Referral bonus',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      'Earned when a business you refer subscribes',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.85),
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ---- Stats ----
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _statCard('People referred', '$_totalReferred', Icons.group_outlined,
                          const Color(0xFF2563EB)),
                      const SizedBox(width: 12),
                      _statCard('Subscribed', '$_subscribed', Icons.trending_up_rounded,
                          const Color(0xFF059669)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.account_balance_wallet_outlined,
                              color: Color(0xFF059669), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total earned',
                                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                              Text(
                                _formatMoney(_totalEarned, _bonusCurrency),
                                style: const TextStyle(
                                  color: Color(0xFF059669),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                ),
                              ),
                              Text('Credited to your Metricorex wallet',
                                  style: TextStyle(color: colors.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ---- Claim code (no referrer yet) ----
                  if (_hasReferrer == false) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.border.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.handshake_outlined,
                                color: Color(0xFF2563EB), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Were you referred by someone? Apply their code.',
                              style: TextStyle(fontSize: 13, color: colors.text),
                            ),
                          ),
                          TextButton(onPressed: _claimCode, child: const Text('Enter')),
                        ],
                      ),
                    ),
                  ],

                  // ---- Referred users ----
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Referred users',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: colors.text)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('$_totalReferred',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_referred.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.border.withOpacity(0.5)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.auto_awesome,
                                color: Color(0xFF2563EB), size: 22),
                          ),
                          const SizedBox(height: 10),
                          Text('No referrals yet',
                              style: TextStyle(fontWeight: FontWeight.w700, color: colors.text)),
                          const SizedBox(height: 4),
                          Text(
                            'Share your link — you earn $_bonusText every time someone you referred subscribes to a plan.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textSecondary, fontSize: 12.5, height: 1.5),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._referred.map((user) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: colors.border.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFF2563EB).withOpacity(0.12),
                                child: Text(
                                  ((user['name'] ?? user['email'] ?? '?').toString()).isNotEmpty
                                      ? (user['name'] ?? user['email'] ?? '?').toString()[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Color(0xFF2563EB), fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (user['name'] ?? user['email'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: colors.text),
                                    ),
                                    Text(
                                      '${(user['businessName'] ?? '')?.toString().isNotEmpty == true ? '${user['businessName']} · ' : ''}Joined ${_formatDate(user['joinedAt']?.toString())}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: colors.textSecondary, fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _referralStatusChip(user),
                            ],
                          ),
                        )),

                  // ---- How it works ----
                  const SizedBox(height: 20),
                  Text('How it works',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15, color: colors.text)),
                  const SizedBox(height: 10),
                  _howItWorksRow(Icons.share_rounded, '1. Share your link',
                      'Send your referral link or code to friends, clients and business owners.'),
                  _howItWorksRow(Icons.group_add_rounded, '2. They sign up & subscribe',
                      'They create a workspace with your code and subscribe to any plan.'),
                  _howItWorksRow(Icons.account_balance_wallet_outlined, '3. You earn',
                      'Your $_bonusText lands in your Metricorex wallet automatically.'),
                ],
              ),
            ),
    );
  }

  Widget _pillButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 15),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: Colors.white, size: 18)),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color accent) {
    final colors = AppTheme.colors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: colors.text)),
            Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  Widget _referralStatusChip(Map<String, dynamic> user) {
    final status = (user['status'] ?? 'pending').toString();
    final (label, bg, fg) = switch (status) {
      'paid' => ('Bonus paid', const Color(0xFF059669), Colors.white),
      'subscribed' => ('Subscribed', const Color(0xFF2563EB), Colors.white),
      _ => ('Not subscribed', Colors.grey.withOpacity(0.15), Colors.grey),
    };
    String? bonus;
    if (status == 'paid' && user['bonusAmount'] != null) {
      bonus = '+${_formatMoney(user['bonusAmount'] as num, (user['bonusCurrency'] ?? 'NGN').toString())}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
          child: Text(label, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ),
        if (bonus != null) ...[
          const SizedBox(height: 4),
          Text(bonus,
              style: const TextStyle(
                  color: Color(0xFF059669), fontWeight: FontWeight.w700, fontSize: 12.5)),
        ],
      ],
    );
  }

  Widget _howItWorksRow(IconData icon, String title, String body) {
    final colors = AppTheme.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: colors.text)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
