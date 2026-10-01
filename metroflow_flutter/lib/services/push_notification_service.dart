import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_feedback.dart';
import '../utils/logger.dart';
import 'api.dart';
import 'app_badge_service.dart';

/// ---------------------------------------------------------------------------
/// Metroflow push notifications (FCM).
///
/// WHAT THIS SERVICE DOES
/// - Initialises Firebase + firebase_messaging (guarded: if the Firebase
///   native config is missing the service degrades to a silent no-op and the
///   app keeps working exactly as before).
/// - Requests notification permissions (alert/badge/sound + critical alert on
///   iOS for incoming-call rings on a locked device).
/// - Creates the Android notification channels: "calls" (max importance,
///   looping call-ringtone raw resource, full-screen-intent capable) and
///   "general".
/// - Foreground pushes -> local notifications (WhatsApp-style); incoming-call
///   pushes additionally ring the device via the in-app ringtone.
/// - Background/terminated pushes -> handled by [firebaseMessagingBackgroundHandler]
///   (top-level, tree-shake safe) which posts a full-screen-intent local
///   notification for calls so a locked device lights up and rings.
/// - Tapping any push deep-links into the relevant screen via the global
///   [navigatorKey] (GoRouter) / callProvider hook.
/// - FCM tokens are POSTed to /notifications/register-device after login, on
///   refresh, and DELETEd on logout (see registerCurrentDevice /
///   unregisterCurrentDevice).
///
/// SETUP REQUIRED FOR FULL FUNCTION (ops, not code):
/// - Android: place `google-services.json` from the Firebase console in
///   `android/app/` and apply the `com.google.gms.google-services` plugin.
///   Until then the Gradle build stays green and Firebase init simply fails
///   gracefully at runtime (this service disables itself).
/// - iOS: place `GoogleService-Info.plist` in `ios/Runner/` (Xcode target) and
///   add the `UIBackgroundModes: [remote-notification]` entry (already added
///   to Info.plist).
/// - Backend: set FIREBASE_SERVICE_ACCOUNT_JSON so server/services/push.ts can
///   mint FCM HTTP v1 tokens.
///
/// INCOMING-CALL DATA PAYLOAD (backend contract):
///   data: { type: 'incoming_call', call_id, call_code, caller_name, call_type }
/// CHAT MESSAGE DATA PAYLOAD:
///   data: { type: 'chat_message', conversation_id, sender_name, message }
/// ---------------------------------------------------------------------------

/// Notification channel ids — MUST match the backend's `androidChannelId`
/// ("calls" for incoming-call pushes, "general" for everything else) and the
/// AndroidManifest meta-data `com.google.firebase.messaging.default_notification_channel_id`.
const String kPushCallChannelId = 'calls';
const String kPushGeneralChannelId = 'general';

/// Normalizes the backend's push `type` discriminator. The contract has used
/// BOTH spellings over time (socket era: `incoming_call`; FCM era:
/// `incoming-call`), so everything is lowercased and hyphens folded to
/// underscores before comparison.
String _normalizePushType(dynamic raw) {
  final value = raw?.toString().trim().toLowerCase() ?? '';
  return value.replaceAll('-', '_');
}

/// Stable notification ids: a new incoming call REPLACES the previous one
/// instead of stacking, and chat notifications group per conversation.
const int _kCallNotificationId = 1001;
const int _kChatNotificationIdBase = 2000;

/// Raw resource (android/app/src/main/res/raw/call_ringtone.wav) used by the
/// "calls" channel. Raw resource names exclude the extension.
const String _kCallRingtoneResource = 'call_ringtone';

/// Background/terminated message handler. MUST be top-level (not a closure /
/// class method) or firebase_messaging throws at runtime; the pragma keeps it
/// alive in AOT release builds.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    debugPrint('FCM background message: ${message.messageId}');
    // Only CALL pushes need the WhatsApp-style full-screen treatment while the
    // app is closed/backgrounded — chat messages land as normal notifications
    // posted by FCM itself (notification payloads) or here for data-only sends.
    final data = message.data;
    final type = _normalizePushType(data['type']);
    if (type == 'incoming_call') {
      await PushNotificationService.showCallNotification(
        callerName: (data['caller_name'] ?? data['callerName'] ?? data['callerId'] ?? 'Incoming call').toString(),
        callType: (data['call_type'] ?? data['callType'] ?? 'video').toString(),
        payload: Map<String, dynamic>.from(data),
      );
      return;
    }
    if (type == 'missed_call') {
      // Missed-call push: an ordinary heads-up on the "general" channel —
      // the user must NOT get a full-screen ring for a call already gone.
      final caller = (data['caller_name'] ?? data['callerName'] ?? data['callerId'] ?? '').toString();
      final callType = (data['call_type'] ?? data['callType'] ?? 'audio').toString();
      await PushNotificationService.showGeneralNotification(
        title: 'Missed ${callType == 'video' ? 'video' : 'audio'} call',
        body: caller.isEmpty ? 'You missed a call' : 'Missed call from $caller',
        payload: Map<String, dynamic>.from(data),
      );
      return;
    }
    if (type == 'chat_message') {
      await PushNotificationService.showChatNotification(
        senderName: (data['sender_name'] ?? data['senderName'] ?? 'New message').toString(),
        body: (data['message'] ?? '').toString(),
        conversationId: (data['conversation_id'] ?? data['conversationId'] ?? '').toString(),
        payload: Map<String, dynamic>.from(data),
      );
      // Launcher badge (Facebook-style) — use the server-computed unread
      // count when present, otherwise tick the local counter.
      await AppBadgeService.instance.addUnread(
        exact: int.tryParse((data['badge'] ?? '').toString()),
      );
      return;
    }
    // Generic data-only push (no `notification` block) — surface it so it is
    // not silently lost while the app is closed.
    if (message.notification == null && data.isNotEmpty) {
      await PushNotificationService.showGeneralNotification(
        title: (data['title'] ?? 'Metricorex').toString(),
        body: (data['body'] ?? '').toString(),
        payload: Map<String, dynamic>.from(data),
      );
    }
  } catch (e) {
    // A crash in the background isolate must never bubble to the OS.
    debugPrint('firebaseMessagingBackgroundHandler error: $e');
  }
}

class PushNotificationService {
  PushNotificationService._internal();
  static final PushNotificationService _instance = PushNotificationService._internal();
  static PushNotificationService get instance => _instance;

  /// False when Firebase could not be initialised (missing native config) —
  /// every public method then no-ops.
  bool _enabled = false;
  bool _initialized = false;

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  /// Guard used by the FOREGROUND incoming-call push: when the socket already
  /// delivered `call:incoming` (callProvider is ringing) we skip the second
  /// ring to avoid overlapping audio. Wired from main.dart.
  bool Function()? foregroundCallGuard;

  SharedPreferences? _prefs;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  /// Last FCM token seen on this device (persisted so logout can unregister
  /// even if Firebase is unavailable in that moment).
  static const String _fcmTokenPrefKey = 'fcm_token';

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Safe to call multiple times (idempotent). Never throws.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {}

    // 1. Firebase — guarded. Without google-services.json / plist this throws
    //    (no default Firebase options) and we disable the whole service.
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _enabled = true;
    } catch (e) {
      _enabled = false;
      Logger.error('PushNotificationService: Firebase unavailable, push disabled '
          '(add google-services.json / GoogleService-Info.plist to enable): $e');
      return;
    }

    try {
      // 2. Local notifications (channels + tap handling).
      await _initLocalNotifications();

      // 3. Permissions — FCM is the single permission authority (the local
      //    notifications plugin is initialised with request*Permission:false).
      // NOTE: criticalAlert MUST stay false unless the app has been granted
      // Apple's "critical alerts" entitlement (a special request form; most
      // apps never get it). Requesting it without the entitlement makes
      // UNUserNotificationCenter.requestAuthorization fail on iOS, which
      // kills the ENTIRE permission prompt -> no notifications at all.
      // Incoming calls already ring via the "calls" channel (Android) and
      // the local-notification ring path (iOS), so regular alert+sound is
      // sufficient here.
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: false,
        announcement: false,
        carPlay: false,
        provisional: false,
      );
      debugPrint('Push permission: ${settings.authorizationStatus}');

      // Present banners + sound for FCM pushes while the app is FOREGROUND.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 4. Streams.
      _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _persistToken(token);
        // Re-register on refresh (needs an authenticated session to attach the
        // Authorization header; unauthenticated calls fail silently).
        registerCurrentDevice();
      });

      // 5. Cold start via notification tap.
      unawaited(_handleInitialMessage());

      // 6. Register the (already known) token for the signed-in user.
      unawaited(registerCurrentDevice());
    } catch (e) {
      Logger.error('PushNotificationService.initialize failed: $e');
    }
  }

  bool get isEnabled => _enabled;

  // -------------------------------------------------------------------------
  // Local notifications setup
  // -------------------------------------------------------------------------

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('ic_notification');
    // Permissions are requested once via FirebaseMessaging.requestPermission,
    // so the Darwin init keeps its request flags off.
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestCriticalPermission: false,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: darwinInit);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationTap(response.payload);
      },
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        // "calls": max importance + looping ringtone + alarm audio usage so it
        // rings while the device is locked.
        const callChannel = AndroidNotificationChannel(
          kPushCallChannelId,
          'Incoming calls',
          description: 'Rings for incoming Metroflow calls even when the app is closed.',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(_kCallRingtoneResource),
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          showBadge: true,
        );
        // "general": default chat/notification sound.
        const generalChannel = AndroidNotificationChannel(
          kPushGeneralChannelId,
          'General notifications',
          description: 'Messages, alerts and account updates.',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );
        await androidPlugin.createNotificationChannel(callChannel);
        await androidPlugin.createNotificationChannel(generalChannel);

        // Android 13+ runtime permission (POST_NOTIFICATIONS). Firebase's
        // requestPermission also covers this; belt & braces, silently ignored
        // on older APIs.
        try {
          await androidPlugin.requestNotificationsPermission();
        } catch (_) {}
      }
    }
  }

  AndroidNotificationDetails _androidDetails({
    required String channelId,
    required String channelName,
    required String channelDescription,
    required bool fullScreenIntent,
  }) {
    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: fullScreenIntent,
      category: fullScreenIntent ? AndroidNotificationCategory.call : null,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
    );
  }

  // -------------------------------------------------------------------------
  // Show helpers (public so the background handler can use them)
  // -------------------------------------------------------------------------

  /// Full-screen-style, high-priority "incoming call" notification.
  static Future<void> showCallNotification({
    required String callerName,
    required String callType,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final details = _instance._androidDetails(
        channelId: kPushCallChannelId,
        channelName: 'Incoming calls',
        channelDescription: 'Rings for incoming Metroflow calls even when the app is closed.',
        fullScreenIntent: true,
      );
      await _instance._localNotifications.show(
        _kCallNotificationId,
        'Incoming ${callType == 'audio' ? 'audio' : 'video'} call',
        callerName,
        NotificationDetails(android: details, iOS: const DarwinNotificationDetails()),
        payload: _encodePayload(payload),
      );
    } catch (e) {
      debugPrint('showCallNotification failed: $e');
    }
  }

  /// Chat message notification (normal priority path, "general" channel).
  static Future<void> showChatNotification({
    required String senderName,
    required String body,
    required String conversationId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final details = _instance._androidDetails(
        channelId: kPushGeneralChannelId,
        channelName: 'General notifications',
        channelDescription: 'Messages, alerts and account updates.',
        fullScreenIntent: false,
      );
      await _instance._localNotifications.show(
        _kChatNotificationIdBase + (conversationId.isEmpty ? 0 : conversationId.hashCode % 50000),
        senderName,
        body.isEmpty ? 'Sent you a message' : body,
        NotificationDetails(android: details, iOS: const DarwinNotificationDetails()),
        payload: _encodePayload(payload),
      );
    } catch (e) {
      debugPrint('showChatNotification failed: $e');
    }
  }

  /// Generic notification for data-only pushes of unknown types.
  static Future<void> showGeneralNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final details = _instance._androidDetails(
        channelId: kPushGeneralChannelId,
        channelName: 'General notifications',
        channelDescription: 'Messages, alerts and account updates.',
        fullScreenIntent: false,
      );
      await _instance._localNotifications.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        title,
        body,
        NotificationDetails(android: details, iOS: const DarwinNotificationDetails()),
        payload: _encodePayload(payload),
      );
    } catch (e) {
      debugPrint('showGeneralNotification failed: $e');
    }
  }

  /// JSON-encode the payload for the notification tap channel (data payloads
  /// from FCM are already flat string maps; encoding keeps it lossless).
  static String? _encodePayload(Map<String, dynamic> data) {
    try {
      return jsonEncode(data.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')));
    } catch (_) {
      return null;
    }
  }

  /// Parses the stored payload back into a map. Never throws — an unreadable
  /// payload still opens the app (to the default screen).
  static Map<String, dynamic> _decodePayload(String? payload) {
    final result = <String, dynamic>{};
    if (payload == null || payload.isEmpty) return result;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        decoded.forEach((k, v) => result[k.toString()] = v?.toString() ?? '');
      }
    } catch (_) {}
    return result;
  }

  // -------------------------------------------------------------------------
  // Message handling
  // -------------------------------------------------------------------------

  /// FOREGROUND push: the socket path handles ringing when the app is open,
  /// but pushes still arrive (e.g. the process was half-dead, or the backend
  /// chose FCM-only delivery). Show a local notification; call pushes also
  /// ring — unless the in-app incoming-call overlay is already ringing.
  void _handleForegroundMessage(RemoteMessage message) {
    try {
      final data = message.data;
      final type = _normalizePushType(data['type']);
      switch (type) {
        case 'incoming_call':
          final alreadyRinging = foregroundCallGuard?.call() ?? false;
          if (alreadyRinging) {
            // The in-app incoming-call overlay is already ringing (socket
            // path): surface the tray banner as well so a swipe-down still
            // shows the call.
            showCallNotification(
              callerName: (data['caller_name'] ?? data['callerName'] ?? data['callerId'] ?? 'Incoming call').toString(),
              callType: (data['call_type'] ?? data['callType'] ?? 'video').toString(),
              payload: Map<String, dynamic>.from(data),
            );
          } else {
            // Push-only delivery: present the global overlay + ring INSTEAD
            // of a tray notification. The old order (post the notification,
            // then _presentIncomingCall cancelled it right away) is exactly
            // the "I hear the ring but nothing shows in the tray" bug.
            _presentIncomingCall(Map<String, dynamic>.from(data));
            AppFeedback.startRingtone();
          }
          break;
        case 'missed_call':
          final caller = (data['caller_name'] ?? data['callerName'] ?? data['callerId'] ?? '').toString();
          final callType = (data['call_type'] ?? data['callType'] ?? 'audio').toString();
          showGeneralNotification(
            title: 'Missed ${callType == 'video' ? 'video' : 'audio'} call',
            body: caller.isEmpty ? 'You missed a call' : 'Missed call from $caller',
            payload: Map<String, dynamic>.from(data),
          );
          break;
        case 'chat_message':
          showChatNotification(
            senderName: (data['sender_name'] ?? data['senderName'] ?? 'New message').toString(),
            body: (data['message'] ?? '').toString(),
            conversationId: (data['conversation_id'] ?? data['conversationId'] ?? '').toString(),
            payload: Map<String, dynamic>.from(data),
          );
          // Launcher badge (Facebook-style) — see the background handler.
          AppBadgeService.instance.addUnread(
            exact: int.tryParse((data['badge'] ?? '').toString()),
          );
          break;
        default:
          if (message.notification != null) return; // FCM already displayed it
          showGeneralNotification(
            title: message.notification?.title ?? 'Metricorex',
            body: message.notification?.body ?? '',
            payload: Map<String, dynamic>.from(data),
          );
      }
    } catch (e) {
      debugPrint('_handleForegroundMessage failed: $e');
    }
  }

  /// Cold start: app was launched by a notification tap.
  Future<void> _handleInitialMessage() async {
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message == null) return;
      // Give the router a beat to mount after the splash/auth flow.
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      _handleMessageTap(message);
    } catch (e) {
      debugPrint('_handleInitialMessage failed: $e');
    }
  }

  /// Unified tap handler for: notification tap (local), FCM onMessageOpenedApp
  /// and getInitialMessage. Deep-links into the relevant screen.
  void _handleMessageTap(RemoteMessage message) {
    _handleNotificationTapPayload(Map<String, dynamic>.from(message.data));
  }

  void _handleNotificationTap(String? payload) {
    _handleNotificationTapPayload(_decodePayload(payload));
  }

  void _handleNotificationTapPayload(Map<String, dynamic> data) {
    try {
      if (data.isEmpty) {
        _navigate('/main');
        return;
      }
      final type = _normalizePushType(data['type']);
      switch (type) {
        case 'incoming_call':
          // Re-present the global incoming-call overlay (WhatsApp-style):
          // the user tapped the call notification, show Accept/Decline.
          _presentIncomingCall(data);
          break;
        case 'missed_call':
          _navigate('/main/calls');
          break;
        case 'chat_message':
          _navigate('/main/chat');
          break;
        default:
          _navigate('/main/notifications');
      }
    } catch (e) {
      debugPrint('_handleNotificationTapPayload failed: $e');
    }
  }

  /// Feeds the tapped incoming-call push into the same provider state that the
  /// socket `call:incoming` handler uses, so the global IncomingCallDialog
  /// handles Accept/Reject/Join exactly like an in-app ring would.
  ///
  /// main.dart assigns [incomingCallHook] — the service stays provider-free
  /// (no riverpod import) to avoid an import cycle.
  void _presentIncomingCall(Map<String, dynamic> data) {
    try {
      // Cancel the full-screen notification: once the overlay is up, the OS
      // banner would just keep ringing after the in-app ring starts.
      unawaited(cancelCallNotification());
      incomingCallHook?.call(data);
    } catch (e) {
      debugPrint('_presentIncomingCall failed: $e');
    }
  }

  /// Assigned from main.dart:
  /// `PushNotificationService.instance.incomingCallHook =
  ///   (data) => ref.read(callProvider.notifier).presentIncomingCall(data);`
  void Function(Map<String, dynamic> data)? incomingCallHook;

  void _navigate(String location) {
    try {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      GoRouter.of(context).go(location);
    } catch (e) {
      debugPrint('Push navigation failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Device registration
  // -------------------------------------------------------------------------

  Future<String?> _currentToken() async {
    try {
      if (!_enabled) {
        return _prefs?.getString(_fcmTokenPrefKey);
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _persistToken(token);
        return token;
      }
      return _prefs?.getString(_fcmTokenPrefKey);
    } catch (e) {
      debugPrint('getToken failed: $e');
      return _prefs?.getString(_fcmTokenPrefKey);
    }
  }

  Future<void> _persistToken(String token) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(_fcmTokenPrefKey, token);
    } catch (_) {}
  }

  static String _platformName() {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      return 'web';
    } catch (_) {
      return 'android';
    }
  }

  static String _deviceName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return _platformName();
    }
  }

  /// POST {fcm_token, platform, device_name, app_version} to
  /// /notifications/register-device. Called:
  /// - after login / biometric restore (main.dart auth listener)
  /// - whenever FCM rotates the token (onTokenRefresh)
  /// - once at service init when the user is already signed in
  /// Never throws; silent on failure (next trigger retries).
  Future<void> registerCurrentDevice() async {
    try {
      final token = await StorageService().getToken();
      if (token == null || token.isEmpty) return; // not signed in yet
      final fcmToken = await _currentToken();
      if (fcmToken == null || fcmToken.isEmpty) return;
      await ApiService().registerDevice(
        fcmToken: fcmToken,
        platform: _platformName(),
        deviceName: _deviceName(),
      );
    } catch (e) {
      debugPrint('registerDevice failed: $e');
    }
  }

  /// DELETE /notifications/register-device for the stored FCM token (logout).
  /// Never throws.
  Future<void> unregisterCurrentDevice() async {
    String? fcmToken;
    try {
      fcmToken = await _currentToken();
    } catch (_) {}
    try {
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await ApiService().unregisterDevice(fcmToken: fcmToken);
      }
    } catch (e) {
      debugPrint('unregisterDevice failed: $e');
    } finally {
      try {
        await _prefs?.remove(_fcmTokenPrefKey);
      } catch (_) {}
    }
  }

  /// Cancel the persistent incoming-call notification (call answered/ended).
  Future<void> cancelCallNotification() async {
    try {
      await _localNotifications.cancel(_kCallNotificationId);
    } catch (_) {}
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
  }
}
