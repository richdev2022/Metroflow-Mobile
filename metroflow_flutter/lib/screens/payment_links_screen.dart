import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';

/// Payment Links ("Get Paid") — create shareable payment links; customers pay
/// through the hosted checkout and the business wallet is settled net of the
/// collection fee. Web counterpart: /payment-links. Public pay page:
/// <site>/pay/<slug> (open the share sheet to send it to customers).
class PaymentLinksScreen extends StatefulWidget {
  const PaymentLinksScreen({super.key});

  @override
  State<PaymentLinksScreen> createState() => _PaymentLinksScreenState();
}

class _PaymentLinksScreenState extends State<PaymentLinksScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _links = [];
  bool _isLoading = true;
  bool _creating = false;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  bool _allowCustomAmount = false;

  @override
  void initState() {
    super.initState();
    _fetchLinks();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchLinks() async {
    setState(() => _isLoading = true);
    try {
      final response = await _api.getPaymentLinks();
      if (response.data['success'] == true && mounted) {
        setState(() {
          _links = (response.data['links'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to load payment links: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _money(dynamic v, [String currency = 'NGN']) {
    final n = double.tryParse(v?.toString() ?? '0') ?? 0;
    final symbol = currency == 'USD'
        ? r'$'
        : currency == 'EUR'
            ? '€'
            : currency == 'GBP'
                ? '£'
                : '₦';
    return '$symbol${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2)}';
  }

  String _payUrl(String slug) => 'https://app.metricorex.com/pay/$slug';

  Future<void> _shareLink(Map<String, dynamic> link) async {
    final url = _payUrl(link['slug']?.toString() ?? '');
    final title = link['title']?.toString() ?? 'Payment link';
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Link copied — $url')),
      );
      await SharePlus.instance.share(ShareParams(text: 'Pay "$title" here: $url'));
    } catch (_) {
      // Clipboard already set above; share sheet is best-effort.
    }
  }

  Future<void> _createLink() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give your link a title')));
      return;
    }
    final custom = _allowCustomAmount;
    final amount = double.tryParse(_amountController.text.trim());
    if (!custom && (amount == null || amount <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter an amount or allow customers to choose')));
      return;
    }
    setState(() => _creating = true);
    try {
      await _api.createPaymentLink({
        'title': title,
        'description': _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        if (!custom) 'amount': amount,
        'allow_custom_amount': custom,
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment link created')));
      _titleController.clear();
      _descriptionController.clear();
      _amountController.clear();
      _allowCustomAmount = false;
      await _fetchLinks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> link) async {
    try {
      await _api.updatePaymentLink(
          link['id'].toString(), {'is_active': !(link['is_active'] == true)});
      await _fetchLinks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> link) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete payment link?'),
        content: Text(
            '"${link['title']}" will stop accepting payments immediately. Payments already received are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deletePaymentLink(link['id'].toString());
      await _fetchLinks();
    } catch (_) {}
  }

  void _openCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create payment link',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.colors.text)),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                    labelText: 'Title', hintText: 'e.g. Website design invoice'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'What is this payment for?'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Let customer choose amount'),
                subtitle: const Text('Good for donations and tips'),
                value: _allowCustomAmount,
                onChanged: (v) => setState(() => _allowCustomAmount = v),
              ),
              if (!_allowCustomAmount) ...[
                const SizedBox(height: 4),
                TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Amount (NGN)', hintText: 'e.g. 25000'),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _creating ? null : _createLink,
                  child: _creating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Create link'),
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
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        foregroundColor: colors.text,
        elevation: 0,
        title: const Text('Payment Links'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateSheet,
        icon: const Icon(Icons.add_link),
        label: const Text('New Link'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : _links.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.link_outlined,
                            size: 48, color: colors.textSecondary),
                        const SizedBox(height: 12),
                        Text('No payment links yet',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colors.text)),
                        const SizedBox(height: 6),
                        Text(
                          'Create a link for invoices, products or donations. Customers pay by card or transfer and you get settled straight into your wallet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: colors.primary,
                  onRefresh: _fetchLinks,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: _links.length,
                    itemBuilder: (context, index) {
                      final link = _links[index];
                      final isActive = link['is_active'] == true;
                      final isCustom = link['allow_custom_amount'] == true;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
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
                                  child: Text(
                                    link['title']?.toString() ?? '',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: colors.text),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? colors.primaryBg
                                        : colors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(isActive ? 'Active' : 'Paused',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isActive
                                              ? colors.primary
                                              : colors.textSecondary)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isCustom
                                  ? 'Open amount'
                                  : _money(link['amount'],
                                      link['currency']?.toString() ?? 'NGN'),
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: colors.text),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.visibility_outlined,
                                    size: 14, color: colors.textSecondary),
                                const SizedBox(width: 4),
                                Text('${link['views'] ?? 0} views',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textSecondary)),
                                const SizedBox(width: 16),
                                Icon(Icons.trending_up,
                                    size: 14, color: colors.textSecondary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${link['successful_payments'] ?? 0} paid · ${_money(link['total_collected'], link['currency']?.toString() ?? 'NGN')}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _shareLink(link),
                                    icon: const Icon(Icons.ios_share, size: 16),
                                    label: const Text('Share',
                                        style: TextStyle(fontSize: 13)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: isActive ? 'Pause' : 'Activate',
                                  onPressed: () => _toggleActive(link),
                                  icon: Icon(
                                    isActive
                                        ? Icons.pause_circle_outline
                                        : Icons.play_circle_outline,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () => _confirmDelete(link),
                                  icon: Icon(Icons.delete_outline,
                                      color: colors.error),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
