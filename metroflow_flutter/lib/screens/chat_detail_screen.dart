import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../models/call.dart';
import '../theme/app_theme.dart';
import '../utils/app_feedback.dart';
import '../widgets/modern_ui.dart';
import 'video_call_screen.dart';
import '../utils/logger.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  final Conversation conversation;
  const ChatDetailScreen({super.key, required this.conversation});

  /// Conversation currently open on this device. The global
  /// `chat:new-message-notification` handler in main.dart checks this to
  /// suppress banners/sounds for the conversation the user is looking at.
  static String? activeConversationId;

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();
  final StorageService _storage = StorageService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _currentUserId;
  String? _peerTypingName;
  Timer? _typingDebounce;
  Timer? _typingStopTimer;
  late final void Function(dynamic) _messageCreatedHandler;
  late final void Function(dynamic) _typingHandler;
  late final void Function(dynamic) _stopTypingHandler;

  @override
  void initState() {
    super.initState();
    ChatDetailScreen.activeConversationId = widget.conversation.id;
    _loadCurrentUser();
    _loadMessages();
    _socket.joinConversation(widget.conversation.id);
    // Mark as read on open so the unread badge clears everywhere (web included)
    _api.markConversationAsRead(widget.conversation.id).catchError((e) {
      Logger.error('markConversationAsRead failed: $e');
      return null;
    });

    _messageCreatedHandler = (data) {
      final payload = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final conversationId = payload['conversationId'] ?? payload['conversation_id'];
      if (!mounted || conversationId != widget.conversation.id) return;
      final message = Message.fromJson(payload);
      final isFromMe = message.senderId == _currentUserId;
      setState(() {
        _upsertMessage(message);
      });
      if (!isFromMe) {
        // Audible pop for messages received while the chat is open
        AppFeedback.playMessageSound();
      }
      _scrollToBottom();
    };
    _socket.onMessageCreated = _messageCreatedHandler;

    _typingHandler = (data) {
      final payload = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      if (!mounted || payload['conversationId'] != widget.conversation.id) return;
      if (payload['userId'] == _currentUserId) return;
      setState(() => _peerTypingName = (payload['userName'] as String?) ?? 'Someone');
    };
    _socket.onChatTyping = _typingHandler;

    _stopTypingHandler = (data) {
      final payload = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      if (!mounted || payload['conversationId'] != widget.conversation.id) return;
      if (payload['userId'] == _currentUserId) return;
      setState(() => _peerTypingName = null);
    };
    _socket.onChatStopTyping = _stopTypingHandler;
  }

  void _upsertMessage(Message message) {
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      _messages.add(message);
    } else {
      _messages[index] = message;
    }
  }

  /// Start an audio/video call with the other chat participants (parity with
  /// the web chat call button). The backend emits `call:incoming` to every
  /// invitee — no manual socket invites needed.
  Future<void> _startCall(String type) async {
    if (_isSending) return;
    final otherIds = widget.conversation.participants
        .map((p) => p.userId)
        .where((id) => id.isNotEmpty && id != _currentUserId)
        .toList();
    if (otherIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No one to call in this conversation')),
        );
      }
      return;
    }

    setState(() => _isSending = true);
    try {
      final response = await _api.createCall({
        'type': type,
        'isGroupCall': otherIds.length > 1,
        'waitingRoomEnabled': otherIds.length > 1,
        'recordingEnabled': false,
        'participantIds': otherIds,
      });
      if (response.data['success'] != true || !mounted) return;
      final data = response.data['data'];
      if (data is! Map) return;
      final call = Call.fromJson(Map<String, dynamic>.from(data));

      await _api.joinCall(call.id);
      if (!mounted) return;
      final userName = await _storage.getUserName();
      if (!mounted) return;
      await VideoCallScreen.showModal(
        context: context,
        roomId: call.id,
        title: type == 'video' ? 'Video Call' : 'Audio Call',
        enableVideo: type == 'video',
        userName: userName,
        isHost: true,
        isGroupCall: call.isGroupCall,
        onLeave: () async {
          try {
            await _api.leaveCall(call.id);
          } catch (e) {
            Logger.error('leaveCall failed (non-fatal): $e');
          }
        },
      );
    } catch (e) {
      Logger.error('Error starting call from chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Message _extractMessage(dynamic responseData) {
    final data = responseData is Map ? responseData['data'] : null;
    if (data is Map && data['message'] is Map) {
      return Message.fromJson(Map<String, dynamic>.from(data['message'] as Map));
    }
    if (data is Map) {
      return Message.fromJson(Map<String, dynamic>.from(data));
    }
    if (responseData is Map) {
      return Message.fromJson(Map<String, dynamic>.from(responseData));
    }
    throw const FormatException('Invalid message response');
  }

  Future<void> _loadCurrentUser() async {
    final userId = await _storage.getUserId();
    if (mounted) {
      setState(() {
        _currentUserId = userId;
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadMessages() async {
    try {
      final response = await _api.getConversationMessages(widget.conversation.id);
      if (response.data['success'] == true) {
        if (!mounted) return;
        final responseData = response.data['data'];
        final data = responseData is Map && responseData['messages'] is List
            ? responseData['messages'] as List
            : responseData is List
                ? responseData
                : <dynamic>[];
        setState(() {
          _messages = data
              .whereType<Map>()
              .map((json) => Message.fromJson(Map<String, dynamic>.from(json)))
              .toList();
        });
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    } catch (e) {
      Logger.error('Error loading messages: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onTextChanged(String text) {
    // Refresh the send-button gradient as the composer empties/fills
    if (mounted) setState(() {});
    _typingDebounce?.cancel();
    if (text.trim().isEmpty) {
      _typingStopTimer?.cancel();
      _socket.emitChatStopTyping({
        'conversationId': widget.conversation.id,
        'userId': _currentUserId,
      });
      return;
    }
    _typingDebounce = Timer(const Duration(milliseconds: 400), () {
      _socket.emitChatTyping({
        'conversationId': widget.conversation.id,
        'userId': _currentUserId,
      });
      // Auto-stop after 3s of no further keystrokes
      _typingStopTimer?.cancel();
      _typingStopTimer = Timer(const Duration(seconds: 3), () {
        _socket.emitChatStopTyping({
          'conversationId': widget.conversation.id,
          'userId': _currentUserId,
        });
      });
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    _typingStopTimer?.cancel();
    _socket.emitChatStopTyping({
      'conversationId': widget.conversation.id,
      'userId': _currentUserId,
    });

    setState(() => _isSending = true);
    try {
      final response = await _api.sendMessage(widget.conversation.id, {
        'content': content,
      });
      _messageController.clear();
      if (response.data['success'] == true && mounted) {
        final message = _extractMessage(response.data);
        setState(() {
          _upsertMessage(message);
        });
        _scrollToBottom();
      }
    } catch (e) {
      Logger.error('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  void dispose() {
    if (ChatDetailScreen.activeConversationId == widget.conversation.id) {
      ChatDetailScreen.activeConversationId = null;
    }
    if (_socket.onMessageCreated == _messageCreatedHandler) {
      _socket.onMessageCreated = null;
    }
    if (_socket.onChatTyping == _typingHandler) {
      _socket.onChatTyping = null;
    }
    if (_socket.onChatStopTyping == _stopTypingHandler) {
      _socket.onChatStopTyping = null;
    }
    _typingDebounce?.cancel();
    _typingStopTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? _dateLabelFor(int index) {
    final msgDate = DateUtils.dateOnly(_messages[index].createdAt);
    if (index == 0) return _prettyDate(_messages[index].createdAt);
    final prevDate = DateUtils.dateOnly(_messages[index - 1].createdAt);
    if (msgDate != prevDate) return _prettyDate(_messages[index].createdAt);
    return null;
  }

  String _prettyDate(DateTime date) {
    final now = DateUtils.dateOnly(DateTime.now());
    final that = DateUtils.dateOnly(date);
    if (that == now) return 'Today';
    if (that == now.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat.MMMEd().format(date);
  }

  @override
  Widget build(BuildContext context) {
    bool isCurrentUser(String senderId) => senderId == _currentUserId;
    final colors = AppTheme.colors;
    final isDirect = widget.conversation.type != 'group';
    final memberCount = widget.conversation.participants.length;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        shadowColor: colors.border,
        iconTheme: IconThemeData(color: colors.text),
        titleSpacing: 0,
        title: Row(
          children: [
            AvatarInitials(
              name: widget.conversation.name ?? 'Chat',
              radius: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.conversation.name ?? 'Chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                  Text(
                    isDirect ? 'Direct message' : '$memberCount members',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          _RoundIconAction(
            icon: Icons.call_outlined,
            color: colors.success,
            tooltip: 'Audio call',
            onTap: () => _startCall('audio'),
          ),
          _RoundIconAction(
            icon: Icons.videocam_outlined,
            color: colors.primary,
            tooltip: 'Video call',
            onTap: () => _startCall('video'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: colors.primary),
                  )
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                color: colors.primaryBg,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.chat_bubble_outline_rounded,
                                  size: 38, color: colors.primary),
                            ),
                            const SizedBox(height: 16),
                            Text('No messages yet',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colors.text)),
                            const SizedBox(height: 6),
                            Text('Say hello — send the first message!',
                                style: TextStyle(color: colors.textSecondary)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMe = isCurrentUser(message.senderId);
                          final dateLabel = _dateLabelFor(index);
                          final showHeader = !isMe &&
                              (index == 0 ||
                                  _messages[index - 1].senderId !=
                                      message.senderId ||
                                  dateLabel != null);

                          return Column(
                            children: [
                              if (dateLabel != null)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: colors.surfaceVariant,
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      dateLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              _MessageBubble(
                                message: message,
                                isMe: isMe,
                                showSenderName:
                                    !isDirect && showHeader,
                                colors: colors,
                              ),
                            ],
                          );
                        },
                      ),
          ),
          // Typing indicator row
          if (_peerTypingName != null)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: colors.primary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$_peerTypingName is typing…',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 5,
                      onChanged: _onTextChanged,
                      style: TextStyle(color: colors.text, fontSize: 14.5),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: colors.textSecondary),
                        filled: true,
                        fillColor: colors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 11),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _messageController.text.trim().isEmpty
                            ? [colors.textSecondary.withValues(alpha: 0.5), colors.textSecondary.withValues(alpha: 0.5)]
                            : [colors.primary, colors.primaryDark],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                      onPressed: _isSending ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool showSenderName;
  final ThemeColors colors;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showSenderName,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMe ? 16 : 4),
      topRight: Radius.circular(isMe ? 4 : 16),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: isMe
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.primary, colors.primaryDark],
                )
              : null,
          color: isMe ? null : colors.surface,
          borderRadius: radius,
          border: isMe ? null : Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isMe ? 0.16 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showSenderName)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.senderName ?? 'User',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              ),
            Text(
              message.content,
              style: TextStyle(
                color: isMe ? Colors.white : colors.text,
                fontSize: 14.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              DateFormat.Hm().format(message.createdAt.toLocal()),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundIconAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: color.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: color, size: 21),
            ),
          ),
        ),
      ),
    );
  }
}
