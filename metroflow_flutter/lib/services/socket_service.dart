import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/logger.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  socket_io.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

  void Function(dynamic)? onMeetingCreated;
  void Function(dynamic)? onMeetingUpdated;
  void Function(dynamic)? onMeetingDeleted;
  void Function(dynamic)? onConversationCreated;
  void Function(dynamic)? onMessageCreated;
  void Function(dynamic)? onCallCreated;
  void Function(dynamic)? onCallUpdated;
  void Function(dynamic)? onCallParticipantJoined;
  void Function(dynamic)? onCallParticipantLeft;
  void Function(dynamic)? onUserPresenceUpdated;

  void connect(String userId, String businessId) {
    final baseUrl = dotenv.env['EXPO_PUBLIC_API_BASE_URL'] ?? 'https://metroflow-backend.netlify.app';

    _socket = socket_io.io(baseUrl, socket_io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
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

    _socket?.on('call:participantJoined', (data) {
      if (onCallParticipantJoined != null) onCallParticipantJoined!(data);
    });

    _socket?.on('call:participantLeft', (data) {
      if (onCallParticipantLeft != null) onCallParticipantLeft!(data);
    });

    _socket?.on('user-presence-updated', (data) {
      if (onUserPresenceUpdated != null) onUserPresenceUpdated!(data);
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void joinConversation(String conversationId) {
    _socket?.emit('join-conversation', conversationId);
  }
}
