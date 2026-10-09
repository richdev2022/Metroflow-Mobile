import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'models/transfer.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'services/api.dart';
import 'services/app_badge_service.dart';
import 'services/biometrics.dart';
import 'services/push_notification_service.dart';
import 'screens/permission_primer.dart';
import 'services/socket_service.dart';
import 'screens/meeting_deep_link_screen.dart';
import 'utils/app_feedback.dart';
import 'utils/app_timezone.dart';
import 'utils/call_deep_link.dart';
import 'utils/logger.dart';
import 'widgets/inapp_banner.dart';
import 'widgets/maintenance_gate.dart';
import 'widgets/metric_ai_fab.dart';
import 'providers/badge_provider.dart';
import 'providers/call_provider.dart';
import 'providers/notifications_provider.dart';
import 'screens/chat_detail_screen.dart';
import 'components/error_boundary.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/verify_otp_screen.dart';
import 'screens/verify_reset_otp_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/kyc_prompt_screen.dart';
import 'screens/profile_completion_screen.dart';
import 'screens/personal_profile_completion_screen.dart';
import 'screens/kyc_initiate_screen.dart';
import 'screens/kyc_otp_screen.dart';
import 'screens/business_kyc_screen.dart';
import 'screens/business_kyc_upgrade_screen.dart';

import 'screens/fund_wallet_screen.dart';
import 'screens/bulk_transfer_screen.dart';
import 'screens/single_transfer_screen.dart';
import 'screens/transfers_screen.dart';
import 'screens/transfer_detail_screen.dart';
import 'screens/transfer_success_screen.dart';
import 'screens/create_task_screen.dart';
import 'screens/task_detail_screen.dart';
import 'screens/ideas_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/idea_detail_screen.dart';
import 'screens/backlog_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/team_screen.dart';
import 'screens/team_roles_screen.dart';
import 'screens/ranking_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/transaction_detail_screen.dart';
import 'screens/bulk_create_tasks_screen.dart';
import 'models/payment_transaction.dart';
import 'screens/fees_screen.dart';
import 'screens/beneficiaries_screen.dart';
import 'screens/payment_links_screen.dart';
import 'screens/ai_credits_screen.dart';
import 'screens/invoices_screen.dart';
import 'screens/store_screen.dart';
import 'screens/recurring_screen.dart';
import 'screens/activity_logs_screen.dart';
import 'screens/board_screen.dart';
import 'screens/meetings_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/calls_screen.dart';
import 'screens/incoming_call_dialog.dart';
import 'screens/notifications_screen.dart';
import 'screens/metric_ai_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // RAM HYGIENE: Flutter's default image cache holds up to 1000 entries /
  // 100 MB of decoded bitmaps. On 2-4 GB devices that alone can push the
  // app into swap and get the process killed mid-use. Tighten both limits —
  // still comfortably large for chat media, avatars and product images.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20; // 48 MB
  PaintingBinding.instance.imageCache.maximumSize = 400;
  await dotenv.load(fileName: ".env");
  // Load the stored business timezone BEFORE the first frame renders so all
  // screens format dates consistently from the start.
  await AppTimezone.instance.load();
  // FCM background/terminated isolate handler — MUST be registered before
  // runApp. Safe without Firebase native config: assignment only, no platform
  // channel, and the handler itself is fully guarded.
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (_) {}
  runApp(const ProviderScope(child: MyApp()));
}

// Global key to access MyAppState - use dynamic since _MyAppState is private
final GlobalKey myAppKey = GlobalKey();

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  late final GoRouter _router;
  StreamSubscription<Uri>? _appLinksSub;

  /// metricorex:// deep links (the web meeting interstitial's "Open in the
  /// app" button fires metricorex://meetings/<code>). Also covers cold
  /// starts via getInitialLink — the app opens straight onto the meeting.
  void _setupAppLinks() {
    try {
      final appLinks = AppLinks();
      Future<void> handle(Uri uri) async {
        Logger.log('App link received: ' + uri.toString());
        final segments = List<String>.from(uri.pathSegments.where((s) => s.isNotEmpty));
        final ctx = navigatorKey.currentContext;
        if (ctx == null) return;
        // metricorex://meetings/<code> (also tolerate host forms)
        String? meetingCode;
        if (segments.length >= 2 && segments[0] == 'meetings') {
          meetingCode = segments[1];
        } else if (uri.host == 'meetings' && segments.isNotEmpty) {
          meetingCode = segments.first;
        }
        if (meetingCode != null && meetingCode.isNotEmpty) {
          await MeetingDeepLinkScreen.open(ctx, meetingCode);
          return;
        }
        // metricorex://calls/<code|uuid> — open the call room directly
        // (mirrors the web /join-call?call=<id>&auto=1 push tap path).
        String? callRef;
        if (segments.length >= 2 && segments[0] == 'calls') {
          callRef = segments[1];
        } else if (uri.host == 'calls' && segments.isNotEmpty) {
          callRef = segments.first;
        }
        if (callRef != null && callRef.isNotEmpty) {
          await CallDeepLinkHelper.openCallRoom(ctx, callRef);
          return;
        }
        // metricorex://transfers/<reference> — transfer history detail view.
        String? transferRef;
        if (segments.length >= 2 && segments[0] == 'transfers') {
          transferRef = segments[1];
        } else if (uri.host == 'transfers' && segments.isNotEmpty) {
          transferRef = segments.first;
        }
        if (transferRef != null && transferRef.isNotEmpty) {
          GoRouter.of(ctx).go('/main/transfers');
        }
      }

      appLinks.getInitialLink().then((uri) {
        if (uri != null) handle(uri);
      }).catchError((_) {});
      _appLinksSub = appLinks.uriLinkStream.listen(
        (uri) => handle(uri),
        onError: (Object e) => Logger.error('App links stream error: ' + e.toString()),
      );
    } catch (e) {
      Logger.error('App links setup failed: ' + e.toString());
    }
  }
  AppLifecycleState _appState = AppLifecycleState.resumed;
  String? _currentRoute;
  final _storage = StorageService();
  bool _isWebViewOpen = false; // New flag to track webview state
  DateTime? _appPausedAt; // Track when app went to background

  // Public method to set webview state
  void setWebViewOpen(bool isOpen) {
    setState(() {
      _isWebViewOpen = isOpen;
    });
  }

  // Global handler for `chat:new-message-notification` pushes: sound +
  // sliding banner + bottom-nav badge. Suppressed while the user is already
  // inside the conversation the message belongs to (ChatDetailScreen plays
  // its own arrival feedback there).
  void _setupGlobalChatNotifications() {
    final socketService = SocketService();
    socketService.onChatNewMessageNotification = (data) {
      try {
        if (data is! Map) return;
        final payload = Map<String, dynamic>.from(data);
        final conversationId = (payload['conversationId'] ?? payload['conversation_id'] ?? '').toString();

        // Inside the open conversation? The detail screen handles UX.
        if (conversationId.isNotEmpty &&
            conversationId == ChatDetailScreen.activeConversationId) {
          return;
        }

        final senderName = (payload['senderName'] ?? payload['sender_name'] ?? 'Someone').toString();
        final conversationName = (payload['conversationName'] ?? '').toString();
        final isGroup = payload['conversationType'] == 'group' ||
            (payload['conversationType'] == null && conversationName.isNotEmpty);
        final content = (payload['content'] ?? '').toString();
        final attachmentType = payload['attachmentType']?.toString();

        // Badge increment
        ref.read(chatUnreadProvider.notifier).increment();

        // Sound + haptic pop — fires for BACKGROUND messages too (the socket
        // stays connected while the app is paused, and audioplayers keeps
        // playing as long as the OS hasn't killed the process).
        AppFeedback.playMessageSound();

        // Sliding in-app banner — only renderable while RESUMED: while the
        // app is hidden the overlay can't attach, so skip it (sound + badge
        // above are the background alert).
        final isResumed =
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
        if (!isResumed) return;

        InAppBanner.show(
          title: isGroup && conversationName.isNotEmpty
              ? '$senderName · $conversationName'
              : senderName,
          message: content.isNotEmpty
              ? content
              : (attachmentType != null && attachmentType.startsWith('image/')
                  ? 'Sent a photo'
                  : 'Sent an attachment'),
          icon: Icons.chat_bubble_outline_rounded,
          accentColor: AppColors.success,
          onTap: () {
            final context = navigatorKey.currentContext;
            if (context != null) {
              GoRouter.of(context).go('/main/chat');
            }
          },
        );
      } catch (e) {
        Logger.error('chat:new-message-notification handler: $e');
      }
    };
  }

  /// FCM push wiring (WhatsApp-style ringing while the app is
  /// killed/backgrounded/locked + notification-tap deep links).
  ///
  /// - [PushNotificationService.initialize] is fully guarded: without the
  ///   Firebase native config it degrades to a silent no-op.
  /// - [incomingCallHook] feeds tapped incoming-call pushes into the same
  ///   provider state the socket `call:incoming` handler uses, so the global
  ///   IncomingCallDialog shows Accept/Decline exactly like an in-app ring.
  /// - [foregroundCallGuard] prevents a double ring when both the socket AND
  ///   FCM deliver the same incoming call while the app is open.
  void _setupPushNotifications() {
    PushNotificationService.instance.incomingCallHook = (data) {
      try {
        ref.read(callProvider.notifier).presentIncomingCall(data);
      } catch (e) {
        Logger.error('incomingCallHook failed: $e');
      }
    };
    PushNotificationService.instance.foregroundCallGuard = () {
      try {
        return ref.read(callProvider).isRinging;
      } catch (_) {
        return false;
      }
    };
    // The callId currently ringing via the in-app overlay: the foreground
    // incoming-call push uses it to IGNORE a server-retried duplicate push
    // for the SAME call (re-presenting reset the ring timer mid-ring).
    PushNotificationService.instance.currentRingingCallId = () {
      try {
        return ref.read(callProvider).call?.id;
      } catch (_) {
        return null;
      }
    };
    // A missed-call / call-ended push proves the call is gone — stop the
    // in-app ring and clear the Accept/Decline overlay.
    PushNotificationService.instance.dismissIncomingCallHook = () {
      try {
        ref.read(callProvider.notifier).clearIncomingCall();
      } catch (e) {
        Logger.error('dismissIncomingCallHook failed: $e');
      }
    };
    // A call-cancelled push (caller hung up while we were ringing) clears the
    // overlay only when THAT call is the one ringing.
    PushNotificationService.instance.callCancelledHook = (callId) {
      try {
        ref.read(callProvider.notifier).dismissIfCurrent(callId);
      } catch (e) {
        Logger.error('callCancelledHook failed: $e');
      }
    };
    // Initialize after auth bootstrap (authProvider.checkAuth kicks off in
    // its build); token registration happens post-login via the auth
    // listener below and inside the service itself.
    unawaited(PushNotificationService.instance.initialize());
    // Restore the persisted launcher-badge count (cold start).
    unawaited(AppBadgeService.instance.initialize());
  }

  /// Launcher badge = unread chats + unread notifications. Refreshed
  /// whenever either provider changes (see the listeners in build) and on
  /// app resume.
  void _syncLauncherBadge() {
    try {
      final chats = ref.read(chatUnreadProvider);
      final notifications = ref.read(notificationsProvider).unreadCount;
      unawaited(LauncherBadge.update(chats + notifications));
    } catch (e) {
      Logger.error('Launcher badge sync failed: $e');
    }
  }

  String _routeValue(GoRouterState state, String key) {
    final extra = state.extra;
    if (extra is Map) {
      final value = extra[key];
      if (value != null) return value.toString();
    }
    return state.uri.queryParameters[key] ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupGlobalChatNotifications();
    _setupPushNotifications();
    _setupAppLinks();

    _router = GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: '/',
      redirect: (context, state) async {
        final authState = ref.read(authProvider);
        final isAuthenticated = authState.isAuthenticated;
        final isLoading = authState.isLoading;
        final hasSeenOnboarding = authState.hasSeenOnboarding;

        if (isLoading) {
          return null; // Stay on splash
        }

        final path = state.uri.path;
        _currentRoute = path;
        // Keep the global route tracker in sync for globally-mounted
        // widgets (the draggable MetricAi bubble hides itself per-route).
        appCurrentRouteNotifier.value = path;

        if (isAuthenticated) {
          if (path.startsWith('/onboarding') ||
              path == '/login' ||
              path == '/register' ||
              path == '/verify-otp') {
            // NOTE: /forgot-password, /verify-reset-otp and /reset-password are
            // deliberately NOT bounced — an authenticated user may legitimately
            // start the email password-reset flow from Settings > Change
            // Password, and bouncing here also broke the back stack.
            // Check if we have a last route to navigate to
            final lastRoute = await _storage.getLastRoute();
            if (lastRoute != null && lastRoute.isNotEmpty && lastRoute != '/login') {
              await _storage.removeLastRoute(); // Clear it after using
              return lastRoute;
            }
            return '/main';
          }
          return null;
        } else {
          if (path == '/' || path == '/main' || path.startsWith('/main/')) {
            if (!hasSeenOnboarding) {
              return '/onboarding1';
            } else {
              return '/login';
            }
          }
          return null;
        }
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/verify-otp',
          builder: (context, state) => VerifyOtpScreen(
            email: (state.extra as String?) ?? state.uri.queryParameters['email'] ?? '',
          ),
        ),
        GoRoute(
          path: '/verify-reset-otp',
          builder: (context, state) => VerifyResetOtpScreen(
            email: state.extra is String
                ? state.extra as String
                : _routeValue(state, 'email'),
          ),
        ),
        GoRoute(
          path: '/reset-password',
          builder: (context, state) => ResetPasswordScreen(
            email: _routeValue(state, 'email'),
            otp: _routeValue(state, 'otp'),
          ),
        ),
        GoRoute(
          path: '/onboarding1',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/kyc-prompt',
          builder: (context, state) => const KycPromptScreen(),
        ),
        // SSO onboarding gate: Google sign-ups land here until the business
        // profile (name / industry / phone / logo) is complete.
        GoRoute(
          path: '/profile-complete',
          builder: (context, state) => const ProfileCompletionScreen(),
        ),
        // PERSONAL completion for invited team members (role-gated by the
        // backend's requiresProfileCompletion flag — admins never route here).
        GoRoute(
          path: '/profile-completion',
          builder: (context, state) => const PersonalProfileCompletionScreen(),
        ),
        GoRoute(
          path: '/kyc-initiate',
          builder: (context, state) => const KycInitiateScreen(),
        ),
        GoRoute(
          path: '/kyc-otp',
          builder: (context, state) => const KycOtpScreen(),
        ),
        // Business KYC upgrade (Non-Registered → Registered "Verified"):
        // pushed from the dashboard's transaction-limit banner.
        GoRoute(
          path: '/business-kyc-upgrade',
          builder: (context, state) => const BusinessKycUpgradeScreen(),
        ),
        GoRoute(
          path: '/main',
          builder: (context, state) {
            final index = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
            // Keyed by tab: navigating from inside the shell (e.g. a
            // dashboard quick action → /main?tab=3) rebuilds MainScreen with
            // the new initialIndex — without the key the State is reused and
            // the tab never switches (dead CTA).
            return MainScreen(key: ValueKey('main-tab-$index'), initialIndex: index);
          },
          routes: [
            GoRoute(
              path: 'business-kyc',
              builder: (context, state) => const BusinessKycScreen(),
            ),

            GoRoute(
              path: 'fund-wallet',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>?;
                final walletType = extra?['walletType'] as String? ?? 'user';
                return FundWalletScreen(walletType: walletType);
              },
            ),
            GoRoute(
              path: 'bulk-transfer',
              builder: (context, state) => const BulkTransferScreen(),
            ),
            GoRoute(
              name: 'single-transfer',
              path: 'single-transfer',
              builder: (context, state) {
                final extra = state.extra;
                final prefill =
                    extra is Map<String, dynamic> ? extra : null;
                return SingleTransferScreen(prefill: prefill);
              },
            ),
            GoRoute(
              path: 'create-task',
              builder: (context, state) => const CreateTaskScreen(),
            ),
            GoRoute(
              path: 'bulk-create-tasks',
              builder: (context, state) {
                final initialTasks = state.extra as List<BulkCreateTask>?;
                return BulkCreateTasksScreen(initialTasks: initialTasks);
              },
            ),
            GoRoute(
              path: 'task-detail',
              builder: (context, state) => const TaskDetailScreen(),
            ),
            GoRoute(
              path: 'ideas',
              builder: (context, state) => const IdeasScreen(),
            ),
            GoRoute(
              path: 'calendar',
              builder: (context, state) => const CalendarScreen(),
            ),
            GoRoute(
              path: 'idea-detail',
              builder: (context, state) => const IdeaDetailScreen(),
            ),
            GoRoute(
              path: 'backlog',
              builder: (context, state) => const BacklogScreen(),
            ),
            GoRoute(
              path: 'profile',
              builder: (context, state) => const ProfileScreen(),
            ),
            GoRoute(
              path: 'settings',
              builder: (context, state) => const SettingsScreen(),
            ),
            GoRoute(
              path: 'team',
              builder: (context, state) => const TeamScreen(),
            ),
            GoRoute(
              path: 'team-roles',
              builder: (context, state) => const TeamRolesScreen(),
            ),
            GoRoute(
              path: 'ranking',
              builder: (context, state) => const RankingScreen(),
            ),
            GoRoute(
              path: 'subscription',
              builder: (context, state) => const SubscriptionScreen(),
            ),
            GoRoute(
              path: 'board',
              builder: (context, state) => const BoardScreen(),
            ),
            GoRoute(
              path: 'fees',
              builder: (context, state) => const FeesScreen(),
            ),
            GoRoute(
              path: 'beneficiaries',
              builder: (context, state) => const BeneficiariesScreen(),
            ),
            GoRoute(
              path: 'payment-links',
              builder: (context, state) => const PaymentLinksScreen(),
            ),
            GoRoute(
              path: 'ai-credits',
              builder: (context, state) => const AiCreditsScreen(),
            ),
            GoRoute(
              path: 'invoices',
              builder: (context, state) => const InvoicesScreen(),
            ),
            GoRoute(
              path: 'store',
              builder: (context, state) => const StoreScreen(),
            ),
            GoRoute(
              path: 'subscriptions',
              builder: (context, state) => const RecurringScreen(),
            ),
            GoRoute(
              path: 'activity-logs',
              builder: (context, state) => const ActivityLogsScreen(),
            ),
            GoRoute(
              path: 'transfers',
              builder: (context, state) => const TransfersScreen(),
            ),
            GoRoute(
              path: 'transfer-detail',
              builder: (context, state) {
                final extra = state.extra;
                if (extra is! Transfer) return const TransfersScreen();
                return TransferDetailScreen(transfer: extra);
              },
            ),
            GoRoute(
              path: 'transfer-success',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>?;
                final bulkResponse = extra?['bulkResponse'] as BulkTransferResponse?;
                final singleResponse = extra?['singleResponse'] as SingleTransferResponse?;
                return TransferSuccessScreen(
                  bulkResponse: bulkResponse,
                  singleResponse: singleResponse,
                );
              },
            ),
            GoRoute(
              path: 'transaction-detail',
              builder: (context, state) {
                final extra = state.extra;
                if (extra is! PaymentTransaction) return const SubscriptionScreen();
                return TransactionDetailScreen(transaction: extra);
              },
            ),
            GoRoute(
              path: 'meetings',
              builder: (context, state) => const MeetingsScreen(),
            ),
            GoRoute(
              path: 'chat',
              builder: (context, state) => const ChatScreen(),
            ),
            GoRoute(
              path: 'metric-ai',
              builder: (context, state) => const MetricAiScreen(),
            ),
            GoRoute(
              path: 'calls',
              builder: (context, state) => const CallsScreen(),
            ),
            GoRoute(
              path: 'notifications',
              builder: (context, state) => const NotificationsScreen(),
            ),
          ],
        ),
      ],
    );

    // Set logout handler. Called on SESSION EXPIRY (api.dart's interceptor)
    // — an AUTOMATIC logout, so the FCM device registration is KEPT: after
    // the re-login push must keep working without waiting for a fresh
    // register. Explicit user logouts still unregister (default).
    setLogoutHandler(() {
      final authNotifier = ref.read(authProvider.notifier);
      authNotifier.logout(unregisterDevice: false);
      _router.go('/login');
    });
  }

  @override
  void dispose() {
    _appLinksSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final authNotifier = ref.read(authProvider.notifier);
    bool wasWebViewOpen = _isWebViewOpen; // Store before modifying

    // ---------------------------------------------------------------------
    // BACKGROUND RINGING CONTRACT:
    // Nothing here may disconnect the SocketService when the app is paused.
    // The Dart socket.io client keeps running while the process lives, so
    // `call:incoming` still arrives in the background and call_provider's
    // handler starts the looping ringtone + haptics (audioplayers keeps
    // playing while backgrounded). The only code allowed to disconnect the
    // socket is an explicit logout (auth_provider.logout) — see the 5-minute
    // idle logout below, which is a deliberate session end.
    //
    // NOTE: full background delivery (ringing after the OS killed the
    // process, push-style notifications) requires FCM integration later —
    // this path only covers "app hidden but process alive".
    // ---------------------------------------------------------------------
    if (state == AppLifecycleState.paused) {
      Logger.log('App paused — socket stays connected for background ring/notifications');
    }

    if (_appState == AppLifecycleState.resumed && 
        (state == AppLifecycleState.inactive || state == AppLifecycleState.paused)) {
      // App is going to background - store timestamp and last route
      if (_currentRoute != null && _currentRoute!.isNotEmpty) {
        await _storage.setLastRoute(_currentRoute!);
      }
      _appPausedAt = DateTime.now(); // Save when app was paused
    }
    
    if ((_appState == AppLifecycleState.inactive || _appState == AppLifecycleState.paused) && 
        state == AppLifecycleState.resumed) {
      // Biometric capability probes are memoized for the process lifetime
      // (repeated platform-channel probes cancelled pending fingerprint
      // prompts on some OEMs). The ONLY realistic moment the underlying
      // facts change is a fingerprint enrollment made in system settings
      // while backgrounded — drop the cache on every resume so the next
      // attempt re-probes fresh.
      BiometricService.resetCapabilityCache();

      // App is coming back to foreground - first re-check auth
      await authNotifier.checkAuth(); // Re-check auth to validate token
      
      // Get updated auth state
      final updatedAuthState = ref.read(authProvider);
      
      if (wasWebViewOpen) {
        // If we were in a payment webview, refresh app data when returning
        setState(() {
          _isWebViewOpen = false;
        });
        // Refresh by re-checking auth and resetting state
        if (updatedAuthState.isAuthenticated) {
          // Refresh the auth provider's data or trigger a refresh of all screens
          // Also navigate back to main to ensure fresh data
          if (mounted) {
            _router.go('/main');
          }
        }
      } else {
        // Check if app was paused for more than 5 minutes
        if (_appPausedAt != null && DateTime.now().difference(_appPausedAt!) > const Duration(minutes: 5)) {
          // More than 5 minutes - security logout. The user lands on the
          // login screen and signs back in (password/Google/biometrics) —
          // biometrics are NEVER auto-triggered (user requirement): they
          // only run when the user taps "Sign in with Biometrics".
          // KEEP the FCM device registration (unregisterDevice: false):
          // this is an automatic security logout, and unregistering made
          // push (call rings, chat alerts) silently stop until the next
          // login re-registered the device.
          if (updatedAuthState.isAuthenticated && !_isWebViewOpen) {
            await authNotifier.logout(unregisterDevice: false);
          }
        } else {
          // Less than 5 minutes - reset idle timer and stay logged in
          if (updatedAuthState.isAuthenticated) {
            authNotifier.resetIdleTimer();
            // The OS may have silently killed the socket while backgrounded —
            // reconnect on resume so `call:incoming` reaches us on ANY route
            // (calls used to ring only while sitting on the chat screen).
            try {
              final socket = SocketService();
              if (!socket.isConnected &&
                  updatedAuthState.userId != null &&
                  updatedAuthState.isAuthenticated) {
                socket.connect(
                  updatedAuthState.userId!,
                  updatedAuthState.businessId ?? '',
                );
              }
            } catch (e) {
              Logger.error('Socket resume reconnect failed: $e');
            }
          }
        }
        
        // Refresh the launcher badge against the live unread counts.
        _syncLauncherBadge();

        // PERMISSION RE-CHECK (user requirement): every time the app comes
        // back to the foreground with a signed-in user, make sure the push
        // notification permission is actually granted — if not, surface the
        // primer (or the OS settings deep-link when permanently denied). The
        // primer self-snoozes so this never nags, and it never covers an
        // incoming call.
        final resumeState = ref.read(authProvider);
        final ringingNow = ref.read(callProvider).isRinging;
        if (resumeState.isAuthenticated && !ringingNow) {
          unawaited(PermissionPrimer.recheckOnResume());
        }
      }
    }
    
    _appState = state;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    // WORKSPACE REBIND: the MaterialApp key includes the active businessId,
    // so switching workspace (authProvider.businessId changes) remounts every
    // screen with fresh data — same mechanism the theme toggle uses. The
    // GoRouter instance is untouched, so the current route is restored.
    
    // Listen for auth state changes to navigate to login when needed
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.isAuthenticated == true && next.isAuthenticated == false) {
        // User was logged in, now logged out - navigate to login
        if (mounted) {
          _router.go('/login');
        }
      }
    });
    
    // Listen for auth changes to reset idle timer
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.isAuthenticated != previous?.isAuthenticated) {
        ref.read(authProvider.notifier).resetIdleTimer();
      }
    });

    // FCM device-registration lifecycle: register the push token after every
    // login / biometric restore. The registration is KEPT on every logout
    // path (button, idle timeout, session expiry) so calls and chats still
    // ring via push while the user is signed out — parity with the web
    // client. The next login re-assigns the token to the new user.
    ref.listen<AuthState>(authProvider, (previous, next) {
      final wasIn = previous?.isAuthenticated == true;
      final isIn = next.isAuthenticated;
      if (!wasIn && isIn) {
        unawaited(PushNotificationService.instance.registerCurrentDevice());
      } else if (wasIn && !isIn) {
        // Clear the launcher badge along with the session (harmless on
        // security logouts too).
        unawaited(LauncherBadge.clear());
        // KEEP the device registered across ALL logouts (manual + automatic):
        // calls and chats must still ring via push while the user is signed
        // out — same behaviour as the web client. registerCurrentDevice() on
        // the next login re-assigns the token to whoever signs in.
      }
    });

    // Launcher badge: recompute whenever unread chats or notifications change.
    ref.listen<int>(chatUnreadProvider, (_, __) => _syncLauncherBadge());
    ref.listen<NotificationsState>(notificationsProvider, (_, __) => _syncLauncherBadge());

    // THEME DESYNC GUARD. The MaterialApp follows `themeState.mode` (the
    // provider), but dozens of screens read the STATIC AppTheme.colors, which
    // is only mutated by AppTheme.setThemeMode(). Those two used to be updated
    // from different places — when they ever disagreed (hot-restart order,
    // async storage load, provider rebuild), SOME screens (chat list, MetricAi
    // room) rendered with the stale palette while the rest of the app was
    // already dark/light. Re-syncing the static on every rebuild of THIS
    // widget (which watches themeProvider) guarantees the static can never
    // lag the state that drives MaterialApp.
    AppTheme.setThemeMode(themeState.mode);

    return ErrorBoundary(
      child: IdleTimeoutHandler(
        child: MaterialApp.router(
          title: 'Metricorex',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeState.mode,
          // AUTO-APPLY THEME: most screens read the STATIC AppTheme.colors
          // (not the inherited Theme), so a plain themeMode change left stale
          // colors on screen until the user force-refreshed. Keying the app on
          // the mode remounts every widget with the fresh palette the moment
          // dark/light is toggled — no manual refresh. The GoRouter instance
          // is untouched, so the current route is restored on the remount.
          key: ValueKey<String>('${themeState.mode}|${ref.watch(authProvider).businessId ?? ''}'),
          routerConfig: _router,
          // The global incoming-call overlay MUST live BELOW MaterialApp:
          // as a sibling in a raw Stack it had no Theme/Directionality/
          // MaterialLocalizations ancestor and crashed on every incoming call.
          builder: (context, child) {
            return Stack(
              children: [
                // GLOBAL KEYBOARD DISMISS: tapping ANY non-input surface
                // closes the keyboard (users expected this everywhere —
                // chat, transfers, search...). GestureDetector wrapping the
                // whole app: only the tapping OUTSIDE an editable field
                // reaches here because text fields consume their own taps.
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    final focus = FocusManager.instance.primaryFocus;
                    if (focus != null && focus.hasFocus) {
                      focus.unfocus();
                    }
                  },
                  child: child ?? const SizedBox.shrink(),
                ),
                // "Hide keyboard" pill: floats just above the keyboard on
                // every screen that has one open (explicit one-tap close).
                const _KeyboardDismissPill(),
                // Floating "Ask MetricAi" bubble (draggable, persists its
                // position) — on EVERY authed screen like the web widget.
                // Rendered below the incoming-call overlay so a call always
                // takes precedence.
                const MetricAiFloatingBubble(),
                const IncomingCallDialog(),
                // MAINTENANCE GATE (web parity): TOP-most child — while the
                // admin has maintenance mode ON it covers the entire app
                // (every screen, dialog and the login form itself), polls
                // /public/app-config every 60s + on app resume, and lets
                // users back in automatically when the flag flips off.
                const MaintenanceGateOverlay(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class IdleTimeoutHandler extends ConsumerStatefulWidget {
  final Widget child;

  const IdleTimeoutHandler({super.key, required this.child});

  @override
  ConsumerState<IdleTimeoutHandler> createState() => _IdleTimeoutHandlerState();
}

class _IdleTimeoutHandlerState extends ConsumerState<IdleTimeoutHandler> {
  @override
  Widget build(BuildContext context) {
    final authNotifier = ref.read(authProvider.notifier);
    
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => authNotifier.resetIdleTimer(),
      onPointerMove: (_) => authNotifier.resetIdleTimer(),
      onPointerUp: (_) => authNotifier.resetIdleTimer(),
      child: widget.child,
    );
  }
}

/// Floating "Hide keyboard" pill — appears on EVERY screen while the
/// keyboard is open (bottom-right, just above the keyboard inset). One tap
/// closes it. Sits above the app content but below the incoming-call overlay.
class _KeyboardDismissPill extends StatelessWidget {
  const _KeyboardDismissPill();

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    // Only show while a keyboard is actually open (~ any inset above 80dp
    // filters out gesture-bar-only insets).
    if (insets < 80) return const SizedBox.shrink();
    return Positioned(
      right: 16,
      bottom: insets + 8,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            final focus = FocusManager.instance.primaryFocus;
            focus?.unfocus();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.keyboard_hide_rounded, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Hide keyboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
