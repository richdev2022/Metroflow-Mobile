import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api.dart';
import '../models/employee.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  List<Employee> _employees = [];
  Employee? _selectedEmployee;
  bool _isLoading = false;
  bool _showConfigModal = false;
  bool _showAdjustmentModal = false;
  bool _showEmployeeDetailModal = false;
  bool _showEditEmployeeModal = false;
  List<dynamic> _adjustments = [];
  String _salaryInterval = 'monthly';
  String _salaryCustomDate = '';
  String _payrollSearch = '';
  String _roleFilter = '';
  String _startDate = '';
  String _endDate = '';
  int _payrollPage = 1;
  int _payrollTotalPages = 1;
  String _adjType = 'bonus';
  String _adjAmount = '';
  String _adjCurrency = 'NGN';
  String _adjReason = '';
  Map<String, dynamic> _editEmployeeData = {};

  final _searchController = TextEditingController();
  final _adjAmountController = TextEditingController();
  final _adjReasonController = TextEditingController();
  final _editSalaryController = TextEditingController();
  final _editBankCodeController = TextEditingController();
  final _editBankAccountController = TextEditingController();
  final _editAccountNameController = TextEditingController();
  final _editContractStartController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchPayrollData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _adjAmountController.dispose();
    _adjReasonController.dispose();
    _editSalaryController.dispose();
    _editBankCodeController.dispose();
    _editBankAccountController.dispose();
    _editAccountNameController.dispose();
    _editContractStartController.dispose();
    super.dispose();
  }

  Future<void> _fetchPayrollData({bool showLoader = true, int page = 1}) async {
    if (showLoader && mounted) setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final summaryParams = <String, dynamic>{
        'page': page,
        'limit': 20,
      };
      if (_payrollSearch.trim().isNotEmpty) summaryParams['search'] = _payrollSearch.trim();
      if (_roleFilter.isNotEmpty) summaryParams['role'] = _roleFilter;
      if (_startDate.isNotEmpty) summaryParams['startDate'] = _startDate;
      if (_endDate.isNotEmpty) summaryParams['endDate'] = _endDate;

      final results = await Future.wait([
        api.getPayrollSummary(params: summaryParams),
        api.getPayrollConfig(),
      ]);

      final summaryRes = results[0];
      if (summaryRes.statusCode == 200) {
        final data = summaryRes.data;
        final payrollList = _extractPayrollList(data);
        if (payrollList.isNotEmpty || (data is Map && data['success'] == true)) {
          final payrollData = payrollList.map((emp) {
            final e = emp as Map<String, dynamic>;
            return Employee.fromJson(e);
          }).toList();
          if (mounted) {
            setState(() {
              _employees = payrollData;
              _payrollPage = page;
              final pagination = data is Map ? data['pagination'] as Map<String, dynamic>? : null;
              _payrollTotalPages = (pagination?['totalPages'] as num?)?.toInt() ?? 1;
            });
          }
        }
      }

      final configRes = results[1];
      if (configRes.statusCode == 200) {
        final data = configRes.data;
        if (data is Map && data['success'] == true) {
          final root = data as Map<String, dynamic>;
          final cfg = (root['config'] as Map<String, dynamic>?) ??
              (root['data'] as Map<String, dynamic>?) ??
              root;
          if (mounted) {
            setState(() {
              _salaryInterval = cfg['salary_interval'] ?? 'monthly';
              _salaryCustomDate = cfg['salary_custom_date'] ?? '';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch payroll data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchAdjustments(String userId) async {
    try {
      final api = ApiService();
      final response = await api.getPayrollAdjustments(userId: userId);
      if (response.statusCode == 200) {
        final data = response.data;
        final adjustments = _extractAdjustmentsList(data);
        if (mounted) {
          setState(() {
            _adjustments = adjustments;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch adjustments: $e');
    }
  }

  Future<void> _handleUpdateConfig() async {
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      await api.updatePayrollConfig({
        'salary_interval': _salaryInterval,
        'salary_custom_date': _salaryInterval == 'custom' ? _salaryCustomDate : null,
      });
      AppToast.show('Payroll config updated successfully', type: AppToastType.success);
      if (mounted) setState(() => _showConfigModal = false);
      await _fetchPayrollData();
    } catch (e) {
      AppToast.show(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAddAdjustment() async {
    if (_selectedEmployee == null ||
        _adjAmount.isEmpty ||
        _adjReason.isEmpty) {
      AppToast.show('Please fill all fields');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      await api.addPayrollAdjustment({
        'userId': _selectedEmployee!.id,
        'type': _adjType,
        'amount': double.tryParse(_adjAmount) ?? 0.0,
        'currency': _adjCurrency,
        'reason': _adjReason,
      });
      AppToast.show('Adjustment added successfully', type: AppToastType.success);
      if (mounted) {
        setState(() {
          _showAdjustmentModal = false;
          _adjAmount = '';
          _adjCurrency = 'NGN';
          _adjReason = '';
        });
      }
      _adjAmountController.clear();
      _adjReasonController.clear();
      await _fetchAdjustments(_selectedEmployee!.id);
      await _fetchPayrollData();
    } catch (e) {
      AppToast.show(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDeleteAdjustment(String adjId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Adjustment'),
        content: const Text('Are you sure you want to delete this adjustment?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final api = ApiService();
      await api.deletePayrollAdjustment(adjId);
      AppToast.show('Adjustment deleted', type: AppToastType.success);
      if (_selectedEmployee != null) {
        await _fetchAdjustments(_selectedEmployee!.id);
        await _fetchPayrollData();
      }
    } catch (e) {
      AppToast.show(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _openEmployeeDetail(Employee employee) {
    setState(() {
      _selectedEmployee = employee;
      _showEmployeeDetailModal = true;
    });
    _fetchAdjustments(employee.id);
  }

  void _openEditEmployeeModal(Employee employee) {
    _editSalaryController.text = employee.salary.toString();
    _editBankAccountController.text = employee.bankAccountNumber ?? '';
    _editBankCodeController.text = employee.bankCode ?? '';
    _editAccountNameController.text = employee.accountName ?? '';
    _editContractStartController.text = employee.contractStartDate ?? '';
    setState(() {
      _editEmployeeData = {
        'salary': employee.salary.toString(),
        'salary_currency': employee.salaryCurrency,
        'bank_account_number': employee.bankAccountNumber,
        'bank_code': employee.bankCode,
        'account_name': employee.accountName,
        'contract_start_date': employee.contractStartDate,
      };
      _showEditEmployeeModal = true;
    });
  }

  Future<void> _handleUpdateEmployee() async {
    if (_selectedEmployee == null) return;

    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      await api.updatePayrollUser(_selectedEmployee!.id, {
        'salary': double.tryParse(_editEmployeeData['salary'] ?? '0') ?? 0,
        'salary_currency': _editEmployeeData['salary_currency'] ?? 'NGN',
        'bank_account_number': _editEmployeeData['bank_account_number'] ?? '',
        'bank_code': _editEmployeeData['bank_code'] ?? '',
        'account_name': _editEmployeeData['account_name'] ?? '',
        'contract_start_date': _editEmployeeData['contract_start_date'] ?? '',
      });
      AppToast.show('Employee payroll details updated successfully', type: AppToastType.success);
      if (mounted) setState(() => _showEditEmployeeModal = false);
      await _fetchPayrollData();
    } catch (e) {
      AppToast.show(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _totalNetPay {
    return _employees.fold(0, (sum, e) => sum + (e.netSalary));
  }

  String _formatAmount(double amount) {
    return '\u20A6${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}';
  }

  String _formatDateParam(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _selectPayrollCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _salaryCustomDate.isNotEmpty
          ? DateTime.tryParse(_salaryCustomDate) ?? DateTime.now()
          : DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _salaryCustomDate = picked.toIso8601String());
    }
  }

  Future<void> _selectPayrollStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate.isNotEmpty ? DateTime.tryParse(_startDate) ?? DateTime.now() : DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _startDate = _formatDateParam(picked));
      _fetchPayrollData();
    }
  }

  Future<void> _selectPayrollEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isNotEmpty ? DateTime.tryParse(_endDate) ?? DateTime.now() : DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _endDate = _formatDateParam(picked));
      _fetchPayrollData();
    }
  }

  void _clearPayrollFilters() {
    _searchController.clear();
    setState(() {
      _payrollSearch = '';
      _roleFilter = '';
      _startDate = '';
      _endDate = '';
      _payrollPage = 1;
    });
    _fetchPayrollData();
  }

  List<dynamic> _extractPayrollList(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return const [];
    final direct = data['payroll'] ?? data['data'];
    if (direct is List) return direct;
    if (direct is Map && direct['payroll'] is List) return direct['payroll'] as List;
    if (direct is Map && direct['items'] is List) return direct['items'] as List;
    return const [];
  }

  List<dynamic> _extractAdjustmentsList(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return const [];
    final direct = data['adjustments'] ?? data['data'];
    if (direct is List) return direct;
    if (direct is Map && direct['adjustments'] is List) return direct['adjustments'] as List;
    if (direct is Map && direct['items'] is List) return direct['items'] as List;
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            _isLoading && _employees.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 24),
                        _buildSummaryCard(),
                        const SizedBox(height: 32),
                        _buildEmployeesSection(),
                        if (_payrollTotalPages > 1) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: _payrollPage <= 1
                                    ? null
                                    : () => _fetchPayrollData(page: _payrollPage - 1),
                                child: const Text('Previous'),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('Page $_payrollPage of $_payrollTotalPages'),
                              ),
                              TextButton(
                                onPressed: _payrollPage >= _payrollTotalPages
                                    ? null
                                    : () => _fetchPayrollData(page: _payrollPage + 1),
                                child: const Text('Next'),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => context.go('/main/bulk-transfer'),
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('Initiate Bulk Transfer'),
                          ),
                        ),
                      ],
                    ),
                  ),
            if (_showConfigModal) _buildConfigModal(),
            if (_showEmployeeDetailModal) _buildEmployeeDetailModal(),
            if (_showAdjustmentModal) _buildAdjustmentModal(),
            if (_showEditEmployeeModal) _buildEditEmployeeModal(),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigModal() {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
          onDismiss: () => setState(() => _showConfigModal = false),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: AppTheme.colors.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Payroll Config',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _showConfigModal = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        const Text('Salary Interval', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ['daily', 'weekly', 'monthly', 'yearly', 'custom'].map((interval) {
                            final isSelected = _salaryInterval == interval;
                            return GestureDetector(
                              onTap: () => setState(() => _salaryInterval = interval),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primary : AppTheme.colors.surface,
                                  border: Border.all(color: isSelected ? AppColors.primary : AppTheme.colors.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  interval[0].toUpperCase() + interval.substring(1),
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : AppTheme.colors.text,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        if (_salaryInterval == 'custom') ...[
                          const SizedBox(height: 24),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _selectPayrollCustomDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Custom Payroll Date',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(Icons.calendar_today_outlined),
                              ),
                              child: Text(_salaryCustomDate.isEmpty ? 'Select date' : _salaryCustomDate),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _handleUpdateConfig,
                            child: const Text('Save Config'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeDetailModal() {
    final emp = _selectedEmployee;
    if (emp == null) return const SizedBox.shrink();

    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
          onDismiss: () => setState(() => _showEmployeeDetailModal = false),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: AppTheme.colors.background,
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
                        emp.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                            onPressed: () {
                              setState(() => _showEmployeeDetailModal = false);
                              _openEditEmployeeModal(emp);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _showEmployeeDetailModal = false),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.colors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.colors.border),
                          ),
                          child: Column(
                            children: [
                              _buildDetailRow('Salary', _formatAmount((emp.salary is num) ? (emp.salary as num).toDouble() : 0.0)),
                              const SizedBox(height: 12),
                              _buildDetailRow('Bonuses', _formatAmount((emp.bonusesTotal ?? 0).toDouble())),
                              const SizedBox(height: 12),
                              _buildDetailRow('Deductions', _formatAmount((emp.deductionsTotal ?? 0).toDouble())),
                              const SizedBox(height: 12),
                              Divider(color: AppTheme.colors.border),
                              const SizedBox(height: 12),
                              _buildDetailRow('Net Pay', _formatAmount(emp.netSalary), isPrimary: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Adjustments',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                              onPressed: () {
                                _adjAmountController.text = _adjAmount;
                                _adjReasonController.text = _adjReason;
                                setState(() => _showAdjustmentModal = true);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_adjustments.isEmpty)
                          const Center(child: Text('No adjustments yet', style: TextStyle(color: Colors.grey)))
                        else
                          ..._adjustments.map((adj) {
                            final isBonus = adj['type'] == 'bonus';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.colors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.colors.border),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isBonus ? 'Bonus' : 'Deduction',
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          adj['reason'] ?? '',
                                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '${isBonus ? '+' : '-'}${adj['currency'] ?? 'NGN'} ${adj['amount']}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isBonus ? Colors.green : AppColors.error,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                                        onPressed: () => _handleDeleteAdjustment(adj['id']),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isPrimary = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isPrimary ? FontWeight.bold : FontWeight.w600,
            color: isPrimary ? AppColors.primary : AppTheme.colors.text,
          ),
        ),
      ],
    );
  }

  Widget _buildAdjustmentModal() {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
          onDismiss: () => setState(() => _showAdjustmentModal = false),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.85,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: AppTheme.colors.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add Adjustment',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _showAdjustmentModal = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        const Text('Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _adjType = 'bonus'),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _adjType == 'bonus' ? AppColors.primary : AppTheme.colors.surface,
                                    border: Border.all(
                                      color: _adjType == 'bonus' ? AppColors.primary : AppTheme.colors.border,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_circle_outline,
                                        color: _adjType == 'bonus' ? Colors.white : Colors.green,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Bonus',
                                        style: TextStyle(
                                          color: _adjType == 'bonus' ? Colors.white : AppTheme.colors.text,
                                          fontWeight: _adjType == 'bonus' ? FontWeight.w600 : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _adjType = 'deduction'),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _adjType == 'deduction' ? AppColors.primary : AppTheme.colors.surface,
                                    border: Border.all(
                                      color: _adjType == 'deduction' ? AppColors.primary : AppTheme.colors.border,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.remove_circle_outline,
                                        color: _adjType == 'deduction' ? Colors.white : AppColors.error,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Deduction',
                                        style: TextStyle(
                                          color: _adjType == 'deduction' ? Colors.white : AppTheme.colors.text,
                                          fontWeight: _adjType == 'deduction' ? FontWeight.w600 : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text('Currency', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: ['NGN', 'USD'].map((currency) {
                            final isSelected = _adjCurrency == currency;
                            return GestureDetector(
                              onTap: () => setState(() => _adjCurrency = currency),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primary : AppTheme.colors.surface,
                                  border: Border.all(color: isSelected ? AppColors.primary : AppTheme.colors.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  currency,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : AppTheme.colors.text,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            prefixText: 'Amount ',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (val) => setState(() => _adjAmount = val),
                          controller: _adjAmountController,
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Reason',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                          onChanged: (val) => setState(() => _adjReason = val),
                          controller: _adjReasonController,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _handleAddAdjustment,
                            child: const Text('Add Adjustment'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditEmployeeModal() {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
          onDismiss: () => setState(() => _showEditEmployeeModal = false),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: AppTheme.colors.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Edit Payroll Details',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _showEditEmployeeModal = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Salary',
                            prefixText: 'NGN ',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (val) => setState(() => _editEmployeeData['salary'] = val),
                          controller: _editSalaryController,
                        ),
                        const SizedBox(height: 24),
                        const Text('Salary Currency', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ['NGN', 'USD'].map((currency) {
                            final isSelected = _editEmployeeData['salary_currency'] == currency;
                            return GestureDetector(
                              onTap: () => setState(() => _editEmployeeData['salary_currency'] = currency),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primary : AppTheme.colors.surface,
                                  border: Border.all(color: isSelected ? AppColors.primary : AppTheme.colors.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  currency,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : AppTheme.colors.text,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Bank Code',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) => setState(() => _editEmployeeData['bank_code'] = val),
                          controller: _editBankCodeController,
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Bank Account Number',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (val) => setState(() => _editEmployeeData['bank_account_number'] = val),
                          controller: _editBankAccountController,
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Account Name',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) => setState(() => _editEmployeeData['account_name'] = val),
                          controller: _editAccountNameController,
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Contract Start Date (YYYY-MM-DD)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) => setState(() => _editEmployeeData['contract_start_date'] = val),
                          controller: _editContractStartController,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _handleUpdateEmployee,
                            child: const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: SizedBox.shrink(),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.primary),
          onPressed: () => setState(() => _showConfigModal = true),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payroll Summary', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_employees.length}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const Text('Employees', style: TextStyle(color: Color(0xFF93c5fd), fontSize: 12)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_formatAmount(_totalNetPay),
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const Text('Total Net Pay', style: TextStyle(color: Color(0xFF93c5fd), fontSize: 12)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: Text('Employees', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: _clearPayrollFilters,
                icon: const Icon(Icons.refresh_outlined, size: 18),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildPayrollFilters(),
        const SizedBox(height: 12),
        if (_employees.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No employees found', style: TextStyle(fontSize: 14, color: Colors.grey)),
          )
        else
          ..._employees.map((emp) {
            return InkWell(
              onTap: () => _openEmployeeDetail(emp),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.colors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(emp.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(emp.role, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatAmount(emp.netSalary),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                        const Text('Net Pay', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPayrollFilters() {
    final colors = AppTheme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name or email',
              prefixIcon: const Icon(Icons.search_outlined),
              suffixIcon: _payrollSearch.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_outlined),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _payrollSearch = '');
                        _fetchPayrollData();
                      },
                    ),
            ),
            onSubmitted: (value) {
              setState(() => _payrollSearch = value);
              _fetchPayrollData();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _roleFilter.isEmpty ? 'all' : _roleFilter,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Roles')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(value: 'employee', child: Text('Employee')),
                    DropdownMenuItem(value: 'member', child: Text('Member')),
                  ],
                  onChanged: (value) {
                    setState(() => _roleFilter = value == 'all' ? '' : (value ?? ''));
                    _fetchPayrollData();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectPayrollStartDate,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(_startDate.isEmpty ? 'Start Date' : _startDate),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectPayrollEndDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_endDate.isEmpty ? 'End Date' : _endDate),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _payrollSearch = _searchController.text.trim());
                    _fetchPayrollData();
                  },
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('Apply Filters'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}
