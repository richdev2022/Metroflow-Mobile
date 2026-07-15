import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/socket_service.dart';
import '../services/api.dart';
import '../models/call.dart';

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

  @override
  IncomingCallState build() {
    // Set up socket listeners
    _socketService.onCallInvite = _handleIncomingCall;
    _socketService.onCallAccepted = _handleCallAccepted;
    _socketService.onCallRejected = _handleCallRejected;
    _socketService.onCallEnded = _handleCallEnded;

    return IncomingCallState();
  }

  void _handleIncomingCall(dynamic data) {
    try {
      final callData = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final call = Call.fromJson(callData);
      final fromUserName = callData['from'] as String?;
      
      state = IncomingCallState(
        call: call,
        fromUserName: fromUserName,
        isRinging: true,
      );
    } catch (e) {
      debugPrint('Error handling incoming call: $e');
    }
  }

  void _handleCallAccepted(dynamic data) {
    if (state.call?.id == (data is Map ? data['callId'] : data)) {
      state = IncomingCallState();
    }
  }

  void _handleCallRejected(dynamic data) {
    if (state.call?.id == (data is Map ? data['callId'] : data)) {
      state = IncomingCallState();
    }
  }

  void _handleCallEnded(dynamic data) {
    if (state.call?.id == (data is Map ? data['callId'] : data)) {
      state = IncomingCallState();
    }
  }

  Future<void> acceptCall(Call call) async {
    try {
      _socketService.emitCallAccept({'callId': call.id});
      
      // Join the call
      final response = await _apiService.joinCall(call.id);
      if (response.data['success'] == true) {
        state = IncomingCallState();
      }
    } catch (e) {
      debugPrint('Error accepting call: $e');
    }
  }

  Future<void> rejectCall(Call call) async {
    try {
      _socketService.emitCallReject({'callId': call.id});
      state = IncomingCallState();
    } catch (e) {
      debugPrint('Error rejecting call: $e');
    }
  }

  void clearIncomingCall() {
    state = IncomingCallState();
  }
}
