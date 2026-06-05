import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/kyc_provider.dart';
import '../theme/app_theme.dart';

class KycPromptScreen extends ConsumerStatefulWidget {
  const KycPromptScreen({super.key});

  @override
  ConsumerState<KycPromptScreen> createState() => _KycPromptScreenState();
}

class _KycPromptScreenState extends ConsumerState<KycPromptScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(kycProvider.notifier).fetchKycStatus());
  }

  @override
  Widget build(BuildContext context) {
    final kycState = ref.watch(kycProvider);
    final colors = AppTheme.colors;
    final bvnVerified = kycState.status?.user.bvnStatus == 'verified';
    final ninVerified = kycState.status?.user.ninStatus == 'verified';

    if (kycState.isLoading && kycState.status == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: colors.text),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/main');
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Identity Verification',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  bvnVerified || ninVerified
                      ? 'Verify your remaining identity document to upgrade to Tier 2.'
                      : 'Complete KYC verification to access your wallet and all features.',
                  style: TextStyle(fontSize: 16, color: colors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 40),
                _buildOptionCard(
                  context: context,
                  title: 'Verify with BVN',
                  subtitle: 'Bank Verification Number',
                  isVerified: bvnVerified,
                  onTap: () => context.go('/kyc-initiate?type=bvn'),
                ),
                const SizedBox(height: 16),
                _buildOptionCard(
                  context: context,
                  title: 'Verify with NIN',
                  subtitle: 'National Identification Number',
                  isVerified: ninVerified,
                  onTap: () => context.go('/kyc-initiate?type=nin'),
                ),
                const SizedBox(height: 40),
                if (bvnVerified && ninVerified)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [colors.primary, AppColors.primaryLight],
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: () => context.go('/main'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        'Continue to Home',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool isVerified,
    required VoidCallback onTap,
  }) {
    final colors = AppTheme.colors;

    return InkWell(
      onTap: isVerified ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isVerified ? AppColors.successBg : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isVerified ? colors.success : colors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isVerified ? colors.textSecondary : colors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 14, color: colors.textSecondary)),
                ],
              ),
            ),
            Icon(
              isVerified ? Icons.check_circle : Icons.chevron_right,
              color: isVerified ? colors.success : colors.textSecondary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
