import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';

/// Smart Invoices ("Get Paid" suite) — create itemised invoices (line items,
/// tax, due date) and share a public payment page with clients. Clients pay
/// through the hosted checkout and the business wallet is settled net of the
/// invoice settlement fee. Web counterpart: /invoices. Public pay page:
/// <site>/invoices/<id>/pay.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchInvoices();
  }

  Future<void> _fetchInvoices() async {
    setState(() => _isLoading = true);
    try {
      final response = await _api.getInvoices();
      if (response.data['success'] == true && mounted) {
        setState(() {
          _invoices = (response.data['invoices'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to load invoices: $e');
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

  String _effectiveStatus(Map<String, dynamic> inv) {
    final status = inv['status']?.toString() ?? 'pending';
    if (status != 'pending') return status;
    final due = inv['due_date']?.toString();
    if (due != null && due.isNotEmpty) {
      final dueDate = DateTime.tryParse(due);
      if (dueDate != null &&
          dueDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
        return 'overdue';
      }
    }
    return status;
  }

  Color _statusColor(String status, ThemeColors colors) {
    switch (status) {
      case 'paid':
        return colors.success;
      case 'overdue':
        return colors.error;
      case 'draft':
      case 'cancelled':
        return colors.textSecondary;
      default:
        return Colors.orange;
    }
  }

  String _payUrl(String id) => 'https://app.metricorex.com/invoices/$id/pay';

  Future<void> _shareInvoice(Map<String, dynamic> inv) async {
    final url = _payUrl(inv['id']?.toString() ?? '');
    final amount = _money(inv['total'], inv['currency']?.toString() ?? 'NGN');
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment link copied — $url')),
      );
      await SharePlus.instance.share(ShareParams(
          text:
              'Invoice ${inv['invoice_number'] ?? ''} for $amount — pay securely here: $url'));
    } catch (_) {
      // Clipboard already set above; share sheet is best-effort.
    }
  }

  Future<void> _cancelInvoice(Map<String, dynamic> inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel invoice?'),
        content: Text(
            'Invoice ${inv['invoice_number'] ?? ''} will be marked cancelled and its payment page will stop working.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep invoice')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cancel invoice',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.cancelInvoice(inv['id'].toString());
      await _fetchInvoices();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _deleteInvoice(Map<String, dynamic> inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete invoice?'),
        content: Text(
            'Invoice ${inv['invoice_number'] ?? ''} for "${inv['client_name'] ?? ''}" will be removed permanently. Payments already received are not affected.'),
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
      await _api.deleteInvoice(inv['id'].toString());
      await _fetchInvoices();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    }
  }

  void _openCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CreateInvoiceSheet(),
    ).then((created) {
      if (created == true) _fetchInvoices();
    });
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
        title: const Text('Invoices'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateSheet,
        icon: const Icon(Icons.receipt_long),
        label: const Text('New Invoice'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : _invoices.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 48, color: colors.textSecondary),
                        const SizedBox(height: 12),
                        Text('No invoices yet',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colors.text)),
                        const SizedBox(height: 6),
                        Text(
                          'Create itemised invoices with line items, tax and a due date. Your client gets a secure online payment page — no account needed.',
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
                  onRefresh: _fetchInvoices,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: _invoices.length,
                    itemBuilder: (context, index) {
                      final inv = _invoices[index];
                      final status = _effectiveStatus(inv);
                      final statusColor = _statusColor(status, colors);
                      final shareable = status == 'pending' || status == 'overdue';
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
                                    inv['client_name']?.toString() ?? '',
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
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                      status.charAt(0).toUpperCase() +
                                          status.substring(1),
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${inv['invoice_number']?.toString() ?? ''} · ${inv['client_email']?.toString() ?? ''}',
                              style: TextStyle(
                                  fontSize: 12, color: colors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _money(inv['total'],
                                  inv['currency']?.toString() ?? 'NGN'),
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: colors.text),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.calendar_today_outlined,
                                    size: 13, color: colors.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  inv['due_date'] != null &&
                                          inv['due_date'].toString().isNotEmpty
                                      ? 'Due ${inv['due_date'].toString().split('T').first}'
                                      : 'No due date',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textSecondary),
                                ),
                                const SizedBox(width: 16),
                                Icon(Icons.visibility_outlined,
                                    size: 14, color: colors.textSecondary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text('${inv['views'] ?? 0} views',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: colors.textSecondary)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (shareable)
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _shareInvoice(inv),
                                      icon: const Icon(Icons.ios_share, size: 16),
                                      label: const Text('Share',
                                          style: TextStyle(fontSize: 13)),
                                    ),
                                  ),
                                if (shareable) const SizedBox(width: 8),
                                if (status == 'pending' || status == 'overdue')
                                  IconButton(
                                    tooltip: 'Cancel invoice',
                                    onPressed: () => _cancelInvoice(inv),
                                    icon: Icon(Icons.cancel_outlined,
                                        color: colors.textSecondary),
                                  ),
                                if (status != 'paid')
                                  IconButton(
                                    tooltip: 'Delete',
                                    onPressed: () => _deleteInvoice(inv),
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

extension _StringCasing on String {
  String charAt(int index) =>
      length <= index ? this : substring(index, index + 1);
}

/// Bottom sheet for creating an invoice with dynamic line items.
class _CreateInvoiceSheet extends StatefulWidget {
  const _CreateInvoiceSheet();

  @override
  State<_CreateInvoiceSheet> createState() => _CreateInvoiceSheetState();
}

class _CreateInvoiceSheetState extends State<_CreateInvoiceSheet> {
  final ApiService _api = ApiService();
  bool _creating = false;
  bool _saveAsDraft = false;

  final TextEditingController _clientName = TextEditingController();
  final TextEditingController _clientEmail = TextEditingController();
  final TextEditingController _clientPhone = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _taxPercent = TextEditingController();
  DateTime? _dueDate;

  final List<_DraftItem> _items = [_DraftItem()];

  double get _subtotal {
    double sum = 0;
    for (final item in _items) {
      sum += (double.tryParse(item.quantity.text) ?? 0) *
          (double.tryParse(item.unitPrice.text) ?? 0);
    }
    return sum;
  }

  double get _tax =>
      _subtotal * ((double.tryParse(_taxPercent.text) ?? 0) / 100);

  double get _total => _subtotal + _tax;

  String _money(double n) =>
      '₦${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2)}';

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 14)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _createInvoice() async {
    final clientName = _clientName.text.trim();
    final clientEmail = _clientEmail.text.trim();
    if (clientName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Add the client's name")));
      return;
    }
    if (clientEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("The client's email is required")));
      return;
    }
    final cleanItems = <Map<String, dynamic>>[];
    for (final item in _items) {
      final desc = item.description.text.trim();
      if (desc.isEmpty) continue;
      cleanItems.add({
        'description': desc,
        'quantity': double.tryParse(item.quantity.text) ?? 1,
        'unit_price': double.tryParse(item.unitPrice.text) ?? 0,
      });
    }
    if (cleanItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one line item')));
      return;
    }
    setState(() => _creating = true);
    try {
      await _api.createInvoice({
        'client_name': clientName,
        'client_email': clientEmail,
        if (_clientPhone.text.trim().isNotEmpty)
          'client_phone': _clientPhone.text.trim(),
        'items': cleanItems,
        'tax_percent': double.tryParse(_taxPercent.text) ?? 0,
        if (_dueDate != null)
          'due_date':
              '${_dueDate!.year.toString().padLeft(4, '0')}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}',
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        'status': _saveAsDraft ? 'draft' : 'pending',
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_saveAsDraft
              ? 'Invoice saved as draft'
              : 'Invoice created — share it with your client')));
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

  @override
  void dispose() {
    _clientName.dispose();
    _clientEmail.dispose();
    _clientPhone.dispose();
    _notes.dispose();
    _taxPercent.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create invoice',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.text)),
                const SizedBox(height: 4),
                Text(
                  'Your client gets a secure payment page. Funds settle into your wallet minus the settlement fee.',
                  style:
                      TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _clientName,
                  decoration: const InputDecoration(
                      labelText: 'Client name', hintText: 'e.g. Acme Ltd'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clientEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Client email',
                      hintText: 'billing@acme.com'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clientPhone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Client phone (optional)',
                      hintText: 'e.g. 0803 000 0000'),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDueDate,
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Due date',
                        suffixIcon: Icon(Icons.calendar_today_outlined,
                            size: 18)),
                    child: Text(
                      _dueDate == null
                          ? 'Select a date'
                          : '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          fontSize: 14,
                          color: _dueDate == null
                              ? colors.textSecondary
                              : colors.text),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Line items',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.text)),
                    TextButton.icon(
                      onPressed: () => setState(() => _items.add(_DraftItem())),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add item'),
                    ),
                  ],
                ),
                ..._items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: item.description,
                                  decoration: const InputDecoration(
                                      hintText: 'What did you do? e.g. Logo design',
                                      labelStyle: TextStyle(fontSize: 13),
                                      labelText: 'Description'),
                                ),
                              ),
                              if (_items.length > 1)
                                IconButton(
                                  tooltip: 'Remove item',
                                  onPressed: () =>
                                      setState(() => _items.removeAt(idx)),
                                  icon: Icon(Icons.remove_circle_outline,
                                      size: 20, color: colors.error),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: item.quantity,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Qty'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: item.unitPrice,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Unit price (₦)'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
                TextField(
                  controller: _taxPercent,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Tax / VAT (%)', hintText: 'e.g. 7.5'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Payment terms, thank-you note…'),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    children: [
                      _TotalRow(
                          label: 'Subtotal', value: _money(_subtotal)),
                      _TotalRow(label: 'Tax', value: _money(_tax)),
                      const SizedBox(height: 4),
                      _TotalRow(label: 'Total', value: _money(_total),
                          bold: true),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('Save as draft (share later)',
                      style: TextStyle(fontSize: 13)),
                  value: _saveAsDraft,
                  onChanged: (v) => setState(() => _saveAsDraft = v ?? false),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _creating ? null : _createInvoice,
                    child: _creating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(_saveAsDraft ? 'Save draft' : 'Create invoice'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftItem {
  final TextEditingController description = TextEditingController();
  final TextEditingController quantity = TextEditingController(text: '1');
  final TextEditingController unitPrice = TextEditingController();

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitPrice.dispose();
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _TotalRow({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: bold ? 14 : 12.5,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  color: colors.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 15 : 12.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  color: colors.text)),
        ],
      ),
    );
  }
}
