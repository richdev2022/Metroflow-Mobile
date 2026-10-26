import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show navigatorKey;
import '../models/call.dart';
import '../providers/call_provider.dart';
import '../screens/video_call_screen.dart';
import '../services/api.dart';
import '../services/push_notification_service.dart'
    show kPendingIncomingCallPrefKey;
import '../utils/app_toast.dart';

/// iOS CallKit + PushKit bridge.
///
/// Native (AppDelegate.swift) reports four things over the
/// `metricorex/callkit` channel:
///   onVoipToken    — the PushKit VoIP token (rotates on reinstall/refresh)
///   onIncomingCall — a VoIP push arrived (the backend is ringing this device)
///   onAnswered     — the user tapped Answer on the NATIVE CallKit screen
///   onDeclined     — the user tapped Decline on the native screen
///
/// Dart drives:
///   register-device({voip_token}) — so the backend can send VoIP pushes
///   endCall({callId})             — clears the native ring when the in-app
///                                   UI accepted/declined/ended the same call
///
/// Without CallKit an incoming call on iOS can only ever be a banner in the
/// notification panel; with it the callee gets the full-screen native ring
/// (Answer/Decline, lock screen included) exactly like WhatsApp.
class CallKitService {
  CallKitService._();
  static final CallKitService instance = CallKitService._();

  static const MethodChannel _channel = MethodChannel('metricorex/callkit');
  static bool _initialized = false;
  static bool? _channelAvailable;

  static const String _kVoipTokenPref = 'voip_token';
  static const String _kVoipRegisteredPref = 'voip_token_registered';

  /// callId -> the native CallKit call UUID string (tracked so [endCall] can
  /// target the right CXCallAction and the in-app flow can check ownership).
  final Map<String, String> _uuidByCallId = <String, String>{};

  /// Payload of the call the native ring is currently presenting (kept from
  /// onIncomingCall so a cold-start Answer still knows what to join).
  Map<String, dynamic>? _activePayload;

  /// Whether the native CallKit ring is CURRENTLY up for [callId].
  bool isOwningCall(String? callId) =>
      callId != null && callId.isNotEmpty && _uuidByCallId.containsKey(callId);

  Future<void> init() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && !_initialized) {
      _initialized = true;
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onVoipToken':
          final token = (call.arguments as Map?)?['token']?.toString() ?? '';
          if (token.isNotEmpty) await _onVoipToken(token);
          break;
        case 'onVoipTokenInvalidated':
          await _prefs((p) async {
            await p.remove(_kVoipTokenPref);
            await p.remove(_kVoipRegisteredPref);
          });
          break;
        case 'onIncomingCall':
          final payload = Map<String, dynamic>.from((call.arguments as Map?) ?? {});
          _onIncomingCall(payload);
          break;
        case 'onAnswered':
          await _onAnswered();
          break;
        case 'onDeclined':
          await _onDeclined();
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('CallKitService.${call.method} failed: $e');
    }
  }

  Future<void> _prefs(Future<void> Function(SharedPreferences) fn) async {
    try {
      await fn(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // VoIP token registration
  // ---------------------------------------------------------------------------
  Future<void> _onVoipToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kVoipTokenPref, token);
      await ApiService().registerDevice(
        fcmToken: '', // empty — voip-only registration (backend accepts it)
        platform: 'ios',
        voipToken: token,
      );
      await prefs.setString(_kVoipRegisteredPref, token);
      debugPrint('CallKitService: voip token registered (${token.substring(0, 12)}…)');
    } catch (e) {
      // Not signed in yet (401) — the token is stashed in prefs and
      // [registerPendingVoipToken] sends it right after the next login.
      debugPrint('CallKitService: voip token registration deferred ($e)');
    }
  }

  /// Called from main.dart after a successful login/register.
  Future<void> registerPendingVoipToken() async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_kVoipTokenPref);
      final registered = prefs.getString(_kVoipRegisteredPref);
      if (token != null && token.isNotEmpty && token != registered) {
        await _onVoipToken(token);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Incoming VoIP push (native ring is now up)
  // ---------------------------------------------------------------------------
  void _onIncomingCall(Map<String, dynamic> payload) {
    final callId = (payload['callId'] ?? payload['call_id'] ?? '').toString();
    final uuid = (payload['callUuid'] ?? payload['callUUID'] ?? '').toString();
    if (callId.isNotEmpty && uuid.isNotEmpty) {
      _uuidByCallId[callId] = uuid;
    }
    _activePayload = payload;
    // call_provider checks [isOwningCall] and suppresses the in-app overlay +
    // ringtone while the native ring owns the call (no double-ring UIs).
    // Payload keys arrive in the FCM/voip shape — normalize for later use.
    payload['callId'] ??= payload['call_id'];
    payload['callCode'] ??= payload['call_code'];
    payload['callerName'] ??= payload['caller_name'];
    payload['callType'] ??= payload['call_type'];
  }

  /// Best-effort re-presentation of the ringing state from a VoIP payload —
  /// used on cold start where the socket never delivered `call:incoming`.
  void presentRingingState(WidgetRef ref) {
    final payload = _activePayload;
    if (payload == null) return;
    ref.read(callProvider.notifier).presentIncomingCall(payload);
  }

  // ---------------------------------------------------------------------------
  // Native Answer / Decline
  // ---------------------------------------------------------------------------
  Future<void> _onAnswered() async {
    final ctx = navigatorKey.currentContext;
    final container = ctx != null ? ProviderScope.containerOf(ctx, listen: false) : null;
    var call = container?.read(callProvider).call;
    var callerName =
        container?.read(callProvider).fromUserName ?? 'Unknown Caller';

    if (call == null) {
      // Cold start: ring state not (yet) present. Rebuild it from the last
      // VoIP payload; if we never saw one, fall back to the parked payload.
      Map<String, dynamic>? payload = _activePayload;
      if (payload == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString(kPendingIncomingCallPrefKey);
          if (raw != null && raw.isNotEmpty) {
            final decoded = jsonDecode(raw);
            if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
      if (payload == null || (payload['callId'] ?? '').toString().isEmpty) {
        // Nothing joinable — end the native call so it doesn't ring forever.
        await _endAllNativeCalls(answered: true);
        return;
      }
      payload['callId'] ??= payload['call_id'];
      payload['callCode'] ??= payload['call_code'];
      payload['callerName'] ??= payload['caller_name'];
      payload['type'] = payload['callType'] ?? payload['call_type'] ?? 'video';
      call = Call.fromJson({
        'id': payload['callId'],
        'callCode': payload['callCode'] ?? payload['callId'],
        'type': (payload['callType'] ?? payload['call_type'] ?? 'video').toString(),
        'status': 'ongoing',
        'isGroupCall': payload['isGroupCall'] == true || payload['isGroupCall'] == '1',
      });
      callerName = (payload['callerName'] ?? 'Unknown Caller').toString();
    }

    Map<String, dynamic>? calling;
    try {
      calling = await container?.read(callProvider.notifier).acceptCall(call);
    } catch (e) {
      debugPrint('CallKit accept: acceptCall failed (non-fatal): $e');
    }

    // Clear the native ring bookkeeping — the call is being answered in-app.
    for (final id in _uuidByCallId.keys.toList()) {
      if (id == call.id || _uuidByCallId.length == 1) {
        _uuidByCallId.remove(id);
      }
    }
    _activePayload = null;

    final navCtx = navigatorKey.currentContext;
    if (navCtx == null || !navCtx.mounted) return;
    try {
      await VideoCallScreen.showModal(
        context: navCtx,
        roomId: call.id,
        title: '${call.type == 'audio' ? 'Audio' : 'Video'} Call with $callerName',
        isMeeting: false,
        enableVideo: call.type == 'video',
        isHost: false,
        // REDIAL FIX: REST leave fallback — CallKit-answer entry points had no
        // onLeave, so when the socket is down at hangup the call:leave emit is
        // silently dropped and the call row stays 'ongoing' forever (phantom
        // Join card + "cannot call again" until the server reaper runs).
        onLeave: () async {
          try {
            await ApiService().leaveCall(call.id);
          } catch (_) {}
        },
        calling: calling,
      );
    } catch (e) {
      debugPrint('CallKit accept: open call screen failed: $e');
      AppToast.show('Could not open the call', type: AppToastType.error);
    }
  }

  Future<void> _onDeclined() async {
    final ctx = navigatorKey.currentContext;
    final container = ctx != null ? ProviderScope.containerOf(ctx, listen: false) : null;
    final state = container?.read(callProvider);
    final call = state?.call;
    final payload = _activePayload;
    _uuidByCallId.clear();
    _activePayload = null;
    if (call != null) {
      try {
        await container?.read(callProvider.notifier).rejectCall(call);
      } catch (_) {}
    } else if (payload != null) {
      // No live ring state (cold start) — reject via REST so the caller does
      // not ring until timeout.
      try {
        final callId = (payload['callId'] ?? payload['call_id'] ?? '').toString();
        if (callId.isNotEmpty) {
          await ApiService().rejectCall(callId);
        }
      } catch (_) {}
    }
  }

  Future<void> _endAllNativeCalls({required bool answered}) async {
    for (final callId in _uuidByCallId.keys.toList()) {
      await endCall(callId: callId, answered: answered);
    }
  }

  /// End the native CallKit ring for [callId] (or everything when [callId] is
  /// null). Called from the in-app accept/decline/hang-up paths so the native
  /// screen never lingers beside the Flutter one.
  Future<void> endCall({String? callId, bool answered = true}) async {
    final targets = callId == null || callId.isEmpty
        ? _uuidByCallId.keys.toList()
        : (_uuidByCallId.containsKey(callId) ? [callId] : <String>[]);
    for (final id in targets) {
      _uuidByCallId.remove(id);
    }
    if (targets.isEmpty) return;
    try {
      if (_channelAvailable != false) {
        await _channel.invokeMethod(
          'endCall',
          {'callId': targets.first, 'answered': answered},
        );
        _channelAvailable = true;
      }
    } on MissingPluginException {
      _channelAvailable = false;
    } catch (e) {
      debugPrint('CallKitService.endCall failed: $e');
    }
  }

  /// Convenience used by the call screens / incoming dialog.
  Future<void> endCallIfOwned(String? callId, {bool answered = true}) async {
    if (isOwningCall(callId)) await endCall(callId: callId, answered: answered);
  }
}
