import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';

class CreateBusinessWalletScreen extends StatefulWidget {
  const CreateBusinessWalletScreen({super.key});

  @override
  State<CreateBusinessWalletScreen> createState() => _CreateBusinessWalletScreenState();
}

class _CreateBusinessWalletScreenState extends State<CreateBusinessWalletScreen> {
  final _businessNameController = TextEditingController();
  final _gtbAccountController = TextEditingController();
  final _kycRefController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _businessNameController.dispose();
    _gtbAccountController.dispose();
    _kycRefController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    final businessName = _businessNameController.text.trim();
    final gtbAccount = _gtbAccountController.text.trim();
    final kycRef = _kycRefController.text.trim();

    if (businessName.isEmpty || gtbAccount.isEmpty) {
      Fluttertoast.showToast(msg: 'Please fill in all required fields');
      return;
    }
    if (gtbAccount.length != 10) {
      Fluttertoast.showToast(msg: 'Account number must be 10 digits');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final response = await api.createBusinessWallet(
        gtbAccount,
        businessName,
        kycReferenceId: kycRef.isEmpty ? null : kycRef,
      );
      if (response.statusCode == 200) {
        final data = response.data;
        Fluttertoast.showToast(
          msg: data['message'] ?? 'Business wallet created successfully',
        );
        if (mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/main');
          }
        }
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/main');
                  }
                },
                child: const Text('\u2190 Back', style: TextStyle(fontSize: 16, color: AppColors.primary)),
              ),
              const SizedBox(height: 24),
              const Text(
                'Create Business Wallet',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Your business KYC has been approved! Now set up your business wallet.',
                style: TextStyle(fontSize: 16, color: AppTheme.colors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _businessNameController,
                decoration: const InputDecoration(
                  labelText: 'Business Name',
                  hintText: 'My Company Limited',
                ),
              ),
              const SizedBox(height: 16),
              const Text('GTBank Account Number', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Text('For settlement and compliance purposes',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              TextField(
                controller: _gtbAccountController,
                keyboardType: TextInputType.number,
                maxLength: 10,
                decoration: const InputDecoration(
                  hintText: '0123456789',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _kycRefController,
                decoration: const InputDecoration(
                  labelText: 'KYC Reference ID (Optional)',
                  hintText: 'KYC Ref ID if provided',
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Create Business Wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
