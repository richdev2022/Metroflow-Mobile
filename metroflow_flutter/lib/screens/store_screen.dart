import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';

/// Metroflow Store — business revenue feature. Manage your storefront: list
/// products/services, share your store link, fulfil paid orders. Customers
/// browse the public storefront on the web and pay through hosted checkout;
/// every paid order settles into the business wallet net of the order fee.
/// Web counterpart: /store (public: /store/public/<businessId>).
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late final TabController _tab = TabController(length: 2, vsync: this);

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _storeInfo;
  bool _isLoading = true;
  bool _busy = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  String _status = 'active';
  Map<String, dynamic>? _editing;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _tab.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _api.getStoreProducts(),
        _api.getStoreOrders(),
      ]);
      if (!mounted) return;
      final p = results[0].data;
      final o = results[1].data;
      setState(() {
        _products = (p['products'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _storeInfo = p['store'] == null
            ? null
            : Map<String, dynamic>.from(p['store'] as Map);
        _orders = (o['orders'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _stats = o['stats'] == null ? null : Map<String, dynamic>.from(o['stats'] as Map);
      });
    } catch (e) {
      debugPrint('Failed to load store: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _money(dynamic v, [String currency = 'NGN']) {
    final n = double.tryParse(v?.toString() ?? '0') ?? 0;
    final symbol = currency == 'USD' ? r'$' : '₦';
    return '$symbol${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2)}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
      case 'active':
        return Colors.green;
      case 'fulfilled':
        return const Color(0xFF4F46E5);
      case 'pending':
      case 'paused':
        return Colors.orange;
      case 'failed':
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _saveProduct() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product name is required')));
      return;
    }
    final price = double.tryParse(_priceController.text.trim());
    if (price == null || price < 50) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a price of at least ₦50')));
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = <String, dynamic>{
        'name': name,
        'description': _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        'price': price,
        'stock': _stockController.text.trim().isNotEmpty
            ? int.tryParse(_stockController.text.trim())
            : null,
        'status': _status,
      };
      if (_editing != null) {
        await _api.updateStoreProduct(_editing!['id'].toString(), payload);
      } else {
        await _api.createStoreProduct(payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_editing != null
              ? 'Product updated'
              : 'Product added to your store')));
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

  Future<void> _confirmDelete(Map<String, dynamic> product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('"${product['name']}" will be removed from your storefront.'),
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
      await _api.deleteStoreProduct(product['id'].toString());
      await _fetch();
    } catch (_) {}
  }

  Future<void> _fulfil(Map<String, dynamic> order) async {
    try {
      await _api.fulfilStoreOrder(order['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order marked fulfilled')));
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.extractErrorMessage(e))));
      }
    }
  }

  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    try {
      await _api.cancelStoreOrder(order['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Order cancelled')));
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.extractErrorMessage(e))));
      }
    }
  }

  void _openProductSheet([Map<String, dynamic>? product]) {
    _editing = product;
    _nameController.text = product?['name']?.toString() ?? '';
    _descriptionController.text = product?['description']?.toString() ?? '';
    _priceController.text = product?['price']?.toString() ?? '';
    _stockController.text = product?['stock']?.toString() ?? '';
    _status = product?['status']?.toString() ?? 'active';
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
              Text(_editing != null ? 'Edit product' : 'Add product',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'Customers see this on your public store page and pay through secure checkout.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Product name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Price (₦)',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _stockController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Stock (blank = ∞)',
                        border: OutlineInputBorder()),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['active', 'paused', 'draft'].map((st) {
                  final selected = _status == st;
                  return ChoiceChip(
                    label: Text(st),
                    selected: selected,
                    onSelected: (_) => setSheetState(() => _status = st),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _saveProduct,
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
                      : Text(_editing != null ? 'Save changes' : 'Add product'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openOrderSheet(Map<String, dynamic> order) {
    final items = (order['items'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order ${order['order_number'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                '${order['customer_name'] ?? ''} · ${order['customer_email'] ?? ''}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              ...items.map((i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${i['product_name'] ?? ''} × ${i['quantity'] ?? 1}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(_money(i['amount']),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(_money(order['total'], order['currency'] ?? 'NGN'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 18),
              if (order['status'] == 'paid')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _fulfil(order);
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Mark fulfilled'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              if (order['status'] == 'pending')
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _cancelOrder(order);
                    },
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Cancel unpaid order'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
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
    final gross = _stats?['gross_sales'];
    final net = _stats?['net_sales'];
    final paidOrders = _stats?['paid_orders'];
    final pendingOrders = _stats?['pending_orders'];

    return Scaffold(
      backgroundColor: AppTheme.colors.background,
      appBar: AppBar(
        title: const Text('Store'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Copy store link',
            icon: const Icon(Icons.link_outlined),
            onPressed: () async {
              final businessId = await _api.getBusinessId();
              final url =
                  'https://app.metricorex.com/store/public/${businessId ?? ''}';
              await Clipboard.setData(ClipboardData(text: url));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Store link copied — $url')));
            },
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Products'),
            Tab(text: 'Orders'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProductSheet(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                // ---- Products ----
                RefreshIndicator(
                  onRefresh: _fetch,
                  child: _products.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Icon(Icons.storefront_outlined,
                              size: 56, color: Colors.grey),
                          SizedBox(height: 12),
                          Center(
                            child: Text(
                              'Your store is empty\nAdd your first product and share your store link.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ])
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: _products.map((p) {
                            final status = p['status']?.toString() ?? 'active';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
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
                                        '${_money(p['price'], p['currency'] ?? 'NGN')} · ${p['stock'] == null ? 'Unlimited stock' : '${p['stock']} in stock'}',
                                        style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
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
                                      child: Text(status,
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: _statusColor(status))),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 20),
                                      onPressed: () =>
                                          _openProductSheet(p),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 20, color: Colors.red),
                                      onPressed: () => _confirmDelete(p),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                // ---- Orders ----
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
                                      const Text('Net sales',
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11)),
                                      Text(_money(net),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold)),
                                      Text('Gross ${_money(gross)}',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11)),
                                    ]),
                              ),
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('$paidOrders paid',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                    Text('$pendingOrders pending',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ]),
                            ],
                          ),
                        ),
                      if (_orders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Column(children: [
                            Icon(Icons.shopping_bag_outlined,
                                size: 56, color: Colors.grey),
                            SizedBox(height: 12),
                            Center(
                              child: Text('No orders yet\nShare your store link with customers.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey)),
                            ),
                          ]),
                        ),
                      ..._orders.map((o) {
                        final status = o['status']?.toString() ?? 'pending';
                        final items = (o['items'] as List<dynamic>? ?? []).length;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            onTap: () => _openOrderSheet(o),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            title: Text(
                                '${o['customer_name'] ?? ''} · ${o['order_number'] ?? ''}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            subtitle: Text(
                                '$items item${items == 1 ? '' : 's'} · ${o['currency'] ?? 'NGN'}',
                                style: const TextStyle(fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_money(o['total'], o['currency'] ?? 'NGN'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
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
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
