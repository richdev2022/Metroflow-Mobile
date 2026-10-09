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
import '../services/app_update_service.dart';
import '../services/api.dart';
import '../utils/kyc_gate.dart';
import '../widgets/app_tour.dart';
import '../widgets/avatar_with_initials.dart';
import '../widgets/maintenance_gate.dart' show AnnouncementBanner;
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
      // In-app update prompt on app start / session restore (the login flow
      // triggers its own check 2s after landing; AppUpdateService de-dupes
      // per session and respects dismissed optional releases). Delayed so
      // initial dashboard loads and the tour never compete with it.
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (mounted) AppUpdateService.instance.checkAndPrompt(source: 'startup');
      });
    });
  }

  // Ensures the tour prompt fires once per MainScreen lifetime.
  bool _tourPrompted = false;

  Future<void> _onItemTapped(int index) async {
    if ((index == 5 || index == 6) && !await _canAccessFinanceFeature()) {
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

  Future<bool> _canAccessFinanceFeature() => KycGate.canUseFinance(context);

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
                      icon: Icons.shield_outlined,
                      title: 'Roles & Permissions',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/team-roles');
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
                    _DrawerTile(
                      icon: Icons.video_call_outlined,
                      title: 'Calls',
                      colors: colors,
                      onTap: () async {
                        _onItemTapped(4);
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
                        if (!await _canAccessFinanceFeature()) return;
                        if (!context.mounted) return;
                        context.push('/main/transfers');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.link_outlined,
                      title: 'Payment Links',
                      colors: colors,
                      onTap: () async {
                        if (!await _canAccessFinanceFeature()) return;
                        if (!context.mounted) return;
                        context.push('/main/payment-links');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.receipt_long_outlined,
                      title: 'Invoices',
                      colors: colors,
                      onTap: () async {
                        if (!await _canAccessFinanceFeature()) return;
                        if (!context.mounted) return;
                        context.push('/main/invoices');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.storefront_outlined,
                      title: 'Store',
                      colors: colors,
                      onTap: () async {
                        if (!await _canAccessFinanceFeature()) return;
                        if (!context.mounted) return;
                        context.push('/main/store');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.autorenew_outlined,
                      title: 'Subscriptions',
                      colors: colors,
                      onTap: () async {
                        if (!await _canAccessFinanceFeature()) return;
                        if (!context.mounted) return;
                        context.push('/main/subscriptions');
                      },
                    ),
                    const _DrawerSectionLabel('MetricAi'),
                    _DrawerTile(
                      icon: Icons.smart_toy_outlined,
                      title: 'MetricAi Chat',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/metric-ai');
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.auto_awesome_outlined,
                      title: 'AI Credits',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/ai-credits');
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
                    _DrawerTile(
                      icon: Icons.settings_outlined,
                      title: 'Settings',
                      colors: colors,
                      onTap: () async {
                        context.push('/main/settings');
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
                      icon: Icons.swap_horizontal_circle_outlined,
                      title: 'Switch workspace',
                      colors: colors,
                      closeOnTap: false,
                      onTap: () async => _showWorkspaceSwitcherSheet(),
                    ),
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
      body: Column(
        children: [
          // Web parity (AnnouncementTicker): slim dismissible strip fed by
          // the public /app-config announcement — hidden when empty.
          const AnnouncementBanner(),
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
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

  /// "More" overflow sheet — the full toolbox, GROUPED so 20+ destinations
  /// stay scannable instead of one confusing flat grid:
  ///   Work & Team · Money · Get Paid · MetricAi · App
  /// Groups follow the same taxonomy as the navigation drawer and the web
  /// sidebar so the mental model is identical across platforms. Wallet and
  /// Payroll still go through the KYC gate. Scrollable (max ~85% height)
  /// because every destination earns a slot here.
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
        final sheetHeight = MediaQuery.of(sheetContext).size.height;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: sheetHeight * 0.85),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: colors.borderVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 2),
                    child: Text(
                      'All features',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // ---------- Work & Team ----------
                  const _MoreSectionLabel('Work & Team'),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
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
                        icon: Icons.view_kanban_outlined,
                        label: 'Board',
                        colors: colors,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          context.go('/main/board');
                        },
                      ),
                      _MoreTile(
                        icon: Icons.calendar_month_outlined,
                        label: 'Calendar',
                        colors: colors,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          context.push('/main/calendar');
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
                        icon: Icons.lightbulb_outline,
                        label: 'Ideas',
                        colors: colors,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          context.push('/main/ideas');
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
                        icon: Icons.leaderboard_outlined,
                        label: 'Rankings',
                        colors: colors,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          context.push('/main/ranking');
                        },
                      ),
                    ],
                  ),

                  // ---------- Money ----------
                  const _MoreSectionLabel('Money'),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    childAspectRatio: 0.92,
                    children: [
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
                        icon: Icons.swap_horiz_outlined,
                        label: 'Transfers',
                        colors: colors,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          if (!await _canAccessFinanceFeature()) return;
                          if (!mounted) return;
                          context.push('/main/transfers');
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
                    ],
                  ),

                  // ---------- Get Paid ----------
                  const _MoreSectionLabel('Get Paid'),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    childAspectRatio: 0.92,
                    children: [
                      _MoreTile(
                        icon: Icons.link_outlined,
                        label: 'Pay Links',
                        colors: colors,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          if (!await _canAccessFinanceFeature()) return;
                          if (!mounted) return;
                          context.push('/main/payment-links');
                        },
                      ),
                      _MoreTile(
                        icon: Icons.receipt_long_outlined,
                        label: 'Invoices',
                        colors: colors,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          if (!await _canAccessFinanceFeature()) return;
                          if (!mounted) return;
                          context.push('/main/invoices');
                        },
                      ),
                      _MoreTile(
                        icon: Icons.storefront_outlined,
                        label: 'Store',
                        colors: colors,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          if (!await _canAccessFinanceFeature()) return;
                          if (!mounted) return;
                          context.push('/main/store');
                        },
                      ),
                      _MoreTile(
                        icon: Icons.autorenew_outlined,
                        label: 'Subscriptions',
                        colors: colors,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          if (!await _canAccessFinanceFeature()) return;
                          if (!mounted) return;
                          context.push('/main/subscriptions');
                        },
                      ),
                    ],
                  ),

                  // ---------- MetricAi ----------
                  const _MoreSectionLabel('MetricAi'),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    childAspectRatio: 0.92,
                    children: [
                      _MoreTile(
                        icon: Icons.smart_toy_outlined,
                        label: 'MetricAi',
                        colors: colors,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          context.push('/main/metric-ai');
                        },
                      ),
                      _MoreTile(
                        icon: Icons.auto_awesome_outlined,
                        label: 'AI Credits',
                        colors: colors,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          context.push('/main/ai-credits');
                        },
                      ),
                    ],
                  ),

                  // ---------- App ----------
                  const _MoreSectionLabel('App'),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    childAspectRatio: 0.92,
                    children: [
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
                        icon: Icons.receipt_long_outlined,
                        label: 'Activity Logs',
                        colors: colors,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          context.push('/main/activity-logs');
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
            ),
          ),
        );
      },
    );
  }

  /// WORKSPACE SWITCHER — opens the sheet listing every other workspace the
  /// signed-in (verified) email belongs to. A successful switch updates
  /// authProvider.businessId; the MaterialApp key in main.dart includes it,
  /// so the whole UI remounts with the new workspace's data automatically.
  void _showWorkspaceSwitcherSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const _WorkspaceSwitchSheet(),
    );
  }
}

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

/// Bottom sheet for multi-workspace switching. Loads GET /auth/workspaces,
/// lists the OTHER memberships (the current one is checked and disabled),
/// and swaps the session via authProvider.switchWorkspace on tap.
class _WorkspaceSwitchSheet extends ConsumerStatefulWidget {
  const _WorkspaceSwitchSheet();

  @override
  ConsumerState<_WorkspaceSwitchSheet> createState() =>
      _WorkspaceSwitchSheetState();
}

class _WorkspaceSwitchSheetState extends ConsumerState<_WorkspaceSwitchSheet> {
  List<Map<String, dynamic>>? _workspaces;
  String? _error;
  String? _switchingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await ApiService().listWorkspaces();
      final data = response.data;
      final raw = (data['data']?['workspaces'] ?? data['workspaces']) as List?;
      if (!mounted) return;
      setState(() {
        _workspaces = raw
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load your workspaces');
    }
  }

  Future<void> _switch(Map<String, dynamic> w) async {
    final businessId = (w['businessId'] ?? '').toString();
    final businessName = (w['businessName'] ?? 'workspace').toString();
    if (businessId.isEmpty || _switchingId != null) return;
    setState(() => _switchingId = businessId);
    try {
      await ref
          .read(authProvider.notifier)
          .switchWorkspace(businessId: businessId, businessName: businessName);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switched to $businessName')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _switchingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                e.toString().replaceFirst('Exception: ', '').isEmpty
                    ? 'Workspace switch failed'
                    : e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horizontal_circle_outlined,
                    size: 20, color: colors.text),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your workspaces',
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: colors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(_error!,
                      style: TextStyle(
                          color: colors.textSecondary, fontSize: 13)),
                ),
              )
            else if (_workspaces == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _workspaces!.length,
                  itemBuilder: (context, i) {
                    final w = _workspaces![i];
                    final isCurrent = w['isCurrent'] == true;
                    final businessId = (w['businessId'] ?? '').toString();
                    final busy = _switchingId == businessId;
                    return ListTile(
                      enabled: !isCurrent && _switchingId == null,
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: colors.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          ((w['businessName'] ?? 'W').toString().isNotEmpty
                                  ? (w['businessName'] as String)[0]
                                  : 'W')
                              .toUpperCase(),
                          style: TextStyle(
                            color: colors.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      title: Text(
                        (w['businessName'] ?? 'Workspace').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        isCurrent
                            ? 'Current workspace'
                            : '${(w['role'] ?? 'member').toString() == 'admin' ? 'Admin' : (w['role'] ?? 'member').toString() == 'owner' ? 'Owner' : 'Member'} · ${w['workspaceCode'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12),
                      ),
                      trailing: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : isCurrent
                              ? Icon(Icons.check_circle,
                                  color: Colors.green, size: 20)
                              : Icon(Icons.chevron_right,
                                  color: colors.textSecondary, size: 20),
                      onTap: () => _switch(w),
                    );
                  },
                ),
              ),
          ],
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

/// Section label used inside the "More" bottom sheet — same treatment as
/// the drawer's `_DrawerSectionLabel` so both surfaces read identically.
class _MoreSectionLabel extends StatelessWidget {
  final String label;
  const _MoreSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 4),
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
