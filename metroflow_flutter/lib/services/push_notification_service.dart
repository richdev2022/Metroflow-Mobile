import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/chat_detail_screen.dart';
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
/// ("calls-v3" for incoming-call pushes, "messages-v3" for chat-message
/// pushes, "general-v3" for every other push) and the AndroidManifest
/// meta-data `com.google.firebase.messaging.default_notification_channel_id`.
///
/// WHY "-v3": Android notification-channel settings (including the sound) are
/// IMMUTABLE once the channel is created on a device — existing installs would
/// keep the old sound forever. v3 carries the FINAL user-supplied sound set
/// (Oct 10 master audio). v2 never shipped for "calls"/"messages" (only
/// "general" was bumped once), so devices that installed ANY earlier build
/// were still locked to the pre-sound defaults — the reason custom sounds
/// "didn't work" on mobile. New channel ids guarantee every install picks up
/// the user-supplied sounds. The legacy "general" channel is still created as
/// a fallback so pushes from an not-yet-updated backend never disappear.
const String kPushCallChannelId = 'calls-v3';
const String kPushMessagesChannelId = 'messages-v3';
const String kPushGeneralChannelId = 'general-v3';
const String kPushLegacyGeneralChannelId = 'general';

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

/// SharedPreferences key that parks an ACCEPTED-from-notification incoming
/// call across an authentication boundary: the notification action persists
/// the payload, and main.dart re-presents the call via callProvider once the
/// user signs back in (cold start → login → ring again).
const String kPendingIncomingCallPrefKey = 'pending_incoming_call';

/// Notification action ids for the WhatsApp-style Accept/Decline buttons on
/// the incoming-call notification (must match showCallNotification).
const String kCallActionAccept = 'accept_call';
const String kCallActionDecline = 'decline_call';

/// Raw resources (android/app/src/main/res/raw/*.mp3) used by the
/// notification channels. Raw resource names exclude the extension.
///  - call_ringtone.mp3      → "calls" channel (user-supplied ringtone)
///  - chat_receive_alert.mp3 → "messages" channel (chat pushes)
///  - push_notification.mp3  → "general-v2" channel (misc pushes)
const String _kCallRingtoneResource = 'call_ringtone';
const String _kChatReceiveAlertResource = 'chat_receive_alert';
const String _kPushNotificationResource = 'push_notification';

/// iOS notification sound files bundled in ios/Runner/*.caf (UNNotificationSound
/// looks them up in the app bundle; the backend's aps.sound uses the same names).
const String kIosCallRingtoneSound = 'call_ringtone.caf';
const String kIosChatReceiveAlertSound = 'chat_receive_alert.caf';
const String kIosPushNotificationSound = 'push_notification.caf';

/// Background/terminated message handler. MUST be top-level (not a closure /
/// class method) or firebase_messaging throws at runtime; the pragma keeps it
/// alive in AOT release builds.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    debugPrint('FCM background message: ${message.messageId}');
    // The background handler runs in its OWN isolate — flutter_local_notifications
    // must be initialized HERE before any show/cancel can work (the main
    // isolate's initialization does not carry over).
    await PushNotificationService.ensureBackgroundInitialized();
    // Only CALL pushes need the WhatsApp-style full-screen treatment while the
    // app is closed/backgrounded — chat messages land as normal notifications
    // posted by FCM itself (notification payloads) or here for data-only sends.
    final data = message.data;
    final type = _normalizePushType(data['type']);
    if (type == 'incoming_call') {
      // Render FIRST, ack AFTER a confirmed render. The ack cancels the
      // server's 8s escalation that re-sends the call as a visible tray
      // notification (OEMs silently drop data-only FCM). Acking before the
      // render was confirmed let a failed/lost render cancel its own safety
      // net — the exact "no ring, nothing in the notification panel" bug.
      final rendered = await PushNotificationService.showCallNotification(
        callerName: (data['caller_name'] ?? data['callerName'] ?? data['callerId'] ?? 'Incoming call').toString(),
        callType: (data['call_type'] ?? data['callType'] ?? 'video').toString(),
        payload: Map<String, dynamic>.from(data),
      );
      if (rendered) {
        unawaited(PushNotificationService.acknowledgeCallPush(data));
      } else {
        debugPrint('incoming-call render FAILED — leaving the server escalation armed');
      }
      return;
    }
    if (type == 'missed_call') {
      // Missed-call push: an ordinary heads-up on the "general" channel —
      // the user must NOT get a full-screen ring for a call already gone.
      // Also clear the still-showing full-screen incoming-call notification
      // (the caller gave up / the call was answered elsewhere).
      final caller = (data['caller_name'] ?? data['callerName'] ?? data['callerId'] ?? '').toString();
      final callType = (data['call_type'] ?? data['callType'] ?? 'audio').toString();
      await PushNotificationService.cancelCallNotification();
      await PushNotificationService.showGeneralNotification(
        title: 'Missed ${callType == 'video' ? 'video' : 'audio'} call',
        body: caller.isEmpty ? 'You missed a call' : 'Missed call from $caller',
        payload: Map<String, dynamic>.from(data),
      );
      await AppBadgeService.instance.addUnread(
        exact: int.tryParse((data['badge'] ?? '').toString()),
      );
      return;
    }
    if (type == 'call_cancelled') {
      // SILENT cleanup: the caller hung up while this device was still
      // ringing. Kill the full-screen ring notification — no banner, no
      // badge (the missed-call push, if any, carries the user-facing notice).
      await PushNotificationService.cancelCallNotification();
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
    // Generic data-only push — surface it so it is not silently lost while
    // the app is closed, and count it on the launcher badge.
    if (data.isNotEmpty) {
      await PushNotificationService.showGeneralNotification(
        title: (data['title'] ?? 'Metricorex').toString(),
        body: (data['body'] ?? '').toString(),
        payload: Map<String, dynamic>.from(data),
      );
      await AppBadgeService.instance.addUnread();
    }
  } catch (e) {
    // A crash in the background isolate must never bubble to the OS.
    debugPrint('firebaseMessagingBackgroundHandler error: $e');
  }
}

/// Background/terminated notification ACTION BUTTON handler (Accept /
/// Decline on the incoming-call notification). MUST be top-level with the
/// entry-point pragma or flutter_local_notifications throws at runtime; it
/// runs in its OWN isolate, so it relies only on statics + fresh plugin
/// instances.
///
/// - Decline → REST POST /calls/:id/reject via ApiService (the socket-only
///   `call:reject` emit is useless from a dead process) + cancel the ring
///   notification. Fire-and-forget, never throws.
/// - Accept → park the decoded payload under SharedPreferences
///   [kPendingIncomingCallPrefKey] and cancel the notification. Once the
///   app finishes its (cold-start) authentication, main.dart reads the key
///   and re-presents the ring via callProvider.presentIncomingCall.
/// - Anything else (plain taps) → no-op here; the main isolate handles taps.
@pragma('vm:entry-point')
Future<void> backgroundNotificationActionHandler(NotificationResponse response) async {
  try {
    final actionId = response.actionId ?? '';
    if (actionId != kCallActionAccept && actionId != kCallActionDecline) {
      return; // plain tap — handled by the main isolate / cold-start path
    }
    final data = PushNotificationService._decodePayload(response.payload);
    final callId = (data['callId'] ?? data['callID'] ?? data['call_id'] ?? data['id'] ?? '')
        .toString();
    if (actionId == kCallActionDecline) {
      if (callId.isNotEmpty) {
        await PushNotificationService._safeRejectCall(callId);
      }
      await PushNotificationService.cancelCallNotification();
      return;
    }
    // accept_call
    if (callId.isNotEmpty) {
      await PushNotificationService.persistPendingIncomingCall(data);
    }
    await PushNotificationService.cancelCallNotification();
  } catch (e) {
    // A crash in the background isolate must never bubble to the OS.
    debugPrint('backgroundNotificationActionHandler error: $e');
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

  /// Reports the callId currently ringing via the in-app overlay
  /// (callProvider's IncomingCallState.call.id), or null when nothing is
  /// ringing. Wired from main.dart — lets the foreground incoming-call push
  /// recognise a SERVER RETRY for the call that is already ringing (the
  /// server now retries failed deliveries, so a data-only push can arrive
  /// while the socket ring is active) and ignore it entirely instead of
  /// re-presenting (which reset the ring timer and restarted the ringtone).
  String? Function()? currentRingingCallId;

  /// Hook that clears the in-app ringing overlay (callProvider) when a
  /// missed-call / ended push proves the call is gone. Wired from main.dart.
  void Function()? dismissIncomingCallHook;

  /// Hook for `call-cancelled` pushes: receives the cancelled callId so the
  /// ringing overlay is dismissed only when THAT call is the one ringing.
  void Function(String callId)? callCancelledHook;

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

    // 1. Local notifications FIRST — deliberately BEFORE Firebase. On iOS the
    //    Darwin initialization is what fires the ONE-TIME system permission
    //    prompt; if we waited for Firebase (which throws when the native
    //    GoogleService-Info.plist is missing) the prompt NEVER appeared, the
    //    app had no Notifications row in iOS Settings at all, and push was
    //    dead with zero user-visible signal. Running this first means:
    //    - the permission is requested once, automatically, on first launch
    //      (the "grant once" behaviour) — regardless of Firebase health;
    //    - local notifications (in-app banners, rings) always work.
    try {
      await _initLocalNotifications();
    } catch (e) {
      Logger.error('PushNotificationService: local notifications init failed: $e');
    }

    // 2. Firebase — guarded. Without google-services.json / plist this throws
    //    (no default Firebase options) and remote push stays off while the
    //    rest of the service (local notifications, permission) keeps working.
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _enabled = true;
    } catch (e) {
      _enabled = false;
      Logger.error(
        'PushNotificationService: Firebase unavailable — REMOTE push disabled '
        '(local notifications + permission still active). FIX: register the iOS '
        'app in the Firebase console, download GoogleService-Info.plist and add '
        'it to ios/Runner/ (Android already has google-services.json): $e',
      );
      return;
    }

    try {
      // 3. FCM permission — idempotent: when step 1 already prompted (iOS),
      //    this just READS the granted status. It stays for Android 13+ (the
      //    POST_NOTIFICATIONS runtime dialog) and for the criticalAlert=false
      //    contract documented below.
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
    // iOS: the Darwin init REQUESTS the permission on first launch (alert +
    // badge + sound, provisional:false so it is the real prompt). This is the
    // path that used to be dead — Firebase failing meant NO prompt ever ran
    // and the app never appeared under iOS Settings → Notifications. Request
    // here unconditionally: when Firebase later also calls
    // FirebaseMessaging.requestPermission the OS just returns the already-
    // granted status (the system prompt only ever shows once).
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestCriticalPermission: false,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: darwinInit);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Notification ACTION BUTTONS (Accept/Decline on the incoming-call
        // notification) branch BEFORE the generic tap deep-linking.
        final actionId = response.actionId ?? '';
        if (actionId == kCallActionAccept || actionId == kCallActionDecline) {
          _handleCallNotificationAction(actionId, response.payload);
          return;
        }
        _handleNotificationTap(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse:
          backgroundNotificationActionHandler,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        // Android 13+ runtime permission (POST_NOTIFICATIONS). Firebase's
        // requestPermission also covers this; belt & braces, silently ignored
        // on older APIs.
        try {
          await androidPlugin.requestNotificationsPermission();
        } catch (_) {}
        // ANDROID 14+ FULL-SCREEN-INTENT PERMISSION: the OS REVOKES the
        // USE_FULL_SCREEN_INTENT grant for sideloaded/sideload-updated apps
        // — the exact "incoming call shows a notification in the panel but
        // never rings full-screen / never lights the lock screen" bug.
        // Re-request explicitly (best-effort: the method exists on
        // AndroidFlutterLocalNotificationsPlugin in v18; failures ignored).
        try {
          await androidPlugin.requestFullScreenIntentPermission();
        } catch (_) {}
      }
    }
    await _ensureAndroidChannels();
  }

  AndroidNotificationDetails _androidDetails({
    required String channelId,
    required String channelName,
    required String channelDescription,
    required bool fullScreenIntent,
    List<AndroidNotificationAction>? actions,
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
      // WhatsApp-style inline Accept/Decline buttons (Android only). Both
      // show the app UI and cancel the notification on press; the response
      // is routed to the background- or main-isolate action handler.
      actions: actions,
    );
  }

  // -------------------------------------------------------------------------
  // Show helpers (public so the background handler can use them)
  // -------------------------------------------------------------------------

  /// Full-screen-style, high-priority "incoming call" notification.
  /// Returns true when the notification was actually posted — the caller
  /// must only ack the server's delivery receipt after a CONFIRMED render,
  /// otherwise a failed render cancels the server's escalation fallback.
  static Future<bool> showCallNotification({
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
        // Accept/Decline right on the notification (lock screen included).
        actions: const [
          AndroidNotificationAction(
            kCallActionAccept,
            'Accept',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            kCallActionDecline,
            'Decline',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );
      await _instance._localNotifications.show(
        _kCallNotificationId,
        'Incoming ${callType == 'audio' ? 'audio' : 'video'} call',
        callerName,
        NotificationDetails(
          android: details,
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            sound: kIosCallRingtoneSound,
            presentBanner: true,
            presentList: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        payload: _encodePayload(payload),
      );
      return true;
    } catch (e) {
      debugPrint('showCallNotification failed: $e');
      return false;
    }
  }

  /// Chat message notification (normal priority path, "messages" channel so
  /// it plays the user-supplied chat-receive alert instead of the misc sound).
  static Future<void> showChatNotification({
    required String senderName,
    required String body,
    required String conversationId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final details = _instance._androidDetails(
        channelId: kPushMessagesChannelId,
        channelName: 'Messages',
        channelDescription: 'Chat messages.',
        fullScreenIntent: false,
      );
      await _instance._localNotifications.show(
        _kChatNotificationIdBase + (conversationId.isEmpty ? 0 : conversationId.hashCode % 50000),
        senderName,
        body.isEmpty ? 'Sent you a message' : body,
        NotificationDetails(
          android: details,
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            sound: kIosChatReceiveAlertSound,
            presentBanner: true,
            presentList: true,
          ),
        ),
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
        NotificationDetails(
          android: details,
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            sound: kIosPushNotificationSound,
            presentBanner: true,
            presentList: true,
          ),
        ),
        payload: _encodePayload(payload),
      );
    } catch (e) {
      debugPrint('showGeneralNotification failed: $e');
    }
  }

  /// Initializes the local-notification plugin inside the BACKGROUND isolate.
  /// flutter_local_notifications requires initialize() per isolate; without
  /// this, show/cancel from firebaseMessagingBackgroundHandler silently fail
  /// (which is exactly why data-only pushes previously showed nothing).
  static Future<void> ensureBackgroundInitialized() async {
    try {
      const androidInit = AndroidInitializationSettings('ic_notification');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
        requestCriticalPermission: false,
      );
      await _instance._localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: darwinInit),
        // Action buttons pressed while the app is dead land here — the
        // main-isolate handler is NOT registered in this isolate.
        onDidReceiveBackgroundNotificationResponse:
            backgroundNotificationActionHandler,
      );
      await _ensureAndroidChannels();
    } catch (e) {
      debugPrint('ensureBackgroundInitialized failed: $e');
    }
  }

  /// POST /calls/push-ack — delivery receipt for an incoming-call push.
  /// Works from BOTH isolates (background handler + foreground stream): it is
  /// what cancels the backend's 8s escalation to a visible tray notification
  /// (OEM launchers drop data-only FCM messages while the app is swiped away,
  /// and FCM still reports those as delivered — the ack is the only way the
  /// server knows the rich ring actually rendered). Fire-and-forget, never
  /// throws; must stay STATIC so the background isolate can call it.
  static Future<void> acknowledgeCallPush(Map<String, dynamic> data) async {
    try {
      final callId = (data['callId'] ?? data['callID'] ?? data['call_id'] ?? data['id'] ?? '')
          .toString();
      if (callId.isEmpty) return;
      await ApiService().acknowledgeCallPush(callId);
    } catch (_) {
      // Never fail a notification render because of an ack.
    }
  }

  /// Extracts the call id from a decoded call push payload (every key
  /// spelling the backend has ever used).
  static String _callIdFromPayloadMap(Map<String, dynamic> data) {
    return (data['callId'] ?? data['callID'] ?? data['call_id'] ?? data['id'] ?? '')
        .toString();
  }

  /// Fire-and-forget REST reject — works from BOTH isolates even when the
  /// app-side socket is dead (that is the whole point of the Decline
  /// notification action). Never throws.
  static Future<void> _safeRejectCall(String callId) async {
    try {
      await ApiService().rejectCall(callId);
    } catch (_) {}
  }

  /// Persists an incoming-call payload under [kPendingIncomingCallPrefKey]
  /// so main.dart can re-present the ring after the auth flow completes
  /// (accept-from-notification on a cold start). Safe in any isolate.
  static Future<void> persistPendingIncomingCall(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPendingIncomingCallPrefKey, jsonEncode(payload));
    } catch (_) {
      // Never fail a notification action because of storage.
    }
  }

  /// Main-isolate handler for the notification ACTION BUTTONS (Accept /
  /// Decline) while the app process is alive. Mirrors the background
  /// isolate handler below.
  void _handleCallNotificationAction(String actionId, String? payload) {
    try {
      final data = _decodePayload(payload);
      final callId = _callIdFromPayloadMap(data);
      if (actionId == kCallActionDecline) {
        // REST reject (socket may be mid-reconnect) + clear the ring.
        if (callId.isNotEmpty) {
          unawaited(_safeRejectCall(callId));
        }
        unawaited(cancelCallNotification());
        // Stop any in-app ringing overlay for this call too.
        callCancelledHook?.call(callId);
        return;
      }
      if (actionId == kCallActionAccept) {
        // Park the payload FIRST (if the user must re-authenticate, the
        // main.dart post-login hook re-presents the call), then show the
        // WhatsApp-style Accept/Decline overlay immediately.
        if (callId.isNotEmpty) {
          unawaited(persistPendingIncomingCall(data));
        }
        unawaited(cancelCallNotification());
        _presentIncomingCall(data);
      }
      // Anything else: no-op (plain taps fall through to _handleNotificationTap).
    } catch (e) {
      debugPrint('_handleCallNotificationAction failed: $e');
    }
  }

  /// Creates the notification channels if missing. Split out so BOTH the main
  /// isolate and the background isolate guarantee a fresh install's first
  /// background push lands in an existing channel.
  static Future<void> _ensureAndroidChannels() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final androidPlugin = _instance._localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin == null) return;
      // "calls": max importance + ringtone + alarm audio usage so it rings
      // while the device is locked. (The resource lookup happens by name at
      // play time, so replacing call_ringtone.wav with call_ringtone.mp3
      // updates EXISTING installs too.)
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
      // "messages": chat pushes — user-supplied chat-receive alert.
      const messagesChannel = AndroidNotificationChannel(
        kPushMessagesChannelId,
        'Messages',
        description: 'Chat messages.',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_kChatReceiveAlertResource),
        enableVibration: true,
        showBadge: true,
      );
      // "general-v2": every non-call non-chat push — user-supplied push sound.
      const generalChannel = AndroidNotificationChannel(
        kPushGeneralChannelId,
        'General notifications',
        description: 'Meeting invites, alerts and account updates.',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_kPushNotificationResource),
        enableVibration: true,
        showBadge: true,
      );
      // Legacy "general" (pre-sound-revamp): still created so pushes from a
      // not-yet-updated backend land somewhere instead of vanishing.
      const legacyGeneralChannel = AndroidNotificationChannel(
        kPushLegacyGeneralChannelId,
        'General notifications',
        description: 'Messages, alerts and account updates.',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      await androidPlugin.createNotificationChannel(callChannel);
      await androidPlugin.createNotificationChannel(messagesChannel);
      await androidPlugin.createNotificationChannel(generalChannel);
      await androidPlugin.createNotificationChannel(legacyGeneralChannel);
    } catch (_) {}
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
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    try {
      final data = message.data;
      final type = _normalizePushType(data['type']);
      switch (type) {
        case 'incoming_call':
          // iOS hybrid pushes carry an aps.alert: the SYSTEM already posted
          // a banner — never stack a local notification on top of it.
          final systemShowed = message.notification != null;
          final alreadyRinging = foregroundCallGuard?.call() ?? false;
          // DUPLICATE-DELIVERY GUARD: the server retries failed deliveries,
          // so a data-only push can arrive while the socket ring for the
          // SAME call is already active. Ignore it entirely — re-presenting
          // would reset the 45s ring timeout and restart the ringtone
          // mid-ring. (Pushes without a usable callId fall through to the
          // pre-existing guards below.)
          if (alreadyRinging) {
            final pushCallId = (data['callId'] ??
                    data['callID'] ??
                    data['call_id'] ??
                    data['id'] ??
                    '')
                .toString();
            final ringingCallId = currentRingingCallId?.call();
            if (pushCallId.isNotEmpty &&
                ringingCallId != null &&
                ringingCallId.isNotEmpty &&
                pushCallId == ringingCallId) {
              // The socket ring for THIS call is up — the call is surfaced,
              // so the delivery receipt is valid now (render first, ack after).
              unawaited(acknowledgeCallPush(data));
              break;
            }
          }
          if (alreadyRinging && !systemShowed) {
            // The in-app incoming-call overlay is already ringing (socket
            // path): surface the tray banner as well so a swipe-down still
            // shows the call.
            final rendered = await showCallNotification(
              callerName: (data['caller_name'] ?? data['callerName'] ?? data['callerId'] ?? 'Incoming call').toString(),
              callType: (data['call_type'] ?? data['callType'] ?? 'video').toString(),
              payload: Map<String, dynamic>.from(data),
            );
            if (rendered) unawaited(acknowledgeCallPush(data));
          } else {
            // Push-only delivery: present the global overlay + ring INSTEAD
            // of a tray notification. The old order (post the notification,
            // then _presentIncomingCall cancelled it right away) is exactly
            // the "I hear the ring but nothing shows in the tray" bug.
            _presentIncomingCall(Map<String, dynamic>.from(data));
            AppFeedback.startRingtone();
            // The overlay IS the render — receipt valid.
            unawaited(acknowledgeCallPush(data));
          }
          break;
        case 'missed_call':
          final caller = (data['caller_name'] ?? data['callerName'] ?? data['callerId'] ?? '').toString();
          final callType = (data['call_type'] ?? data['callType'] ?? 'audio').toString();
          // The call is gone — stop any in-app ring and clear the ringing
          // overlay + the full-screen call notification.
          AppFeedback.stopRingtone();
          dismissIncomingCallHook?.call();
          unawaited(cancelCallNotification());
          if (message.notification == null) {
            // System banner already shown for iOS hybrid pushes.
            showGeneralNotification(
              title: 'Missed ${callType == 'video' ? 'video' : 'audio'} call',
              body: caller.isEmpty ? 'You missed a call' : 'Missed call from $caller',
              payload: Map<String, dynamic>.from(data),
            );
          }
          AppBadgeService.instance.addUnread(
            exact: int.tryParse((data['badge'] ?? '').toString()),
          );
          break;
        case 'call_cancelled':
          // SILENT cleanup for "caller hung up while we were still ringing":
          // stop the ring, clear the in-app overlay (only if THIS call is the
          // one ringing) and kill the full-screen notification. No banner.
          AppFeedback.stopRingtone();
          unawaited(cancelCallNotification());
          callCancelledHook?.call(
            (data['callId'] ?? data['call_id'] ?? data['id'] ?? '').toString(),
          );
          break;
        case 'chat_message':
          // ANDROID FOREGROUND FIX: FCM does NOT auto-display notification
          // payloads while the app is FOREGROUNDED — the old
          // `notification == null` skip silently dropped every chat message
          // that arrived as a hybrid push while the app was open. On Android
          // ALWAYS render the local notification (flutter_local_notifications
          // dedupes via stable per-conversation ids); on iOS the hybrid
          // push's aps.alert IS displayed by the system, so the skip stays.
          final systemShowedChat = message.notification != null;
          if (!(systemShowedChat && !Platform.isAndroid)) {
            showChatNotification(
              senderName: (data['sender_name'] ?? data['senderName'] ?? 'New message').toString(),
              body: (data['message'] ?? '').toString(),
              conversationId: (data['conversation_id'] ?? data['conversationId'] ?? '').toString(),
              payload: Map<String, dynamic>.from(data),
            );
          }
          // Launcher badge (Facebook-style) — see the background handler.
          AppBadgeService.instance.addUnread(
            exact: int.tryParse((data['badge'] ?? '').toString()),
          );
          break;
        default:
          // ANDROID FOREGROUND FIX (same as chat_message): FCM does not
          // display notification payloads in the foreground on Android, so
          // the local notification must fire there unconditionally or the
          // push is silently lost. iOS keeps the original skip — the system
          // already displayed the aps.alert.
          final systemShowedDefault = message.notification != null;
          if (systemShowedDefault && !Platform.isAndroid) {
            break; // FCM already displayed it (iOS)
          }
          showGeneralNotification(
            title: message.notification?.title ?? (data['title'] ?? 'Metricorex'),
            body: message.notification?.body ?? (data['body'] ?? ''),
            payload: Map<String, dynamic>.from(data),
          );
          // Count it on the launcher badge too.
          AppBadgeService.instance.addUnread(
            exact: int.tryParse((data['badge'] ?? '').toString()),
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
          _navigate(_tabCalls);
          break;
        case 'transaction':
          // Transfer reversals / payment alerts — land on the transfers list
          // where the referenced transaction (and its reversal) is visible.
          // PUSH: detail-style screen, back must return to the app.
          _push('/main/transfers');
          break;
        case 'chat_message':
          // Deep-link into the EXACT conversation (not just the chat list).
          try {
            final conversationId =
                (data['conversation_id'] ?? data['conversationId'] ?? '').toString();
            if (conversationId.isNotEmpty) {
              ChatDetailScreen.pendingOpenConversationId = conversationId;
            }
          } catch (_) {}
          _navigate(_tabChat);
          break;
        case 'meeting':
        case 'meeting_invite':
          _navigate(_tabMeetings);
          break;
        case 'invoice':
          _push('/main/invoices');
          break;
        case 'subscription':
          _push('/main/subscription');
          break;
        case 'task':
        case 'assignment':
          _push('/main/board');
          break;
        case 'credit':
        case 'debit':
        case 'reversal':
        case 'transfer':
          // Wallet money movement — the transfers screen is the mobile
          // transaction history (mirrors the in-app notifications map).
          _push('/main/transfers');
          break;
        case 'chat':
        case 'chat_new':
          _navigate(_tabChat);
          break;
        case 'kyc':
        case 'business_kyc':
        case 'kyc_approved':
        case 'kyc_rejected':
          // Business-KYC upgrade wizard (dashboard banner deep link).
          _push('/business-kyc-upgrade');
          break;
        case 'chat_invite':
        case 'group_invite':
        case 'chat_join':
          // Group invite link tap → join-by-code once the chat list lands.
          try {
            final code =
                (data['code'] ?? data['inviteCode'] ?? '').toString();
            if (code.isNotEmpty) {
              ChatDetailScreen.pendingChatJoinCode = code;
            }
          } catch (_) {}
          _navigate(_tabChat);
          break;
        default:
          // GENERIC ESCAPE HATCH: a payload-declared route/actionUrl/screen
          // is honoured for unknown push types, so future backend pushes
          // deep-link without waiting for a client release.
          final route =
              (data['route'] ?? data['actionUrl'] ?? data['screen'] ?? '')
                  .toString();
          if (route.startsWith('/')) {
            _push(route);
            return;
          }
          _push('/main/notifications');
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

  /// PUSH (stack-preserving) navigation for DETAIL screens: the previous
  /// screen stays underneath so the system/page back button always works.
  /// TAB targets use [_navigate] (go) instead — tabs are roots, and go()
  /// guarantees the MainScreen SHELL (bottom bar) is present.
  void _push(String location) {
    try {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      GoRouter.of(context).push(location);
    } catch (e) {
      debugPrint('Push navigation failed: $e');
    }
  }

  /// MainScreen tab indexes (lib/screens/main_screen.dart `_pages`).
  /// Deep links MUST go through `/main?tab=N` — a `go('/main/<child>')`
  /// renders the bare child route WITHOUT the MainScreen shell (no bottom
  /// bar, no back), which left notification-tap users stuck on a shell-less
  /// screen.
  static const String _tabHome = '/main?tab=0';
  static const String _tabTasks = '/main?tab=1';
  static const String _tabChat = '/main?tab=2';
  static const String _tabMeetings = '/main?tab=3';
  static const String _tabCalls = '/main?tab=4';
  static const String _tabWallet = '/main?tab=5';

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
  /// Static so the background isolate (firebaseMessagingBackgroundHandler)
  /// can use it via [PushNotificationService.cancelCallNotification].
  static Future<void> cancelCallNotification() async {
    try {
      await _instance._localNotifications.cancel(_kCallNotificationId);
    } catch (_) {}
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
  }
}
