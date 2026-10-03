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
  // When set, the link sheet edits this existing link instead of creating one.
  Map<String, dynamic>? _editingLink;

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

  Future<void> _submitLink() async {
    final editing = _editingLink;
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
      if (editing != null) {
        await _api.updatePaymentLink(editing['id'].toString(), {
          'title': title,
          // Empty string clears the description; backend COALESCEs null.
          'description': _descriptionController.text.trim(),
          if (!custom) 'amount': amount,
          'allow_custom_amount': custom,
        });
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment link updated')));
      } else {
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
      }
      _clearForm();
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

  void _clearForm() {
    _titleController.clear();
    _descriptionController.clear();
    _amountController.clear();
    _allowCustomAmount = false;
    _editingLink = null;
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

  void _openLinkSheet({Map<String, dynamic>? link}) {
    _editingLink = link;
    if (link != null) {
      _titleController.text = link['title']?.toString() ?? '';
      _descriptionController.text = link['description']?.toString() ?? '';
      _amountController.text =
          link['amount'] != null ? link['amount'].toString() : '';
      _allowCustomAmount = link['allow_custom_amount'] == true;
    } else {
      _titleController.clear();
      _descriptionController.clear();
      _amountController.clear();
      _allowCustomAmount = false;
    }
    final isEditing = link != null;
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
              Text(isEditing ? 'Edit payment link' : 'Create payment link',
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
                  onPressed: _creating ? null : _submitLink,
                  child: _creating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(isEditing ? 'Save changes' : 'Create link'),
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
        onPressed: () => _openLinkSheet(),
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
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: colors.text.withValues(alpha: 0.05),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Gradient brand header strip: icon chip + title
                              // + live status pill.
                              Container(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.link_rounded,
                                          color: Colors.white, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        link['title']?.toString() ?? '',
                                        style: const TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isActive
                                                  ? const Color(0xFF6EE7B7)
                                                  : Colors.white
                                                      .withValues(alpha: 0.6),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                              isActive ? 'Active' : 'Paused',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isCustom
                                          ? 'Open amount'
                                          : _money(link['amount'],
                                              link['currency']?.toString() ?? 'NGN'),
                                      style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                          color: colors.primary),
                                    ),
                                    const SizedBox(height: 10),
                                    // Stats as soft chips.
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _statChip(colors,
                                            Icons.visibility_outlined,
                                            '${link['views'] ?? 0} views'),
                                        _statChip(colors,
                                            Icons.check_circle_outline,
                                            '${link['successful_payments'] ?? 0} paid'),
                                        _statChip(colors, Icons.account_balance_wallet_outlined,
                                            _money(link['total_collected'],
                                                link['currency']?.toString() ?? 'NGN')),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Material(
                                            color: colors.primary,
                                            borderRadius: BorderRadius.circular(12),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              onTap: () => _shareLink(link),
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(
                                                    vertical: 10),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.ios_share_rounded,
                                                        size: 16,
                                                        color: Colors.white),
                                                    SizedBox(width: 6),
                                                    Text('Share',
                                                        style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Colors.white)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _iconAction(
                                          tooltip: 'Edit link',
                                          onTap: () => _openLinkSheet(link: link),
                                          icon: Icons.edit_outlined,
                                          color: colors.textSecondary,
                                        ),
                                        _iconAction(
                                          tooltip: isActive ? 'Pause' : 'Activate',
                                          onTap: () => _toggleActive(link),
                                          icon: isActive
                                              ? Icons.pause_circle_outline
                                              : Icons.play_circle_outline,
                                          color: colors.textSecondary,
                                        ),
                                        _iconAction(
                                          tooltip: 'Delete',
                                          onTap: () => _confirmDelete(link),
                                          icon: Icons.delete_outline,
                                          color: colors.error,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _statChip(ThemeColors colors, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.primary),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: colors.primary)),
        ],
      ),
    );
  }

  Widget _iconAction({
    required String tooltip,
    required VoidCallback onTap,
    required IconData icon,
    required Color color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
