import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/badge_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/api.dart';
import '../utils/app_toast.dart';
import '../widgets/app_tour.dart';
import '../widgets/avatar_with_initials.dart';
import 'dashboard_screen.dart';
import 'tasks_screen.dart';
import 'wallet_screen.dart';
import 'payroll_screen.dart';
import 'meetings_screen.dart';
import 'chat_screen.dart';
import 'calls_screen.dart';

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

  // NOTE on ordering: the bottom-nav shows [Home, Tasks, Chat, Meetings, More]
  // — so index 2 MUST be the ChatScreen and index 3 the MeetingsScreen.
  // These two were historically swapped (nav said "Chat" but opened
  // Meetings) which is also why the dashboard quick actions
  // (Start Meeting → tab=3, New Chat → tab=2) looked dead/mixed up.
  final List<Widget> _pages = const [
    DashboardScreen(),
    TasksScreen(),
    ChatScreen(),
    MeetingsScreen(),
    CallsScreen(),
    WalletScreen(),
    PayrollScreen(),
  ];

  final List<String> _pageTitles = const [
    'Home',
    'Tasks',
    'Chat',
    'Meetings',
    'Calls',
    'Wallet',
    'Payroll',
  ];

  @override
  void initState() {
    super.initState();
    // Bottom nav has 5 visible tabs (0-3 + "More"). Legacy deep links that
    // point at Wallet (5) / Payroll (6) start on Home and re-enter through
    // the KYC gate post-frame, exactly as before.
    _selectedIndex = widget.initialIndex >= 0 && widget.initialIndex <= 3
        ? widget.initialIndex
        : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (widget.initialIndex == 5 || widget.initialIndex == 6)) {
        _onItemTapped(widget.initialIndex);
      }
      // Warm the shared user profile so the drawer identity block shows the
      // real name/email even before the dashboard finishes loading.
      if (mounted) {
        ref.read(userProfileProvider.notifier).hydrate();
      }
      // First-run guided tour — anchored to dashboard regions registered by
      // DashboardScreen; skipped silently when already seen.
      if (mounted && !_tourPrompted) {
        _tourPrompted = true;
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (mounted) maybeShowAppTour(context);
        });
      }
    });
  }

  // Ensures the tour prompt fires once per MainScreen lifetime.
  bool _tourPrompted = false;

  Future<void> _onItemTapped(int index) async {
    if ((index == 5 || index == 6) && !await _canAccessWalletOrPayroll()) {
      return;
    }
    // Viewing the Meetings tab clears its "new invite" dot
    if (index == 3) {
      ref.read(meetingsUnreadProvider.notifier).clear();
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  /// Bottom-nav icon with an optional unread badge (Chat) or a small dot
  /// (new meeting invites). Kept compact (no pill background) so five tabs
  /// fit comfortably on narrow screens.
  Widget _navIcon({
    required IconData icon,
    required int index,
    required ThemeColors colors,
    int badgeCount = 0,
    bool dot = false,
  }) {
    final selected = _selectedIndex == index;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: Icon(
            icon,
            size: 24,
            color: selected ? colors.primary : colors.textSecondary,
          ),
        ),
        if (badgeCount > 0 || dot)
          Positioned(
            top: -2,
            right: -2,
            child: badgeCount > 0
                ? Container(
                    constraints: const BoxConstraints(minWidth: 17),
                    height: 17,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.error,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: colors.surface, width: 1.5),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  )
                : Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 1.5),
                    ),
                  ),
          ),
      ],
    );
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
          Consumer(
            builder: (context, ref, child) {
              final notificationsState = ref.watch(notificationsProvider);
              return Stack(
                children: [
                  IconButton(
                    tooltip: 'Notifications',
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                    onPressed: () => context.push('/main/notifications'),
                  ),
                  if (notificationsState.unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          notificationsState.unreadCount > 99 ? '99+' : notificationsState.unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (_selectedIndex == 0)
            IconButton(
              tooltip: 'Profile',
              icon: const Icon(Icons.person_outline, color: Colors.white),
              onPressed: () => context.push('/main/profile'),
            ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: colors.background,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ---- Brand + identity header (fixed brand gradient) ----
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF1E3A8A),
                      Color(0xFF2563EB),
                      Color(0xFF7C3AED),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: [0.0, 0.55, 1.0],
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                child: Consumer(builder: (context, ref, _) {
                  final authState = ref.watch(authProvider);
                  final profile = ref.watch(userProfileProvider);
                  final nameCandidate = (profile.name.trim().isNotEmpty
                          ? profile.name.trim()
                          : (authState.userName ?? '').trim())
                      .split(' ')
                      .first;
                  final email = profile.email.trim();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.9),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              // Official BLUE shield mark on white — exactly
                              // the brand treatment used on the website.
                              'assets/images/logo-mark.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Metricorex',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close menu',
                            icon: Icon(
                              Icons.close_rounded,
                              color: Colors.white.withValues(alpha: 0.85),
                              size: 20,
                            ),
                            onPressed: () =>
                                Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.55),
                                width: 1.5,
                              ),
                            ),
                            child: AvatarWithInitials(
                              name: nameCandidate.isEmpty
                                  ? 'Me'
                                  : nameCandidate,
                              imageUrl:
                                  profile.avatarUrl ?? authState.avatarUrl,
                              radius: 19,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nameCandidate.isEmpty
                                      ? 'Welcome'
                                      : nameCandidate,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (email.isNotEmpty)
                                  Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.78),
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }),
              ),
              // ---- Navigation body ----
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                  children: [
                    const _DrawerSectionLabel('Workspace'),
                    _DrawerTile(
                      icon: Icons.view_kanban_outlined,
                      title: 'Board',
                      colors: colors,
                      onTap: () async {
                        context.go('/main/board');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.calendar_month_outlined,
                      title: 'Calendar',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/calendar');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.lightbulb_outline,
                      title: 'Ideas',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/ideas');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.archive_outlined,
                      title: 'Backlog',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/backlog');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.people_outline,
                      title: 'Team',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/team');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.leaderboard_outlined,
                      title: 'Rankings',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/ranking');
                      },
                    ),
                    const _DrawerSectionLabel('Finance'),
                    _DrawerTile(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Wallet',
                      colors: colors,
                      onTap: () async {
                        await _onItemTapped(5);
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.payments_outlined,
                      title: 'Payroll',
                      colors: colors,
                      onTap: () async {
                        await _onItemTapped(6);
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.swap_horiz_outlined,
                      title: 'Transfers',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/transfers');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.link_outlined,
                      title: 'Payment Links',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/payment-links');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.receipt_long_outlined,
                      title: 'Invoices',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/invoices');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.storefront_outlined,
                      title: 'Store',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/store');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.autorenew_outlined,
                      title: 'Subscriptions',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/subscriptions');
                      },
                    ),
                    const _DrawerSectionLabel('Account'),
                    _DrawerTile(
                      icon: Icons.person_outline,
                      title: 'Profile',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/profile');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.credit_card_outlined,
                      title: 'Subscription',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/subscription');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.auto_awesome_outlined,
                      title: 'MetricAi Credits',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/ai-credits');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.local_offer_outlined,
                      title: 'Pricing',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/fees');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.receipt_long_outlined,
                      title: 'Activity Logs',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/activity-logs');
                      },
                    ),
                    const SizedBox(height: 10),
                    // Theme toggle — themed row (works in light & dark).
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.border),
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            themeState.mode == ThemeMode.dark
                                ? Icons.dark_mode_outlined
                                : Icons.light_mode_outlined,
                            size: 19,
                            color: const Color(0xFF7C3AED),
                          ),
                        ),
                        title: Text(
                          'Dark Mode',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                        trailing: themeState.isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : Switch(
                                value: themeState.mode == ThemeMode.dark,
                                onChanged: (value) {
                                  ref.read(themeProvider.notifier).toggleTheme(
                                        value
                                            ? ThemeMode.dark
                                            : ThemeMode.light,
                                      );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _DrawerTile(
                      icon: Icons.logout_outlined,
                      title: 'Logout',
                      colors: colors,
                      danger: true,
                      closeOnTap: false,
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Logout'),
                            content: const Text(
                                'Are you sure you want to logout?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
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
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'Metricorex v1.0.0',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex > 3 ? 4 : _selectedIndex,
        onTap: (index) {
          if (index == 4) {
            _showMoreSheet();
          } else {
            _onItemTapped(index);
          }
        },
        backgroundColor: colors.surface,
        selectedItemColor: colors.primary,
        unselectedItemColor: colors.textSecondary,
        selectedFontSize: 11.5,
        unselectedFontSize: 11,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        items: [
          BottomNavigationBarItem(
            icon: _navIcon(icon: Icons.home_outlined, index: 0, colors: colors),
            activeIcon: _navIcon(icon: Icons.home_rounded, index: 0, colors: colors),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: _navIcon(icon: Icons.task_outlined, index: 1, colors: colors),
            activeIcon: _navIcon(icon: Icons.task_alt_rounded, index: 1, colors: colors),
            label: 'Tasks',
          ),
          BottomNavigationBarItem(
            icon: _navIcon(
              icon: Icons.chat_bubble_outline_rounded,
              index: 2,
              colors: colors,
              badgeCount: ref.watch(chatUnreadProvider),
            ),
            activeIcon: _navIcon(
              icon: Icons.chat_bubble_rounded,
              index: 2,
              colors: colors,
              badgeCount: ref.watch(chatUnreadProvider),
            ),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: _navIcon(
              icon: Icons.calendar_today_outlined,
              index: 3,
              colors: colors,
              dot: ref.watch(meetingsUnreadProvider) > 0,
            ),
            activeIcon: _navIcon(
              icon: Icons.calendar_month_rounded,
              index: 3,
              colors: colors,
              dot: ref.watch(meetingsUnreadProvider) > 0,
            ),
            label: 'Meetings',
          ),
          BottomNavigationBarItem(
            icon: _navIcon(
              icon: Icons.apps_rounded,
              index: 4,
              colors: colors,
            ),
            activeIcon: _navIcon(
              icon: Icons.apps_rounded,
              index: 4,
              colors: colors,
            ),
            label: 'More',
          ),
        ],
      ),
    );
  }

  /// "More" overflow sheet: everything that no longer earns a bottom-nav
  /// slot (Calls, Wallet, Payroll + routed destinations like Board, Team,
  /// Transfers…). Wallet/Payroll still go through the KYC gate.
  void _showMoreSheet() {
    final colors = AppTheme.colors;
    final themeState = ref.read(themeProvider);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: colors.borderVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                childAspectRatio: 0.92,
                children: [
                  _MoreTile(
                    icon: Icons.video_call_outlined,
                    label: 'Calls',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _onItemTapped(4);
                    },
                  ),
                  _MoreTile(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Wallet',
                    colors: colors,
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _onItemTapped(5);
                    },
                  ),
                  _MoreTile(
                    icon: Icons.payments_outlined,
                    label: 'Payroll',
                    colors: colors,
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _onItemTapped(6);
                    },
                  ),
                  _MoreTile(
                    icon: Icons.view_kanban_outlined,
                    label: 'Board',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.go('/main/board');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.people_outline,
                    label: 'Team',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/team');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.swap_horiz_outlined,
                    label: 'Transfers',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/transfers');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.lightbulb_outline,
                    label: 'Ideas',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/ideas');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.archive_outlined,
                    label: 'Backlog',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/backlog');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.leaderboard_outlined,
                    label: 'Rankings',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/ranking');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Activity Logs',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/activity-logs');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.credit_card_outlined,
                    label: 'Plan',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/subscription');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.local_offer_outlined,
                    label: 'Pricing',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/fees');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.person_outline,
                    label: 'Profile',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/profile');
                    },
                  ),
                  _MoreTile(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/settings');
                    },
                  ),
                  _MoreTile(
                    icon: themeState.mode == ThemeMode.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    label: themeState.mode == ThemeMode.dark
                        ? 'Light Mode'
                        : 'Dark Mode',
                    colors: colors,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref.read(themeProvider.notifier).toggleTheme(
                            themeState.mode == ThemeMode.dark
                                ? ThemeMode.light
                                : ThemeMode.dark,
                          );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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

/// Section label used inside the navigation drawer.
class _DrawerSectionLabel extends StatelessWidget {
  final String label;
  const _DrawerSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: colors.textSecondary.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

/// Navigation tile used inside the drawer: tinted icon container + label +
/// chevron, full-width tap target. Closes the drawer BEFORE running the
/// action so the destination never renders behind an open drawer.
class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final ThemeColors colors;
  final Future<void> Function() onTap;
  final bool danger;

  /// When false the drawer is NOT closed before [onTap] — used by actions
  /// that open their own dialog first (e.g. the logout confirmation) so the
  /// tap context stays mounted.
  final bool closeOnTap;

  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.colors,
    required this.onTap,
    this.danger = false,
    this.closeOnTap = true,
  });

  @override
  Widget build(BuildContext context) {
    final tint = danger ? colors.error : colors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            if (closeOnTap) {
              Navigator.of(context).pop(); // close the drawer first
            }
            await onTap();
          },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 19, color: tint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: danger ? FontWeight.w600 : FontWeight.w600,
                      color: danger ? colors.error : colors.text,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon tile used inside the "More" bottom sheet.
class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeColors colors;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 21, color: colors.primary),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
