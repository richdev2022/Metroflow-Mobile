import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

class KycInitiateScreen extends ConsumerStatefulWidget {
  const KycInitiateScreen({super.key});

  @override
  ConsumerState<KycInitiateScreen> createState() => _KycInitiateScreenState();
}

class _KycInitiateScreenState extends ConsumerState<KycInitiateScreen> {
  String? _type;
  final _numberController = TextEditingController();
  bool _isLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    final queryType = GoRouterState.of(context).uri.queryParameters['type'];
    if (_type == null) {
      final extraType = extra is Map<String, dynamic> ? extra['type'] as String? : null;
      _type = (queryType ?? extraType ?? 'bvn').toLowerCase() == 'nin' ? 'nin' : 'bvn';
      setState(() {});
    }
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  String get _title => '${(_type ?? 'bvn').toUpperCase()} Verification';
  String get _subtitle => _type == 'bvn'
      ? 'Please enter your 11-digit Bank Verification Number to verify your identity.'
      : 'Please enter your 11-digit National Identification Number to verify your identity.';

  Future<void> _handleSubmit() async {
    final type = _type ?? 'bvn';
    final number = _numberController.text.replaceAll(RegExp(r'\D'), '');
    if (number.length != 11) {
      AppToast.show('Please enter a valid 11-digit ${type == 'bvn' ? 'BVN' : 'NIN'}');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      await api.initiateKyc(type, number);
      if (mounted) {
        context.go('/kyc-otp?type=$type', extra: {
          'type': type,
          'number': number,
        });
      }
    } catch (e) {
      debugPrint('KYC initiate error: $e');
      AppToast.show(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = _type ?? 'bvn';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/kyc-prompt'),
              ),
              const SizedBox(height: 32),
              Text(_title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              Text(_subtitle, style: const TextStyle(fontSize: 16, color: Colors.grey, height: 1.5)),
              const SizedBox(height: 40),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.colors.border, width: 1.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _numberController,
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                  decoration: InputDecoration(
                    hintText: type == 'bvn' ? 'Enter 11-digit BVN' : 'Enter 11-digit NIN',
                    hintStyle: TextStyle(color: AppTheme.colors.textSecondary),
                    prefixIcon: Icon(Icons.description_outlined, color: AppTheme.colors.textSecondary),
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 1),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Send Verification Code',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
