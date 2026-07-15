import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/logger.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  socket_io.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

  String get _socketBaseUrl {
    final configured = dotenv.env['EXPO_PUBLIC_API_BASE_URL'] ?? 'https://metroflow-backend.netlify.app';
    return configured.replaceFirst(RegExp(r'/api/?$'), '');
  }

  // Event callbacks
  void Function(dynamic)? onMeetingCreated;
  void Function(dynamic)? onMeetingUpdated;
  void Function(dynamic)? onMeetingDeleted;
  void Function(dynamic)? onMeetingParticipantJoined;
  void Function(dynamic)? onMeetingParticipantLeft;
  void Function(dynamic)? onMeetingEnded;
  void Function(dynamic)? onConversationCreated;
  void Function(dynamic)? onMessageCreated;
  void Function(dynamic)? onCallCreated;
  void Function(dynamic)? onCallUpdated;
  void Function(dynamic)? onCallInvite;
  void Function(dynamic)? onCallAccepted;
  void Function(dynamic)? onCallRejected;
  void Function(dynamic)? onCallEnded;
  void Function(dynamic)? onCallParticipantJoined;
  void Function(dynamic)? onCallParticipantLeft;
  void Function(dynamic)? onCallDeleted;
  void Function(dynamic)? onUserPresenceUpdated;
  void Function(dynamic)? onMediasoupNewProducer;
  void Function(dynamic)? onRecordingStarted;
  void Function(dynamic)? onRecordingPaused;
  void Function(dynamic)? onRecordingStopped;
  void Function(dynamic)? onScreenShareStarted;
  void Function(dynamic)? onScreenShareStopped;
  void Function(dynamic)? onMeetingChatMessage;

  void connect(String userId, String businessId) {
    if (_socket?.connected == true) return;

    _socket = socket_io.io(_socketBaseUrl, socket_io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .enableReconnection() // Enable auto reconnection
        .setReconnectionDelay(1000) // Initial delay
        .setReconnectionDelayMax(5000) // Max delay
        .setReconnectionAttempts(5) // Max attempts
        .build());

    _socket?.on('connect', (_) {
      Logger.log('Connected to socket');
      _socket?.emit('user-online', [userId, businessId]);

      // Keep alive every 30 seconds
      Future.doWhile(() async {
        await Future.delayed(const Duration(seconds: 30));
        if (_socket?.connected ?? false) {
          _socket?.emit('user-keep-alive', [userId, businessId]);
        }
        return _socket?.connected ?? false;
      });
    });

    _socket?.on('disconnect', (_) {
      Logger.log('Disconnected from socket');
    });

    _socket?.on('reconnect', (_) {
      Logger.log('Reconnected to socket');
      _socket?.emit('user-online', [userId, businessId]);
    });

    _socket?.on('reconnect_attempt', (attempt) {
      Logger.log('Reconnect attempt: $attempt');
    });

    _socket?.on('reconnect_failed', (_) {
      Logger.log('Reconnection failed');
    });

    // Listen to events
    _socket?.on('meeting:created', (data) {
      if (onMeetingCreated != null) onMeetingCreated!(data);
    });

    _socket?.on('meeting:updated', (data) {
      if (onMeetingUpdated != null) onMeetingUpdated!(data);
    });

    _socket?.on('meeting:deleted', (data) {
      if (onMeetingDeleted != null) onMeetingDeleted!(data);
    });

    _socket?.on('meeting:participantJoined', (data) {
      if (onMeetingParticipantJoined != null) onMeetingParticipantJoined!(data);
    });

    _socket?.on('meeting:participantLeft', (data) {
      if (onMeetingParticipantLeft != null) onMeetingParticipantLeft!(data);
    });

    _socket?.on('meeting:ended', (data) {
      if (onMeetingEnded != null) onMeetingEnded!(data);
    });

    _socket?.on('conversation:created', (data) {
      if (onConversationCreated != null) onConversationCreated!(data);
    });

    _socket?.on('message:created', (data) {
      if (onMessageCreated != null) onMessageCreated!(data);
    });

    _socket?.on('call:created', (data) {
      if (onCallCreated != null) onCallCreated!(data);
    });

    _socket?.on('call:updated', (data) {
      if (onCallUpdated != null) onCallUpdated!(data);
    });

    _socket?.on('call:incoming', (data) {
      if (onCallInvite != null) onCallInvite!(data);
    });

    _socket?.on('call:accepted', (data) {
      if (onCallAccepted != null) onCallAccepted!(data);
    });

    _socket?.on('call:rejected', (data) {
      if (onCallRejected != null) onCallRejected!(data);
    });

    _socket?.on('call:ended', (data) {
      if (onCallEnded != null) onCallEnded!(data);
    });

    _socket?.on('call:participantJoined', (data) {
      if (onCallParticipantJoined != null) onCallParticipantJoined!(data);
    });

    _socket?.on('call:participantLeft', (data) {
      if (onCallParticipantLeft != null) onCallParticipantLeft!(data);
    });

    _socket?.on('call:deleted', (data) {
      if (onCallDeleted != null) onCallDeleted!(data);
    });

    _socket?.on('user-presence-updated', (data) {
      if (onUserPresenceUpdated != null) onUserPresenceUpdated!(data);
    });

    _socket?.on('mediasoup:newProducer', (data) {
      if (onMediasoupNewProducer != null) onMediasoupNewProducer!(data);
    });

    _socket?.on('recording:started', (data) {
      if (onRecordingStarted != null) onRecordingStarted!(data);
    });

    _socket?.on('recording:paused', (data) {
      if (onRecordingPaused != null) onRecordingPaused!(data);
    });

    _socket?.on('recording:stopped', (data) {
      if (onRecordingStopped != null) onRecordingStopped!(data);
    });

    _socket?.on('screen-share:started', (data) {
      if (onScreenShareStarted != null) onScreenShareStarted!(data);
    });

    _socket?.on('screen-share:stopped', (data) {
      if (onScreenShareStopped != null) onScreenShareStopped!(data);
    });

    _socket?.on('meeting-chat:message', (data) {
      if (onMeetingChatMessage != null) onMeetingChatMessage!(data);
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  // Emit functions
  void emitUserPresence(String status) {
    _socket?.emit('user-presence', status);
  }

  void emitCallInvite(Map<String, dynamic> data) {
    _socket?.emit('call:invite', data);
  }

  void emitCallAccept(Map<String, dynamic> data) {
    _socket?.emit('call:accept', data);
  }

  void emitCallReject(Map<String, dynamic> data) {
    _socket?.emit('call:reject', data);
  }

  void emitCallEnd(Map<String, dynamic> data) {
    _socket?.emit('call:end', data);
  }

  void emitMeetingJoin(Map<String, dynamic> data) {
    _socket?.emit('meeting:join', data);
  }

  void emitMeetingLeave(Map<String, dynamic> data) {
    _socket?.emit('meeting:leave', data);
  }

  void emitMeetingEnd(Map<String, dynamic> data) {
    _socket?.emit('meeting:end', data);
  }

  void emitMediasoupGetRouterRtpCapabilities(Function(dynamic) callback) {
    _socket?.emitWithAck('mediasoup:getRouterRtpCapabilities', [], ack: callback);
  }

  void emitMediasoupCreateWebRtcTransport(Map<String, dynamic> data, Function(dynamic) callback) {
    _socket?.emitWithAck('mediasoup:createWebRtcTransport', data, ack: callback);
  }

  void emitMediasoupConnectWebRtcTransport(Map<String, dynamic> data, [Function? callback]) {
    if (callback != null) {
      _socket?.emitWithAck('mediasoup:connectWebRtcTransport', data, ack: callback);
    } else {
      _socket?.emit('mediasoup:connectWebRtcTransport', data);
    }
  }

  void emitMediasoupProduce(Map<String, dynamic> data, Function(dynamic) callback) {
    _socket?.emitWithAck('mediasoup:produce', data, ack: callback);
  }

  void emitMediasoupConsume(Map<String, dynamic> data, Function(dynamic) callback) {
    _socket?.emitWithAck('mediasoup:consume', data, ack: callback);
  }

  void emitMediasoupResume(Map<String, dynamic> data, [Function? callback]) {
    if (callback != null) {
      _socket?.emitWithAck('mediasoup:resume', data, ack: callback);
    } else {
      _socket?.emit('mediasoup:resume', data);
    }
  }

  void emitRecordingStart(Map<String, dynamic> data) {
    _socket?.emit('recording:start', data);
  }

  void emitRecordingStop(Map<String, dynamic> data) {
    _socket?.emit('recording:stop', data);
  }

  void emitScreenShareStart(Map<String, dynamic> data) {
    _socket?.emit('screen-share:start', data);
  }

  void emitScreenShareStop(Map<String, dynamic> data) {
    _socket?.emit('screen-share:stop', data);
  }

  void emitMeetingChatMessage(Map<String, dynamic> data) {
    _socket?.emit('meeting-chat:message', data);
  }

  void joinConversation(String conversationId) {
    _socket?.emit('join-conversation', conversationId);
  }

  Future<dynamic> _emitAck(String event, [dynamic data]) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      return Future.error(StateError('Socket is not connected'));
    }

    final completer = Completer<dynamic>();
    socket.emitWithAck(
      event,
      data,
      ack: (response) {
        if (!completer.isCompleted) completer.complete(response);
      },
    );
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException('Socket ack timed out for $event'),
    );
  }

  Future<dynamic> mediasoupGetRouterRtpCapabilities() {
    return _emitAck('mediasoup:getRouterRtpCapabilities', []);
  }

  Future<dynamic> mediasoupCreateWebRtcTransport(Map<String, dynamic> data) {
    return _emitAck('mediasoup:createWebRtcTransport', data);
  }

  Future<dynamic> mediasoupConnectWebRtcTransport(Map<String, dynamic> data) {
    return _emitAck('mediasoup:connectWebRtcTransport', data);
  }

  Future<dynamic> mediasoupProduce(Map<String, dynamic> data) {
    return _emitAck('mediasoup:produce', data);
  }

  Future<dynamic> mediasoupConsume(Map<String, dynamic> data) {
    return _emitAck('mediasoup:consume', data);
  }

  Future<dynamic> mediasoupResume(Map<String, dynamic> data) {
    return _emitAck('mediasoup:resume', data);
  }
}
