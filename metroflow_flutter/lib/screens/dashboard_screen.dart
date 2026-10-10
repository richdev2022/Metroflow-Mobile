import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/task.dart';
import '../providers/auth_provider.dart';
import '../providers/user_profile_provider.dart';
import '../utils/app_timezone.dart';
import '../utils/kyc_gate.dart';
import '../widgets/app_tour.dart';
import '../widgets/transaction_limits_card.dart';
import '../widgets/avatar_with_initials.dart';
import '../widgets/modern_ui.dart';

/// Home — the whole business suite at a glance.
///
/// v3 layout: the previous "lean" revision was 100% task-centric, which hid
/// the platform's other pillars after Storefront + Recurring Billing shipped.
/// This revision stays scannable while surfacing every pillar:
///   1. Compact hero — greeting, task chips + a wallet balance strip
///      (tap = Wallet tab, Fund pill = top-up).
///   2. Quick actions — a work + money mix (task, meeting, chat, invoice,
///      payment link, product).
///   3. "Get Paid" hub — the four revenue surfaces (Payment Links, Invoices,
///      Storefront, Subscriptions) with live counts.
///   4. Money row — move-money operations (Transfers, Payroll, Fund).
///   5. My Tasks preview + overdue banner (unchanged).
///
/// Suite stats load best-effort AFTER the shell renders — each fetch fails
/// silently into an em dash so the page never blocks or errors on them.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<dynamic> _allTasks = [];
  bool _isLoading = true;

  // "Get Paid" hub counters — null means "still loading / unavailable".
  int? _linkCount;
  int? _invoiceCount;
  int? _productCount;
  int? _planCount;

  // Wallet balance strip — the primary wallet shown in the hero.
  Map<String, dynamic>? _primaryWallet;
  String _walletLabel = 'Wallet balance';
  // Which wallet the hero card is showing — the Fund CTA MUST fund THIS
  // wallet, not the router default ('user'), or business admins fund their
  // personal wallet from the Business overview card.
  String _primaryWalletType = 'user';

  // Business logo (businesses.logo_url) — shown in the hero avatar slot when
  // the workspace has one (uploaded from the SSO Complete-Profile screen or
  // Settings). Falls back to the personal avatar.
  String? _businessLogoUrl;

  // Business-KYC status (GET /business-kyc/status, unwrapped `data` map):
  // drives the transaction-limit banner (pending verification / Non-Registered
  // limits / hidden once verified). Best-effort — null means "unknown".
  Map<String, dynamic>? _businessKycStatus;

  // Anchors for the guided app tour (lib/widgets/app_tour.dart) — the tour
  // spotlights these regions on first launch.
  final GlobalKey _tourHeroKey = GlobalKey(debugLabel: 'tour-hero');
  final GlobalKey _tourQuickActionsKey = GlobalKey(debugLabel: 'tour-quick-actions');
  final GlobalKey _tourTasksKey = GlobalKey(debugLabel: 'tour-tasks');

  @override
  void initState() {
    super.initState();
    AppTourAnchors.register('dashboard-hero', _tourHeroKey);
    AppTourAnchors.register('dashboard-quick-actions', _tourQuickActionsKey);
    AppTourAnchors.register('dashboard-tasks', _tourTasksKey);
    _fetchData();
    _fetchSuiteStats();
    _fetchBusinessKycStatus();
    // Warm the shared user profile (name/avatar) from the local cache and,
    // best-effort, from the server — used by the greeting + avatar chip.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(userProfileProvider.notifier).hydrate();
      ref.read(userProfileProvider.notifier).refreshFromServer();
    });
  }

  Future<void> _fetchData([bool showLoader = true]) async {
    if (showLoader) {
      setState(() => _isLoading = true);
    }
    try {
      final api = ApiService();

      // Fetch ALL tasks without filters, we'll aggregate locally.
      final tasksResponse =
          await api.getTasks(params: <String, dynamic>{'limit': '10000'});

      if (mounted) {
        setState(() {
          if (tasksResponse.data != null &&
              tasksResponse.data['success'] == true) {
            _allTasks = tasksResponse.data['data']['tasks'] ?? [];
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch dashboard data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Best-effort loaders for the "Get Paid" hub counters + wallet balance.
  /// Every block is independently guarded — a failing surface just keeps its
  /// em dash instead of breaking the home page.
  Future<void> _fetchSuiteStats() async {
    final api = ApiService();

    // Business logo — uploaded via the SSO Complete-Profile screen or
    // Settings; rendered in the hero so the workspace identity is visible
    // the moment the user lands on the dashboard.
    try {
      final s = await api.getSettings();
      final data = s.data;
      if (mounted && data is Map && data['settings'] is Map) {
        final settings = Map<String, dynamic>.from(data['settings'] as Map);
        final logo = (settings['logo_url'] ?? settings['logoUrl'] ?? '')
            .toString();
        if (logo.isNotEmpty) {
          setState(() {
            _businessLogoUrl = ApiService.resolveMediaUrl(logo);
          });
        }
      }
    } catch (_) {}

    try {
      final r = await api.getPaymentLinks();
      final links = r.data?['links'];
      if (mounted && links is List) setState(() => _linkCount = links.length);
    } catch (_) {}

    try {
      final r = await api.getInvoices();
      final invoices = r.data?['invoices'];
      if (mounted && invoices is List) {
        setState(() => _invoiceCount = invoices.length);
      }
    } catch (_) {}

    try {
      final r = await api.getStoreProducts();
      final products = r.data?['products'];
      if (mounted && products is List) {
        setState(() => _productCount = products.length);
      }
    } catch (_) {}

    try {
      final r = await api.getRecurringPlans();
      final plans = r.data?['plans'];
      if (mounted && plans is List) setState(() => _planCount = plans.length);
    } catch (_) {}

    try {
      final r = await api.getWallet();
      final data = r.data;
      if (mounted && data is Map) {
        final canManage = data['canManageBusinessWallet'] == true;
        final business = data['business_wallet'] is Map
            ? Map<String, dynamic>.from(data['business_wallet'] as Map)
            : null;
        final personal = data['user_wallet'] is Map
            ? Map<String, dynamic>.from(data['user_wallet'] as Map)
            : null;
        if (!mounted) return;
        setState(() {
          if (canManage && business != null) {
            // Business-first: this is the business suite.
            _primaryWallet = business;
            _walletLabel = 'Business wallet';
            _primaryWalletType = 'business';
          } else if (personal != null) {
            _primaryWallet = personal;
            _walletLabel = 'Wallet balance';
            _primaryWalletType = 'user';
          } else if (business != null) {
            _primaryWallet = business;
            _walletLabel = 'Business wallet';
            _primaryWalletType = 'business';
          }
        });
      }
    } catch (_) {}
  }

  /// Best-effort business-KYC (registration category + transaction limits)
  /// fetch for the _TransactionLimitBanner. Errors are swallowed — the
  /// banner is informational and must never break the dashboard.
  Future<void> _fetchBusinessKycStatus() async {
    try {
      final status = await ApiService().getBusinessKycStatus();
      if (mounted) setState(() => _businessKycStatus = status);
    } catch (_) {}
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Friendly display name for the greeting — the user's NAME, never the
  /// email. authProvider sometimes stores the email as a fallback, so a
  /// name-like string is derived from the email prefix in that case.
  String _displayName(AuthState authState, UserProfile profile) {
    final fromAuth = (authState.userName ?? '').trim();
    final candidate = fromAuth.isNotEmpty ? fromAuth : profile.name.trim();
    if (candidate.isEmpty) return 'there';
    if (candidate.contains('@')) {
      final prefix = candidate.split('@').first;
      final cleaned = prefix.replaceAll(RegExp(r'[._\-+0-9]+'), ' ').trim();
      if (cleaned.isEmpty) return 'there';
      return cleaned
          .split(RegExp(r'\s+'))
          .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
          .join(' ');
    }
    return candidate;
  }

  bool _isTaskOverdue(dynamic task) {
    // If API provides isOverdue, use that
    if (task['isOverdue'] == true) return true;

    // Otherwise calculate from due date
    final dueDateStr = task['dueDate'] as String? ?? task['endDate'] as String?;
    if (dueDateStr == null) return false;

    try {
      final dueDate = DateTime.parse(dueDateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return dueDate.isBefore(today) && task['status'] != 'completed';
    } catch (e) {
      return false;
    }
  }

  String _taskDateLabel(dynamic task) {
    final dueDateStr = task['dueDate'] as String? ?? task['endDate'] as String? ?? '';
    if (dueDateStr.isEmpty) return 'No due date';
    try {
      return AppTimezone.instance.formatDateShort(DateTime.parse(dueDateStr));
    } catch (e) {
      return dueDateStr;
    }
  }


  int _completedThisWeekCount() {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return _allTasks.where((task) {
      if (task['status'] != 'completed') return false;
      final dateStr = task['updatedAt'] as String? ?? task['endDate'] as String? ?? task['dueDate'] as String? ?? '';
      if (dateStr.isEmpty) return false;
      try {
        return DateTime.parse(dateStr).isAfter(weekAgo);
      } catch (e) {
        return false;
      }
    }).length;
  }

  Color _statusColorFor(ThemeColors colors, dynamic task) {
    if (_isTaskOverdue(task)) return colors.error;
    switch (task['status'] as String?) {
      case 'completed':
        return colors.success;
      case 'in_progress':
        return colors.warning;
      default:
        return colors.primary;
    }
  }

  void _openTask(dynamic task) {
    try {
      context.go(
        '/main/task-detail',
        extra: Task.fromJson(Map<String, dynamic>.from(task)),
      );
    } catch (e) {
      debugPrint('Failed to open task: $e');
    }
  }

  /// KYC-gated navigation for every finance surface on the home page (Fund
  /// pill, money row, quick actions, "Get Paid" hub). Mirrors MainScreen's
  /// gate: Tier-1 KYC (BVN OR NIN) required — a fresh, unverified account
  /// is routed to /kyc-prompt instead of the destination.
  Future<void> _pushFinance(String route, {Map<String, dynamic>? extra}) async {
    if (!await KycGate.canUseFinance(context)) return;
    if (!mounted) return;
    context.push(route, extra: extra);
  }

  String _walletBalanceLabel() {
    final w = _primaryWallet;
    if (w == null) return '—';
    final currency = (w['currency']?.toString() ?? 'NGN').toUpperCase();
    final balance = double.tryParse(w['balance']?.toString() ?? '0') ?? 0.0;
    final symbol = currency == 'USD'
        ? r'$'
        : (currency == 'EUR'
            ? '€'
            : (currency == 'GBP' ? '£' : '₦'));
    return '$symbol${balance.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (_isLoading) {
      return const SafeArea(child: _DashboardSkeleton());
    }

    final totalTasks = _allTasks.length;
    final completedTasks = _allTasks.where((t) => t['status'] == 'completed').length;
    final openTasksCount = totalTasks - completedTasks;
    final overdueTasks = _allTasks.where(_isTaskOverdue).toList();

    final openTasks = _allTasks.where((t) => t['status'] != 'completed').toList()
      ..sort((a, b) {
        final aDate = a['dueDate'] as String? ?? a['endDate'] as String? ?? '';
        final bDate = b['dueDate'] as String? ?? b['endDate'] as String? ?? '';
        if (aDate.isEmpty && bDate.isEmpty) return 0;
        if (aDate.isEmpty) return 1;
        if (bDate.isEmpty) return -1;
        try {
          return DateTime.parse(aDate).compareTo(DateTime.parse(bDate));
        } catch (e) {
          return 0;
        }
      });

    final authState = ref.watch(authProvider);
    final profile = ref.watch(userProfileProvider);
    final displayName = _displayName(authState, profile);
    final firstName = displayName.split(' ').first;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await _fetchData(false);
          await _fetchSuiteStats();
          await _fetchBusinessKycStatus();
        },
        color: colors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- Compact hero (greeting + stats + wallet) ----------
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _buildCompactHero(
                  colors,
                  firstName,
                  profile,
                  openTasksCount,
                  _completedThisWeekCount(),
                  overdueTasks.length,
                ),
              ),
              const SizedBox(height: 22),

              // ---------- Business KYC transaction-limit banner ----------
              if (_TransactionLimitBanner.shouldShow(_businessKycStatus)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: _TransactionLimitBanner(
                    status: _businessKycStatus!,
                    colors: colors,
                    // Re-fetch the status when the upgrade screen pops so a
                    // fresh "pending review" banner replaces the limit one.
                    onUpgrade: () async {
                      await context.push('/business-kyc-upgrade');
                      if (mounted) _fetchBusinessKycStatus();
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ---------- Web-parity inflow/outflow limits card ----------
              // ALWAYS visible (registered or not) so the tier's funding and
              // transfer limits + daily head-room are one glance away — the
              // old banner only spoke to non-registered accounts.
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: TransactionLimitsCard(),
              ),
              const SizedBox(height: 12),

              // ---------- Quick actions ----------
              _buildQuickActions(colors),
              const SizedBox(height: 22),

              // ---------- "Get Paid" hub (revenue surfaces) ----------
              _buildGetPaidHub(colors),
              const SizedBox(height: 20),

              // ---------- Money row (move money) ----------
              _buildMoneyRow(colors),
              const SizedBox(height: 22),

              // ---------- My Tasks preview ----------
              Padding(
                key: _tourTasksKey,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionKicker(
                      label: 'My Tasks',
                      subtitle: '$openTasksCount open of $totalTasks total',
                      actionLabel: 'View all',
                      onAction: () => context.go('/main?tab=1'),
                      actionIcon: Icons.arrow_forward_rounded,
                    ),
                    const SizedBox(height: 10),
                    if (openTasks.isEmpty)
                      ModernCard(
                        margin: EdgeInsets.zero,
                        child: EmptyState(
                          icon: Icons.task_alt_outlined,
                          title: 'You are all caught up!',
                          subtitle:
                              'No open tasks right now. Create a task to get things moving.',
                          actionLabel: 'New Task',
                          onAction: () => context.go('/main/create-task'),
                        ),
                      )
                    else
                      ...openTasks.take(3).map((task) {
                        return _MyTaskCard(
                          task: task,
                          colors: colors,
                          dateLabel: _taskDateLabel(task),
                          isOverdue: _isTaskOverdue(task),
                          statusColor: _statusColorFor(colors, task),
                          onTap: () => _openTask(task),
                        );
                      }),
                  ],
                ),
              ),

              // ---------- Overdue banner ----------
              if (overdueTasks.isNotEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _OverdueBanner(
                    count: overdueTasks.length,
                    colors: colors,
                    onTap: () => context.go('/main?tab=1'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Compact hero: greeting + avatar + today's date + three tappable task
  /// stat chips + a wallet balance strip. The balance row taps into the
  /// Wallet tab (KYC-gated via MainScreen) and the Fund pill jumps straight
  /// to the top-up screen.
  Widget _buildCompactHero(
    ThemeColors colors,
    String firstName,
    UserProfile profile,
    int openCount,
    int doneThisWeek,
    int overdueCount,
  ) {
    return Container(
      key: _tourHeroKey,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1E3A8A),
            Color(0xFF2563EB),
            Color(0xFF7C3AED),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${_greeting()}, $firstName!',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55),
                    width: 1.6,
                  ),
                ),
                child: AvatarWithInitials(
                  name: firstName == 'there' ? 'Me' : firstName,
                  // Prefer the business logo when the workspace has one —
                  // the uploaded logo must be VISIBLE on the dashboard.
                  imageUrl: _businessLogoUrl ?? profile.avatarUrl,
                  radius: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AppTimezone.instance.formatDateFull(DateTime.now()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 16),
          // Wallet balance strip — glanceable money anchor for the whole app.
          Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => context.go('/main?tab=5'), // Wallet tab (KYC-gated)
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _walletLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Colors.white.withValues(alpha: 0.75),
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  _walletBalanceLabel(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Fund pill — the highest-frequency money action, one tap away.
              // Passes the hero card's wallet type: the button sits on the
              // Business wallet overview, so it funds the BUSINESS wallet.
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => _pushFinance('/main/fund-wallet',
                      extra: {'walletType': _primaryWalletType}),
                  borderRadius: BorderRadius.circular(14),
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.add_rounded,
                            size: 16, color: Color(0xFF2563EB)),
                        SizedBox(width: 3),
                        Text(
                          'Fund',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Three tappable task stat chips — the whole row is one flexible
          // unit, so it never overflows on narrow screens.
          Row(
            children: [
              Expanded(
                child: _HeroStatChip(
                  icon: Icons.assignment_outlined,
                  value: '$openCount',
                  label: 'Open',
                  onTap: () => context.go('/main?tab=1'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStatChip(
                  icon: Icons.task_alt_rounded,
                  value: '$doneThisWeek',
                  label: 'Done · 7d',
                  onTap: () => context.go('/main?tab=1'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStatChip(
                  icon: Icons.error_outline,
                  value: '$overdueCount',
                  label: 'Overdue',
                  alert: overdueCount > 0,
                  onTap: () => context.go('/main?tab=1'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(ThemeColors colors) {
    final actions = <_QuickActionData>[
      _QuickActionData(
        icon: Icons.add_task_outlined,
        label: 'New Task',
        tint: colors.primary,
        onTap: () => context.go('/main/create-task'),
      ),
      _QuickActionData(
        icon: Icons.video_call_outlined,
        label: 'Start Meeting',
        tint: colors.success,
        // tab=3 → Meetings (index 3 = MeetingsScreen on the bottom nav)
        onTap: () => context.go('/main?tab=3'),
      ),
      _QuickActionData(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'New Chat',
        tint: const Color(0xFF7C3AED),
        // tab=2 → Chat (index 2 = ChatScreen on the bottom nav)
        onTap: () => context.go('/main?tab=2'),
      ),
      _QuickActionData(
        icon: Icons.smart_toy_outlined,
        label: 'MetricAi',
        tint: const Color(0xFF4F46E5),
        onTap: () => context.push('/main/metric-ai'),
      ),
      _QuickActionData(
        icon: Icons.receipt_long_outlined,
        label: 'New Invoice',
        tint: const Color(0xFF059669),
        onTap: () => _pushFinance('/main/invoices'),
      ),
      _QuickActionData(
        icon: Icons.link_rounded,
        label: 'Payment Link',
        tint: const Color(0xFF2563EB),
        onTap: () => _pushFinance('/main/payment-links'),
      ),
      _QuickActionData(
        icon: Icons.storefront_outlined,
        label: 'Add Product',
        tint: const Color(0xFFEA580C),
        onTap: () => _pushFinance('/main/store'),
      ),
      // 8th tile: completes the 4x2 grid (was 7 items -> ragged gap on row 2).
      _QuickActionData(
        icon: Icons.call_outlined,
        label: 'Calls',
        tint: const Color(0xFF0891B2),
        onTap: () => context.push('/main/calls'),
      ),
    ];

    return Padding(
      key: _tourQuickActionsKey,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionKicker(label: 'Quick Actions'),
          const SizedBox(height: 10),
          // 2-row grid instead of the old horizontally-scrolling strip: every
          // action is visible at a glance and the row wraps evenly on small
          // screens (4 per row, MetricAi slotted alongside the essentials).
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.8,
            children: [
              for (final action in actions) _QuickAction(data: action, colors: colors),
            ],
          ),
        ],
      ),
    );
  }

  /// "Get Paid" hub — the four revenue surfaces, 2×2, each with a live
  /// counter (best-effort; em dash while loading / on failure). The section
  /// header links to Pricing so plan limits are one tap away.
  Widget _buildGetPaidHub(ThemeColors colors) {
    final cards = <_GetPaidData>[
      _GetPaidData(
        icon: Icons.link_rounded,
        title: 'Payment Links',
        tagline: 'Sell with a shareable link',
        tint: const Color(0xFF2563EB),
        count: _linkCount,
        countNoun: 'link',
        onTap: () => _pushFinance('/main/payment-links'),
      ),
      _GetPaidData(
        icon: Icons.receipt_long_rounded,
        title: 'Invoices',
        tagline: 'Bill clients smartly',
        tint: const Color(0xFF059669),
        count: _invoiceCount,
        countNoun: 'invoice',
        onTap: () => _pushFinance('/main/invoices'),
      ),
      _GetPaidData(
        icon: Icons.storefront_rounded,
        title: 'Storefront',
        tagline: 'Your online store',
        tint: const Color(0xFFEA580C),
        count: _productCount,
        countNoun: 'product',
        onTap: () => _pushFinance('/main/store'),
      ),
      _GetPaidData(
        icon: Icons.autorenew_rounded,
        title: 'Subscriptions',
        tagline: 'Recurring revenue',
        tint: const Color(0xFF7C3AED),
        count: _planCount,
        countNoun: 'plan',
        onTap: () => _pushFinance('/main/subscriptions'),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionKicker(
            label: 'Get Paid',
            subtitle: 'Every way your customers pay you',
            actionLabel: 'Pricing',
            actionIcon: Icons.local_offer_outlined,
            onAction: () => context.push('/main/fees'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _GetPaidCard(data: cards[0], colors: colors)),
              const SizedBox(width: 10),
              Expanded(child: _GetPaidCard(data: cards[1], colors: colors)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _GetPaidCard(data: cards[2], colors: colors)),
              const SizedBox(width: 10),
              Expanded(child: _GetPaidCard(data: cards[3], colors: colors)),
            ],
          ),
        ],
      ),
    );
  }

  /// Money row — the move-money operations that don't fit "Get Paid":
  /// Transfers (send to banks), Payroll (salaries; KYC-gated) and Fund
  /// Wallet (top-up). Wallet itself lives behind the hero balance strip.
  Widget _buildMoneyRow(ThemeColors colors) {
    final tiles = <_MoneyTileData>[
      _MoneyTileData(
        icon: Icons.swap_horiz_rounded,
        label: 'Transfers',
        tint: const Color(0xFF0891B2),
        onTap: () => _pushFinance('/main/transfers'),
      ),
      _MoneyTileData(
        icon: Icons.payments_rounded,
        label: 'Payroll',
        tint: const Color(0xFF4F46E5),
        // tab=6 → Payroll inside MainScreen (KYC gate re-enters post-frame)
        onTap: () => context.go('/main?tab=6'),
      ),
      _MoneyTileData(
        icon: Icons.savings_outlined,
        label: 'Fund Wallet',
        tint: colors.success,
        // Same wallet as the hero overview card (business-first there).
        onTap: () => _pushFinance('/main/fund-wallet',
            extra: {'walletType': _primaryWalletType}),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _MoneyTile(data: tiles[i], colors: colors)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

/// Small translucent stat chip used inside the compact hero.
class _HeroStatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool alert;
  final VoidCallback onTap;

  const _HeroStatChip({
    required this.icon,
    required this.value,
    required this.label,
    this.alert = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: alert ? Colors.red.shade200 : Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$value  $label',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: alert ? Colors.red.shade100 : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ShimmerBox(
              width: double.infinity,
              height: 208,
              radius: 24,
            ),
          ),
          SizedBox(height: 22),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ShimmerBox(width: 84, height: 96, radius: 18),
                SizedBox(width: 12),
                ShimmerBox(width: 84, height: 96, radius: 18),
                SizedBox(width: 12),
                ShimmerBox(width: 84, height: 96, radius: 18),
              ],
            ),
          ),
          SizedBox(height: 24),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: ShimmerBox(height: 118, radius: 18)),
                    SizedBox(width: 10),
                    Expanded(child: ShimmerBox(height: 118, radius: 18)),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: ShimmerBox(height: 118, radius: 18)),
                    SizedBox(width: 10),
                    Expanded(child: ShimmerBox(height: 118, radius: 18)),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 24),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SkeletonCard(),
                SkeletonCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionData {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  const _QuickActionData({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });
}

class _QuickAction extends StatelessWidget {
  final _QuickActionData data;
  final ThemeColors colors;

  const _QuickAction({required this.data, required this.colors});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: data.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.text.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TintedCircleIcon(
              icon: data.icon,
              tint: data.tint,
              size: 38,
              iconSize: 19,
            ),
            const SizedBox(height: 8),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
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

/// Data for one "Get Paid" hub card.
class _GetPaidData {
  final IconData icon;
  final String title;
  final String tagline;
  final Color tint;
  final int? count;
  final String countNoun;
  final VoidCallback onTap;

  const _GetPaidData({
    required this.icon,
    required this.title,
    required this.tagline,
    required this.tint,
    required this.count,
    required this.countNoun,
    required this.onTap,
  });
}

/// Revenue-surface card in the "Get Paid" hub.
class _GetPaidCard extends StatelessWidget {
  final _GetPaidData data;
  final ThemeColors colors;

  const _GetPaidCard({required this.data, required this.colors});

  String get _countLabel {
    final c = data.count;
    if (c == null) return '—';
    return '$c ${data.countNoun}${c == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TintedCircleIcon(
                    icon: data.icon,
                    tint: data.tint,
                    size: 34,
                    iconSize: 18,
                  ),
                  const Spacer(),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _countLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                data.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.tagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data for one money-row tile.
class _MoneyTileData {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  const _MoneyTileData({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });
}

/// Move-money tile in the money row (Transfers / Payroll / Fund).
class _MoneyTile extends StatelessWidget {
  final _MoneyTileData data;
  final ThemeColors colors;

  const _MoneyTile({required this.data, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              TintedCircleIcon(
                icon: data.icon,
                tint: data.tint,
                size: 34,
                iconSize: 18,
              ),
              const SizedBox(height: 6),
              Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyTaskCard extends StatelessWidget {
  final dynamic task;
  final ThemeColors colors;
  final String dateLabel;
  final bool isOverdue;
  final Color statusColor;
  final VoidCallback onTap;

  const _MyTaskCard({
    required this.task,
    required this.colors,
    required this.dateLabel,
    required this.isOverdue,
    required this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = task['status'] == 'completed';
    final epic = task['epic'] as String?;

    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Row(
        children: [
          // Priority / status color bar
          Container(
            width: 5,
            height: 68,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                bottomLeft: Radius.circular(20),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  // Checkbox-style leading icon
                  Icon(
                    isCompleted
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked_rounded,
                    color: isCompleted ? colors.success : colors.borderVariant,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task['title'] as String? ?? 'Untitled task',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (epic != null && epic.isNotEmpty)
                              ModernBadge(
                                label: epic,
                                color: colors.primary,
                              ),
                            ModernBadge(
                              label: isOverdue
                                  ? 'Overdue · $dateLabel'
                                  : 'Due $dateLabel',
                              color: isOverdue
                                  ? colors.error
                                  : colors.textSecondary,
                              icon: Icons.schedule,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverdueBanner extends StatelessWidget {
  final int count;
  final ThemeColors colors;
  final VoidCallback onTap;

  const _OverdueBanner({
    required this.count,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colors.error.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            TintedCircleIcon(
              icon: Icons.warning_amber_rounded,
              tint: colors.error,
              size: 40,
              iconSize: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$count overdue ${count == 1 ? 'task' : 'tasks'} — review them before the day gets away.',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                  height: 1.35,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.error,
            ),
          ],
        ),
      ),
    );
  }
}

/// Home-page banner for business-KYC limits (amber variant of _OverdueBanner's
/// container style). Three states, driven by the GET /business-kyc/status
/// `data` map:
///   1. Verified business (business.isRegistered == true) → renders NOTHING.
///   2. latestSubmission.status == 'pending' → info banner (under review).
///   3. registrationCategory == 'non_registered' → current single-transaction
///      limit + upgrade CTA → /business-kyc-upgrade.
/// Nulls are parsed defensively everywhere — a malformed payload just hides
/// the banner.
class _TransactionLimitBanner extends StatelessWidget {
  final Map<String, dynamic> status;
  final ThemeColors colors;
  final VoidCallback onUpgrade;

  const _TransactionLimitBanner({
    required this.status,
    required this.colors,
    required this.onUpgrade,
  });

  /// Whether the banner has something to say for this status payload.
  static bool shouldShow(Map<String, dynamic>? status) {
    if (status == null || status.isEmpty) return false;
    final business = status['business'];
    if (business is Map && business['isRegistered'] == true) return false;
    final submission = status['latestSubmission'];
    if (submission is Map && submission['status'] == 'pending') return true;
    if (business is Map &&
        business['registrationCategory']?.toString() == 'non_registered') {
      return true;
    }
    return false;
  }

  static String _currencySymbol(String? currency) {
    switch ((currency ?? 'NGN').toUpperCase()) {
      case 'NGN':
        return '₦';
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return '$currency ';
    }
  }

  /// 50000 -> "50,000" (#,## thousands separators, decimals dropped).
  static String _formatAmount(dynamic value) {
    final n = double.tryParse(value?.toString() ?? '') ?? 0;
    return n
        .round()
        .toString()
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    final submission = status['latestSubmission'];

    // PENDING REVIEW — informational, no CTA (the upgrade screen shows the
    // same pending card if opened from elsewhere).
    if (submission is Map && submission['status'] == 'pending') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.warning.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            TintedCircleIcon(
              icon: Icons.hourglass_top_rounded,
              tint: colors.warning,
              size: 40,
              iconSize: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Business verification under review — we'll notify you once approved",
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // NON-REGISTERED LIMITS — current limit + upgrade CTA.
    final limits = status['limits'] is Map
        ? Map<String, dynamic>.from(status['limits'] as Map)
        : null;
    final innerLimits = limits != null && limits['limits'] is Map
        ? Map<String, dynamic>.from(limits['limits'] as Map)
        : null;
    final registeredLimits =
        limits != null && limits['registeredLimits'] is Map
            ? Map<String, dynamic>.from(limits['registeredLimits'] as Map)
            : null;
    final symbol = _currencySymbol(limits?['currency']?.toString());
    final singleLimit = _formatAmount(innerLimits?['singleTransactionLimit']);
    final registeredSingle =
        _formatAmount(registeredLimits?['singleTransactionLimit']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.warning.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TintedCircleIcon(
                icon: Icons.speed_rounded,
                tint: colors.warning,
                size: 40,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Transaction limit: $symbol$singleLimit per transaction',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "You're on Non-Registered Business limits. Upgrade to Registered (Verified) to unlock up to $symbol$registeredSingle.",
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onUpgrade,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Upgrade',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded,
                        size: 14, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionKicker extends StatelessWidget {
  final String label;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  const _SectionKicker({
    required this.label,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: colors.textSecondary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: colors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (actionIcon != null) ...[
                  const SizedBox(width: 2),
                  Icon(actionIcon, size: 16),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
