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
      AppFeedback.stopRingtone();
    });

    return IncomingCallState();
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
    // Someone accepted (or the caller's own accept echo came back) —
    // stop ringing and drop the dialog.
    if (_matchesCurrentCall(data)) {
      _ringTimeout?.cancel();
      AppFeedback.stopRingtone();
      state = IncomingCallState();
    }
  }

  void _handleCallRejected(dynamic data) {
    if (_matchesCurrentCall(data)) {
      _ringTimeout?.cancel();
      AppFeedback.stopRingtone();
      state = IncomingCallState();
    }
  }

  void _handleCallEnded(dynamic data) {
    if (_matchesCurrentCall(data)) {
      _ringTimeout?.cancel();
      AppFeedback.stopRingtone();
      state = IncomingCallState();
    }
  }

  /// Accept the incoming call. Emits `call:accept`, clears the ringing state
  /// immediately (so the overlay disappears), and best-effort marks the
  /// participant as joined via REST. Never throws — navigation continues
  /// regardless of REST failures.
  Future<void> acceptCall(Call call) async {
    _ringTimeout?.cancel();
    AppFeedback.stopRingtone();
    try {
      _socketService.emitCallAccept({'callId': call.id});
    } catch (e) {
      debugPrint('Error emitting call accept: $e');
    }
    state = IncomingCallState();
    try {
      await _apiService.joinCall(call.id);
    } catch (e) {
      // Non-fatal: the participant may not exist in call_participants yet;
      // the socket room join + mediasoup flow do not depend on this.
      debugPrint('Non-fatal: REST joinCall failed while accepting: $e');
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
