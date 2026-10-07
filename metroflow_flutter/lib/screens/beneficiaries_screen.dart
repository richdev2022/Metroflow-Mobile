import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';

/// Beneficiaries — the user's saved transfer recipients, both local (NGN) and
/// international (USD/GBP/EUR). Adding a beneficiary verifies it first:
/// NGN accounts resolve the real account name through the provider;
/// international corridors are format-validated (routing checksum / sort
/// code / SWIFT). Every successful transfer auto-saves its recipient here.
class BeneficiariesScreen extends ConsumerStatefulWidget {
  const BeneficiariesScreen({super.key});

  @override
  ConsumerState<BeneficiariesScreen> createState() => _BeneficiariesScreenState();
}

class _BeneficiariesScreenState extends ConsumerState<BeneficiariesScreen> {
  static const List<String> _currencies = ['NGN', 'USD', 'GBP', 'EUR'];
  static const List<Map<String, String>> _intlCountries = [
    {'code': 'US', 'name': 'United States'},
    {'code': 'GB', 'name': 'United Kingdom'},
    {'code': 'DE', 'name': 'Germany'},
    {'code': 'FR', 'name': 'France'},
    {'code': 'IE', 'name': 'Ireland'},
    {'code': 'NL', 'name': 'Netherlands'},
    {'code': 'ES', 'name': 'Spain'},
    {'code': 'IT', 'name': 'Italy'},
    {'code': 'BE', 'name': 'Belgium'},
    {'code': 'AT', 'name': 'Austria'},
    {'code': 'PT', 'name': 'Portugal'},
    {'code': 'FI', 'name': 'Finland'},
    {'code': 'GR', 'name': 'Greece'},
    {'code': 'LU', 'name': 'Luxembourg'},
  ];

  String _currency = 'NGN';
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  List<Map<String, String>> _banks = [];

  // Add-beneficiary form
  final _accountNumberController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _routingController = TextEditingController();
  final _swiftController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalController = TextEditingController();
  final _emailController = TextEditingController();
  String _formBankCode = '';
  String _formCountry = 'US';
  String _formAccountType = '';
  bool _saving = false;
  bool _verifying = false;
  String? _verifiedName;
  bool _verifiedResolved = false;

  bool get _isIntl => _currency != 'NGN';

  @override
  void initState() {
    super.initState();
    _fetchBeneficiaries();
    _fetchBanks();
  }

  @override
  void dispose() {
    _accountNumberController.dispose();
    _accountNameController.dispose();
    _bankNameController.dispose();
    _routingController.dispose();
    _swiftController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _fetchBanks() async {
    try {
      final response = await ApiService().getBanks();
      final list = response.data is Map ? response.data['data'] : null;
      if (mounted && list is List) {
        setState(() {
          _banks = list
              .whereType<Map>()
              .map((e) => Map<String, String>.from(e.map(
                  (k, v) => MapEntry(k.toString(), v?.toString() ?? ''))))
              .toList();
        });
      }
    } catch (_) {
      // Cosmetic only.
    }
  }

  Future<void> _fetchBeneficiaries() async {
    setState(() => _loading = true);
    try {
      final response =
          await ApiService().getBeneficiaries(currency: _currency, limit: 200);
      final list = response.data is Map ? response.data['data'] : null;
      if (mounted) {
        setState(() {
          _items = list is List
              ? list
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : <Map<String, dynamic>>[];
        });
      }
    } catch (_) {
      if (mounted) setState(() => _items = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchCurrency(String currency) {
    if (_currency == currency) return;
    setState(() {
      _currency = currency;
      _formCountry = currency == 'GBP'
          ? 'GB'
          : currency == 'EUR'
              ? 'DE'
              : 'US';
    });
    _fetchBeneficiaries();
  }

  Map<String, dynamic> _formPayload() {
    return {
      'currency': _currency,
      if (_isIntl)
        'bankCode': 'SWIFT'
      else if (_formBankCode.isNotEmpty)
        'bankCode': _formBankCode,
      'accountNumber': _accountNumberController.text.trim(),
      if (_accountNameController.text.trim().isNotEmpty)
        'accountName': _accountNameController.text.trim(),
      if (_bankNameController.text.trim().isNotEmpty)
        'bankName': _bankNameController.text.trim(),
      if (_routingController.text.trim().isNotEmpty)
        'routingNumber': _routingController.text.trim(),
      if (_swiftController.text.trim().isNotEmpty)
        'swiftCode': _swiftController.text.trim().toUpperCase(),
      if (_formAccountType.isNotEmpty) 'accountType': _formAccountType,
      if (_isIntl && _addressController.text.trim().isNotEmpty)
        'address': _addressController.text.trim(),
      if (_isIntl && _cityController.text.trim().isNotEmpty)
        'city': _cityController.text.trim(),
      if (_isIntl && _stateController.text.trim().isNotEmpty)
        'state': _stateController.text.trim(),
      if (_isIntl && _postalController.text.trim().isNotEmpty)
        'postalCode': _postalController.text.trim(),
      if (_isIntl) 'country': _formCountry,
      if (_emailController.text.trim().isNotEmpty)
        'email': _emailController.text.trim(),
    };
  }

  Future<void> _verifyBeneficiary() async {
    if (_accountNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the account number first')));
      return;
    }
    if (!_isIntl && _formBankCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select the beneficiary\'s bank first')));
      return;
    }
    setState(() => _verifying = true);
    try {
      final response = await ApiService().createBeneficiary(_formPayload());
      final data = response.data is Map ? response.data['data'] : null;
      if (mounted && response.data['success'] == true && data is Map) {
        final verification = data['verification']?.toString() ?? 'format';
        final resolvedName = data['resolvedName']?.toString() ?? '';
        setState(() {
          _verifiedResolved = verification == 'resolved';
          _verifiedName = resolvedName.isNotEmpty ? resolvedName : null;
          if (resolvedName.isNotEmpty &&
              _accountNameController.text.trim().isEmpty) {
            _accountNameController.text = resolvedName;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_verifiedResolved
                ? 'Account verified: $resolvedName'
                : 'Details passed validation for this corridor')));
      } else {
        final msg = response.data is Map
            ? (response.data['error']?.toString() ?? 'Could not verify this account')
            : 'Could not verify this account';
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(ApiService.extractErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _saveBeneficiary() async {
    if (_accountNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account number is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final response = await ApiService().createBeneficiary(_formPayload());
      if (mounted && response.data['success'] == true) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Beneficiary saved')));
        _fetchBeneficiaries();
      } else {
        final msg = response.data is Map
            ? (response.data['error']?.toString() ?? 'Could not save beneficiary')
            : 'Could not save beneficiary';
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ApiService.extractErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteBeneficiary(Map<String, dynamic> b) async {
    final id = b['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove beneficiary?'),
        content: Text(
            '${b['accountName'] ?? b['accountNumber']} will be removed from your saved beneficiaries. Transfers already sent are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService().deleteBeneficiary(id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Beneficiary removed')));
        _fetchBeneficiaries();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ApiService.extractErrorMessage(e))));
      }
    }
  }

  void _openAddSheet() {
    _accountNumberController.clear();
    _accountNameController.clear();
    _bankNameController.clear();
    _routingController.clear();
    _swiftController.clear();
    _addressController.clear();
    _cityController.clear();
    _stateController.clear();
    _postalController.clear();
    _emailController.clear();
    _formBankCode = '';
    _formAccountType = '';
    _verifiedName = null;
    _verifiedResolved = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final colors = AppTheme.colors;
          final mediaQuery = MediaQuery.of(sheetContext);
          Widget field(String label, TextEditingController controller,
              {TextInputType keyboard = TextInputType.text,
              int maxLines = 1,
              int? maxLength,
              bool enabled = true,
              String? hint}) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colors.text)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: controller,
                    enabled: enabled,
                    maxLines: maxLines,
                    maxLength: maxLength,
                    keyboardType: keyboard,
                    style: TextStyle(color: colors.text, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle:
                          TextStyle(color: colors.textSecondary, fontSize: 14),
                      counterText: '',
                      filled: true,
                      fillColor: colors.background,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.border)),
                    ),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: mediaQuery.viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Add beneficiary ($_currency)',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: colors.text)),
                      const Spacer(),
                      IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon:
                              Icon(Icons.close_rounded, color: colors.text)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Accounts are verified before saving — NGN accounts resolve the real account name; international details are validated per corridor.',
                    style: TextStyle(
                        fontSize: 12, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  if (!_isIntl)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bank',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colors.text)),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () async {
                            final selected = await showDialog<String>(
                              context: sheetContext,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Select bank'),
                                content: SizedBox(
                                  width: double.maxFinite,
                                  height: 350,
                                  child: ListView.builder(
                                    itemCount: _banks.length,
                                    itemBuilder: (context, index) {
                                      final bank = _banks[index];
                                      return ListTile(
                                        dense: true,
                                        title: Text(bank['name'] ?? '',
                                            style: TextStyle(
                                                fontSize: 14,
                                                color: colors.text)),
                                        onTap: () => Navigator.of(dialogContext)
                                            .pop(bank['code']),
                                      );
                                    },
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(),
                                      child: const Text('Close')),
                                ],
                              ),
                            );
                            if (selected != null) {
                              setSheetState(() => _formBankCode = selected);
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              color: colors.background,
                              border: Border.all(color: colors.border),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _banks.firstWhere(
                                        (b) => b['code'] == _formBankCode,
                                        orElse: () =>
                                            {'name': 'Select a bank'})['name'] ??
                                        'Select a bank',
                                    style: TextStyle(
                                        fontSize: 15,
                                        color: _formBankCode.isEmpty
                                            ? colors.textSecondary
                                            : colors.text),
                                  ),
                                ),
                                Icon(Icons.expand_more,
                                    color: colors.textSecondary, size: 20),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  if (_isIntl) ...[
                    field('Bank Name *', _bankNameController,
                        hint: 'e.g. Bank of America'),
                    if (_currency == 'USD')
                      field('Routing Number (ABA)',
                          _routingController,
                          keyboard: TextInputType.number,
                          maxLength: 12,
                          hint: '9 digits, e.g. 021000021'),
                    if (_currency == 'GBP')
                      field('Sort Code *', _routingController,
                          keyboard: TextInputType.number,
                          maxLength: 8,
                          hint: '6 digits, e.g. 308463'),
                    if (_currency == 'EUR')
                      field('SWIFT / BIC *', _swiftController,
                          maxLength: 11, hint: 'e.g. BECFDE7HKKX'),
                    if (_currency == 'USD')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Account type',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.text)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: ['checking', 'savings'].map((t) {
                                final selected =
                                    (_formAccountType.isEmpty
                                            ? 'checking'
                                            : _formAccountType) ==
                                        t;
                                return ChoiceChip(
                                  label: Text(t),
                                  selected: selected,
                                  onSelected: (_) =>
                                      setSheetState(() => _formAccountType = t),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    if (_currency == 'GBP')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Account type',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.text)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: ['personal', 'corporate'].map((t) {
                                final selected =
                                    (_formAccountType.isEmpty
                                            ? 'personal'
                                            : _formAccountType) ==
                                        t;
                                return ChoiceChip(
                                  label: Text(t),
                                  selected: selected,
                                  onSelected: (_) =>
                                      setSheetState(() => _formAccountType = t),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Country',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: colors.text)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _intlCountries.map((c) {
                              final selected = _formCountry == c['code'];
                              return ChoiceChip(
                                label: Text('${c['code']}'),
                                selected: selected,
                                onSelected: (_) => setSheetState(
                                    () => _formCountry = c['code']!),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    field('Street address', _addressController,
                        hint: 'e.g. 1801 Main St'),
                    Row(children: [
                      Expanded(
                          child: field('City', _cityController, hint: 'City')),
                      const SizedBox(width: 8),
                      Expanded(
                          child:
                              field('State', _stateController, hint: 'State')),
                    ]),
                    field('Postal code', _postalController,
                        hint: 'ZIP / postcode'),
                    field('Email (optional)', _emailController,
                        keyboard: TextInputType.emailAddress,
                        hint: 'beneficiary@email.com'),
                  ],
                  field(
                      _isIntl ? 'Account Number / IBAN *' : 'Account Number *',
                      _accountNumberController,
                      keyboard: _isIntl
                          ? TextInputType.text
                          : TextInputType.number,
                      maxLength: _isIntl ? 40 : 10,
                      hint: _isIntl
                          ? 'International account number or IBAN'
                          : '10-digit NUBAN'),
                  field(
                      _isIntl ? 'Beneficiary name' : 'Account name',
                      _accountNameController,
                      enabled:
                          _isIntl || !_verifiedResolved,
                      hint: _isIntl
                          ? 'Full beneficiary name'
                          : 'Auto-filled after verification'),
                  if (_verifiedName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.verified_rounded,
                              size: 16,
                              color: _verifiedResolved
                                  ? Colors.green
                                  : colors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _verifiedResolved
                                  ? 'Verified account name: $_verifiedName'
                                  : 'Details passed corridor validation',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: _verifiedResolved
                                      ? Colors.green
                                      : colors.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _verifying || _saving ? null : _verifyBeneficiary,
                          icon: _verifying
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.verified_rounded, size: 16),
                          label: const Text('Verify account'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saving || _verifying
                              ? null
                              : _saveBeneficiary,
                          icon: _saving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.save_rounded, size: 16),
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text('Beneficiaries'),
        actions: [
          IconButton(
            tooltip: 'Add beneficiary',
            icon: const Icon(Icons.person_add_alt_rounded),
            onPressed: _openAddSheet,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        onPressed: _openAddSheet,
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              scrollDirection: Axis.horizontal,
              itemCount: _currencies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final c = _currencies[index];
                final selected = _currency == c;
                return GestureDetector(
                  onTap: () => _switchCurrency(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? colors.primary : colors.surface,
                      border: Border.all(
                          color:
                              selected ? colors.primary : colors.border),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      c,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : colors.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: colors.primary))
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline_rounded,
                                size: 56, color: colors.textSecondary),
                            const SizedBox(height: 12),
                            Text('No $_currency beneficiaries yet',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: colors.text)),
                            const SizedBox(height: 6),
                            Text(
                              _isIntl
                                  ? 'Add an international beneficiary once and reuse it for every payout.'
                                  : 'Transfer to a Nigerian bank account, or add one manually.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: colors.primary,
                        onRefresh: _fetchBeneficiaries,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final b = _items[index];
                            final name =
                                (b['accountName'] ?? '').toString();
                            final acct =
                                (b['accountNumber'] ?? '').toString();
                            final bank =
                                (b['bankName'] ?? '').toString();
                            final currency =
                                (b['currency'] ?? _currency).toString();
                            final routing =
                                (b['routingNumber'] ?? '').toString();
                            final swift =
                                (b['swiftCode'] ?? '').toString();
                            final country =
                                (b['recipientCountry'] ?? '').toString();
                            final meta = [
                              if (bank.isNotEmpty) bank,
                              if (routing.isNotEmpty) 'Sort/Routing: $routing',
                              if (swift.isNotEmpty) 'SWIFT: $swift',
                              if (country.isNotEmpty) country,
                            ].join(' · ');
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                border: Border.all(color: colors.border),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor:
                                        colors.primary.withValues(alpha: 0.12),
                                    child: Text(
                                      (name.isNotEmpty
                                              ? name[0]
                                              : acct.isNotEmpty
                                                  ? acct[0]
                                                  : '?')
                                          .toUpperCase(),
                                      style: TextStyle(
                                          color: colors.primary,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name.isEmpty
                                                    ? acct
                                                    : name,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    color: colors.text),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                  horizontal: 8,
                                                  vertical: 2),
                                              decoration: BoxDecoration(
                                                color: colors.primaryBg,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text(currency,
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color:
                                                          colors.primary)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(acct,
                                            style: TextStyle(
                                                fontSize: 13,
                                                color:
                                                    colors.textSecondary)),
                                        if (meta.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(meta,
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: colors
                                                      .textSecondary)),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove beneficiary',
                                    icon: Icon(Icons.delete_outline_rounded,
                                        size: 20, color: colors.textSecondary),
                                    onPressed: () => _deleteBeneficiary(b),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
