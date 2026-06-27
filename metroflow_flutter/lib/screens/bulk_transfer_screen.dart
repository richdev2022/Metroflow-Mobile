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
  List<Bank> _banks = [];
  List<Recipient> _recipients = [];
  String _otp = '';
  bool _loading = true;
  bool _showOtpModal = false;
  bool _submitting = false;
  String _bankSearchQuery = '';
  final _bankSearchController = TextEditingController();
  int _otpCountdown = 30;
  Timer? _otpTimer;
  bool _canResendOtp = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
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
    super.dispose();
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
            return Recipient(
              id: r.id,
              recipientAccount: value,
              recipientBank: r.recipientBank,
              recipientName: r.recipientName,
              amount: r.amount,
              remark: r.remark,
              sourceType: r.sourceType,
              sourceId: r.sourceId,
            );
          case 'recipientBank':
            return Recipient(
              id: r.id,
              recipientAccount: r.recipientAccount,
              recipientBank: value,
              recipientName: r.recipientName,
              amount: r.amount,
              remark: r.remark,
              sourceType: r.sourceType,
              sourceId: r.sourceId,
            );
          case 'recipientName':
            return Recipient(
              id: r.id,
              recipientAccount: r.recipientAccount,
              recipientBank: r.recipientBank,
              recipientName: value,
              amount: r.amount,
              remark: r.remark,
              sourceType: r.sourceType,
              sourceId: r.sourceId,
            );
          case 'amount':
            return Recipient(
              id: r.id,
              recipientAccount: r.recipientAccount,
              recipientBank: r.recipientBank,
              recipientName: r.recipientName,
              amount: value,
              remark: r.remark,
              sourceType: r.sourceType,
              sourceId: r.sourceId,
            );
          default:
            return r;
        }
      }).toList();
    });
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
    if (recipient.recipientBank.isEmpty || recipient.recipientAccount.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a bank and enter account number first')),
        );
      }
      return;
    }

    try {
      final api = ApiService();
      final response = await api.resolveAccount(
        recipient.recipientBank,
        recipient.recipientAccount,
        suppressToast: true,
      );
      if (response.data['success'] == true && mounted) {
        final data = response.data['data'];
        String? name;
        if (data is Map) {
          if (data['account_name'] != null) {
            name = data['account_name'];
          } else if (data['responseBody'] != null && data['responseBody']['accountName'] != null) {
            name = data['responseBody']['accountName'];
          }
        }
        if (name != null) {
          setState(() {
            _updateRecipient(recipientId, 'recipientName', name!);
          });
        }
      } else if (mounted) {
        final errorMessage = response.data['message'] ?? response.data['error'] ?? 'Failed to resolve account';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve account: ${e.toString()}')),
        );
      }
    }
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
      final hasEmptyFields = _recipients.any((r) =>
          r.recipientAccount.isEmpty || r.recipientBank.isEmpty || r.amount.isEmpty);
      if (hasEmptyFields) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please fill in all recipient details')),
          );
        }
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final api = ApiService();
      await api.requestTransferOtp(walletId: wallet['id']);
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

    if (_otp.length != 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid 6-digit OTP')),
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
      final hasEmptyFields = _recipients.any((r) =>
          r.recipientAccount.isEmpty || r.recipientBank.isEmpty || r.amount.isEmpty);
      if (hasEmptyFields) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please fill in all recipient details')),
          );
        }
        return;
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
        final payload = {
          'bankCode': recipient.recipientBank,
          'accountNumber': recipient.recipientAccount,
          'accountName': recipient.recipientName,
          'amount': double.tryParse(recipient.amount) ?? 0,
          'remark': recipient.remark,
          'otp': _otp,
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
          items = _recipients.map((r) {
            return {
              'amount': double.tryParse(r.amount) ?? 0,
              'bankCode': r.recipientBank.trim(),
              'accountNumber': r.recipientAccount.trim(),
              'accountName': r.recipientName.trim(),
              'remark': r.remark,
            };
          }).toList();
        }
        
        final payload = {
          'type': _transferType == 'salary' ? 'Salary' : 'Epic',
          'otp': _otp,
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

  double get _totalAmount {
    if (_transferType == 'salary') {
      return _employees.fold(0, (sum, emp) => sum + emp.netSalary);
    } else {
      return _recipients.fold(0, (sum, r) => sum + (double.tryParse(r.amount) ?? 0));
    }
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
                    totalAmount: _totalAmount,
                    transferType: _transferType,
                    recipientCount: _transferType == 'salary' ? _employees.length : _recipients.length,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selectedWalletData == null || _submitting ? null : _handleRequestOtp,
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Request OTP'),
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
              Text(
                'Recipient ${_recipients.indexOf(recipient) + 1}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
              ),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.delete_outlined, color: AppColors.error, size: 20),
                  onPressed: onRemove,
                ),
            ],
          ),
          _buildField(
            'Bank',
            GestureDetector(
              onTap: () {
                setState(() {
                  _bankSearchQuery = '';
                  _bankSearchController.clear();
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
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 20, color: AppColors.success),
                  const SizedBox(width: 8),
                  Text(
                    recipient.recipientName,
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildField(
            'Amount',
            TextField(
              decoration: InputDecoration(
                hintText: 'Enter amount (min: 100)',
                hintStyle: TextStyle(color: colors.textSecondary),
              ),
              style: TextStyle(color: colors.text, fontSize: 16),
              keyboardType: TextInputType.number,
              onChanged: (value) => _updateRecipient(recipient.id, 'amount', value),
            ),
          ),
        ],
      ),
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
                  hintText: 'Enter account number',
                ),
                style: const TextStyle(fontSize: 16),
                keyboardType: TextInputType.number,
                onChanged: (value) =>
                    _updateRecipient(recipient.id, 'recipientAccount', value),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _resolveAccountName(recipient.id),
              child: const Text('Verify'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard({
    required double totalAmount,
    required String transferType,
    required int recipientCount,
  }) {
    final colors = AppTheme.colors;
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
                Text(
                  '₦${totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                  style: TextStyle(
                    fontSize: 24,
                    color: colors.primary,
                    fontWeight: FontWeight.bold,
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
                                  return Recipient(
                                    id: r.id,
                                    recipientAccount: r.recipientAccount,
                                    recipientBank: r.recipientBank,
                                    recipientName: r.recipientName,
                                    amount: r.amount,
                                    remark: remark,
                                    sourceType: r.sourceType,
                                    sourceId: epic.id,
                                  );
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
                                  return Recipient(
                                    id: r.id,
                                    recipientAccount: r.recipientAccount,
                                    recipientBank: bank.code,
                                    recipientName: r.recipientName,
                                    amount: r.amount,
                                    remark: r.remark,
                                    sourceType: r.sourceType,
                                    sourceId: r.sourceId,
                                  );
                                }).toList();
                                _showBankPicker = false;
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
                        Text(
                          'Enter OTP',
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
                                hintText: 'Enter OTP',
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

class Recipient {
  final String id;
  final String recipientAccount;
  final String recipientBank;
  final String recipientName;
  final String amount;
  final String remark;
  final String sourceType;
  final String sourceId;

  Recipient({
    required this.id,
    required this.recipientAccount,
    required this.recipientBank,
    required this.recipientName,
    required this.amount,
    required this.remark,
    required this.sourceType,
    required this.sourceId,
  });
}
