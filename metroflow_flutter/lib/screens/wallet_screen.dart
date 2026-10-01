import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/bank.dart';


class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool isLoading = true;
  bool isRefreshing = false;
  bool isKycLoading = true;
  bool isTransferLoading = false;
  bool isOtpLoading = false;
  bool isVirtualAccountLoading = false;
  Map<String, dynamic> kycStatus = {'ninVerified': false, 'bvnVerified': false};
  Map<String, dynamic> wallets = {};
  /// Invited members must never see the business wallet — only owner/admin
  /// roles get the business wallet card (mirrors the backend flag).
  bool canManageBusinessWallet = false;
  List<Bank> banks = [];
  String bankSearchQuery = '';
  String selectedWalletType = 'user';
  String selectedBankCode = '';
  String accountNumber = '';
  String accountName = '';
  String amount = '';
  String remark = '';
  String otpCode = '';
  String selectedAccountType = 'Personal';

  // -- International (USD) payout — mirrors the web app Wallet transfer form --
  String transferCurrency = 'NGN';
  // Payout rail (backend `bankCode`): ACH local rails or SWIFT wire.
  String payoutRail = '';
  String bankName = '';
  String swiftCode = '';
  String routingNumber = '';
  String recipientCountry = 'US';
  String recipientAddress = '';
  String recipientCity = '';
  String recipientState = '';
  String recipientPostalCode = '';

  // Persistent controllers for the intl address fields (programmatic fills
  // from the autocomplete picker + user typing share the same state).
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _postalController = TextEditingController();

  /// OpenStreetMap Nominatim address autocomplete (keyless public API): as the
  /// user picks the country and types the street address, debounced queries
  /// suggest matching addresses and fill city/state/postcode.
  List<Map<String, dynamic>> addressSuggestions = [];
  bool addressSuggestLoading = false;
  bool showAddressSuggestions = false;
  bool _addressPickLock = false;
  Timer? _addressDebounce;
  Timer? _quoteDebounce;
  final Dio _nominatim = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  // Live FX quote for USD payouts (funded from an NGN wallet).
  Map<String, dynamic>? transferQuote;
  bool quoteLoading = false;
  bool quoteConfirmed = false;

  bool get _isIntlTransfer => transferCurrency != 'NGN';

  static const List<Map<String, String>> _intlPayoutCountries = [
    {'code': 'US', 'name': 'United States'},
    {'code': 'GB', 'name': 'United Kingdom'},
    {'code': 'CA', 'name': 'Canada'},
    {'code': 'AU', 'name': 'Australia'},
    {'code': 'IE', 'name': 'Ireland'},
    {'code': 'FR', 'name': 'France'},
    {'code': 'DE', 'name': 'Germany'},
    {'code': 'IT', 'name': 'Italy'},
    {'code': 'ES', 'name': 'Spain'},
    {'code': 'NL', 'name': 'Netherlands'},
    {'code': 'BE', 'name': 'Belgium'},
    {'code': 'AT', 'name': 'Austria'},
    {'code': 'PT', 'name': 'Portugal'},
    {'code': 'FI', 'name': 'Finland'},
    {'code': 'GR', 'name': 'Greece'},
    {'code': 'LU', 'name': 'Luxembourg'},
    {'code': 'KE', 'name': 'Kenya'},
    {'code': 'GH', 'name': 'Ghana'},
    {'code': 'ZA', 'name': 'South Africa'},
    {'code': 'TZ', 'name': 'Tanzania'},
    {'code': 'UG', 'name': 'Uganda'},
    {'code': 'RW', 'name': 'Rwanda'},
  ];

  bool showTransferModal = false;
  bool showOtpModal = false;
  bool showVirtualAccountModal = false;
  bool showBankSearchModal = false;

  /// Debounced auto account-name lookup: fires 600ms after the user types a
  /// complete 10-digit account number (or picks a bank with one entered).
  Timer? _lookupDebounce;

  @override
  void initState() {
    super.initState();
    checkKycStatus();
    fetchBanks();
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _addressDebounce?.cancel();
    _quoteDebounce?.cancel();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalController.dispose();
    super.dispose();
  }

  void _scheduleAccountLookup() {
    _lookupDebounce?.cancel();
    if (selectedBankCode.isEmpty || accountNumber.trim().length != 10) return;
    _lookupDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) handleResolveAccount();
    });
  }

  // -----------------------------------------------------------------------
  // International (USD) payout helpers
  // -----------------------------------------------------------------------

  /// Debounced Nominatim lookup: fires ~400ms after the user stops typing the
  /// street address (only for USD payouts with a country selected).
  void _scheduleAddressLookup() {
    _addressDebounce?.cancel();
    final q = recipientAddress.trim();
    if (!_isIntlTransfer || q.length < 3 || recipientCountry.isEmpty) {
      if (mounted) {
        setState(() {
          showAddressSuggestions = false;
          addressSuggestions = [];
        });
      }
      return;
    }
    _addressDebounce = Timer(const Duration(milliseconds: 400), _lookupAddressSuggestions);
  }

  Future<void> _lookupAddressSuggestions() async {
    setState(() => addressSuggestLoading = true);
    try {
      final response = await _nominatim.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'format': 'jsonv2',
          'addressdetails': 1,
          'limit': 5,
          'countrycodes': recipientCountry.toLowerCase(),
          'q': recipientAddress.trim(),
        },
        options: Options(headers: {
          'Accept': 'application/json',
          'User-Agent': 'Metroflow-Mobile/1.0 (support@metricorex.com)',
        }),
      );
      final list = response.data is List ? response.data as List : const [];
      if (!mounted) return;
      setState(() {
        addressSuggestions = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        showAddressSuggestions = addressSuggestions.isNotEmpty && !_addressPickLock;
      });
    } catch (e) {
      debugPrint('Address autocomplete failed: $e');
      if (mounted) {
        setState(() {
          addressSuggestions = [];
          showAddressSuggestions = false;
        });
      }
    } finally {
      if (mounted) setState(() => addressSuggestLoading = false);
    }
  }

  /// Fill street/city/state/postcode from a picked Nominatim result.
  void _pickAddressSuggestion(Map<String, dynamic> item) {
    final address = item['address'] is Map
        ? Map<String, dynamic>.from(item['address'] as Map)
        : <String, dynamic>{};
    _addressPickLock = true;
    final houseNumber = address['house_number']?.toString() ?? '';
    final road = address['road']?.toString() ?? '';
    String street = [houseNumber, road]
        .where((p) => p.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (street.isEmpty) {
      final name = item['name']?.toString() ?? '';
      final display = item['display_name']?.toString() ?? '';
      street = name.isNotEmpty
          ? name
          : (display.isNotEmpty ? display.split(',').first : '');
    }
    final city = (address['city'] ??
            address['town'] ??
            address['village'] ??
            address['suburb'] ??
            address['county'] ??
            '')
        .toString();
    final state = address['state']?.toString() ?? '';
    final postal = address['postcode']?.toString() ?? '';
    _addressController.text = street;
    _cityController.text = city;
    _stateController.text = state;
    _postalController.text = postal;
    setState(() {
      recipientAddress = street;
      recipientCity = city;
      recipientState = state;
      recipientPostalCode = postal;
      showAddressSuggestions = false;
    });
    Timer(const Duration(milliseconds: 500), () => _addressPickLock = false);
  }

  /// Debounced live FX quote fetch for USD payouts.
  void _scheduleQuoteFetch() {
    _quoteDebounce?.cancel();
    if (!_isIntlTransfer) return;
    final amt = double.tryParse(amount);
    if (amt == null || amt <= 0) {
      if (mounted) {
        setState(() {
          transferQuote = null;
          quoteConfirmed = false;
        });
      }
      return;
    }
    _quoteDebounce = Timer(const Duration(milliseconds: 500), _fetchQuote);
  }

  Future<void> _fetchQuote() async {
    final amt = double.tryParse(amount);
    if (amt == null || amt <= 0) return;
    setState(() => quoteLoading = true);
    try {
      final response = await ApiService().getTransferQuote(
        amount: amt,
        sourceCurrency: 'NGN',
        destinationCurrency: transferCurrency,
      );
      final data = response.data is Map ? response.data['data'] : null;
      if (!mounted) return;
      setState(() {
        transferQuote = data is Map ? Map<String, dynamic>.from(data) : null;
        quoteConfirmed = false;
      });
    } catch (e) {
      debugPrint('Quote fetch failed: $e');
      if (mounted) setState(() => transferQuote = null);
    } finally {
      if (mounted) setState(() => quoteLoading = false);
    }
  }

  /// USD beneficiary block completeness (backend rejects intl payouts without
  /// street address, city, postal code and ISO-2 country).
  bool get _intlBeneficiaryComplete {
    return payoutRail.isNotEmpty &&
        bankName.trim().isNotEmpty &&
        accountNumber.trim().isNotEmpty &&
        accountName.trim().isNotEmpty &&
        recipientCountry.trim().length == 2 &&
        recipientAddress.trim().isNotEmpty &&
        recipientCity.trim().isNotEmpty &&
        recipientPostalCode.trim().isNotEmpty;
  }

  void _resetTransferForm() {
    setState(() {
      selectedBankCode = '';
      accountNumber = '';
      accountName = '';
      amount = '';
      remark = '';
      otpCode = '';
      transferCurrency = 'NGN';
      payoutRail = '';
      bankName = '';
      swiftCode = '';
      routingNumber = '';
      recipientCountry = 'US';
      recipientAddress = '';
      recipientCity = '';
      recipientState = '';
      recipientPostalCode = '';
      addressSuggestions = [];
      showAddressSuggestions = false;
      transferQuote = null;
      quoteConfirmed = false;
    });
    _addressController.clear();
    _cityController.clear();
    _stateController.clear();
    _postalController.clear();
  }

  Future<void> checkKycStatus([bool showLoader = true]) async {
    if (showLoader) setState(() => isKycLoading = true);
    try {
      final api = ApiService();
      final response = await api.getKycStatus();
      final data = response.data as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>?;
      final business = data['business'] as Map<String, dynamic>?;
      final ninVerified = user?['ninStatus'] == 'verified' ||
          user?['nin_status'] == 'verified' ||
          data['nin_verified'] == true;
      final bvnVerified = user?['bvnStatus'] == 'verified' ||
          user?['bvn_status'] == 'verified' ||
          data['bvn_verified'] == true;
      final businessVerified = business?['status'] == 'verified' ||
          data['business_kyc_status'] == 'verified';
      setState(() {
        kycStatus = {
          'ninVerified': ninVerified,
          'bvnVerified': bvnVerified,
          'businessVerified': businessVerified
        };
      });
      if (ninVerified && bvnVerified) {
        await fetchWalletData();
      }
    } catch (e) {
      debugPrint('Failed to fetch KYC status: $e');
    } finally {
      if (mounted) {
        setState(() {
          isKycLoading = false;
          isRefreshing = false;
        });
      }
    }
  }

  Future<void> fetchWalletData() async {
    try {
      final api = ApiService();
      final response = await api.getWallet();
      if (mounted) {
        setState(() {
          wallets = response.data ?? {};
          canManageBusinessWallet = response.data?['canManageBusinessWallet'] == true;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch wallet data: $e');
    }
  }

  Future<void> fetchBanks() async {
    try {
      final api = ApiService();
      final response = await api.getBanks();
      if (response.data['success'] == true && mounted) {
        setState(() {
          banks = (response.data['data'] as List<dynamic>?)
                  ?.map((e) => Bank.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              [];
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch banks: $e');
    }
  }

  Future<void> handleCreateVirtualAccount() async {
    setState(() => isVirtualAccountLoading = true);
    try {
      final api = ApiService();
      await api.createVirtualAccount(selectedAccountType);
      if (mounted) {
        setState(() => showVirtualAccountModal = false);
        await fetchWalletData();
      }
    } catch (e) {
      debugPrint('Failed to create virtual account: $e');
    } finally {
      if (mounted) {
        setState(() => isVirtualAccountLoading = false);
      }
    }
  }

  Future<void> handleResolveAccount() async {
    if (selectedBankCode.isEmpty || accountNumber.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select bank and enter account number')),
        );
      }
      return;
    }
    setState(() => isTransferLoading = true);
    try {
      final api = ApiService();
      final response = await api.resolveAccount(selectedBankCode, accountNumber, suppressToast: true);
      // The backend nests provider responses several layers deep:
      //   { success, data: { status: 'success', data: { account_name } } }
      // extractAccountName walks every known shape (nested, flattened and
      // legacy responseBody) and returns null when nothing fits.
      final name = ApiService.extractAccountName(response.data);
      if (mounted) {
        if (name != null && name.isNotEmpty) {
          setState(() {
            accountName = name;
          });
        } else {
          setState(() => accountName = '');
          final errorMessage = response.data is Map
              ? (response.data['message'] ?? response.data['error'] ?? 'Could not verify this account — check the details')
              : 'Could not verify this account — check the details';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage.toString())),
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to resolve account: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to verify account: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isTransferLoading = false);
      }
    }
  }

  Future<void> handleRequestOtp() async {
    final wallet = selectedWalletType == 'user' ? wallets['user_wallet'] : wallets['business_wallet'];
    if (wallet == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wallet not found')),
        );
      }
      return;
    }

    if (_isIntlTransfer) {
      if (!_intlBeneficiaryComplete) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'International payouts need the payout rail, bank name, account number, beneficiary name, street address, city, postal code and country')));
        }
        return;
      }
      if (transferQuote == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Exchange rate quote unavailable — please check the amount and try again')));
        }
        return;
      }
    } else if (selectedBankCode.isEmpty || accountNumber.isEmpty || accountName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a bank, enter the account number and verify the account name')),
        );
      }
      return;
    }

    final amt = double.tryParse(amount);
    if (amount.isEmpty || amt == null || amt <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid amount')),
        );
      }
      return;
    }

    setState(() => isOtpLoading = true);
    try {
      final api = ApiService();
      await api.requestTransferOtp(walletId: wallet['id']);
      if (mounted) {
        setState(() => showOtpModal = true);
      }
    } catch (e) {
      debugPrint('Failed to send OTP: $e');
    } finally {
      if (mounted) {
        setState(() => isOtpLoading = false);
      }
    }
  }

  Future<void> handleInitiateTransfer() async {
    final wallet = selectedWalletType == 'user' ? wallets['user_wallet'] : wallets['business_wallet'];
    if (wallet == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wallet not found')),
        );
      }
      return;
    }

    if (amount.isEmpty || otpCode.isEmpty || (double.tryParse(amount) ?? 0) <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all fields')),
        );
      }
      return;
    }

    if (_isIntlTransfer) {
      if (!quoteConfirmed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Please review and confirm the exchange rate quote before sending')));
        }
        return;
      }
      if (!_intlBeneficiaryComplete) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('International payouts require the full beneficiary details')));
        }
        return;
      }
    }

    // Transaction PIN is mandatory on the backend (4 digits)
    final pin = await _promptForTransactionPin();
    if (pin == null || pin.isEmpty) return; // user cancelled

    setState(() => isOtpLoading = true);
    try {
      final api = ApiService();
      final payload = <String, dynamic>{
        // For international payouts `bankCode` carries the payout rail (ACH/SWIFT)
        'bank_code': _isIntlTransfer ? payoutRail : selectedBankCode,
        'account_number': accountNumber,
        'account_name': accountName,
        'amount': double.tryParse(amount) ?? 0,
        'remark': remark,
        'otp': otpCode,
        'pin': pin,
        'wallet_id': wallet['id'],
      };
      if (_isIntlTransfer) {
        payload['currency'] = transferCurrency;
        payload['bankName'] = bankName.trim();
        if (swiftCode.trim().isNotEmpty) {
          payload['swiftCode'] = swiftCode.trim().toUpperCase();
        }
        if (routingNumber.trim().isNotEmpty) {
          payload['routingNumber'] = routingNumber.trim();
        }
        payload['recipientAddress'] = recipientAddress.trim();
        payload['recipientCity'] = recipientCity.trim();
        if (recipientState.trim().isNotEmpty) {
          payload['recipientState'] = recipientState.trim();
        }
        payload['recipientPostalCode'] = recipientPostalCode.trim();
        payload['recipientCountry'] = recipientCountry.trim().toUpperCase();
        if (transferQuote != null && transferQuote!['total_debit'] != null) {
          payload['debitAmount'] = transferQuote!['total_debit'];
          payload['debitCurrency'] = 'NGN';
        }
      }
      await api.singleTransfer(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer submitted successfully')),
        );
        setState(() {
          showTransferModal = false;
          showOtpModal = false;
        });
        _resetTransferForm();
        await fetchWalletData();
        // Navigate to transfers history so the user sees the queued transfer
        if (mounted) context.push('/main/transfers');
      }
    } catch (e) {
      debugPrint('Transfer failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isOtpLoading = false);
      }
    }
  }

  /// Shows a secure 4-digit PIN dialog. Returns null when cancelled.
  Future<String?> _promptForTransactionPin() {
    final pinController = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Transaction PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter your 4-digit transaction PIN to authorize this transfer.'),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: '••••',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final pin = pinController.text.trim();
              if (pin.length == 4) {
                Navigator.of(dialogContext).pop(pin);
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void openTransferModal(String walletType) {
    setState(() {
      selectedWalletType = walletType;
      selectedBankCode = '';
      accountNumber = '';
      accountName = '';
      amount = '';
      remark = '';
      otpCode = '';
      showTransferModal = true;
    });
  }



  String _formatCurrency(dynamic wallet) {
    if (wallet == null) return '₦0.00';
    final currency = (wallet['currency']?.toString() ?? 'NGN').toUpperCase();
    final balance = double.tryParse(wallet['balance']?.toString() ?? '0') ?? 0.0;
    switch (currency) {
      case 'USD':
        return '\$${balance.toStringAsFixed(2)}';
      case 'EUR':
        return '€${balance.toStringAsFixed(2)}';
      case 'GBP':
        return '£${balance.toStringAsFixed(2)}';
      default:
        return '₦${balance.toStringAsFixed(2)}';
    }
  }

  Widget _buildWalletCard(dynamic wallet, String label, String walletType) {
    final hasWallet = wallet != null;
    final virtualAccounts = (wallet?['virtual_accounts'] as List?) ?? [];
    final hasVirtualAccounts = virtualAccounts.isNotEmpty;
    final colors = AppTheme.colors;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.text.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: colors.textSecondary, fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primaryBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasWallet ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _formatCurrency(wallet),
            style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: colors.text),
          ),
          if (hasVirtualAccounts) ...[
            const SizedBox(height: 24),
            ...virtualAccounts.map((account) {
                      final isActive = account['is_active'] == true;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isActive
                              ? colors.surfaceVariant
                              : colors.errorBg.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive ? colors.border : colors.error,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Account Number:', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                                Text(
                                  account['virtual_account_number'] ?? '',
                                  style: TextStyle(
                                    color: colors.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Bank:', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                                Text(
                                  _getBankName(account),
                                  style: TextStyle(
                                    color: colors.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            if (account['account_name'] != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Account Name:', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                                  Expanded(
                                    child: Text(
                                      account['account_name'] ?? '',
                                      style: TextStyle(
                                        color: colors.text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.right,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            if (!isActive)
                              Row(
                                children: [
                                  Icon(Icons.warning, color: colors.error, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Do not use this account. It is currently inactive.',
                                      style: TextStyle(
                                        color: colors.error,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (isActive)
                              Row(
                                children: [
                                  Icon(Icons.check_circle, color: colors.success, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Active - Use this account',
                                    style: TextStyle(
                                      color: colors.success,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    }),
          ],
          const SizedBox(height: 20),
          if (hasWallet)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: hasVirtualAccounts ? () => context.go('/main/fund-wallet', extra: {'walletType': walletType}) : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Fund Wallet', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasVirtualAccounts ? () => openTransferModal(walletType) : null,
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Transfer', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: colors.primary),
                      foregroundColor: colors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _getBankName(dynamic account) {
    // Backend-resolved bank name (from provider metadata or bank-code lookup)
    final resolvedName = account['bank_name'];
    if (resolvedName != null && resolvedName.toString().trim().isNotEmpty) {
      return resolvedName.toString();
    }
    // Try to get bank name from provider metadata if available
    final provider = account['payment_provider'];
    final providerMetadata = account['provider_metadata'];
    if (provider == 'monnify' && providerMetadata is Map) {
      final responseBody = providerMetadata['responseBody'];
      if (responseBody is Map) {
        final accounts = responseBody['accounts'] as List?;
        if (accounts != null && accounts.isNotEmpty) {
          final firstAccount = accounts.first as Map;
          return firstAccount['bankName'] ?? 'Monnify';
        }
      }
    }
    // Flutterwave stores the full VA response in metadata (data.bank_name)
    if (provider == 'flutterwave' && providerMetadata is Map) {
      final data = providerMetadata['data'];
      if (data is Map && data['bank_name'] != null) {
        return data['bank_name'].toString();
      }
    }
    // Default to bank code or provider
    final bankCode = account['bank_code'];
    if (bankCode == '058') return 'GTBank';
    if (bankCode == '035') return 'Wema Bank';
    if (bankCode == '232') return 'Sterling Bank';
    return provider ?? 'Unknown Bank';
  }

  Widget _buildQuickAction(IconData icon, String label, VoidCallback onTap) {
    final colors = AppTheme.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferModal(ThemeColors colors) {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Send Money', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text)),
                        IconButton(icon: Icon(Icons.close, color: colors.text), onPressed: () => setState(() => showTransferModal = false)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // -- Currency toggle: NGN local bank vs USD intl --
                            Row(
                              children: [
                                Expanded(
                                  child: _buildCurrencyToggle(
                                    colors,
                                    label: 'NGN — Local bank',
                                    selected: transferCurrency == 'NGN',
                                    onTap: () {
                                      if (transferCurrency == 'NGN') return;
                                      setState(() {
                                        transferCurrency = 'NGN';
                                        payoutRail = '';
                                        bankName = '';
                                        swiftCode = '';
                                        routingNumber = '';
                                        addressSuggestions = [];
                                        showAddressSuggestions = false;
                                        transferQuote = null;
                                        quoteConfirmed = false;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildCurrencyToggle(
                                    colors,
                                    label: 'USD — International',
                                    selected: transferCurrency == 'USD',
                                    onTap: () {
                                      if (transferCurrency == 'USD') return;
                                      setState(() {
                                        transferCurrency = 'USD';
                                        selectedBankCode = '';
                                        accountName = '';
                                        transferQuote = null;
                                        quoteConfirmed = false;
                                      });
                                      _scheduleQuoteFetch();
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (!_isIntlTransfer) ..._buildNgnTransferFields(colors),
                            if (_isIntlTransfer) ..._buildIntlTransferFields(colors),
                            const SizedBox(height: 20),
                            _buildField('Amount (${_isIntlTransfer ? '$transferCurrency — amount recipient receives' : 'NGN'})', TextField(
                              decoration: InputDecoration(
                                hintText: _isIntlTransfer ? 'e.g. 500' : 'Enter amount',
                                hintStyle: TextStyle(color: colors.textSecondary),
                              ),
                              style: TextStyle(color: colors.text, fontSize: 16),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (value) {
                                setState(() => amount = value);
                                if (_isIntlTransfer) _scheduleQuoteFetch();
                              },
                            )),
                            if (_isIntlTransfer) ...[
                              const SizedBox(height: 16),
                              _buildQuoteCard(colors),
                            ],
                            const SizedBox(height: 20),
                            _buildField('Remark (Optional)', TextField(
                              decoration: InputDecoration(hintText: 'Add a remark', hintStyle: TextStyle(color: colors.textSecondary)),
                              style: TextStyle(color: colors.text, fontSize: 16),
                              onChanged: (value) => setState(() => remark = value),
                            )),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: (isOtpLoading || (_isIntlTransfer ? !_intlBeneficiaryComplete : accountName.isEmpty)) ? null : handleRequestOtp,
                                child: isOtpLoading
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Send OTP'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCurrencyToggle(ThemeColors colors,
      {required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? colors.primaryBg : colors.surface,
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? 1.4 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colors.primary : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// NGN (local) fields: bank select + account number with provider lookup.
  List<Widget> _buildNgnTransferFields(ThemeColors colors) {
    return [
      _buildField('Select Bank', GestureDetector(
        onTap: () => setState(() => showBankSearchModal = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                banks.firstWhere((b) => b.code == selectedBankCode, orElse: () => Bank(code: '', name: 'Select a bank')).name,
                style: TextStyle(color: selectedBankCode.isEmpty ? colors.textSecondary : colors.text, fontSize: 16),
              ),
              Icon(Icons.expand_more, color: colors.textSecondary),
            ],
          ),
        ),
      )),
      const SizedBox(height: 20),
      _buildField('Account Number', Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Enter 10-digit account number',
                hintStyle: TextStyle(color: colors.textSecondary),
                counterText: '',
              ),
              style: TextStyle(color: colors.text, fontSize: 16),
              keyboardType: TextInputType.number,
              maxLength: 10,
              onChanged: (value) {
                setState(() => accountNumber = value);
                // Auto-verify once a full 10-digit
                // number is typed (600ms debounce).
                _scheduleAccountLookup();
              },
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(12)),
            child: TextButton(
              onPressed: isTransferLoading ? null : handleResolveAccount,
              child: isTransferLoading
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Verify', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ],
      )),
      if (accountName.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, size: 20, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Account name: $accountName',
                    style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  /// USD (international) fields: payout rail, beneficiary identity and the
  /// Flutterwave-required address block with Nominatim street autocomplete.
  List<Widget> _buildIntlTransferFields(ThemeColors colors) {
    return [
      _buildField('Payout Rail', Row(
        children: [
          Expanded(
            child: _buildCurrencyToggle(
              colors,
              label: 'ACH — U.S. bank (local rails)',
              selected: payoutRail == 'ACH',
              onTap: () => setState(() => payoutRail = 'ACH'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildCurrencyToggle(
              colors,
              label: 'SWIFT — International wire',
              selected: payoutRail == 'SWIFT',
              onTap: () => setState(() => payoutRail = 'SWIFT'),
            ),
          ),
        ],
      )),
      const SizedBox(height: 20),
      _buildField('Bank Name', TextField(
        decoration: InputDecoration(
          hintText: 'e.g. JPMorgan Chase Bank',
          hintStyle: TextStyle(color: colors.textSecondary),
        ),
        style: TextStyle(color: colors.text, fontSize: 16),
        onChanged: (value) => setState(() => bankName = value),
      )),
      if (payoutRail == 'SWIFT') ...[
        const SizedBox(height: 20),
        _buildField('SWIFT / BIC Code', TextField(
          decoration: InputDecoration(
            hintText: 'e.g. CHASUS33',
            hintStyle: TextStyle(color: colors.textSecondary),
          ),
          style: TextStyle(color: colors.text, fontSize: 16),
          textCapitalization: TextCapitalization.characters,
          onChanged: (value) => setState(() => swiftCode = value),
        )),
      ],
      if (payoutRail == 'ACH') ...[
        const SizedBox(height: 20),
        _buildField('Routing Number (ABA)', TextField(
          decoration: InputDecoration(
            hintText: 'e.g. 021000021',
            hintStyle: TextStyle(color: colors.textSecondary),
            counterText: '',
          ),
          style: TextStyle(color: colors.text, fontSize: 16),
          keyboardType: TextInputType.number,
          maxLength: 12,
          onChanged: (value) => setState(() => routingNumber = value),
        )),
      ],
      const SizedBox(height: 20),
      _buildField('Account Number / IBAN', TextField(
        decoration: InputDecoration(
          hintText: 'International account number',
          hintStyle: TextStyle(color: colors.textSecondary),
        ),
        style: TextStyle(color: colors.text, fontSize: 16),
        onChanged: (value) => setState(() => accountNumber = value),
      )),
      const SizedBox(height: 20),
      _buildField('Beneficiary Name', TextField(
        decoration: InputDecoration(
          hintText: 'Enter beneficiary name',
          hintStyle: TextStyle(color: colors.textSecondary),
        ),
        style: TextStyle(color: colors.text, fontSize: 16),
        onChanged: (value) => setState(() => accountName = value),
      )),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Recipient address *',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colors.text)),
                const Spacer(),
                if (addressSuggestLoading)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Used by Flutterwave for international payouts',
                style: TextStyle(fontSize: 11.5, color: colors.textSecondary)),
            const SizedBox(height: 10),
            _buildField('Country', Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colors.background,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _intlPayoutCountries.any((c) => c['code'] == recipientCountry)
                      ? recipientCountry
                      : 'US',
                  isExpanded: true,
                  dropdownColor: colors.surface,
                  icon: Icon(Icons.expand_more, color: colors.textSecondary),
                  items: _intlPayoutCountries
                      .map((c) => DropdownMenuItem<String>(
                            value: c['code'],
                            child: Text('${c['name']} (${c['code']})',
                                style: TextStyle(fontSize: 14, color: colors.text)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      recipientCountry = value;
                      showAddressSuggestions = false;
                    });
                    _scheduleAddressLookup();
                  },
                ),
              ),
            )),
            const SizedBox(height: 14),
            _buildField('Street Address', Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    hintText: 'Start typing the street address…',
                    hintStyle: TextStyle(color: colors.textSecondary),
                  ),
                  style: TextStyle(color: colors.text, fontSize: 16),
                  onChanged: (value) {
                    setState(() {
                      recipientAddress = value;
                      showAddressSuggestions = false;
                    });
                    _scheduleAddressLookup();
                  },
                ),
                if (showAddressSuggestions && addressSuggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(maxHeight: 190),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: addressSuggestions.length,
                      itemBuilder: (context, index) {
                        final item = addressSuggestions[index];
                        final label = item['display_name']?.toString() ?? '';
                        return InkWell(
                          onTap: () => _pickAddressSuggestion(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Text(
                              label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: colors.text, height: 1.3),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            )),
            const SizedBox(height: 14),
            _buildField('City', TextField(
              decoration: InputDecoration(
                hintText: 'City',
                hintStyle: TextStyle(color: colors.textSecondary),
              ),
              style: TextStyle(color: colors.text, fontSize: 16),
              controller: _cityController,
              onChanged: (value) => recipientCity = value,
            )),
            const SizedBox(height: 14),
            _buildField('State / Province (Optional)', TextField(
              decoration: InputDecoration(
                hintText: 'State',
                hintStyle: TextStyle(color: colors.textSecondary),
              ),
              style: TextStyle(color: colors.text, fontSize: 16),
              controller: _stateController,
              onChanged: (value) => recipientState = value,
            )),
            const SizedBox(height: 14),
            _buildField('Postal Code *', TextField(
              decoration: InputDecoration(
                hintText: 'e.g. 10001',
                hintStyle: TextStyle(color: colors.textSecondary),
              ),
              style: TextStyle(color: colors.text, fontSize: 16),
              keyboardType: TextInputType.text,
              controller: _postalController,
              onChanged: (value) => recipientPostalCode = value,
            )),
          ],
        ),
      ),
    ];
  }

  /// Live FX quote card (USD payouts): rate, fee, receiving amount and the
  /// mandatory confirmation checkbox before the transfer can be submitted.
  Widget _buildQuoteCard(ThemeColors colors) {
    String fmt(num? v) => (v ?? 0).toStringAsFixed(2);
    final rate = transferQuote?['marked_up_rate'] ?? transferQuote?['live_rate'];
    final totalDebit = transferQuote?['total_debit'];
    final fee = transferQuote?['fee'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryBg,
        border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Exchange rate quote',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: colors.text)),
              const Spacer(),
              if (quoteLoading)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          if (transferQuote == null && !quoteLoading)
            Text('Enter an amount to fetch the live rate.',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary))
          else if (transferQuote != null) ...[
            Text('Rate: 1 USD = ₦${fmt(rate is num ? rate : num.tryParse('$rate'))}',
                style: TextStyle(fontSize: 12.5, color: colors.text)),
            if (fee != null)
              Text('Fee: ₦${fmt(fee is num ? fee : num.tryParse('$fee'))}',
                  style: TextStyle(fontSize: 12.5, color: colors.text)),
            if (totalDebit != null)
              Text('You will be debited: ₦${fmt(totalDebit is num ? totalDebit : num.tryParse('$totalDebit'))}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.primary)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => quoteConfirmed = !quoteConfirmed),
              child: Row(
                children: [
                  Icon(
                    quoteConfirmed
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: quoteConfirmed ? colors.primary : colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('I confirm the exchange rate and total debit',
                        style: TextStyle(fontSize: 12.5, color: colors.text)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOtpModal(ThemeColors colors) {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.5,
          maxChildSize: 0.8,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Enter OTP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text)),
                        IconButton(icon: Icon(Icons.close, color: colors.text), onPressed: () => setState(() => showOtpModal = false)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildField('OTP Code', TextField(
                              decoration: InputDecoration(hintText: 'Enter OTP', hintStyle: TextStyle(color: colors.textSecondary)),
                              style: TextStyle(color: colors.text, fontSize: 16),
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              onChanged: (value) => setState(() => otpCode = value),
                            )),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: isOtpLoading ? null : handleInitiateTransfer,
                                child: isOtpLoading
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Confirm Transfer'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildVirtualAccountModal(ThemeColors colors) {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.5,
          maxChildSize: 0.8,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Create Virtual Account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text)),
                        IconButton(icon: Icon(Icons.close, color: colors.text), onPressed: () => setState(() => showVirtualAccountModal = false)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Select the type of virtual account to create.',
                                style: TextStyle(fontSize: 16, color: colors.textSecondary, height: 1.5)),
                            const SizedBox(height: 24),
                            _buildAccountTypeOption('Personal', 'Personal Wallet', colors),
                            if (canManageBusinessWallet) ...[
                              const SizedBox(height: 12),
                              _buildAccountTypeOption('Business', 'Business Wallet', colors),
                            ],
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: isVirtualAccountLoading ? null : handleCreateVirtualAccount,
                                child: isVirtualAccountLoading
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Create Virtual Account'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAccountTypeOption(String type, String label, ThemeColors colors) {
    final isSelected = selectedAccountType == type;
    return GestureDetector(
      onTap: () => setState(() => selectedAccountType = type),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary.withValues(alpha: 0.1) : colors.surface,
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: colors.text,
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankSearchModal(ThemeColors colors) {
    final filteredBanks = banks
        .where((b) => b.name.toLowerCase().contains(bankSearchQuery.toLowerCase()))
        .toList();

    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Select Bank', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text)),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.text),
                          onPressed: () {
                            setState(() {
                              showBankSearchModal = false;
                              bankSearchQuery = '';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: colors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Search bank name...',
                                hintStyle: TextStyle(color: colors.textSecondary),
                              ),
                              style: TextStyle(color: colors.text, fontSize: 16),
                              onChanged: (value) => setState(() => bankSearchQuery = value),
                              autofocus: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filteredBanks.length,
                        itemBuilder: (context, index) {
                          final bank = filteredBanks[index];
                          final isSelected = selectedBankCode == bank.code;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedBankCode = bank.code;
                                showBankSearchModal = false;
                                bankSearchQuery = '';
                              });
                              // Bank picked after typing the number? Verify now.
                              _scheduleAccountLookup();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.border))),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(bank.name, style: TextStyle(fontSize: 16, color: colors.text)),
                                  if (isSelected) Icon(Icons.check_circle, color: colors.primary, size: 20),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }



  Widget _buildField(String label, Widget child) {
    final colors = AppTheme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.text)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (isKycLoading) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }

    if (!kycStatus['ninVerified'] || !kycStatus['bvnVerified']) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: colors.surface),
                child: const SizedBox.shrink(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(60),
                        ),
                        child: Icon(Icons.lock, size: 64, color: colors.primary),
                      ),
                      const SizedBox(height: 24),
                      Text('KYC Verification Required',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.text),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Text(
                          'To access your wallet and perform transactions, you need to verify both your NIN and BVN.',
                          style: TextStyle(fontSize: 16, color: colors.textSecondary, height: 1.5),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  kycStatus['bvnVerified'] ? Icons.check_circle : Icons.warning,
                                  size: 20,
                                  color: kycStatus['bvnVerified'] ? AppColors.success : AppColors.error,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'BVN ${kycStatus['bvnVerified'] ? 'Verified' : 'Not Verified'}',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: colors.text),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  kycStatus['ninVerified'] ? Icons.check_circle : Icons.warning,
                                  size: 20,
                                  color: kycStatus['ninVerified'] ? AppColors.success : AppColors.error,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'NIN ${kycStatus['ninVerified'] ? 'Verified' : 'Not Verified'}',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: colors.text),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: colors.primary.withValues(alpha: 0.3), offset: const Offset(0, 4), blurRadius: 8),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [colors.primary, colors.primaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            ),
                            child: TextButton(
                              onPressed: () => context.go('/kyc-prompt'),
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                              child: const Text('Complete KYC Now',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() => isRefreshing = true);
                await checkKycStatus(false);
              },
              color: colors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: colors.surface),
                      child: const SizedBox.shrink(),
                    ),
                    _buildWalletCard(wallets['user_wallet'], 'Personal Wallet', 'user'),
                    if (canManageBusinessWallet)
                      _buildWalletCard(wallets['business_wallet'], 'Business Wallet', 'business'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildQuickAction(Icons.credit_card, 'Create Virtual Account',
                                () => setState(() => showVirtualAccountModal = true)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickAction(Icons.swap_horiz, 'View Transfers', () => context.go('/main/transfers')),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
          if (showTransferModal) _buildTransferModal(colors),
          if (showOtpModal) _buildOtpModal(colors),
          if (showVirtualAccountModal) _buildVirtualAccountModal(colors),
          if (showBankSearchModal) _buildBankSearchModal(colors),
        ],
      ),
    );
  }
}
