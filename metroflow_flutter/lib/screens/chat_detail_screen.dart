import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../providers/call_provider.dart';
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
import '../widgets/avatar_with_initials.dart';
import '../widgets/user_profile_sheet.dart';

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
  final AudioRecorder _voiceRecorder = AudioRecorder();
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _currentUserId;
  String? _peerTypingName;
  Timer? _typingDebounce;
  Timer? _typingStopTimer;
  // Voice-note recording state (see _startVoiceRecording)
  bool _isRecordingVoice = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _recordPath;
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

  /// Opens the profile sheet for the chat partner (direct) or the member
  /// list (group). Uses the enriched participants the backend returns with
  /// every conversation.
  void _openChatProfile() {
    final conversation = widget.conversation;
    final currentId = _currentUserId;
    final members = conversation.participants
        .map((p) => ChatUserProfile(
              userId: p.userId,
              name: p.name.trim().isNotEmpty
                  ? p.name.trim()
                  : (p.email.isNotEmpty ? p.email : 'Member'),
              email: p.email,
              avatarUrl: p.avatarUrl,
            ))
        .toList();
    final other = conversation.otherParticipant(currentId);
    final ChatUserProfile profile = (other != null && other.name.trim().isNotEmpty)
        ? ChatUserProfile(
            userId: other.userId,
            name: other.name.trim(),
            email: other.email,
            avatarUrl: other.avatarUrl,
          )
        : (members.isNotEmpty
            ? members.first
            : ChatUserProfile(
                userId: '',
                name: conversation.displayTitle(currentId),
              ));

    UserProfileSheet.show(
      context,
      profile: profile,
      members: members,
      conversationName: conversation.displayTitle(currentId),
    );
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

      // We are now DIALING OUT: loop the ringback until the callee accepts
      // (call:accepted), declines (call:rejected), the call ends, or we leave
      // the room (see CallNotifier.stopOutboundRing).
      ref.read(callProvider.notifier).startOutboundRing(call.id);

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
      // Modal closed → we left the room; make sure the ringback is silenced.
      if (mounted) ref.read(callProvider.notifier).stopOutboundRing();
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

  Future<void> _sendMessage({Map<String, dynamic>? overrides}) async {
    final content = (overrides?['content'] as String?) ?? _messageController.text.trim();
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
        ...?overrides,
      });
      if (overrides == null) _messageController.clear();
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

  // -------------------------------------------------------------------------
  // Voice notes (record → upload → send)
  // -------------------------------------------------------------------------

  String _formatSeconds(int total) {
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Start recording a voice note to a temp .m4a file. `hasPermission()` also
  /// triggers the platform mic-permission dialog on first use (built into the
  /// record package — no separate permission_handler needed).
  Future<void> _startVoiceRecording() async {
    if (_isRecordingVoice || _isSending) return;
    try {
      final granted = await _voiceRecorder.hasPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Microphone permission is required for voice notes')),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );
      _recordPath = path;
      _recordSeconds = 0;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds += 1);
      });
      if (mounted) setState(() => _isRecordingVoice = true);
    } catch (e) {
      Logger.error('Voice recording failed to start: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start recording')),
        );
      }
    }
  }

  /// Discard the recording: stop the recorder and delete the temp file.
  Future<void> _cancelVoiceRecording() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    String? stoppedPath;
    try {
      stoppedPath = await _voiceRecorder.stop();
    } catch (_) {}
    await _deleteTempRecording(stoppedPath ?? _recordPath);
    _recordPath = null;
    _recordSeconds = 0;
    if (mounted) setState(() => _isRecordingVoice = false);
  }

  /// Stop recording, upload the clip via POST /chat/media, then send the
  /// message with attachmentUrl/attachmentType through the normal flow.
  Future<void> _sendVoiceNote() async {
    if (_isSending) return;
    _recordTimer?.cancel();
    _recordTimer = null;
    final requestedPath = _recordPath;
    _recordPath = null;
    _recordSeconds = 0;
    setState(() {
      _isRecordingVoice = false;
      _isSending = true;
    });
    try {
      String? stoppedPath;
      try {
        stoppedPath = await _voiceRecorder.stop();
      } catch (_) {}
      final filePath =
          (stoppedPath != null && stoppedPath.isNotEmpty) ? stoppedPath : requestedPath;
      if (filePath == null || filePath.isEmpty) {
        throw const FormatException('Recording was not captured');
      }
      final url = await _api.uploadChatMedia(File(filePath));
      if (url == null || url.isEmpty) {
        throw const FormatException('Voice note upload failed');
      }
      await _sendMessage(overrides: <String, dynamic>{
        'content': '🎤 Voice note',
        'attachmentUrl': url,
        'attachmentType': 'audio',
      });
      AppFeedback.playSentSound();
    } catch (e) {
      Logger.error('Error sending voice note: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is FormatException
                ? e.message
                : ApiService.extractErrorMessage(e)),
          ),
        );
      }
    } finally {
      await _deleteTempRecording(requestedPath);
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _deleteTempRecording(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
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
    _recordTimer?.cancel();
    _recordTimer = null;
    unawaited(_deleteTempRecording(_recordPath));
    _recordPath = null;
    unawaited(_voiceRecorder.dispose());
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
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openChatProfile(),
          child: Row(
            children: [
              AvatarWithInitials(
                name: widget.conversation.displayTitle(_currentUserId),
                imageUrl: widget.conversation.displayAvatar(_currentUserId),
                radius: 17,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.conversation.displayTitle(_currentUserId),
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
              child: _isRecordingVoice
                  ? _buildRecordingComposer(colors)
                  : _buildTextComposer(colors),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Composer (text + voice-note recording pill)
  // -------------------------------------------------------------------------

  /// Normal text composer. A mic button sits to the LEFT of the text field
  /// while it is empty; once the user types, the send button takes over as
  /// before.
  Widget _buildTextComposer(ThemeColors colors) {
    final hasText = _messageController.text.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!hasText) ...[
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Record voice note',
              style: IconButton.styleFrom(
                backgroundColor: colors.primaryBg,
                shape: const CircleBorder(),
              ),
              icon: Icon(Icons.mic_none_rounded, color: colors.primary, size: 21),
              onPressed: _startVoiceRecording,
            ),
          ),
          const SizedBox(width: 8),
        ],
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
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
              colors: hasText
                  ? [colors.primary, colors.primaryDark]
                  : [
                      colors.textSecondary.withValues(alpha: 0.5),
                      colors.textSecondary.withValues(alpha: 0.5),
                    ],
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
            onPressed: _isSending ? null : () => _sendMessage(),
          ),
        ),
      ],
    );
  }

  /// Recording state replaces the composer: pulsing red dot, elapsed timer,
  /// cancel (trash) and send.
  Widget _buildRecordingComposer(ThemeColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _PulsingDot(),
        const SizedBox(width: 10),
        Text(
          _formatSeconds(_recordSeconds),
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: colors.text,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _isSending ? 'Uploading voice note…' : 'Recording voice note…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: colors.textSecondary,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Cancel recording',
          icon:
              Icon(Icons.delete_outline_rounded, color: colors.error, size: 22),
          onPressed: _isSending ? null : _cancelVoiceRecording,
        ),
        const SizedBox(width: 4),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primary, colors.primaryDark],
            ),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: 'Send voice note',
            icon: _isSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
            onPressed: _isSending ? null : _sendVoiceNote,
          ),
        ),
      ],
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

    final isVoiceNote = message.attachmentType == 'audio' &&
        (message.attachmentUrl?.isNotEmpty ?? false);
    final voiceUrl = isVoiceNote
        ? ApiService.resolveMediaUrl(message.attachmentUrl)
        : null;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
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
            if (isVoiceNote && voiceUrl != null)
              _VoiceNoteBubble(url: voiceUrl, isMe: isMe, colors: colors)
            else
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

/// Compact in-bubble voice-note player (WhatsApp-style): play/pause button,
/// tap/drag-to-seek progress bar, elapsed/total duration and a 1x → 1.5x → 2x
/// speed toggle. Owns a single audioplayers instance, disposed with the
/// widget. Adapts its palette to sent (primary-tinted) vs received (surface)
/// bubbles.
class _VoiceNoteBubble extends StatefulWidget {
  final String url;
  final bool isMe;
  final ThemeColors colors;

  const _VoiceNoteBubble({
    required this.url,
    required this.isMe,
    required this.colors,
  });

  @override
  State<_VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<_VoiceNoteBubble> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _speed = 1.0;
  bool _failed = false;

  bool get _isPlaying => _playerState == PlayerState.playing;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    try {
      _player.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_isPlaying) {
        await _player.pause();
        return;
      }
      if (_playerState == PlayerState.paused) {
        await _player.resume();
      } else {
        // stopped / completed → (re)start from the beginning (or resume point).
        await _player.play(UrlSource(widget.url));
        await _player.setPlaybackRate(_speed);
      }
      if (mounted) setState(() => _failed = false);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _cycleSpeed() async {
    final next = _speed >= 2.0 ? 1.0 : (_speed >= 1.5 ? 2.0 : 1.5);
    setState(() => _speed = next);
    try {
      await _player.setPlaybackRate(next);
    } catch (_) {}
  }

  Future<void> _seekTo(Duration target) async {
    try {
      await _player.seek(target);
      if (mounted) setState(() => _position = target);
    } catch (_) {}
  }

  void _seekFromFraction(double dx, double width) {
    final total = _duration;
    if (total == null || total.inMilliseconds <= 0 || width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    _seekTo(Duration(milliseconds: (total.inMilliseconds * fraction).round()));
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final isMe = widget.isMe;
    final iconColor = isMe ? Colors.white : colors.primary;
    final labelColor = isMe ? Colors.white70 : colors.textSecondary;
    final trackColor =
        isMe ? Colors.white24 : colors.primary.withValues(alpha: 0.18);

    final totalMs = _duration?.inMilliseconds ?? 0;
    final playedMs =
        totalMs > 0 ? _position.inMilliseconds.clamp(0, totalMs).toInt() : 0;
    final progress = totalMs > 0 ? playedMs / totalMs : 0.0;
    final totalLabel = totalMs > 0 ? _fmt(Duration(milliseconds: totalMs)) : '--:--';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.22)
                    : colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 20,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) =>
                      _seekFromFraction(details.localPosition.dx, constraints.maxWidth),
                  onHorizontalDragUpdate: (details) => _seekFromFraction(
                      details.localPosition.dx, constraints.maxWidth),
                  child: SizedBox(
                    height: 22,
                    child: Center(
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(999),
                        backgroundColor: trackColor,
                        valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _failed
                ? 'Tap to retry'
                : '${_fmt(Duration(milliseconds: playedMs))} / $totalLabel',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: _failed ? colors.error : labelColor,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _cycleSpeed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.18)
                    : colors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_speed}x',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsing red dot shown while a voice note is being recorded.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.15).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: Color(0xFFEF4444),
            shape: BoxShape.circle,
          ),
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
