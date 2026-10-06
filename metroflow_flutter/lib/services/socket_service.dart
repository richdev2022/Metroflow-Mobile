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

  /// Auth token attached to the socket handshake so the backend can verify
  /// identity server-side (see server/lib/socket.ts).
  String? _authToken;
  String? get authToken => _authToken;

  String get _socketBaseUrl {
    final configured = dotenv.env['EXPO_PUBLIC_API_BASE_URL'] ?? 'https://api.metricorex.com';
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
  /// Batch-4 parity: `message:updated` fires after an edit / delete-for-
  /// everyone; payload is the updated message row (editedAt, content and/or
  /// deletedForEveryone flags).
  void Function(dynamic)? onMessageUpdated;
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
  /// Presence parity (batch 4): `presence:update` { userId, lastSeenAt,
  /// presenceStatus } — carries the last-seen instant the chat header needs
  /// ("last seen today at 19:46"). `lastSeenAt` may be ISO string OR epoch.
  void Function(dynamic)? onPresenceUpdate;
  void Function(dynamic)? onMediasoupNewProducer;
  void Function(dynamic)? onMediasoupProducerClosed;
  void Function(dynamic)? onRecordingStarted;
  void Function(dynamic)? onRecordingPaused;
  void Function(dynamic)? onRecordingStopped;
  void Function(dynamic)? onScreenShareStarted;
  void Function(dynamic)? onScreenShareStopped;
  void Function(dynamic)? onMeetingChatMessage;
  void Function(dynamic)? onNotificationNew;
  void Function(dynamic)? onConversationRead;
  /// Read-receipt rebroadcast for the Teams-style double tick. Two events
  /// carry the same fact (the newer one is fired in addition so old clients
  /// keep working):
  /// - `conversation:read`    { conversationId, userId, lastReadAt }
  /// - `chat:conversation-read` { conversationId, userId, readAt }
  void Function(dynamic)? onChatConversationRead;
  void Function(dynamic)? onChatTyping;
  void Function(dynamic)? onChatStopTyping;
  /// WhatsApp-style typing presence (new pipeline): the server relays
  /// `chat:typing` { conversationId, isTyping } emissions to every OTHER
  /// participant's user room as `chat:typing-updated` with the payload
  /// { conversationId, userId, name, isTyping, ts }. Consumed by the chat
  /// list screen to render per-conversation "typing…" tiles.
  void Function(dynamic)? onChatTypingUpdated;
  void Function(dynamic)? onChatNewMessageNotification;
  void Function(dynamic)? onCallDurationStarted;
  void Function(dynamic)? onCallDurationActive;
  void Function(dynamic)? onCallCountdownWarning;

  /// Live captions relay (provider-agnostic — rides the app socket whether
  /// the room media runs through either provider). Payload:
  /// { roomId, roomType: "call"|"meeting", speakerId, speakerName, text,
  ///   isFinal, language, ts }
  void Function(dynamic)? onCaptionUpdated;

  /// AI meeting notes generated/refreshed after a meeting ends. Payload:
  /// { meetingId, notes }
  void Function(dynamic)? onMeetingNotesUpdated;

  /// Waiting-room results for THIS socket (server unicasts to the waiter):
  /// - `waiting-room:admitted` payload { roomId, meetingId, participantId, userName }
  /// - `waiting-room:denied`  payload { roomId, meetingId, participantId }
  void Function(dynamic)? onWaitingRoomAdmitted;
  void Function(dynamic)? onWaitingRoomDenied;

  /// Server-verified echo-risk alert: the same account joined this room on
  /// 2+ devices (backend counts sockets per room). Payload:
  /// { roomId, userId, userName, deviceCount, message }
  void Function(dynamic)? onCallMultiDevice;

  /// Call-room reactions: someone in `room:{id}` tapped an emoji. Payload:
  /// { emoji, from, fromName, roomId, roomType, ts }. NOTE the emitter's own
  /// socket also receives this broadcast (io.to includes the sender) —
  /// consumers echo-guard their own reactions via `from`.
  void Function(dynamic)? onCallReactionReceived;

  /// Raise-hand state changes in a call room. Payload:
  /// { userId, name, raised, roomId, roomType, ts }.
  void Function(dynamic)? onCallHandUpdated;

  void connect(String userId, String businessId, {String? token}) {
    // A socket in reconnect-limbo (connected == false but not disposed) used to
    // be abandoned here and replaced by a fresh one -> duplicate event delivery
    // (e.g. double incoming-call rings). Tear the old one down first.
    if (_socket != null && _socket?.connected != true) {
      try {
        _socket?.disconnect();
        _socket?.dispose();
      } catch (_) {}
      _socket = null;
    }
    if (_socket?.connected == true) return;

    // Keep/refresh the handshake auth token
    if (token != null && token.isNotEmpty) _authToken = token;

    final optionsBuilder = socket_io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .enableReconnection() // Enable auto reconnection
        .setReconnectionDelay(1000) // Initial delay
        // Back off up to 30s (was capped at 5s/5 attempts — after which the
        // socket silently died and `call:incoming` stopped arriving until the
        // next login, i.e. calls only rang while sitting in the app).
        .setReconnectionDelayMax(30000)
        .setReconnectionAttempts(100000); // effectively always retry

    if (_authToken != null && _authToken!.isNotEmpty) {
      optionsBuilder.setAuth({'token': _authToken});
    }

    _socket = socket_io.io(_socketBaseUrl, optionsBuilder.build());

    _socket?.on('connect', (_) {
      Logger.log('Connected to socket');
      // The Dart socket_io_client emit() takes a SINGLE data argument (three
      // positional args do not compile — release CI proved it), so send the
      // identity as one map. The server normalizes BOTH shapes (the web JS
      // client sends two positional args) and always overrides them with the
      // server-verified handshake identity, and it auto-joins
      // user:{id}/business:{id} on authenticated connect — so personal events
      // (call:accepted etc.) reach this socket either way.
      _socket?.emit('user-online', {'userId': userId, 'businessId': businessId});

      // Keep alive every 30 seconds
      Future.doWhile(() async {
        await Future.delayed(const Duration(seconds: 30));
        if (_socket?.connected ?? false) {
          _socket?.emit('user-keep-alive', {'userId': userId, 'businessId': businessId});
        }
        return _socket?.connected ?? false;
      });
    });

    _socket?.on('disconnect', (_) {
      Logger.log('Disconnected from socket');
    });

    _socket?.on('reconnect', (_) {
      Logger.log('Reconnected to socket');
      _socket?.emit('user-online', {'userId': userId, 'businessId': businessId});
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

    _socket?.on('message:updated', (data) {
      if (onMessageUpdated != null) onMessageUpdated!(data);
    });

    _socket?.on('chat:new-message-notification', (data) {
      if (onChatNewMessageNotification != null) onChatNewMessageNotification!(data);
    });

    _socket?.on('call:duration-started', (data) {
      if (onCallDurationStarted != null) onCallDurationStarted!(data);
    });

    _socket?.on('call:duration-active', (data) {
      if (onCallDurationActive != null) onCallDurationActive!(data);
    });

    _socket?.on('call:countdown-warning', (data) {
      if (onCallCountdownWarning != null) onCallCountdownWarning!(data);
    });

    _socket?.on('call:multi-device', (data) {
      if (onCallMultiDevice != null) onCallMultiDevice!(data);
    });

    // Waiting-room lifecycle (see server/lib/socket.ts). The server answers
    // `call:join` with { waitingRoom: true } and parks the joiner; the host
    // then admit/denies and ONLY the waiting socket receives these events.
    _socket?.on('waiting-room:admitted', (data) {
      if (onWaitingRoomAdmitted != null) onWaitingRoomAdmitted!(data);
    });

    _socket?.on('waiting-room:denied', (data) {
      if (onWaitingRoomDenied != null) onWaitingRoomDenied!(data);
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

    // Newer presence payload with the last-seen instant (chat last-seen
    // header). Kept separate from user-presence-updated so old backends
    // simply never fire it.
    _socket?.on('presence:update', (data) {
      if (onPresenceUpdate != null) onPresenceUpdate!(data);
    });

    _socket?.on('mediasoup:newProducer', (data) {
      if (onMediasoupNewProducer != null) onMediasoupNewProducer!(data);
    });

    // Fired when a remote producer is closed (peer left / stopped track).
    // Clients must drop the matching consumer + remote tile.
    _socket?.on('mediasoup:producerClosed', (data) {
      if (onMediasoupProducerClosed != null) onMediasoupProducerClosed!(data);
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

    _socket?.on('notification:new', (data) {
      if (onNotificationNew != null) onNotificationNew!(data);
    });

    _socket?.on('conversation:read', (data) {
      if (onConversationRead != null) onConversationRead!(data);
    });

    // Newer read-receipt rebroadcast (same payload shape, `readAt` instead of
    // `lastReadAt`). Old backends simply never fire it.
    _socket?.on('chat:conversation-read', (data) {
      if (onChatConversationRead != null) onChatConversationRead!(data);
    });

    _socket?.on('chat:typing', (data) {
      if (onChatTyping != null) onChatTyping!(data);
    });

    _socket?.on('chat:stop-typing', (data) {
      if (onChatStopTyping != null) onChatStopTyping!(data);
    });

    // New typing pipeline — relays to the USER room (the authenticated
    // handshake auto-joins user:{id}), so the chat LIST screen sees typing
    // for every conversation at once. Old backends simply never fire it.
    _socket?.on('chat:typing-updated', (data) {
      if (onChatTypingUpdated != null) onChatTypingUpdated!(data);
    });

    // Call-room reactions + raise hand (web & mobile parity — see
    // server/lib/socket.ts). Broadcast to room:{id} including the sender.
    _socket?.on('call:reaction-received', (data) {
      if (onCallReactionReceived != null) onCallReactionReceived!(data);
    });

    _socket?.on('call:hand-updated', (data) {
      if (onCallHandUpdated != null) onCallHandUpdated!(data);
    });

    _socket?.on('caption:updated', (data) {
      if (onCaptionUpdated != null) onCaptionUpdated!(data);
    });

    _socket?.on('meeting:notes_updated', (data) {
      if (onMeetingNotesUpdated != null) onMeetingNotesUpdated!(data);
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

  void emitCallLeave(Map<String, dynamic> data) {
    _socket?.emit('call:leave', data);
  }

  void emitMeetingJoin(Map<String, dynamic> data) {
    _socket?.emit('meeting:join', data);
  }

  /// Join a call room on the server. REQUIRED for calls (meetings join via
  /// meeting:join): without it the socket is never added to `room:{id}`, so
  /// mediasoup events (newProducer etc.) are never delivered for calls.
  ///
  /// Always advertises `waitingRoomSupport: true` so the server can QUEUE us
  /// (instead of silently letting us through / dropping us) when the room has
  /// waiting_room_enabled and we are not the host. Use [emitCallJoinWithAck]
  /// to read the server's decision.
  void emitCallJoin(Map<String, dynamic> data) {
    _socket?.emit('call:join', {
      ...data,
      'waitingRoomSupport': true,
    });
  }

  /// Join a call room and wait for the server ack. Ack shapes:
  /// - { success: true, waitingRoom: true, roomId, participantId } → parked in
  ///   the waiting room; wait for `waiting-room:admitted` / `:denied`.
  /// - { success: true, roomId } → joined straight away.
  /// - { success: false, error } → refused (room not found, ended, ...).
  /// Throws TimeoutException / StateError when no ack arrives in time.
  Future<dynamic> emitCallJoinWithAck(Map<String, dynamic> data) {
    return _emitAck('call:join', {
      ...data,
      'waitingRoomSupport': true,
    });
  }

  /// Explicitly (re-)enqueue ourselves in a room's waiting queue. Safety net
  /// for races (reconnect while waiting, lost join-time enqueue, ...).
  void emitWaitingRoomRequest(Map<String, dynamic> data) {
    _socket?.emit('waiting-room:request', data);
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

  /// Publish one live-caption segment for the room we are in. The backend
  /// relays it to everyone in the room as `caption:updated` and persists
  /// final segments for meetings (transcript → AI notes). Payload:
  /// { roomId, roomType: "call"|"meeting", text, isFinal, language }
  void emitCaptionSegment(Map<String, dynamic> data) {
    _socket?.emit('caption:segment', data);
  }

  void joinConversation(String conversationId) {
    _socket?.emit('join-conversation', conversationId);
  }

  /// Notify the conversation room that this user is typing (backend relays to peers)
  void emitChatTyping(Map<String, dynamic> data) {
    _socket?.emit('chat:typing', data);
  }

  void emitChatStopTyping(Map<String, dynamic> data) {
    _socket?.emit('chat:stop-typing', data);
  }

  // Throttle state for [emitChatTypingState]. `true` is emitted at most
  // every 2.5s while the user keeps typing; `false` always goes out on
  // send/blur so the peer's indicator can drop early.
  DateTime? _lastTypingTrueAt;
  String? _typingConversationId;

  /// WhatsApp-style typing emitter for the NEW pipeline: emits
  /// `chat:typing` { conversationId, isTyping } — the server relays it as
  /// `chat:typing-updated` to every other participant's user room.
  ///
  /// Throttled: while typing, `true` goes out at most every 2.5s (the peer
  /// keeps the indicator alive with the 4s auto-clear rule); `false` is
  /// ALWAYS emitted (send/blur) so the indicator never lingers.
  void emitChatTypingState(String conversationId, bool isTyping) {
    if (conversationId.isEmpty) return;
    if (isTyping) {
      final now = DateTime.now();
      if (_typingConversationId == conversationId &&
          _lastTypingTrueAt != null &&
          now.difference(_lastTypingTrueAt!) < const Duration(milliseconds: 2500)) {
        return; // throttled — peer's indicator is still alive
      }
      _typingConversationId = conversationId;
      _lastTypingTrueAt = now;
      _socket?.emit('chat:typing', {
        'conversationId': conversationId,
        'isTyping': true,
      });
      return;
    }
    // Stop: always emit false (send/blur), then reset the throttle window.
    _socket?.emit('chat:typing', {
      'conversationId': conversationId,
      'isTyping': false,
    });
    _typingConversationId = null;
    _lastTypingTrueAt = null;
  }

  /// Call-room reaction: emit `call:reaction` { roomCode, emoji } — the
  /// server resolves the room (uuid/code/roomId all work) and broadcasts
  /// `call:reaction-received` to everyone in it (including us).
  void emitCallReaction(Map<String, dynamic> data) {
    _socket?.emit('call:reaction', data);
  }

  /// Call-room raise-hand toggle: emit `call:raise-hand`
  /// { roomCode, raised } — the server broadcasts `call:hand-updated`.
  void emitCallRaiseHand(Map<String, dynamic> data) {
    _socket?.emit('call:raise-hand', data);
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

  Future<dynamic> mediasoupGetRouterRtpCapabilities({String? roomId}) {
    // The server handler destructures `{ roomId }` from the first argument.
    // Emitting an empty list used to leave roomId undefined forever ->
    // "Router not initialized" -> mobile could never load the device.
    return _emitAck('mediasoup:getRouterRtpCapabilities', {'roomId': roomId});
  }

  /// Existing producers in the room (late-joiner discovery). Without this a
  /// joiner can never see/hear participants who joined earlier.
  Future<dynamic> mediasoupGetProducers(Map<String, dynamic> data) {
    return _emitAck('mediasoup:getProducers', data);
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
