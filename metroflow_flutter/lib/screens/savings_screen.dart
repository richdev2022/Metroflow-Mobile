import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';

/// Savings Vaults — daily-use revenue feature. Goal-based vaults with
/// auto-save (daily/weekly/monthly) pulling from a wallet; early withdrawal
/// before the target date charges a break fee (2% cap ₦5,000, discounted on
/// paid plans). Web counterpart: /savings.
class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  final ApiService _api = ApiService();

  List<Map<String, dynamic>> _vaults = [];
  Map<String, dynamic>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.getSavingsVaults();
      if (!mounted) return;
      if (res.data['success'] == true) {
        setState(() {
          _vaults = ((res.data['vaults'] as List<dynamic>?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _stats = res.data['stats'] == null ? null : Map<String, dynamic>.from(res.data['stats']);
        });
      }
    } catch (e) {
      debugPrint('Failed to load savings vaults: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _money(dynamic v, [String currency = 'NGN']) {
    final n = double.tryParse(v?.toString() ?? '0') ?? 0;
    final symbol = currency == 'USD' ? r'$' : '₦';
    return '$symbol${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2)}';
  }

  double _progress(Map<String, dynamic> vault) {
    final goal = double.tryParse('${vault['goal_amount'] ?? 0}') ?? 0;
    final balance = double.tryParse('${vault['balance'] ?? 0}') ?? 0;
    if (goal <= 0) return 0;
    return (balance / goal).clamp(0.0, 1.0);
  }

  bool _isEarlyBreak(Map<String, dynamic> vault) {
    final target = DateTime.tryParse('${vault['target_date'] ?? ''}');
    if (target == null) return false;
    final today = DateTime.now();
    return target.isAfter(DateTime(today.year, today.month, today.day));
  }

  String _freqLabel(String? freq) {
    switch (freq) {
      case 'weekly':
        return 'every week';
      case 'monthly':
        return 'every month';
      default:
        return 'every day';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: Text('Savings Vaults',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _openCreateSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New vault'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Row(
                    children: [
                      _statCard('Total saved', _money(_stats?['total_saved'] ?? 0)),
                      const SizedBox(width: 10),
                      _statCard('Vaults', '${_stats?['total_vaults'] ?? 0}'),
                      const SizedBox(width: 10),
                      _statCard('Auto-saves on', '${_stats?['active_auto_saves'] ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_vaults.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(Icons.savings_outlined, size: 44, color: colors.textSecondary),
                          const SizedBox(height: 12),
                          Text('No vaults yet',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700, color: colors.text)),
                          const SizedBox(height: 6),
                          Text(
                            'Create a vault and save towards a goal — rent, equipment or that next big move.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: colors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._vaults.map((vault) => _vaultCard(vault)),
                  const SizedBox(height: 12),
                  Text(
                    'Deposits debit your wallet instantly. Withdrawing before the target date charges a small early-break fee (2%, max ₦5,000 — lower on paid plans).',
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statCard(String label, String value) {
    final colors = AppTheme.colors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: colors.textSecondary)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
          ],
        ),
      ),
    );
  }

  Widget _vaultCard(Map<String, dynamic> vault) {
    final colors = AppTheme.colors;
    final progress = _progress(vault);
    final paused = '${vault['status']}' == 'paused';
    final autoSave = vault['auto_save_enabled'] == true;
    final early = _isEarlyBreak(vault);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${vault['name']}',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.text)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: paused ? colors.textSecondary.withValues(alpha: 0.12) : const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(paused ? 'Paused' : 'Active',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: paused ? colors.textSecondary : const Color(0xFF10B981))),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            vault['goal_amount'] != null
                ? 'Goal ${_money(vault['goal_amount'], '${vault['currency'] ?? 'NGN'}')}${vault['target_date'] != null ? ' · by ${_shortDate('${vault['target_date']}')}' : ''}'
                : 'Flexible savings',
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
          const SizedBox(height: 10),
          Text(_money(vault['balance'], '${vault['currency'] ?? 'NGN'}'),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: colors.text)),
          if (progress > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: colors.textSecondary.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 4),
            Text('${(progress * 100).round()}% of goal',
                style: TextStyle(fontSize: 11, color: colors.textSecondary)),
          ],
          if (autoSave) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.autorenew_rounded, size: 13, color: AppColors.primary),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'Auto-save ${_money(vault['auto_save_amount'])} ${_freqLabel('${vault['auto_save_frequency'] ?? 'daily'}')}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openMoneySheet(vault, 'deposit'),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Deposit', style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openMoneySheet(vault, 'withdraw'),
                  icon: const Icon(Icons.account_balance_wallet_outlined, size: 16),
                  label: const Text('Withdraw', style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.text,
                    side: BorderSide(color: colors.border),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _togglePause(vault),
                tooltip: paused ? 'Resume' : 'Pause',
                icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 20, color: colors.textSecondary),
              ),
              if (double.tryParse('${vault['balance'] ?? 0}') == 0)
                IconButton(
                  onPressed: () => _deleteVault(vault),
                  tooltip: 'Delete',
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: colors.textSecondary),
                ),
            ],
          ),
          if (early) ...[
            const SizedBox(height: 6),
            Text('Withdrawing before the target date attracts an early-break fee.',
                style: TextStyle(fontSize: 10.5, color: colors.textSecondary)),
          ],
        ],
      ),
    );
  }

  String _shortDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day}/${d.month}/${d.year}';
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _togglePause(Map<String, dynamic> vault) async {
    final paused = '${vault['status']}' == 'paused';
    try {
      final res = await _api.updateSavingsVault('${vault['id']}', {
        'status': paused ? 'active' : 'paused',
      });
      if (res.data?['success'] == true) {
        _load();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ApiService.extractErrorMessage(res))));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiService.extractErrorMessage(e))));
      }
    }
  }

  Future<void> _deleteVault(Map<String, dynamic> vault) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete vault?'),
        content: Text('"${vault['name']}" will be removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await _api.deleteSavingsVault('${vault['id']}');
      if (res.data?['success'] == true) {
        _load();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ApiService.extractErrorMessage(res))));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiService.extractErrorMessage(e))));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadWallets() async {
    try {
      final res = await _api.getWallet();
      final data = res.data;
      final list = <Map<String, dynamic>>[];
      if (data?['user_wallet'] != null) list.add(Map<String, dynamic>.from(data!['user_wallet']));
      if (data?['business_wallet'] != null) {
        list.add(Map<String, dynamic>.from(data!['business_wallet']));
      }
      return list;
    } catch (e) {
      debugPrint('Failed to load wallets: $e');
      return [];
    }
  }

  Future<void> _openMoneySheet(Map<String, dynamic> vault, String mode) async {
    final colors = AppTheme.colors;
    final amountCtrl = TextEditingController();
    String? walletId;
    List<Map<String, dynamic>> wallets = [];
    bool submitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            if (wallets.isEmpty) {
              _loadWallets().then((list) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    wallets = list;
                    walletId ??= list.isNotEmpty ? '${list.first['id']}' : null;
                  });
                }
              });
            }

            Future<void> submit() async {
              final amount = double.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
                return;
              }
              if (walletId == null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Choose a wallet')));
                return;
              }
              setSheetState(() => submitting = true);
              try {
                final payload = {'amount': amount, 'wallet_id': walletId};
                final res = mode == 'deposit'
                    ? await _api.depositToVault('${vault['id']}', payload)
                    : await _api.withdrawFromVault('${vault['id']}', payload);
                final ok = res.data?['success'] == true;
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok
                        ? (mode == 'deposit'
                            ? 'Added ${_money(amount)} to "${vault['name']}"'
                            : 'Withdrew ${_money(res.data?['payout'] ?? amount)}${res.data?['fee'] != null && double.tryParse('${res.data?['fee']}')! > 0 ? ' (fee: ${_money(res.data?['fee'])})' : ''}')
                        : ApiService.extractErrorMessage(res)),
                  ));
                }
                if (ok) _load();
              } catch (e) {
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(ApiService.extractErrorMessage(e))));
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode == 'deposit' ? 'Deposit into ${vault['name']}' : 'Withdraw from ${vault['name']}',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode == 'deposit'
                        ? 'Move money from a wallet into this vault.'
                        : _isEarlyBreak(vault)
                            ? 'Heads up: an early-break fee applies before the target date.'
                            : 'Money returns to your wallet in full — no fees.',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Amount',
                      prefixText: '₦ ',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: walletId,
                    isExpanded: true,
                    dropdownColor: colors.surface,
                    hint: Text(wallets.isEmpty ? 'Loading wallets…' : 'Choose wallet',
                        style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: wallets
                        .map((w) => DropdownMenuItem(
                              value: '${w['id']}',
                              child: Text(
                                  '${w['business_id'] != null ? 'Business' : 'Personal'} wallet — ${_money(w['balance'], '${w['currency'] ?? 'NGN'}')}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: colors.text)),
                            ))
                        .toList(),
                    onChanged: (v) => setSheetState(() => walletId = v),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: submitting ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(mode == 'deposit' ? 'Deposit' : 'Withdraw',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openCreateSheet() {
    final colors = AppTheme.colors;
    final nameCtrl = TextEditingController();
    final goalCtrl = TextEditingController();
    final autoAmountCtrl = TextEditingController();
    DateTime? targetDate;
    bool autoSave = false;
    String frequency = 'daily';
    String? walletId;
    List<Map<String, dynamic>> wallets = [];
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            if (wallets.isEmpty) {
              _loadWallets().then((list) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    wallets = list;
                    walletId ??= list.isNotEmpty ? '${list.first['id']}' : null;
                  });
                }
              });
            }

            Future<void> submit() async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Give your vault a name')));
                return;
              }
              setSheetState(() => submitting = true);
              try {
                final res = await _api.createSavingsVault({
                  'name': name,
                  if (goalCtrl.text.trim().isNotEmpty)
                    'goal_amount': double.tryParse(goalCtrl.text.trim()),
                  'target_date': targetDate?.toIso8601String().split('T').first,
                  'auto_save_enabled': autoSave,
                  if (autoSave) 'auto_save_amount': double.tryParse(autoAmountCtrl.text.trim()),
                  if (autoSave) 'auto_save_frequency': frequency,
                  if (autoSave) 'auto_save_wallet_id': walletId,
                });
                final ok = res.data?['success'] == true;
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? 'Vault "$name" created' : ApiService.extractErrorMessage(res)),
                  ));
                }
                if (ok) _load();
              } catch (e) {
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(ApiService.extractErrorMessage(e))));
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New savings vault',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colors.text)),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        hintText: 'Vault name (e.g. New shop rent)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: goalCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Goal (₦)',
                              prefixText: '₦ ',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: sheetContext,
                                initialDate: targetDate ?? DateTime.now().add(const Duration(days: 30)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 3650)),
                              );
                              if (picked != null) setSheetState(() => targetDate = picked);
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                hintText: 'Target date',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              child: Text(
                                targetDate != null ? _shortDate(targetDate!.toIso8601String()) : '',
                                style: TextStyle(fontSize: 13, color: colors.text),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Switch(
                          value: autoSave,
                          activeColor: AppColors.primary,
                          onChanged: (v) => setSheetState(() => autoSave = v),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('Auto-save (move money automatically)',
                              style: TextStyle(fontSize: 13, color: colors.text)),
                        ),
                      ],
                    ),
                    if (autoSave) ...[
                      TextField(
                        controller: autoAmountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Auto-save amount (₦)',
                          prefixText: '₦ ',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: frequency,
                        dropdownColor: colors.surface,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'daily', child: Text('Every day')),
                          DropdownMenuItem(value: 'weekly', child: Text('Every week')),
                          DropdownMenuItem(value: 'monthly', child: Text('Every month')),
                        ],
                        onChanged: (v) => setSheetState(() => frequency = v ?? 'daily'),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: walletId,
                        isExpanded: true,
                        dropdownColor: colors.surface,
                        hint: Text(wallets.isEmpty ? 'Loading wallets…' : 'From wallet',
                            style: TextStyle(fontSize: 13, color: colors.textSecondary)),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: wallets
                            .map((w) => DropdownMenuItem(
                                  value: '${w['id']}',
                                  child: Text(
                                      '${w['business_id'] != null ? 'Business' : 'Personal'} wallet — ${_money(w['balance'], '${w['currency'] ?? 'NGN'}')}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13, color: colors.text)),
                                ))
                            .toList(),
                        onChanged: (v) => setSheetState(() => walletId = v),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: submitting ? null : submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Create vault',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
