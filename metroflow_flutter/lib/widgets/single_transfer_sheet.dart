import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/bank.dart';
import '../models/transfer.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../widgets/pin_input_boxes.dart';

/// Shared "Send Money" single-transfer flow (extracted from wallet_screen).
///
/// Owns ALL transfer-form state: wallet selector, NGN local-bank fields
/// (bank select + provider account lookup), USD international payout fields
/// (rail, SWIFT/ACH, Nominatim address autocomplete), live FX quote, remark,
/// Transaction PIN (PinInputBoxes) and the OTP request → confirm flow that
/// submits POST single transfer and navigates to the transfer-success page.
///
/// Hosted in two places:
///  - wallet_screen: `asPage: false` — renders as a draggable bottom sheet.
///  - single_transfer_screen: `asPage: true` — renders as a page body.
class SingleTransferSheet extends StatefulWidget {
  const SingleTransferSheet({
    super.key,
    this.initialWalletType = 'user',
    this.asPage = false,
    this.onSuccess,
    this.onClosed,
  });

  /// Wallet pre-selected when the form opens ('user' or 'business').
  final String initialWalletType;

  /// When true the form is embedded in a page (no bottom-sheet chrome);
  /// when false it renders as a draggable modal sheet.
  final bool asPage;

  /// Called after a transfer is submitted successfully (used by the wallet
  /// screen to refresh balances and close the modal).
  final VoidCallback? onSuccess;

  /// Called when the user closes the bottom sheet via the X button (wallet
  /// hides the modal host).
  final VoidCallback? onClosed;

  @override
  State<SingleTransferSheet> createState() => _SingleTransferSheetState();
}

class _SingleTransferSheetState extends State<SingleTransferSheet> {
  Map<String, dynamic> wallets = {};
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
  /// Inline 4-digit Transaction PIN for the transfer form (was a late dialog
  /// after OTP — users reported the section never appearing).
  String transactionPin = '';

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
  final TextEditingController _pinController = TextEditingController();

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

  bool isTransferLoading = false;
  bool isOtpLoading = false;
  bool showOtpModal = false;
  bool showBankSearchModal = false;
  /// Live OTP-for-transactions configuration. Fetched when the sheet opens
  /// AND re-checked at submit time — when the server says OTP verification
  /// is switched off, the "Send OTP" step disappears and the form submits
  /// with the transaction PIN only.
  bool otpRequired = true;

  /// Debounced auto account-name lookup: fires 600ms after the user types a
  /// complete 10-digit account number (or picks a bank with one entered).
  Timer? _lookupDebounce;

  @override
  void initState() {
    super.initState();
    selectedWalletType = widget.initialWalletType;
    _fetchWallets();
    _fetchBanks();
    _fetchOtpRequirement();
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
    _pinController.dispose();
    super.dispose();
  }

  void _scheduleAccountLookup() {
    _lookupDebounce?.cancel();
    if (selectedBankCode.isEmpty || accountNumber.trim().length != 10) return;
    _lookupDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) handleResolveAccount();
    });
  }

  Future<void> _fetchWallets() async {
    try {
      final response = await ApiService().getWallet();
      if (mounted) {
        setState(() {
          wallets = response.data ?? {};
          canManageBusinessWallet =
              response.data?['canManageBusinessWallet'] == true;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch wallet data: $e');
    }
  }

  /// Reads the live OTP-for-transactions configuration so the form only
  /// shows the OTP step when the server actually requires it.
  Future<void> _fetchOtpRequirement() async {
    try {
      final response = await ApiService().getOtpEnabled();
      final data = response.data;
      if (mounted && data is Map && data['success'] == true) {
        setState(() => otpRequired = data['otpEnabled'] as bool? ?? true);
      }
    } catch (e) {
      // Keep the safe default (OTP required) — the backend enforces the
      // authoritative setting at transfer time anyway.
      debugPrint('Failed to load OTP setting: $e');
    }
  }

  Future<void> _fetchBanks() async {
    try {
      final response = await ApiService().getBanks();
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
      transactionPin = '';
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
    _pinController.clear();
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
      final response = await ApiService()
          .resolveAccount(selectedBankCode, accountNumber, suppressToast: true);
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

  /// The form's single submit entry point: routes to the OTP request step
  /// when the configuration requires OTP verification, otherwise submits
  /// the transfer directly (PIN only).
  void _handleSubmitTransfer() {
    if (otpRequired) {
      handleRequestOtp();
    } else {
      handleInitiateTransfer();
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
      // Re-check the live configuration at submit time — the value cached
      // on open may be stale (e.g. the user toggled the setting on the web
      // or on another device in the meantime).
      final otpStatus = await ApiService().getOtpEnabled();
      final statusData = otpStatus.data;
      final liveOtpRequired = (statusData is Map && statusData['success'] == true)
          ? (statusData['otpEnabled'] as bool? ?? true)
          : true;
      if (mounted) setState(() => otpRequired = liveOtpRequired);
      if (!liveOtpRequired) {
        // OTP verification is switched off — skip straight to the
        // transaction-PIN-confirmed submission.
        await handleInitiateTransfer();
        return;
      }
      // suppressToast: false → the request method surfaces provider errors;
      // we also catch locally so the user ALWAYS sees why OTP failed
      // (previously errors were only debugPrint'ed and the flow stalled).
      await ApiService().requestTransferOtp(walletId: wallet['id']);
      if (mounted) {
        setState(() => showOtpModal = true);
      }
    } catch (e) {
      debugPrint('Failed to send OTP: $e');
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

    if (amount.isEmpty || (otpRequired && otpCode.isEmpty) || (double.tryParse(amount) ?? 0) <= 0) {
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

    // Transaction PIN is mandatory on the backend (4 digits). Prefer the
    // inline PIN section; fall back to the secure dialog when left blank.
    String pin = transactionPin.trim();
    if (pin.length != 4) {
      final prompted = await _promptForTransactionPin();
      if (prompted == null || prompted.isEmpty) return; // user cancelled
      pin = prompted;
    }

    setState(() => isOtpLoading = true);
    try {
      final payload = <String, dynamic>{
        // For international payouts `bankCode` carries the payout rail (ACH/SWIFT)
        'bank_code': _isIntlTransfer ? payoutRail : selectedBankCode,
        'account_number': accountNumber,
        'account_name': accountName,
        'amount': double.tryParse(amount) ?? 0,
        'remark': remark,
        // Only send the OTP when the configuration requires one.
        if (otpRequired) 'otp': otpCode,
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
      final response = await ApiService().singleTransfer(payload);
      if (!mounted) return;
      final singleResponse = SingleTransferResponse.fromJson(response.data);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer submitted successfully')),
      );
      setState(() {
        showOtpModal = false;
      });
      _resetTransferForm();
      // Refresh balances / close the host modal before navigating.
      widget.onSuccess?.call();
      if (mounted) {
        context.push('/main/transfer-success', extra: {
          'singleResponse': singleResponse,
        });
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

  /// Shows a secure 4-digit PIN dialog (PinInputBoxes). Returns null when
  /// cancelled.
  Future<String?> _promptForTransactionPin() {
    final pinController = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Transaction PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter your 4-digit transaction PIN to authorize this transfer.'),
              const SizedBox(height: 20),
              PinInputBoxes(
                controller: pinController,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
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
      ),
    );
  }

  // -----------------------------------------------------------------------
  // UI
  // -----------------------------------------------------------------------

  /// Wallet selector: every wallet the user may fund the transfer from
  /// (personal + business when available). The tapped card pre-selects one —
  /// users can switch here instead of closing and re-opening the modal from
  /// another card.
  Widget _buildTransferWalletSelector(ThemeColors colors) {
    final options = <Map<String, dynamic>>[
      if (wallets['user_wallet'] != null)
        {
          'type': 'user',
          'label': 'Personal Wallet',
          'wallet': wallets['user_wallet'],
        },
      if (canManageBusinessWallet && wallets['business_wallet'] != null)
        {
          'type': 'business',
          'label': 'Business Wallet',
          'wallet': wallets['business_wallet'],
        },
    ];

    if (options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          'No wallet available — complete your KYC to create one.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('From Wallet',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: colors.text)),
        const SizedBox(height: 8),
        ...options.map((option) {
          final type = option['type'] as String;
          final wallet = option['wallet'];
          final selected = selectedWalletType == type;
          final currency = (wallet['currency']?.toString() ?? 'NGN').toUpperCase();
          final balance = double.tryParse(wallet['balance']?.toString() ?? '0') ?? 0.0;
          final symbol = currency == 'USD' ? r'$' : (currency == 'EUR' ? '€' : (currency == 'GBP' ? '£' : '₦'));
          return GestureDetector(
            onTap: () => setState(() => selectedWalletType = type),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? colors.primaryBg : colors.surface,
                border: Border.all(
                  color: selected ? colors.primary : colors.border,
                  width: selected ? 1.4 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 20,
                    color: selected ? colors.primary : colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      option['label'] as String,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: colors.text,
                      ),
                    ),
                  ),
                  Text(
                    '$symbol${balance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected ? colors.primary : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Inline Transaction PIN section — always visible in the transfer form so
  /// users can authorise before sending the OTP (the post-OTP dialog
  /// remains as a fallback when this is left blank).
  Widget _buildTransactionPinField(ThemeColors colors) {
    return _buildField('Transaction PIN', PinInputBoxes(
      controller: _pinController,
      onChanged: (value) => setState(() => transactionPin = value),
    ));
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

  /// The scrollable transfer form (shared by the sheet and the page host).
  Widget _buildFormContent(ThemeColors colors, {ScrollController? scrollController}) {
    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -- Wallet selector (personal / business) --
          _buildTransferWalletSelector(colors),
          const SizedBox(height: 16),
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
          const SizedBox(height: 20),
          // -- Inline Transaction PIN section --
          _buildTransactionPinField(colors),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (isOtpLoading || (_isIntlTransfer ? !_intlBeneficiaryComplete : accountName.isEmpty)) ? null : _handleSubmitTransfer,
              child: isOtpLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(otpRequired ? 'Send OTP' : 'Confirm Transfer'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (widget.asPage) {
      // Page host (SingleTransferScreen): form fills the body directly.
      return Stack(
        children: [
          SafeArea(
            top: false,
            child: _buildFormContent(colors),
          ),
          if (showOtpModal) _buildOtpModal(colors),
          if (showBankSearchModal) _buildBankSearchModal(colors),
        ],
      );
    }

    // Bottom-sheet host (wallet screen).
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
                        IconButton(
                          icon: Icon(Icons.close, color: colors.text),
                          onPressed: () => widget.onClosed?.call(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: _buildFormContent(colors, scrollController: scrollController),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (showOtpModal) _buildOtpModal(colors),
        if (showBankSearchModal) _buildBankSearchModal(colors),
      ],
    );
  }
}
