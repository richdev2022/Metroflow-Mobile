import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/employee.dart';
import '../models/epic.dart';
import '../models/bank.dart';
import '../models/wallet.dart';
import '../models/transfer.dart';
import '../widgets/pin_input_boxes.dart';
import '../widgets/pin_setup_sheet.dart';

class BulkTransferScreen extends ConsumerStatefulWidget {
  const BulkTransferScreen({super.key});

  @override
  ConsumerState<BulkTransferScreen> createState() => _BulkTransferScreenState();
}

class _BulkTransferScreenState extends ConsumerState<BulkTransferScreen> {
  List<Employee> _employees = [];
  List<Epic> _epics = [];
  Map<String, dynamic> _wallets = {};
  String _selectedWallet = 'business';
  String _transferType = 'salary';
  String _transferMode = 'bulk';
  Epic? _selectedEpic;
  bool _showEpicPicker = false;
  bool _showBankPicker = false;
  String? _selectedRecipientIdForBank;
  List<Bank> _banks = [];
  List<Recipient> _recipients = [];
  String _otp = '';
  String _pin = '';
  String _selectedOtpMethod = 'sms';
  bool _loading = true;
  bool _showOtpModal = false;
  bool _submitting = false;
  /// Live OTP-for-transactions configuration — re-checked when the screen
  /// loads and again at submit time. When the server has OTP verification
  /// switched off, the "Request OTP" step is skipped entirely.
  bool _otpRequired = true;
  String _bankSearchQuery = '';
  final _bankSearchController = TextEditingController();
  int _otpCountdown = 30;
  Timer? _otpTimer;
  bool _canResendOtp = false;

  /// Debounced auto account-name lookups per recipient: 600ms after a
  /// complete 10-digit account number is typed (or a bank is picked for it).
  final Map<String, Timer> _lookupTimers = {};
  final Set<String> _resolvingRecipients = {};

  /// Transaction PIN gate — auto-prompted at most ONCE per app session.
  static bool _pinPromptShownThisSession = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _fetchOtpRequirement();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePinSetup());
  }

  /// Reads GET /settings/otp-enabled so the submit flow mirrors the current
  /// server-side configuration (OTP step only when actually enabled).
  Future<void> _fetchOtpRequirement() async {
    try {
      final response = await ApiService().getOtpEnabled();
      final data = response.data;
      if (mounted && data is Map && data['success'] == true) {
        setState(() => _otpRequired = data['otpEnabled'] as bool? ?? true);
      }
    } catch (e) {
      debugPrint('OTP setting check failed: $e');
    }
  }

  /// Checks GET /settings/otp-enabled; when no PIN exists yet, shows the
  /// setup sheet once (silent on failure — never blocks the screen).
  Future<void> _ensurePinSetup() async {
    if (_pinPromptShownThisSession) return;
    _pinPromptShownThisSession = true;
    try {
      final response = await ApiService().getOtpEnabled();
      final data = response.data;
      final pinCreated = data is Map && data['pinCreated'] == true;
      if (!mounted || pinCreated) return;
      await showPinSetupSheet(context);
    } catch (e) {
      debugPrint('PIN status check failed: $e');
    }
  }

  void _startOtpCountdown() {
    setState(() {
      _otpCountdown = 30;
      _canResendOtp = false;
    });
    _otpTimer?.cancel();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_otpCountdown > 0) {
          _otpCountdown--;
        } else {
          _canResendOtp = true;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _bankSearchController.dispose();
    _otpTimer?.cancel();
    for (final timer in _lookupTimers.values) {
      timer.cancel();
    }
    _lookupTimers.clear();
    super.dispose();
  }

  void _scheduleRecipientLookup(String recipientId) {
    _lookupTimers[recipientId]?.cancel();
    final recipient = _recipients.where((r) => r.id == recipientId).toList();
    if (recipient.isEmpty) return;
    // USD (international) rows have NO NGN account lookup — Flutterwave has
    // no account resolution there, the beneficiary details are typed in.
    if (recipient.first.isUsd) return;
    final account = recipient.first.recipientAccount.trim();
    final bank = recipient.first.recipientBank.trim();
    if (bank.isEmpty || account.length != 10) return;
    _lookupTimers[recipientId] = Timer(const Duration(milliseconds: 600), () {
      _lookupTimers.remove(recipientId);
      if (mounted) _resolveAccountName(recipientId);
    });
  }

  Future<void> _fetchData() async {
    try {
      final api = ApiService();
      final results = await Future.wait([
        api.getPayrollSummary(),
        api.getWallet(),
        api.getEpics(),
        api.getBanks(),
      ]);

      final payrollRes = results[0];
      final walletRes = results[1];
      final epicsRes = results[2];
      final banksRes = results[3];

      if (payrollRes.data != null && payrollRes.data['success'] == true && mounted) {
        final payroll = payrollRes.data['payroll'] as List<dynamic>? ?? [];
        setState(() {
          _employees = payroll
              .map((e) => Employee.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }

      if (walletRes.data != null && mounted) {
        final walletData = walletRes.data as Map<String, dynamic>;
        setState(() {
          _wallets = walletData;
        });
      }

      if (epicsRes.data != null && epicsRes.data['success'] == true && mounted) {
        final epicsData = epicsRes.data['data'] as List<dynamic>? ?? [];
        setState(() {
          _epics = epicsData
              .map((e) => Epic.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }

      if (banksRes.data != null && banksRes.data['success'] == true && mounted) {
        final banksData = banksRes.data['data'] as List<dynamic>? ?? [];
        setState(() {
          _banks = banksData
              .map((e) => Bank.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch data: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _addRecipient() {
    final remark = _selectedEpic != null
        ? (_selectedEpic!.name.length > 30
            ? '${_selectedEpic!.name.substring(0, 27)}...'
            : _selectedEpic!.name)
        : '';
    final newRecipient = Recipient(
      id: DateTime.now().toString(),
      recipientAccount: '',
      recipientBank: '',
      recipientName: '',
      amount: '',
      remark: remark,
      sourceType: _transferType == 'epic' ? 'epic' : '',
      sourceId: _selectedEpic?.id ?? '',
    );
    setState(() {
      _recipients = [..._recipients, newRecipient];
    });
  }

  void _removeRecipient(String id) {
    setState(() {
      _recipients = _recipients.where((r) => r.id != id).toList();
    });
  }

  void _updateRecipient(String id, String field, String value) {
    setState(() {
      _recipients = _recipients.map((r) {
        if (r.id != id) return r;
        switch (field) {
          case 'recipientAccount':
            return r.copyWith(recipientAccount: value);
          case 'recipientBank':
            return r.copyWith(recipientBank: value);
          case 'recipientName':
            return r.copyWith(recipientName: value);
          case 'amount':
            return r.copyWith(amount: value);
          case 'currency':
            // Corridor switch clears the OTHER side's fields so a stale
            // NGN bank code never rides along with a USD payout (and vice
            // versa) — mirrors the web behaviour.
            if (value == 'USD') {
              return r.copyWith(
                currency: 'USD',
                recipientBank: '',
                recipientName: '',
                recipientCountry: r.recipientCountry.isEmpty ? 'US' : r.recipientCountry,
              );
            }
            return r.copyWith(
              currency: 'NGN',
              bankName: '',
              swiftCode: '',
              routingNumber: '',
              accountType: 'checking',
              beneficiaryEmail: '',
              recipientAddress: '',
              recipientCity: '',
              recipientCountry: 'US',
            );
          case 'bankName':
            return r.copyWith(bankName: value);
          case 'swiftCode':
            return r.copyWith(swiftCode: value.toUpperCase());
          case 'routingNumber':
            return r.copyWith(routingNumber: value);
          case 'accountType':
            return r.copyWith(accountType: value);
          case 'beneficiaryEmail':
            return r.copyWith(beneficiaryEmail: value);
          case 'recipientAddress':
            return r.copyWith(recipientAddress: value);
          case 'recipientCity':
            return r.copyWith(recipientCity: value);
          case 'recipientCountry':
            return r.copyWith(recipientCountry: value);
          default:
            return r;
        }
      }).toList();
    });
    // Auto-verify as soon as a full 10-digit account number is typed
    // (NGN rows only — USD rows have no lookup).
    if (field == 'recipientAccount' && !_recipients.any((r) => r.id == id && r.isUsd)) {
      _scheduleRecipientLookup(id);
    }
  }

  Future<void> _resolveAccountName(String recipientId) async {
    final recipient = _recipients.firstWhere(
      (r) => r.id == recipientId,
      orElse: () => Recipient(
        id: '',
        recipientAccount: '',
        recipientBank: '',
        recipientName: '',
        amount: '',
        remark: '',
        sourceType: '',
        sourceId: '',
      ),
    );
    // USD (international) rows have no NGN account-name lookup.
    if (recipient.isUsd) return;
    if (recipient.recipientBank.isEmpty || recipient.recipientAccount.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a bank and enter account number first')),
        );
      }
      return;
    }

    setState(() => _resolvingRecipients.add(recipientId));
    try {
      final api = ApiService();
      final response = await api.resolveAccount(
        recipient.recipientBank,
        recipient.recipientAccount,
        suppressToast: true,
      );
      // Deep-defensive parsing: the backend nests the provider payload as
      // { success, data: { status: 'success', data: { account_name } } }.
      final name = ApiService.extractAccountName(response.data);
      if (mounted) {
        if (name != null && name.isNotEmpty) {
          _updateRecipient(recipientId, 'recipientName', name);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not verify this account — check the details')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve account: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _resolvingRecipients.remove(recipientId));
      }
    }
  }

  /// ABA routing-number checksum (US): weights cycle [3,7,1] over the first
  /// 8 digits; the 9th digit must equal (10 - sum % 10) % 10 — the standard
  /// 3-7-1 checksum the backend validates server-side.
  bool _isValidAbaRouting(String routing) {
    if (!RegExp(r'^\d{9}$').hasMatch(routing)) return false;
    final digits = routing.split('').map((c) => int.parse(c)).toList();
    const weights = [3, 7, 1];
    var sum = 0;
    for (var i = 0; i < 8; i++) {
      sum += digits[i] * weights[i % 3];
    }
    return (10 - (sum % 10)) % 10 == digits[8];
  }

  /// SWIFT/BIC: 8 or 11 alphanumeric characters.
  bool _isValidSwift(String swift) =>
      RegExp(r'^[A-Za-z0-9]{8}(?:[A-Za-z0-9]{3})?$').hasMatch(swift.trim());

  /// Per-recipient completeness + validity. Returns null when the row is
  /// submittable, otherwise a human-readable reason (first failure wins).
  String? _recipientValidationError(Recipient r) {
    if (r.amount.trim().isEmpty || (double.tryParse(r.amount) ?? 0) <= 0) {
      return 'enter a valid amount';
    }
    if (r.isUsd) {
      if (r.bankName.trim().isEmpty) return 'bank name is required for USD transfers';
      if (!_isValidSwift(r.swiftCode)) {
        return 'SWIFT code must be 8 or 11 characters';
      }
      if (!_isValidAbaRouting(r.routingNumber.trim())) {
        return 'routing number must be a valid 9-digit ABA number';
      }
      if (r.recipientAccount.trim().isEmpty) return 'account number is required';
      if (r.recipientName.trim().isEmpty) return 'account name is required';
    } else {
      if (r.recipientBank.isEmpty) return 'select a bank';
      if (!RegExp(r'^\d{10}$').hasMatch(r.recipientAccount.trim())) {
        return 'NGN account numbers must be exactly 10 digits';
      }
    }
    return null;
  }

  Future<void> _handleRequestOtp() async {
    final wallet = _selectedWallet == 'business' ? _wallets['business_wallet'] : _wallets['user_wallet'];
    if (wallet == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wallet not found')),
        );
      }
      return;
    }

    if (_transferType == 'epic' && _selectedEpic == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an Epic')),
        );
      }
      return;
    }

    if (_transferType == 'epic') {
      // Per-currency completeness: NGN rows need bank + 10-digit account;
      // USD rows need bank name + SWIFT + valid ABA routing + account.
      for (final r in _recipients) {
        final error = _recipientValidationError(r);
        if (error != null) {
          if (mounted) {
            final label = r.accountDisplayLabel();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label: $error')),
            );
          }
          return;
        }
      }
    }

    setState(() => _submitting = true);
    try {
      final api = ApiService();

      // Re-check the live configuration at submit time — the cached value
      // may be stale (e.g. toggled on the web or another device).
      final otpStatus = await api.getOtpEnabled();
      final statusData = otpStatus.data;
      if (mounted && statusData is Map && statusData['success'] == true) {
        setState(() => _otpRequired = statusData['otpEnabled'] as bool? ?? true);
      }
      if (!_otpRequired) {
        await _handleInitiateTransfer();
        return;
      }

      await api.requestTransferOtp(walletId: wallet['id'], otpMethod: _selectedOtpMethod);
      if (mounted) {
        setState(() => _showOtpModal = true);
        _startOtpCountdown();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send OTP: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// The screen's single submit entry point: requests an OTP first when the
  /// configuration requires it, otherwise initiates the transfer directly.
  void _handleSubmitTransfer() {
    if (_otpRequired) {
      _handleRequestOtp();
    } else {
      _handleInitiateTransfer();
    }
  }

  Future<void> _handleInitiateTransfer() async {
    final wallet = _selectedWallet == 'business' ? _wallets['business_wallet'] : _wallets['user_wallet'];
    if (wallet == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wallet not found')),
        );
      }
      return;
    }

    if (_otpRequired && _otp.length != 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid 6-digit OTP')),
        );
      }
      return;
    }

    if (_pin.length < 4) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid transaction PIN')),
        );
      }
      return;
    }

    if (_transferType == 'epic' && _selectedEpic == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an Epic')),
        );
      }
      return;
    }

    if (_transferType == 'epic') {
      // Per-currency completeness + validity (same gate as the OTP step).
      for (final r in _recipients) {
        final error = _recipientValidationError(r);
        if (error != null) {
          if (mounted) {
            final label = r.accountDisplayLabel();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label: $error')),
            );
          }
          return;
        }
      }
      
      // Check minimum amount for epic transfers
      final hasInvalidAmount = _recipients.any((r) => (double.tryParse(r.amount) ?? 0) < 100);
      if (hasInvalidAmount) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All amounts must be at least 100')),
          );
        }
        return;
      }
    }
    
    // Check minimum amount for salary transfers
    if (_transferType == 'salary') {
      final hasInvalidAmount = _employees.any((emp) => (emp.netSalary as num) < 100);
      if (hasInvalidAmount) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All salaries must be at least 100')),
          );
        }
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final api = ApiService();
      
      // Check if it's single transfer mode
      if (_transferType == 'epic' && _transferMode == 'single') {
        final recipient = _recipients.first;
        // Per-recipient corridor: USD rows send the single-transfer
        // handler's native international names, NGN rows keep bankCode.
        final payload = <String, dynamic>{
          'accountNumber': recipient.recipientAccount.trim(),
          'accountName': recipient.recipientName.trim(),
          'amount': double.tryParse(recipient.amount) ?? 0,
          // Row currency — the wallet-currency guard stays server-side.
          'currency': recipient.currency.toUpperCase(),
          'remark': recipient.remark,
          if (recipient.isUsd) ...{
            'bankName': recipient.bankName.trim(),
            'swiftCode': recipient.swiftCode.trim(),
            'routingNumber': recipient.routingNumber.trim(),
            'recipientAddress': recipient.recipientAddress.trim(),
            'recipientCity': recipient.recipientCity.trim(),
            'recipientCountry': recipient.recipientCountry.trim().toUpperCase(),
            'accountType': recipient.accountType,
            if (recipient.beneficiaryEmail.trim().isNotEmpty)
              'beneficiaryEmail': recipient.beneficiaryEmail.trim(),
          } else ...{
            'bankCode': recipient.recipientBank.trim(),
          },
          // Only send the OTP when the configuration requires one.
          if (_otpRequired) 'otp': _otp,
          'pin': _pin,
          'wallet_id': wallet['id'],
        };
        
        final response = await api.singleTransfer(payload);
        final singleResponse = SingleTransferResponse.fromJson(response.data);
        
        if (mounted) {
          setState(() {
            _submitting = false;
            _showOtpModal = false;
          });
          context.push('/main/transfer-success', extra: {
            'singleResponse': singleResponse,
          });
        }
      } else {
        // Bulk transfer (Salary or Epic bulk)
        List<Map<String, dynamic>> items;
        
        if (_transferType == 'salary') {
          items = _employees.map((emp) {
            return {
              'amount': emp.netSalary,
              'bankCode': emp.bankCode ?? '',
              'accountNumber': emp.bankAccountNumber ?? '',
              'accountName': emp.name,
              'remark': 'Salary Payment',
            };
          }).toList();
        } else {
          // Epic recipients — per-recipient corridor (NGN|USD). USD items
          // use the POST /transfers/bulk contract names (recipientBankName,
          // recipientSwiftCode, recipientRoutingNumber, ...); NGN items keep
          // bankCode + 10-digit account.
          items = _recipients.map((r) {
            return <String, dynamic>{
              'amount': double.tryParse(r.amount) ?? 0,
              'accountNumber': r.recipientAccount.trim(),
              'accountName': r.recipientName.trim(),
              'currency': r.currency.toUpperCase(),
              'remark': r.remark,
              if (r.isUsd) ...{
                'recipientBankName': r.bankName.trim(),
                'recipientSwiftCode': r.swiftCode.trim(),
                'recipientRoutingNumber': r.routingNumber.trim(),
                'recipientAddress': r.recipientAddress.trim(),
                'recipientCity': r.recipientCity.trim(),
                'recipientCountry': r.recipientCountry.trim().toUpperCase(),
                'beneficiaryEmail': r.beneficiaryEmail.trim(),
                'accountType': r.accountType,
              } else ...{
                'bankCode': r.recipientBank.trim(),
              },
            };
          }).toList();
        }

        final payload = <String, dynamic>{
          'type': _transferType == 'salary' ? 'Salary' : 'Epic',
          // New contract: top-level `items` (+ `epicId`). The legacy
          // `data.items` shape below is kept so older backends keep working.
          if (_transferType == 'epic') ...{
            'items': items,
            if (_selectedEpic?.id != null) 'epicId': _selectedEpic!.id,
          },
          // Only send the OTP when the configuration requires one.
          if (_otpRequired) 'otp': _otp,
          'pin': _pin,
          'source_wallet_id': wallet['id'],
          'data': {
            'items': items,
          },
        };
        
        final response = await api.bulkTransferV2(payload);
        final bulkResponse = BulkTransferResponse.fromJson(response.data);
        
        if (mounted) {
          setState(() {
            _submitting = false;
            _showOtpModal = false;
          });
          context.push('/main/transfer-success', extra: {
            'bulkResponse': bulkResponse,
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: ${e.toString()}')),
        );
      }
    }
  }

  /// Per-currency totals — the summary card renders one line per currency
  /// ("NGN 12,000 · USD 300") for mixed-corridor Epic batches.
  Map<String, double> get _totalsByCurrency {
    if (_transferType == 'salary') {
      return {
        'NGN': _employees.fold<double>(
            0, (sum, emp) => sum + (emp.netSalary as num).toDouble()),
      };
    }
    final totals = <String, double>{};
    for (final r in _recipients) {
      final currency = r.currency.toUpperCase();
      totals[currency] = (totals[currency] ?? 0) + (double.tryParse(r.amount) ?? 0);
    }
    return totals;
  }

  Wallet? get _selectedWalletData {
    final wallet = _selectedWallet == 'business' ? _wallets['business_wallet'] : _wallets['user_wallet'];
    return wallet != null ? Wallet.fromJson(wallet as Map<String, dynamic>) : null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (_loading) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: colors.text),
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Initiate Transfer',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colors.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle(title: 'Transfer Type'),
                  Row(
                    children: ['salary', 'epic'].map((type) {
                      final isSelected = _transferType == type;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _transferType = type;
                              _transferMode = 'bulk';
                              _recipients = [];
                              _selectedEpic = null;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected ? colors.primary : colors.surface,
                              border: Border.all(
                                color: isSelected ? colors.primary : colors.border,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  type == 'salary' ? Icons.payments : Icons.folder_outlined,
                                  color: isSelected ? Colors.white : colors.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  type[0].toUpperCase() + type.substring(1),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? Colors.white : colors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_transferType == 'epic') ...[
                    const SizedBox(height: 24),
                    _sectionTitle(title: 'Transfer Mode'),
                    Row(
                      children: ['single', 'bulk'].map((mode) {
                        final isSelected = _transferMode == mode;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _transferMode = mode;
                                _recipients = [];
                                if (mode == 'single') {
                                  _addRecipient();
                                }
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSelected ? colors.primary : colors.surface,
                                border: Border.all(
                                  color: isSelected ? colors.primary : colors.border,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    mode == 'single' ? Icons.person_outlined : Icons.people_outlined,
                                    color: isSelected ? Colors.white : colors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    mode[0].toUpperCase() + mode.substring(1),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? Colors.white : colors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle(title: 'Select Epic'),
                    GestureDetector(
                      onTap: () => setState(() => _showEpicPicker = true),
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
                              _selectedEpic?.name ?? 'Select an Epic',
                              style: TextStyle(
                                fontSize: 16,
                                color: _selectedEpic == null ? colors.textSecondary : colors.text,
                              ),
                            ),
                            Icon(Icons.expand_more, color: colors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _sectionTitle(title: 'Source Wallet'),
                  Column(
                    children: [
                      if (_wallets['business_wallet'] != null)
                        _buildWalletOption('Business Wallet', 'business'),
                      if (_wallets['user_wallet'] != null)
                        _buildWalletOption('Personal Wallet', 'user'),
                    ],
                  ),
                  if (_transferType == 'salary') ...[
                    const SizedBox(height: 24),
                    _sectionTitle(title: 'Employees (${_employees.length})'),
                    ..._employees.map((emp) => _employeeTile(employee: emp)),
                  ],
                  if (_transferType == 'epic') ...[
                    const SizedBox(height: 24),
                    _sectionTitle(
                      title: 'Recipients${_transferMode == 'bulk' ? ' (${_recipients.length})' : ''}',
                    ),
                    if (_transferMode == 'bulk')
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: _addRecipient,
                              icon: Icon(Icons.add, color: colors.primary),
                              label: Text('Add Recipient', style: TextStyle(color: colors.primary)),
                            ),
                          ),
                        ],
                      ),
                    ..._recipients.map((r) => _recipientCard(
                      recipient: r,
                      onRemove: _transferMode == 'bulk' ? () => _removeRecipient(r.id) : null,
                    )),
                  ],
                  const SizedBox(height: 24),
                  _summaryCard(
                    totalsByCurrency: _totalsByCurrency,
                    transferType: _transferType,
                    recipientCount: _transferType == 'salary' ? _employees.length : _recipients.length,
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle(title: 'OTP Delivery Method'),
                  const SizedBox(height: 12),
                  Row(
                    children: ['sms', 'whatsapp', 'email'].map((method) {
                      final isSelected = _selectedOtpMethod == method;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedOtpMethod = method),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? colors.primary.withValues(alpha: 0.1) : colors.surface,
                                border: Border.all(
                                  color: isSelected ? colors.primary : colors.border,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                method.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected ? colors.primary : colors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selectedWalletData == null || _submitting ? null : _handleSubmitTransfer,
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_otpRequired ? 'Request OTP' : 'Confirm Transfer'),
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
            if (_showEpicPicker) _buildEpicPicker(colors),
            if (_showBankPicker) _buildBankPicker(colors),
            if (_showOtpModal) _buildOtpModal(colors),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle({required String title}) {
    final colors = AppTheme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.textSecondary,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildWalletOption(String label, String type) {
    final colors = AppTheme.colors;
    final wallet = _wallets[type == 'business' ? 'business_wallet' : 'user_wallet'];
    final isSelected = _selectedWallet == type;

    if (wallet == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => setState(() => _selectedWallet = type),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$label (${wallet['currency'] ?? 'NGN'} ${_formatWalletBalance(wallet['balance'])})',
          style: TextStyle(
            fontSize: 16,
            color: isSelected ? colors.primary : colors.text,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  String _formatWalletBalance(dynamic balance) {
    double numBalance = 0.0;
    if (balance is num) {
      numBalance = balance.toDouble();
    } else if (balance is String) {
      numBalance = double.tryParse(balance) ?? 0.0;
    }
    return numBalance.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  Widget _employeeTile({required Employee employee}) {
    final colors = AppTheme.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
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
                  employee.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  employee.email,
                  style: TextStyle(fontSize: 14, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '₦${(employee.netSalary as num).toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recipientCard({
    required Recipient recipient,
    VoidCallback? onRemove,
  }) {
    final colors = AppTheme.colors;
    final isUsd = recipient.isUsd;
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Recipient ${_recipients.indexOf(recipient) + 1}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
              ),
              // Per-recipient corridor toggle (NGN | USD) — mirrors the web
              // Payroll page's mixed batches.
              _buildCurrencyToggle(recipient),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.delete_outlined, color: AppColors.error, size: 20),
                  onPressed: onRemove,
                ),
            ],
          ),
          if (isUsd) ...[
            _buildUsdFields(recipient),
          ] else ...[
            _buildField(
              'Bank',
              GestureDetector(
                onTap: () {
                  setState(() {
                    _bankSearchQuery = '';
                    _bankSearchController.clear();
                    _selectedRecipientIdForBank = recipient.id;
                    _showBankPicker = true;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: colors.background,
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _banks.firstWhere((b) => b.code == recipient.recipientBank, orElse: () => Bank(code: '', name: 'Select a bank')).name,
                        style: TextStyle(
                          fontSize: 16,
                          color: recipient.recipientBank.isEmpty ? colors.textSecondary : colors.text,
                        ),
                      ),
                      Icon(Icons.expand_more, color: colors.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildAccountField(recipient),
            if (recipient.recipientName.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
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
                        'Account name: ${recipient.recipientName}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          _buildField(
            'Amount${isUsd ? ' (USD)' : ' (NGN)'}',
            TextField(
              decoration: InputDecoration(
                hintText: 'Enter amount (min: 100)',
                hintStyle: TextStyle(color: colors.textSecondary),
                prefixText: isUsd ? '\u0024 ' : '\u20A6 ',
                prefixStyle: TextStyle(color: colors.text, fontSize: 16),
              ),
              style: TextStyle(color: colors.text, fontSize: 16),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) => _updateRecipient(recipient.id, 'amount', value),
            ),
          ),
        ],
      ),
    );
  }

  /// NGN | USD segmented pill for one recipient row.
  Widget _buildCurrencyToggle(Recipient recipient) {
    final colors = AppTheme.colors;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['NGN', 'USD'].map((currency) {
          final isSelected = recipient.currency.toUpperCase() == currency;
          return GestureDetector(
            onTap: () => _updateRecipient(recipient.id, 'currency', currency),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? colors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                currency,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : colors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// USD (international) beneficiary fields — validated per the backend's
  /// corridor rules: bank name required, SWIFT 8/11, 9-digit ABA routing
  /// with the 3-7-1 checksum. No account-name lookup exists on this route.
  Widget _buildUsdFields(Recipient recipient) {
    final colors = AppTheme.colors;
    final routing = recipient.routingNumber.trim();
    final routingValid = routing.isEmpty || _isValidAbaRouting(routing);
    final swift = recipient.swiftCode.trim();
    final swiftValid = swift.isEmpty || _isValidSwift(swift);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildField(
          'Bank Name *',
          TextField(
            decoration: InputDecoration(
              hintText: 'e.g. JPMorgan Chase Bank',
              hintStyle: TextStyle(color: colors.textSecondary),
            ),
            style: TextStyle(color: colors.text, fontSize: 16),
            controller: TextEditingController(text: recipient.bankName)
              ..selection = TextSelection.collapsed(offset: recipient.bankName.length),
            onChanged: (value) => _updateRecipient(recipient.id, 'bankName', value),
          ),
        ),
        const SizedBox(height: 16),
        _buildField(
          'SWIFT / BIC *',
          TextField(
            decoration: InputDecoration(
              hintText: '8 or 11 characters (e.g. CHASUS33)',
              hintStyle: TextStyle(color: colors.textSecondary),
              errorText: swiftValid ? null : '8 or 11 characters',
            ),
            style: TextStyle(color: colors.text, fontSize: 16),
            textCapitalization: TextCapitalization.characters,
            controller: TextEditingController(text: recipient.swiftCode)
              ..selection = TextSelection.collapsed(offset: recipient.swiftCode.length),
            onChanged: (value) => _updateRecipient(recipient.id, 'swiftCode', value),
          ),
        ),
        const SizedBox(height: 16),
        _buildField(
          'Routing Number (ABA, 9 digits) *',
          TextField(
            decoration: InputDecoration(
              hintText: 'e.g. 021000021',
              hintStyle: TextStyle(color: colors.textSecondary),
              errorText: routingValid
                  ? null
                  : 'Invalid ABA checksum — double-check with the beneficiary',
              counterText: '',
            ),
            style: TextStyle(color: colors.text, fontSize: 16),
            keyboardType: TextInputType.number,
            maxLength: 9,
            controller: TextEditingController(text: recipient.routingNumber)
              ..selection = TextSelection.collapsed(offset: recipient.routingNumber.length),
            onChanged: (value) => _updateRecipient(recipient.id, 'routingNumber', value),
          ),
        ),
        const SizedBox(height: 16),
        _buildField(
          'Account Number *',
          TextField(
            decoration: InputDecoration(
              hintText: 'Beneficiary account number',
              hintStyle: TextStyle(color: colors.textSecondary),
            ),
            style: TextStyle(color: colors.text, fontSize: 16),
            keyboardType: TextInputType.number,
            controller: TextEditingController(text: recipient.recipientAccount)
              ..selection = TextSelection.collapsed(offset: recipient.recipientAccount.length),
            onChanged: (value) => _updateRecipient(recipient.id, 'recipientAccount', value),
          ),
        ),
        const SizedBox(height: 16),
        _buildField(
          'Account Type *',
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.background,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonFormField<String>(
              initialValue: (recipient.accountType == 'savings') ? 'savings' : 'checking',
              dropdownColor: colors.surface,
              style: TextStyle(color: colors.text, fontSize: 16),
              icon: Icon(Icons.expand_more, color: colors.textSecondary),
              decoration: const InputDecoration(border: InputBorder.none),
              items: const [
                DropdownMenuItem(value: 'checking', child: Text('Checking')),
                DropdownMenuItem(value: 'savings', child: Text('Savings')),
              ],
              onChanged: (value) {
                if (value != null) {
                  _updateRecipient(recipient.id, 'accountType', value);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildField(
          'Account Name *',
          TextField(
            decoration: InputDecoration(
              hintText: 'Beneficiary full name (as on the account)',
              hintStyle: TextStyle(color: colors.textSecondary),
            ),
            style: TextStyle(color: colors.text, fontSize: 16),
            controller: TextEditingController(text: recipient.recipientName)
              ..selection = TextSelection.collapsed(offset: recipient.recipientName.length),
            onChanged: (value) => _updateRecipient(recipient.id, 'recipientName', value),
          ),
        ),
        const SizedBox(height: 16),
        _buildField(
          'Beneficiary Email',
          TextField(
            decoration: InputDecoration(
              hintText: 'name@example.com',
              hintStyle: TextStyle(color: colors.textSecondary),
            ),
            style: TextStyle(color: colors.text, fontSize: 16),
            keyboardType: TextInputType.emailAddress,
            controller: TextEditingController(text: recipient.beneficiaryEmail)
              ..selection = TextSelection.collapsed(offset: recipient.beneficiaryEmail.length),
            onChanged: (value) => _updateRecipient(recipient.id, 'beneficiaryEmail', value),
          ),
        ),
        const SizedBox(height: 16),
        _buildField(
          'Street Address',
          TextField(
            decoration: InputDecoration(
              hintText: 'Beneficiary street address',
              hintStyle: TextStyle(color: colors.textSecondary),
            ),
            style: TextStyle(color: colors.text, fontSize: 16),
            controller: TextEditingController(text: recipient.recipientAddress)
              ..selection = TextSelection.collapsed(offset: recipient.recipientAddress.length),
            onChanged: (value) => _updateRecipient(recipient.id, 'recipientAddress', value),
          ),
        ),
        const SizedBox(height: 16),
        _buildField(
          'City',
          TextField(
            decoration: InputDecoration(
              hintText: 'e.g. New York',
              hintStyle: TextStyle(color: colors.textSecondary),
            ),
            style: TextStyle(color: colors.text, fontSize: 16),
            controller: TextEditingController(text: recipient.recipientCity)
              ..selection = TextSelection.collapsed(offset: recipient.recipientCity.length),
            onChanged: (value) => _updateRecipient(recipient.id, 'recipientCity', value),
          ),
        ),
        const SizedBox(height: 16),
        _buildField(
          'Country',
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.background,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonFormField<String>(
              initialValue: _usdCountries.any((c) => c.code == recipient.recipientCountry)
                  ? recipient.recipientCountry
                  : 'US',
              dropdownColor: colors.surface,
              style: TextStyle(color: colors.text, fontSize: 16),
              icon: Icon(Icons.expand_more, color: colors.textSecondary),
              decoration: const InputDecoration(border: InputBorder.none),
              items: _usdCountries
                  .map((country) => DropdownMenuItem(
                        value: country.code,
                        child: Text(country.name),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  _updateRecipient(recipient.id, 'recipientCountry', value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField(String label, Widget child) {
    final colors = AppTheme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildAccountField(Recipient recipient) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Account Number',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Enter 10-digit account number',
                  counterText: '',
                ),
                style: const TextStyle(fontSize: 16),
                keyboardType: TextInputType.number,
                maxLength: 10,
                onChanged: (value) =>
                    _updateRecipient(recipient.id, 'recipientAccount', value),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _resolvingRecipients.contains(recipient.id)
                  ? null
                  : () => _resolveAccountName(recipient.id),
              child: _resolvingRecipients.contains(recipient.id)
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Verify'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard({
    required Map<String, double> totalsByCurrency,
    required String transferType,
    required int recipientCount,
  }) {
    final colors = AppTheme.colors;
    final totalsLabel = totalsByCurrency.entries
        .map((entry) =>
            '${entry.key} ${entry.value.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}')
        .join('  ·  ');
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transfer Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                transferType == 'salary' ? 'Number of Employees' : 'Number of Recipients',
                style: TextStyle(fontSize: 16, color: colors.textSecondary),
              ),
              Text(
                recipientCount.toString(),
                style: TextStyle(
                  fontSize: 16,
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Amount',
                  style: TextStyle(fontSize: 16, color: colors.textSecondary),
                ),
                Flexible(
                  child: Text(
                    totalsLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: totalsByCurrency.length > 1 ? 17 : 24,
                      color: colors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpicPicker(ThemeColors colors) {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
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
                        Text(
                          'Select Epic',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colors.text,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.text),
                          onPressed: () => setState(() => _showEpicPicker = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _epics.length,
                        itemBuilder: (context, index) {
                          final epic = _epics[index];
                          final isSelected = _selectedEpic?.id == epic.id;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedEpic = epic;
                                _recipients = _recipients.map((r) {
                                  final remark = epic.name.length > 30
                                      ? '${epic.name.substring(0, 27)}...'
                                      : epic.name;
                                  return r.copyWith(remark: remark, sourceId: epic.id);
                                }).toList();
                                _showEpicPicker = false;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: colors.border)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    epic.name,
                                    style: TextStyle(fontSize: 16, color: colors.text),
                                  ),
                                  if (isSelected)
                                    Icon(Icons.check_circle, color: colors.primary, size: 20),
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

  Widget _buildBankPicker(ThemeColors colors) {
    final filteredBanks = _banks
        .where((bank) => bank.name.toLowerCase().contains(_bankSearchQuery.toLowerCase()))
        .toList();

    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
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
                        Text(
                          'Select Bank',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colors.text,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.text),
                          onPressed: () => setState(() => _showBankPicker = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _bankSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search banks...',
                        prefixIcon: Icon(Icons.search, color: colors.textSecondary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colors.primary),
                        ),
                      ),
                      style: TextStyle(color: colors.text),
                      onChanged: (value) {
                        setState(() => _bankSearchQuery = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filteredBanks.length,
                        itemBuilder: (context, index) {
                          final bank = filteredBanks[index];
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _recipients = _recipients.map((r) {
                                  if (r.id == _selectedRecipientIdForBank) {
                                    return r.copyWith(recipientBank: bank.code);
                                  }
                                  return r;
                                }).toList();
                                _showBankPicker = false;
                                final selectedId = _selectedRecipientIdForBank;
                                _selectedRecipientIdForBank = null;
                                // Bank picked for a complete 10-digit number?
                                // Verify automatically.
                                if (selectedId != null) {
                                  _scheduleRecipientLookup(selectedId);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: colors.border)),
                              ),
                              child: Text(
                                bank.name,
                                style: TextStyle(fontSize: 16, color: colors.text),
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

  Future<void> _handleResendOtp() async {
    await _handleRequestOtp();
  }

  Widget _buildOtpModal(ThemeColors colors) {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
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
                        Text(
                          'Confirm Transfer',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colors.text,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.text),
                          onPressed: () => setState(() => _showOtpModal = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              decoration: const InputDecoration(
                                labelText: 'OTP Code',
                                hintText: 'Enter 6-digit OTP',
                              ),
                              style: const TextStyle(fontSize: 24),
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              textAlign: TextAlign.center,
                              onChanged: (value) => setState(() => _otp = value),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _canResendOtp
                                      ? 'Didn\'t receive OTP?'
                                      : 'Resend OTP in $_otpCountdown seconds',
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                                if (_canResendOtp)
                                  TextButton(
                                    onPressed: _submitting ? null : _handleResendOtp,
                                    child: Text(
                                      'Resend OTP',
                                      style: TextStyle(
                                        color: colors.primary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            PinInputBoxes(
                              boxSize: 46,
                              onChanged: (value) => setState(() => _pin = value),
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _submitting ? null : _handleInitiateTransfer,
                                child: _submitting
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
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
}

/// ISO-2 country options for the USD beneficiary country dropdown
/// (default US — mirrors the web Payroll page's country select).
class _CountryOption {
  final String code;
  final String name;
  const _CountryOption(this.code, this.name);
}

const List<_CountryOption> _usdCountries = [
  _CountryOption('US', 'United States (US)'),
  _CountryOption('CA', 'Canada (CA)'),
  _CountryOption('GB', 'United Kingdom (GB)'),
  _CountryOption('DE', 'Germany (DE)'),
  _CountryOption('FR', 'France (FR)'),
  _CountryOption('ES', 'Spain (ES)'),
  _CountryOption('IT', 'Italy (IT)'),
  _CountryOption('NL', 'Netherlands (NL)'),
  _CountryOption('IE', 'Ireland (IE)'),
  _CountryOption('PT', 'Portugal (PT)'),
  _CountryOption('BE', 'Belgium (BE)'),
  _CountryOption('AT', 'Austria (AT)'),
  _CountryOption('CH', 'Switzerland (CH)'),
  _CountryOption('SE', 'Sweden (SE)'),
  _CountryOption('NO', 'Norway (NO)'),
  _CountryOption('DK', 'Denmark (DK)'),
  _CountryOption('FI', 'Finland (FI)'),
  _CountryOption('PL', 'Poland (PL)'),
  _CountryOption('AU', 'Australia (AU)'),
  _CountryOption('NZ', 'New Zealand (NZ)'),
  _CountryOption('JP', 'Japan (JP)'),
  _CountryOption('SG', 'Singapore (SG)'),
  _CountryOption('HK', 'Hong Kong (HK)'),
  _CountryOption('AE', 'United Arab Emirates (AE)'),
  _CountryOption('ZA', 'South Africa (ZA)'),
  _CountryOption('KE', 'Kenya (KE)'),
  _CountryOption('GH', 'Ghana (GH)'),
  _CountryOption('BR', 'Brazil (BR)'),
  _CountryOption('MX', 'Mexico (MX)'),
  _CountryOption('IN', 'India (IN)'),
];

class Recipient {
  final String id;
  final String recipientAccount;
  final String recipientBank;
  final String recipientName;
  final String amount;
  final String remark;
  final String sourceType;
  final String sourceId;

  /// Per-recipient corridor: 'NGN' (default) or 'USD' (Epic international
  /// payout). Mirrors the web Payroll page's mixed NGN+USD batches.
  final String currency;

  // USD (international) beneficiary fields — only meaningful when
  // currency == 'USD'. Sent with the /transfers contract names below.
  final String bankName;
  final String swiftCode;
  final String routingNumber;
  final String accountType; // 'checking' | 'savings'
  final String beneficiaryEmail;
  final String recipientAddress;
  final String recipientCity;
  final String recipientCountry; // ISO-2, default 'US'

  Recipient({
    required this.id,
    required this.recipientAccount,
    required this.recipientBank,
    required this.recipientName,
    required this.amount,
    required this.remark,
    required this.sourceType,
    required this.sourceId,
    this.currency = 'NGN',
    this.bankName = '',
    this.swiftCode = '',
    this.routingNumber = '',
    this.accountType = 'checking',
    this.beneficiaryEmail = '',
    this.recipientAddress = '',
    this.recipientCity = '',
    this.recipientCountry = 'US',
  });

  bool get isUsd => currency.toUpperCase() == 'USD';

  /// Short label for validation messages: account name, else masked account,
  /// else a generic "Recipient".
  String accountDisplayLabel() {
    if (recipientName.trim().isNotEmpty) return recipientName.trim();
    final account = recipientAccount.trim();
    if (account.length >= 4) return '••••${account.substring(account.length - 4)}';
    return 'Recipient';
  }

  Recipient copyWith({
    String? recipientAccount,
    String? recipientBank,
    String? recipientName,
    String? amount,
    String? remark,
    String? sourceType,
    String? sourceId,
    String? currency,
    String? bankName,
    String? swiftCode,
    String? routingNumber,
    String? accountType,
    String? beneficiaryEmail,
    String? recipientAddress,
    String? recipientCity,
    String? recipientCountry,
  }) {
    return Recipient(
      id: id,
      recipientAccount: recipientAccount ?? this.recipientAccount,
      recipientBank: recipientBank ?? this.recipientBank,
      recipientName: recipientName ?? this.recipientName,
      amount: amount ?? this.amount,
      remark: remark ?? this.remark,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      currency: currency ?? this.currency,
      bankName: bankName ?? this.bankName,
      swiftCode: swiftCode ?? this.swiftCode,
      routingNumber: routingNumber ?? this.routingNumber,
      accountType: accountType ?? this.accountType,
      beneficiaryEmail: beneficiaryEmail ?? this.beneficiaryEmail,
      recipientAddress: recipientAddress ?? this.recipientAddress,
      recipientCity: recipientCity ?? this.recipientCity,
      recipientCountry: recipientCountry ?? this.recipientCountry,
    );
  }
}
