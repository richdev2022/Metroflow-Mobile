import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../utils/logger.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  final Conversation conversation;
  const ChatDetailScreen({super.key, required this.conversation});

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
  late final void Function(dynamic) _messageCreatedHandler;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadMessages();
    _socket.joinConversation(widget.conversation.id);
    _messageCreatedHandler = (data) {
      final payload = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final conversationId = payload['conversationId'] ?? payload['conversation_id'];
      if (!mounted || conversationId != widget.conversation.id) return;
      final message = Message.fromJson(payload);
      setState(() {
        _upsertMessage(message);
      });
      _scrollToBottom();
    };
    _socket.onMessageCreated = _messageCreatedHandler;
  }

  void _upsertMessage(Message message) {
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      _messages.add(message);
    } else {
      _messages[index] = message;
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

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

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
    if (_socket.onMessageCreated == _messageCreatedHandler) {
      _socket.onMessageCreated = null;
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isCurrentUser(String senderId) => senderId == _currentUserId;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.conversation.name ?? 'Chat'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.message_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No messages yet', style: TextStyle(color: Colors.grey[600])),
                            const SizedBox(height: 8),
                            Text('Send the first message!', style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMe = isCurrentUser(message.senderId);
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Theme.of(context).primaryColor.withValues(alpha: 1.0)
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                                  bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  if (!isMe)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        message.senderName ?? 'User',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    message.content,
                                    style: TextStyle(
                                      color: isMe ? Colors.white : Colors.black87,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat.Hm().format(message.createdAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isMe ? Colors.white70 : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
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
