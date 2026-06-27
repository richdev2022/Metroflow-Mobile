import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api.dart';
import '../utils/app_toast.dart';
import 'dashboard_screen.dart';
import 'tasks_screen.dart';
import 'wallet_screen.dart';
import 'payroll_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  late int _selectedIndex;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _checkingProtectedTab = false;

  final List<Widget> _pages = const [
    DashboardScreen(),
    TasksScreen(),
    WalletScreen(),
    PayrollScreen(),
  ];

  final List<String> _pageTitles = const [
    'Home',
    'Tasks',
    'Wallet',
    'Payroll',
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex == 2 || widget.initialIndex == 3 ? 0 : widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (_selectedIndex == 2 || _selectedIndex == 3)) {
        _onItemTapped(_selectedIndex);
      } else if (mounted && (widget.initialIndex == 2 || widget.initialIndex == 3)) {
        _onItemTapped(widget.initialIndex);
      }
    });
  }

  Future<void> _onItemTapped(int index) async {
    if ((index == 2 || index == 3) && !await _canAccessWalletOrPayroll()) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<bool> _canAccessWalletOrPayroll() async {
    if (_checkingProtectedTab) return false;
    setState(() => _checkingProtectedTab = true);
    try {
      final response = await ApiService().getKycStatus();
      if (!mounted) return false;
      final status = _KycGateStatus.fromResponse(response.data);

      if (!status.bvnVerified && !status.ninVerified) {
        context.go('/kyc-prompt');
        return false;
      }

      if (status.bvnVerified && status.ninVerified) return true;

      await _showMissingKycModal(status);
      return false;
    } catch (e) {
      AppToast.show('Unable to confirm KYC status. Please try again.');
      return false;
    } finally {
      if (mounted) setState(() => _checkingProtectedTab = false);
    }
  }

  Future<void> _showMissingKycModal(_KycGateStatus status) async {
    final missingType = status.bvnVerified ? 'nin' : 'bvn';
    final verifiedLabel = status.bvnVerified ? 'BVN' : 'NIN';
    final missingLabel = missingType.toUpperCase();
    final documentLabel = missingType == 'nin'
        ? 'National Identity Number (NIN)'
        : 'Bank Verification Number (BVN)';
    final controller = TextEditingController();
    var isSubmitting = false;

    String? submittedNumber;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final colors = AppTheme.colors;
          return AlertDialog(
            backgroundColor: colors.surface,
            title: const Text('Identity Verification Required'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Please verify your $missingLabel to continue.'),
                const SizedBox(height: 20),
                const Text('Document Type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: colors.surfaceVariant,
                    suffixIcon: const Icon(Icons.keyboard_arrow_down),
                  ),
                  child: Text(documentLabel),
                ),
                const SizedBox(height: 8),
                Text(
                  '$verifiedLabel verified. Please verify $missingLabel.',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                const SizedBox(height: 16),
                Text('$missingLabel Number', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Enter 11-digit $missingLabel',
                  ),
                ),
              ],
            ),
            actions: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton(
                    onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final number = controller.text.replaceAll(RegExp(r'\D'), '');
                            if (number.length != 11) {
                              AppToast.show('Please enter a valid 11-digit $missingLabel');
                              return;
                            }
                            setDialogState(() => isSubmitting = true);
                            try {
                              await ApiService().initiateKyc(missingType, number);
                              submittedNumber = number;
                              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                            } catch (e) {
                              debugPrint('Failed to initiate KYC: $e');
                            } finally {
                              if (dialogContext.mounted) setDialogState(() => isSubmitting = false);
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Verify Identity'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (!mounted || submittedNumber == null) return;
    context.go('/kyc-otp?type=$missingType', extra: {
      'type': missingType,
      'number': submittedNumber,
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final authNotifier = ref.read(authProvider.notifier);
    final colors = AppTheme.colors;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        title: Text(_pageTitles[_selectedIndex]),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              tooltip: 'Profile',
              icon: const Icon(Icons.person_outline, color: Colors.white),
              onPressed: () => context.push('/main/profile'),
            ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                top: 64,
                bottom: 24,
                left: 24,
                right: 24,
              ),
              decoration: BoxDecoration(
                color: colors.primary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/Logo-white.png',
                    height: 64,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Metricorex',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(Icons.dashboard_outlined),
                    title: const Text('Board'),
                    onTap: () {
                      context.go('/main/board');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Profile'),
                    onTap: () {
                      context.push('/main/profile');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.credit_card_outlined),
                    title: const Text('Subscription'),
                    onTap: () {
                      context.push('/main/subscription');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.local_offer_outlined),
                    title: const Text('Pricing'),
                    onTap: () {
                      context.push('/main/fees');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.lightbulb_outline),
                    title: const Text('Ideas'),
                    onTap: () {
                      context.push('/main/ideas');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: const Text('Backlog'),
                    onTap: () {
                      context.push('/main/backlog');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('Activity Logs'),
                    onTap: () {
                      context.push('/main/activity-logs');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.swap_horiz_outlined),
                    title: const Text('Transfers'),
                    onTap: () {
                      context.push('/main/transfers');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: const Text('Team'),
                    onTap: () {
                      context.push('/main/team');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.leaderboard_outlined),
                    title: const Text('Rankings'),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/main/ranking');
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(
                      themeState.mode == ThemeMode.dark
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                    ),
                    title: const Text('Dark Mode'),
                    trailing: themeState.isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Switch(
                            value: themeState.mode == ThemeMode.dark,
                            onChanged: (value) {
                              ref.read(themeProvider.notifier).toggleTheme(
                                value ? ThemeMode.dark : ThemeMode.light,
                              );
                            },
                          ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout_outlined, color: Colors.red),
                    title: const Text('Logout', style: TextStyle(color: Colors.red)),
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Logout'),
                          content: const Text('Are you sure you want to logout?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Logout'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await authNotifier.logout();
                        if (context.mounted) {
                          context.go('/login');
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) => _onItemTapped(index),
        backgroundColor: colors.surface,
        selectedItemColor: colors.primary,
        unselectedItemColor: colors.textSecondary,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        items: [
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: _selectedIndex == 0
                  ? BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: Icon(Icons.home_outlined, color: _selectedIndex == 0 ? Colors.white : null),
            ),
            activeIcon: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.home, color: Colors.white),
            ),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: _selectedIndex == 1
                  ? BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: Icon(Icons.list_outlined, color: _selectedIndex == 1 ? Colors.white : null),
            ),
            activeIcon: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.list, color: Colors.white),
            ),
            label: 'Tasks',
          ),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: _selectedIndex == 2
                  ? BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: Icon(Icons.account_balance_wallet_outlined, color: _selectedIndex == 2 ? Colors.white : null),
            ),
            activeIcon: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.account_balance_wallet, color: Colors.white),
            ),
            label: 'Wallet',
          ),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: _selectedIndex == 3
                  ? BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: Icon(Icons.payments_outlined, color: _selectedIndex == 3 ? Colors.white : null),
            ),
            activeIcon: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.payments, color: Colors.white),
            ),
            label: 'Payroll',
          ),
        ],
      ),
    );
  }
}

class _KycGateStatus {
  final bool bvnVerified;
  final bool ninVerified;

  const _KycGateStatus({required this.bvnVerified, required this.ninVerified});

  factory _KycGateStatus.fromResponse(dynamic data) {
    final root = data is Map<String, dynamic> ? data : <String, dynamic>{};
    final user = root['user'] is Map<String, dynamic> ? root['user'] as Map<String, dynamic> : null;
    return _KycGateStatus(
      bvnVerified: user?['bvnStatus'] == 'verified' ||
          user?['bvn_status'] == 'verified' ||
          root['bvn_verified'] == true,
      ninVerified: user?['ninStatus'] == 'verified' ||
          user?['nin_status'] == 'verified' ||
          root['nin_verified'] == true,
    );
  }
}
