import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';

/// Subscriptions (Recurring Billing) — business revenue feature. Create
/// customer subscription plans (daily / weekly / monthly), add subscribers and
/// track every charge. Subscribers with a Metroflow wallet are auto-charged by
/// the platform; others receive an emailed hosted-checkout link each cycle.
/// Web counterpart: /subscriptions (public subscribe: /subscribe/<publicId>).
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late final TabController _tab = TabController(length: 3, vsync: this);

  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _subscribers = [];
  List<Map<String, dynamic>> _charges = [];
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _billing;
  bool _isLoading = true;
  bool _busy = false;

  final TextEditingController _planNameController = TextEditingController();
  final TextEditingController _planDescController = TextEditingController();
  final TextEditingController _planAmountController = TextEditingController();
  String _planInterval = 'monthly';
  Map<String, dynamic>? _editingPlan;

  String _subPlanId = '';
  final TextEditingController _subNameController = TextEditingController();
  final TextEditingController _subEmailController = TextEditingController();
  final TextEditingController _subPhoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _tab.dispose();
    _planNameController.dispose();
    _planDescController.dispose();
    _planAmountController.dispose();
    _subNameController.dispose();
    _subEmailController.dispose();
    _subPhoneController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _api.getSubscriptionPlans(),
        _api.getSubscribers(),
        _api.getSubscriptionCharges(),
      ]);
      if (!mounted) return;
      final p = results[0].data;
      final s = results[1].data;
      final c = results[2].data;
      setState(() {
        _plans = (p['plans'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _stats = p['stats'] == null ? null : Map<String, dynamic>.from(p['stats'] as Map);
        _billing = p['billing'] == null ? null : Map<String, dynamic>.from(p['billing'] as Map);
        _subscribers = (s['subscribers'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _charges = (c['charges'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      debugPrint('Failed to load subscriptions: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _money(dynamic v, [String currency = 'NGN']) {
    final n = double.tryParse(v?.toString() ?? '0') ?? 0;
    final symbol = currency == 'USD' ? r'$' : '₦';
    return '$symbol${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2)}';
  }

  String _intervalLabel(String interval) =>
      interval == 'daily' ? 'day' : interval == 'weekly' ? 'week' : 'month';

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
      case 'success':
        return Colors.green;
      case 'past_due':
      case 'awaiting_payment':
      case 'pending':
        return Colors.orange;
      case 'cancelled':
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _cleanStatus(String status) => status.replaceAll('_', ' ');

  Future<void> _savePlan() async {
    final name = _planNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Plan name is required')));
      return;
    }
    final amount = double.tryParse(_planAmountController.text.trim());
    if (amount == null || amount < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amount must be at least ₦100')));
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = <String, dynamic>{
        'name': name,
        'description': _planDescController.text.trim().isNotEmpty
            ? _planDescController.text.trim()
            : null,
        'amount': amount,
        'interval': _planInterval,
      };
      if (_editingPlan != null) {
        await _api.updateSubscriptionPlan(_editingPlan!['id'].toString(), payload);
      } else {
        await _api.createSubscriptionPlan(payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_editingPlan != null
              ? 'Plan updated'
              : 'Subscription plan created')));
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.extractErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePause(Map<String, dynamic> plan) async {
    final next = plan['status'] == 'active' ? 'paused' : 'active';
    try {
      await _api.updateSubscriptionPlan(plan['id'].toString(), {'status': next});
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.extractErrorMessage(e))));
      }
    }
  }

  Future<void> _deletePlan(Map<String, dynamic> plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete plan?'),
        content: Text('"${plan['name']}" can only be deleted when it has no subscribers.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteSubscriptionPlan(plan['id'].toString());
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.extractErrorMessage(e))));
      }
    }
  }

  Future<void> _addSubscriber() async {
    if (_subPlanId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick a plan')));
      return;
    }
    if (_subNameController.text.trim().isEmpty ||
        _subEmailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer name and email are required')));
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await _api.addSubscriber({
        'plan_id': _subPlanId,
        'customer_name': _subNameController.text.trim(),
        'customer_email': _subEmailController.text.trim(),
        if (_subPhoneController.text.trim().isNotEmpty)
          'customer_phone': _subPhoneController.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      if (response.data['checkout_url'] != null) {
        final url = response.data['checkout_url'].toString();
        await Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Subscriber added — first-cycle checkout link copied: $url')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                response.data['message']?.toString() ?? 'Subscriber added')));
      }
      _subPlanId = '';
      _subNameController.clear();
      _subEmailController.clear();
      _subPhoneController.clear();
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.extractErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelSubscriber(Map<String, dynamic> sub) async {
    try {
      await _api.cancelSubscriber(sub['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Subscriber cancelled')));
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.extractErrorMessage(e))));
      }
    }
  }

  Future<void> _reactivateSubscriber(Map<String, dynamic> sub) async {
    try {
      await _api.reactivateSubscriber(sub['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscriber reactivated')));
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.extractErrorMessage(e))));
      }
    }
  }

  void _openPlanSheet([Map<String, dynamic>? plan]) {
    _editingPlan = plan;
    _planNameController.text = plan?['name']?.toString() ?? '';
    _planDescController.text = plan?['description']?.toString() ?? '';
    _planAmountController.text = plan?['amount']?.toString() ?? '';
    _planInterval = plan?['interval']?.toString() ?? 'monthly';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_editingPlan != null ? 'Edit plan' : 'New subscription plan',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'Subscribers are charged automatically on the schedule you pick.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: _planNameController,
                decoration: const InputDecoration(
                    labelText: 'Plan name (e.g. Weekly cleaning service)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _planDescController,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _planAmountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Amount per cycle (₦)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: ['daily', 'weekly', 'monthly'].map((iv) {
                  final selected = _planInterval == iv;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(iv, textAlign: TextAlign.center),
                        selected: selected,
                        onSelected: (_) => setSheetState(() => _planInterval = iv),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _savePlan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_editingPlan != null ? 'Save changes' : 'Create plan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSubscriberSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add subscriber',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'Wallet holders are charged automatically; others get a secure payment link by email each cycle.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _subPlanId.isEmpty ? null : _subPlanId,
                decoration: const InputDecoration(
                    labelText: 'Plan', border: OutlineInputBorder()),
                items: _plans
                    .where((p) => p['status']?.toString() == 'active')
                    .map((p) => DropdownMenuItem(
                          value: p['id'].toString(),
                          child: Text(
                            '${p['name']} — ${_money(p['amount'])}/${_intervalLabel(p['interval']?.toString() ?? 'monthly')}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setSheetState(() => _subPlanId = v ?? ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subNameController,
                decoration: const InputDecoration(
                    labelText: 'Customer name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Customer email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _addSubscriber,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Add subscriber'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mrr = _stats?['estimated_monthly_revenue'];
    final activeSubs = _stats?['active_subscribers'];
    final pastDue = _stats?['past_due'];
    final totalPlans = _stats?['total_plans'];

    return Scaffold(
      backgroundColor: AppTheme.colors.background,
      appBar: AppBar(
        title: const Text('Subscriptions'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _openSubscriberSheet,
            icon: const Icon(Icons.person_add_alt_1_outlined,
                size: 18, color: Colors.white),
            label: const Text('Add',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Plans'),
            Tab(text: 'Subscribers'),
            Tab(text: 'Charges'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPlanSheet(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New plan'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                // ---- Plans ----
                RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_stats != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Est. monthly revenue',
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11)),
                                      Text(_money(mrr),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold)),
                                    ]),
                              ),
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('$activeSubs active',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                    Text('$pastDue past due · $totalPlans plans',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ]),
                            ],
                          ),
                        ),
                      if (_plans.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Column(children: [
                            Icon(Icons.autorenew_outlined,
                                size: 56, color: Colors.grey),
                            SizedBox(height: 12),
                            Center(
                              child: Text(
                                  'No subscription plans yet\nCreate a plan and share the subscribe link.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey)),
                            ),
                          ]),
                        ),
                      ..._plans.map((p) {
                        final status = p['status']?.toString() ?? 'active';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            title: Text(p['name']?.toString() ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(
                                  '${_money(p['amount'], p['currency'] ?? 'NGN')} / ${_intervalLabel(p['interval']?.toString() ?? 'monthly')} · ${p['active_subscribers'] ?? 0} active subscriber(s)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 6),
                                Row(children: [
                                  InkWell(
                                    onTap: () async {
                                      final publicId =
                                          p['public_id']?.toString() ?? '';
                                      final url =
                                          'https://app.metricorex.com/subscribe/$publicId';
                                      await Clipboard.setData(
                                          ClipboardData(text: url));
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  'Subscribe link copied — $url')));
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: const Row(children: [
                                        Icon(Icons.link_outlined,
                                            size: 12,
                                            color: AppColors.primary),
                                        SizedBox(width: 4),
                                        Text('Copy link',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.primary,
                                                fontWeight:
                                                    FontWeight.w600)),
                                      ]),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _togglePause(p),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                          status == 'active'
                                              ? 'Pause'
                                              : 'Resume',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ]),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(status,
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _statusColor(status))),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 20),
                                  onPressed: () => _openPlanSheet(p),
                                ),
                                if ((p['total_subscribers'] ?? 0) == 0)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20, color: Colors.red),
                                    onPressed: () => _deletePlan(p),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                // ---- Subscribers ----
                RefreshIndicator(
                  onRefresh: _fetch,
                  child: _subscribers.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Icon(Icons.people_outline,
                              size: 56, color: Colors.grey),
                          SizedBox(height: 12),
                          Center(
                            child: Text(
                                'No subscribers yet\nShare a plan link or add customers yourself.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ])
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: _subscribers.map((s) {
                            final status = s['status']?.toString() ?? 'active';
                            final nextCharge = s['next_charge_date'];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                title: Text(
                                    '${s['customer_name'] ?? ''} · ${s['plan_name'] ?? ''}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                subtitle: Text(
                                  '${s['customer_email'] ?? ''}\n${status == 'active' && nextCharge != null ? 'Next charge ${nextCharge.toString().split('T').first}' : ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _statusColor(status)
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(_cleanStatus(status),
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: _statusColor(status))),
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (action) {
                                        if (action == 'cancel') {
                                          _cancelSubscriber(s);
                                        } else if (action == 'reactivate') {
                                          _reactivateSubscriber(s);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        if (status == 'past_due' ||
                                            status == 'cancelled')
                                          const PopupMenuItem(
                                              value: 'reactivate',
                                              child: Text('Reactivate')),
                                        if (status != 'cancelled')
                                          const PopupMenuItem(
                                              value: 'cancel',
                                              child: Text('Cancel',
                                                  style: TextStyle(
                                                      color: Colors.red))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                // ---- Charges ----
                RefreshIndicator(
                  onRefresh: _fetch,
                  child: _charges.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Icon(Icons.receipt_outlined,
                              size: 56, color: Colors.grey),
                          SizedBox(height: 12),
                          Center(
                            child: Text(
                                'No charges yet\nEvery subscription charge lands here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ])
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: _charges.map((c) {
                            final status = c['status']?.toString() ?? 'pending';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                title: Text(
                                    '${c['customer_name'] ?? ''} · ${c['plan_name'] ?? ''}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                subtitle: Text(
                                    '${c['charge_path'] == 'wallet' ? 'Wallet auto-charge' : 'Checkout'} · net ${_money(c['net_amount'])} · fee ${_money(c['fee'])}',
                                    style: const TextStyle(fontSize: 12)),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                        _money(c['amount'],
                                            c['currency'] ?? 'NGN'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _statusColor(status)
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(_cleanStatus(status),
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: _statusColor(status))),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
    );
  }
}
