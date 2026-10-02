import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/api.dart';

/// Bills Hub — daily-use revenue feature. Pay airtime, data, TV, electricity
/// and betting top-ups straight from any wallet. Every payment is
/// PIN-verified and charged amount + a flat convenience fee (reduced on paid
/// plans). Web counterpart: /bills.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  final ApiService _api = ApiService();

  static const Map<String, (String, IconData)> _categories = {
    'airtime': ('Airtime', Icons.smartphone_rounded),
    'data': ('Data', Icons.wifi_rounded),
    'tv': ('TV', Icons.tv_rounded),
    'electricity': ('Electricity', Icons.bolt_rounded),
    'betting': ('Betting', Icons.sports_esports_rounded),
  };

  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _bills = [];
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String _category = 'airtime';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([_api.getBillsCatalog(), _api.getBills()]);
      if (!mounted) return;
      final catalog = results[0].data;
      final history = results[1].data;
      setState(() {
        _providers = ((catalog?['providers'] as List<dynamic>?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _bills = ((history?['bills'] as List<dynamic>?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _stats = history?['stats'] == null ? null : Map<String, dynamic>.from(history!['stats']);
      });
    } catch (e) {
      debugPrint('Failed to load bills: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _money(dynamic v, [String currency = 'NGN']) {
    final n = double.tryParse(v?.toString() ?? '0') ?? 0;
    final symbol = currency == 'USD' ? r'$' : '₦';
    return '$symbol${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2)}';
  }

  List<Map<String, dynamic>> get _categoryProviders =>
      _providers.where((p) => p['category'] == _category).toList();

  (String, Color) _statusMeta(String status) {
    switch (status) {
      case 'success':
        return ('Successful', const Color(0xFF10B981));
      case 'failed':
        return ('Failed', const Color(0xFFEF4444));
      default:
        return ('Pending', const Color(0xFFF59E0B));
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
        title: Text('Bills', style: TextStyle(color: colors.text, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Stats strip
                  Row(
                    children: [
                      _statCard('Total paid', _money(_stats?['total_spent'] ?? 0)),
                      const SizedBox(width: 10),
                      _statCard('Bills paid', '${_stats?['total_count'] ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Category chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _categories.entries.map((entry) {
                        final selected = entry.key == _category;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: selected,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(entry.value.$2, size: 15,
                                    color: selected ? Colors.white : AppColors.primary),
                                const SizedBox(width: 6),
                                Text(entry.value.$1),
                              ],
                            ),
                            selectedColor: AppColors.primary,
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) => setState(() => _category = entry.key),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Provider grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 3.1,
                    ),
                    itemCount: _categoryProviders.length,
                    itemBuilder: (context, index) {
                      final provider = _categoryProviders[index];
                      return Material(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _openPaySheet(provider),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.border),
                            ),
                            child: Row(
                              children: [
                                Icon(_categories[provider['category']]?.$2 ?? Icons.smartphone_rounded,
                                    size: 18, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${provider['name']}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.text),
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, size: 16, color: colors.textSecondary),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text('Recent bills',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colors.text)),
                  const SizedBox(height: 8),
                  if (_bills.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text('No bill payments yet',
                            style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                      ),
                    )
                  else
                    ..._bills.take(30).map((bill) {
                      final meta = _statusMeta('${bill['status']}');
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${bill['provider_name'] ?? ''}${bill['plan_name'] != null ? ' · ${bill['plan_name']}' : ''} — ${bill['customer_ref']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.text),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${bill['reference'] ?? ''}',
                                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_money(bill['total'], '${bill['currency'] ?? 'NGN'}'),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                const SizedBox(height: 2),
                                Text(meta.$1, style: TextStyle(fontSize: 11, color: meta.$2)),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
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
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pay bottom sheet
  // ---------------------------------------------------------------------------

  void _openPaySheet(Map<String, dynamic> provider) {
    final colors = AppTheme.colors;
    final plans = (provider['plans'] as List<dynamic>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final hasPlans = plans != null && plans.isNotEmpty;
    String? selectedPlan = hasPlans ? '${plans!.first['code']}' : null;
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
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
            Future<void> loadWallets() async {
              try {
                final res = await _api.getWallet();
                final data = res.data;
                final list = <Map<String, dynamic>>[];
                if (data?['user_wallet'] != null) {
                  list.add(Map<String, dynamic>.from(data!['user_wallet']));
                }
                if (data?['business_wallet'] != null) {
                  list.add(Map<String, dynamic>.from(data!['business_wallet']));
                }
                setSheetState(() {
                  wallets = list;
                  walletId ??= list.isNotEmpty ? '${list.first['id']}' : null;
                });
              } catch (e) {
                debugPrint('Failed to load wallets: $e');
              }
            }

            // Load once when the sheet builds.
            if (wallets.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) => loadWallets());
            }

            double? planAmount() {
              if (!hasPlans) return null;
              final match = plans!.firstWhere(
                (p) => '${p['code']}' == selectedPlan,
                orElse: () => plans!.first,
              );
              return double.tryParse('${match['amount']}');
            }

            Future<void> submit() async {
              final customerRef = refCtrl.text.trim();
              final pin = pinCtrl.text.trim();
              if (customerRef.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${provider['refLabel']} is required')));
                return;
              }
              final amount = planAmount() ?? double.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a valid amount')));
                return;
              }
              if (walletId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Choose a wallet to pay from')));
                return;
              }
              if (pin.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter your transaction PIN')));
                return;
              }
              setSheetState(() => submitting = true);
              try {
                final res = await _api.payBill({
                  'category': provider['category'],
                  'provider_code': provider['code'],
                  if (hasPlans) 'plan_code': selectedPlan,
                  'customer_ref': customerRef,
                  if (!hasPlans) 'amount': amount,
                  'wallet_id': walletId,
                  'pin': pin,
                });
                final ok = res.data?['success'] == true;
                if (mounted) Navigator.of(sheetContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? (res.data?['message'] ?? 'Bill payment successful')
                      : ApiService.extractErrorMessage(res))),
                );
                if (ok) _load();
              } catch (e) {
                if (mounted) Navigator.of(sheetContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ApiService.extractErrorMessage(e))));
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
                    Row(
                      children: [
                        Icon(_categories[provider['category']]?.$2 ?? Icons.smartphone_rounded,
                            color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('${provider['name']}',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800, color: colors.text)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (hasPlans) ...[
                      const Text('Package', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: selectedPlan,
                        isExpanded: true,
                        dropdownColor: colors.surface,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: plans!
                            .map((p) => DropdownMenuItem(
                                  value: '${p['code']}',
                                  child: Text(
                                      '${p['name']} — ${_money(p['amount'])}${p['validity'] != null ? ' (${p['validity']})' : ''}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13, color: colors.text)),
                                ))
                            .toList(),
                        onChanged: (v) => setSheetState(() => selectedPlan = v),
                      ),
                    ] else ...[
                      const Text('Amount (₦50 – ₦500,000)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: amountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'e.g. 1000',
                          prefixText: '₦ ',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text('${provider['refLabel']}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: refCtrl,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        hintText: '${provider['refExample'] ?? ''}',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Pay from', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
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
                    const SizedBox(height: 12),
                    const Text('Transaction PIN',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        hintText: '••••',
                        counterText: '',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
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
                            : const Text('Pay bill',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text('A small convenience fee applies per bill (lower on paid plans).',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: colors.textSecondary)),
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
