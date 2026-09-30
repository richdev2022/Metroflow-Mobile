import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/socket_service.dart';
import '../services/api.dart';
import '../models/call.dart';
import '../utils/app_feedback.dart';

class IncomingCallState {
  final Call? call;
  final String? fromUserName;
  final bool isRinging;

  IncomingCallState({
    this.call,
    this.fromUserName,
    this.isRinging = false,
  });

  IncomingCallState copyWith({
    Call? call,
    String? fromUserName,
    bool? isRinging,
  }) {
    return IncomingCallState(
      call: call ?? this.call,
      fromUserName: fromUserName ?? this.fromUserName,
      isRinging: isRinging ?? this.isRinging,
    );
  }
}

final callProvider = NotifierProvider<CallNotifier, IncomingCallState>(CallNotifier.new);

class CallNotifier extends Notifier<IncomingCallState> {
  final SocketService _socketService = SocketService();
  final ApiService _apiService = ApiService();
  Timer? _ringTimeout;

  /// The call WE are dialing out (ringback playing). Used to stop the
  /// ringback on call:accepted / call:rejected / call:ended without touching
  /// the incoming-ring state.
  String? _outboundCallId;
  Timer? _outboundRingTimeout;

  @override
  IncomingCallState build() {
    // Set up socket listeners
    _socketService.onCallInvite = _handleIncomingCall;
    _socketService.onCallAccepted = _handleCallAccepted;
    _socketService.onCallRejected = _handleCallRejected;
    _socketService.onCallEnded = _handleCallEnded;

    ref.onDispose(() {
      _ringTimeout?.cancel();
      _ringTimeout = null;
      _outboundRingTimeout?.cancel();
      _outboundRingTimeout = null;
      AppFeedback.stopRingtone();
      AppFeedback.stopRingback();
    });

    return IncomingCallState();
  }

  // -------------------------------------------------------------------------
  // Outbound ringback (dialing screen calls this right after creating a call)
  // -------------------------------------------------------------------------

  /// Play the ringback loop while waiting for the callee to accept an
  /// OUTBOUND call. Stopped automatically when that call is accepted,
  /// rejected or ended (see the socket handlers below), and by
  /// [stopOutboundRing] when the dialer closes the call screen.
  void startOutboundRing(String callId) {
    _outboundCallId = callId;
    AppFeedback.startRingback();
    // Safety: never ring back forever — auto-silence after 90s.
    _outboundRingTimeout?.cancel();
    _outboundRingTimeout = Timer(const Duration(seconds: 90), stopOutboundRing);
  }

  void stopOutboundRing() {
    _outboundRingTimeout?.cancel();
    _outboundRingTimeout = null;
    _outboundCallId = null;
    AppFeedback.stopRingback();
  }

  static String? _callIdFromPayload(dynamic data) {
    if (data is Map) return (data['callId'] ?? data['callID'] ?? '').toString();
    if (data is String) return data;
    return null;
  }

  /// Build a Call from the flat `call:incoming` socket payload.
  ///
  /// The backend sends `{ callId, callCode, roomId, from, callerName, type, ... }`
  /// — there is no `id` key, so feeding the payload straight into
  /// Call.fromJson produced a call with an EMPTY id: accept/reject emitted
  /// `callId: ''` and joining hit `POST /calls//join` (404). Every incoming
  /// call was unjoinable/unrejectable.
  Call _callFromInvitePayload(Map<String, dynamic> callData) {
    final callId = (callData['callId'] ?? callData['id'] ?? callData['roomId'] ?? '').toString();
    final callCode = (callData['callCode'] ?? callData['call_code'] ?? callId).toString();
    // Fall back to the full call object shape (REST-delivered events).
    if (callData['id'] != null && callData['participants'] is List) {
      return Call.fromJson(callData);
    }
    return Call.fromJson({
      'id': callId,
      'callCode': callCode,
      'type': callData['type'] ?? 'video',
      'status': 'ongoing',
      'isGroupCall': callData['isGroupCall'] ?? false,
      'waitingRoomEnabled': callData['waitingRoomEnabled'] ?? false,
      'recordingEnabled': callData['recordingEnabled'] ?? false,
      'hasPassword': callData['hasPassword'],
      'maxParticipants': callData['maxParticipants'] ?? 10,
    });
  }

  void _handleIncomingCall(dynamic data) {
    try {
      final callData = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final call = _callFromInvitePayload(callData);
      // Prefer a human-readable caller name; `from` is a raw user UUID.
      final fromUserName = (callData['callerName'] ?? callData['fromName'] ?? callData['from'] ?? '')
          .toString();

      _ringTimeout?.cancel();
      state = IncomingCallState(
        call: call,
        fromUserName: fromUserName,
        isRinging: true,
      );

      // Audible + haptic ring (no third-party audio package needed)
      AppFeedback.startRingtone();

      // Auto-dismiss after 45s so the dialog can never ring forever.
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (state.isRinging && state.call?.id == call.id) {
          clearIncomingCall();
        }
      });
    } catch (e) {
      debugPrint('Error handling incoming call: $e');
    }
  }

  /// Public entry point for FCM push taps: re-presents the incoming call from
  /// a push payload — e.g. the FCM contract
  /// `{ type:'incoming-call', callId, callType:'audio'|'video', callerName,
  /// callerId, callCode, conversationId? }` or the legacy
  /// `{ type:'incoming_call', call_id, call_code, caller_name, call_type }` —
  /// the same shape the socket `call:incoming` handler receives. Used by
  /// PushNotificationService so tapping the full-screen call notification
  /// shows the Accept/Decline overlay.
  void presentIncomingCall(Map<String, dynamic> payload) {
    final data = Map<String, dynamic>.from(payload);
    // Normalize the FCM payload keys onto the socket payload names.
    data['callId'] ??= data['call_id'];
    data['callCode'] ??= data['call_code'];
    data['callerName'] ??= data['caller_name'];
    // The call type is `callType`/`call_type`; the push `type` discriminator
    // ('incoming-call') must NEVER leak in as the call type.
    final callType = (data['callType'] ?? data['call_type'])?.toString();
    data['type'] = (callType == 'audio' || callType == 'video')
        ? callType
        : 'video';
    _handleIncomingCall(data);
  }

  bool _matchesCurrentCall(dynamic data) {
    final current = state.call;
    if (current == null) return false;
    if (data is Map) {
      final callId = (data['callId'] ?? data['callID'] ?? '').toString();
      if (callId.isNotEmpty) return callId == current.id;
    }
    if (data is String && data.isNotEmpty) return data == current.id;
    return false;
  }

  void _handleCallAccepted(dynamic data) {
    // Outbound: the callee accepted OUR call — drop the ringback.
    final acceptedCallId = _callIdFromPayload(data);
    if (_outboundCallId != null && acceptedCallId == _outboundCallId) {
      stopOutboundRing();
    }

    // Incoming: someone accepted (or the caller's own accept echo came back) —
    // stop ringing and drop the dialog.
    if (_matchesCurrentCall(data)) {
      _ringTimeout?.cancel();
      AppFeedback.stopRingtone();
      state = IncomingCallState();
    }
  }

  void _handleCallRejected(dynamic data) {
    // Outbound: the callee declined — stop the ringback.
    final rejectedCallId = _callIdFromPayload(data);
    if (_outboundCallId != null && rejectedCallId == _outboundCallId) {
      stopOutboundRing();
    }

    if (_matchesCurrentCall(data)) {
      _ringTimeout?.cancel();
      AppFeedback.stopRingtone();
      state = IncomingCallState();
    }
  }

  void _handleCallEnded(dynamic data) {
    // Outbound: the call we were dialing was ended before we joined.
    final endedCallId = _callIdFromPayload(data);
    if (_outboundCallId != null && endedCallId == _outboundCallId) {
      stopOutboundRing();
    }

    // IMPORTANT: only act on the RINGING state here. Once the user has
    // accepted and entered the room, VideoCallScreen owns the `call:ended`
    // UX (it registers its own handler that tears the mediasoup room down);
    // wiping provider state here would double-handle the event and fight
    // with the screen. While ringing (no screen mounted), an ended call is a
    // missed call: stop the ring, blip, and clear the dialog.
    if (!state.isRinging) return;
    if (!_matchesCurrentCall(data)) return;
    _ringTimeout?.cancel();
    AppFeedback.stopRingtone();
    AppFeedback.playCallEndedSound();
    state = IncomingCallState();
  }

  /// Accept the incoming call. Emits `call:accept`, clears the ringing state
  /// immediately (so the overlay disappears), and best-effort marks the
  /// participant as joined via REST. Never throws — navigation continues
  /// regardless of REST failures.
  ///
  /// Returns the provider credentials attached to the join response (when the
  /// backend routes the room through its secondary provider), null otherwise.
  Future<Map<String, dynamic>?> acceptCall(Call call) async {
    _ringTimeout?.cancel();
    AppFeedback.stopRingtone();
    try {
      _socketService.emitCallAccept({'callId': call.id});
    } catch (e) {
      debugPrint('Error emitting call accept: $e');
    }
    state = IncomingCallState();
    try {
      final response = await _apiService.joinCall(call.id);
      final data = response.data['data'];
      final calling = data is Map ? data['calling'] : null;
      return calling is Map ? Map<String, dynamic>.from(calling) : null;
    } catch (e) {
      // Non-fatal: the participant may not exist in call_participants yet;
      // the socket room join + media flow do not depend on this.
      debugPrint('Non-fatal: REST joinCall failed while accepting: $e');
      return null;
    }
  }

  Future<void> rejectCall(Call call) async {
    _ringTimeout?.cancel();
    AppFeedback.stopRingtone();
    try {
      _socketService.emitCallReject({'callId': call.id});
    } catch (e) {
      debugPrint('Error emitting call reject: $e');
    }
    state = IncomingCallState();
  }

  void clearIncomingCall() {
    _ringTimeout?.cancel();
    AppFeedback.stopRingtone();
    state = IncomingCallState();
  }
}
