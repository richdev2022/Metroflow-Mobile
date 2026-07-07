import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'models/transfer.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'services/api.dart';
import 'services/biometrics.dart';
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
import 'screens/kyc_initiate_screen.dart';
import 'screens/kyc_otp_screen.dart';
import 'screens/business_kyc_screen.dart';

import 'screens/fund_wallet_screen.dart';
import 'screens/bulk_transfer_screen.dart';
import 'screens/transfers_screen.dart';
import 'screens/transfer_detail_screen.dart';
import 'screens/transfer_success_screen.dart';
import 'screens/create_task_screen.dart';
import 'screens/task_detail_screen.dart';
import 'screens/ideas_screen.dart';
import 'screens/idea_detail_screen.dart';
import 'screens/backlog_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/team_screen.dart';
import 'screens/ranking_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/transaction_detail_screen.dart';
import 'screens/bulk_create_tasks_screen.dart';
import 'models/payment_transaction.dart';
import 'screens/fees_screen.dart';
import 'screens/activity_logs_screen.dart';
import 'screens/board_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
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
  AppLifecycleState _appState = AppLifecycleState.resumed;
  String? _currentRoute;
  final _storage = StorageService();
  bool _shouldPromptBiometricsOnResume = false;
  bool _isWebViewOpen = false; // New flag to track webview state
  DateTime? _appPausedAt; // Track when app went to background

  // Public method to set webview state
  void setWebViewOpen(bool isOpen) {
    setState(() {
      _isWebViewOpen = isOpen;
    });
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

        if (isAuthenticated) {
          if (path.startsWith('/onboarding') ||
              path == '/login' ||
              path == '/register' ||
              path == '/verify-otp' ||
              path == '/forgot-password' ||
              path == '/verify-reset-otp' ||
              path == '/reset-password') {
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
        GoRoute(
          path: '/kyc-initiate',
          builder: (context, state) => const KycInitiateScreen(),
        ),
        GoRoute(
          path: '/kyc-otp',
          builder: (context, state) => const KycOtpScreen(),
        ),
        GoRoute(
          path: '/main',
          builder: (context, state) {
            final index = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
            return MainScreen(initialIndex: index);
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
          ],
        ),
      ],
    );

    // Set logout handler
    setLogoutHandler(() {
      final authNotifier = ref.read(authProvider.notifier);
      authNotifier.logout();
      _router.go('/login');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final authNotifier = ref.read(authProvider.notifier);
    bool wasWebViewOpen = _isWebViewOpen; // Store before modifying
    
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
          // More than 5 minutes - logout and prompt for biometrics
          if (updatedAuthState.isAuthenticated && !_isWebViewOpen) {
            await authNotifier.logout();
            _shouldPromptBiometricsOnResume = true;
          }
        } else {
          // Less than 5 minutes - reset idle timer and stay logged in
          if (updatedAuthState.isAuthenticated) {
            authNotifier.resetIdleTimer();
          }
        }
        
        // Prompt biometrics if needed
        if (_shouldPromptBiometricsOnResume && updatedAuthState.biometricsEnabled && !updatedAuthState.isAuthenticated) {
          // Prompt biometrics
          final hasBiometrics = await BiometricService.isAvailable();
          if (hasBiometrics && mounted) {
            // Try to auto-prompt biometrics login
            try {
              final success = await authNotifier.loginWithBiometrics();
              if (success) {
              // Navigate to last route or main
              final lastRoute = await _storage.getLastRoute();
              if (lastRoute != null && lastRoute.isNotEmpty && lastRoute != '/login') {
                await _storage.removeLastRoute();
                if (mounted) _router.go(lastRoute);
              } else {
                if (mounted) _router.go('/main');
              }
            }
            } catch (e) {
              debugPrint('Auto biometric login failed: $e');
            }
          }
          _shouldPromptBiometricsOnResume = false;
        }
      }
    }
    
    _appState = state;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    
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

    return ErrorBoundary(
      child: IdleTimeoutHandler(
        child: MaterialApp.router(
          title: 'Metricorex',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeState.mode,
          routerConfig: _router,
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
