import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
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
import '../utils/app_timezone.dart';
import '../utils/app_toast.dart';
import '../utils/chat_media_utils.dart';
import '../widgets/chat_attachment_views.dart';
import '../widgets/emoji_sticker_gif_panel.dart';
import 'video_call_screen.dart';
import '../utils/logger.dart';
import '../widgets/avatar_with_initials.dart';
import '../widgets/styled_text.dart';
import '../widgets/user_profile_sheet.dart';

/// MetricAi accent (violet) shared by the in-chat intelligence UI — mirrors
/// the web Chat.tsx AI styling (violet-600 chips, sparkle icons).
const Color kMetricAiViolet = Color(0xFF7C3AED);
const Color kMetricAiVioletSoft = Color(0xFF8B5CF6);

class ChatDetailScreen extends ConsumerStatefulWidget {
  final Conversation conversation;
  const ChatDetailScreen({super.key, required this.conversation});

  /// Conversation currently open on this device. The global
  /// `chat:new-message-notification` handler in main.dart checks this to
  /// suppress banners/sounds for the conversation the user is looking at.
  static String? activeConversationId;

  /// Set by the push-notification tap handler (chat_message) right before
  /// navigating to '/main/chat' — ChatScreen consumes it once the
  /// conversations list arrives and opens THIS conversation directly.
  static String? pendingOpenConversationId;

  /// Set by the group invite deep link (metricorex://chat/join/<code>) or a
  /// chat_invite push tap right before navigating to '/main/chat' —
  /// ChatScreen consumes it once, POSTs /chat/join/<code> and opens the
  /// returned conversation directly.
  static String? pendingChatJoinCode;

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState
    extends ConsumerState<ChatDetailScreen>
    with WidgetsBindingObserver {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();
  final StorageService _storage = StorageService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _voiceRecorder = AudioRecorder();
  List<Message> _messages = [];
  bool _isLoading = true;
  /// Non-null when loading messages FAILED (dead session / network / 500).
  /// The empty state then shows the real reason + a retry, instead of the
  /// misleading "No messages yet".
  String? _loadError;
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
  // Attachment picking/uploading (paperclip flow)
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingAttachment = false;
  // Whether the backend GIF proxy is configured (GET /chat/gifs) — hides the
  // GIF tab in the emoji/sticker/GIF panel when Tenor is not set up.
  bool _gifsConfigured = false;
  // Reply quoting + edit composer context (batch-4 parity).
  Message? _replyTo;
  Message? _editingMessage;
  // Peer presence for the header: live values from `presence:update`, falling
  // back to the conversation payload's otherUserLastSeenAt / participant
  // lastSeenAt when no socket event has arrived yet.
  DateTime? _peerLastSeenAt;
  String? _peerPresenceStatus;
  // Read receipts (Teams-style double tick): the latest instant a PEER read
  // this conversation. Seeded from the conversation participants, refreshed
  // from the messages payload (`data.participants[].lastReadAt`) and live
  // `conversation:read` / `chat:conversation-read` socket events. Own
  // messages created at/below this instant render ✔✔.
  DateTime? _peerLastReadAt;
  /// userId → lastReadAt captured from the messages payload / conversation
  /// participants. Recomputed against [_currentUserId] once that resolves
  /// (both loaders race at initState time).
  List<MapEntry<String, DateTime?>> _participantReadEntries = const [];
  late final void Function(dynamic) _messageCreatedHandler;
  late final void Function(dynamic) _messageUpdatedHandler;
  late final void Function(dynamic) _presenceHandler;
  late final void Function(dynamic) _typingHandler;
  late final void Function(dynamic) _stopTypingHandler;
  late final void Function(dynamic) _conversationReadHandler;
  // Coalesces resync work (resume + socket reconnect can fire together).
  bool _resyncInFlight = false;
  // Multi-select forward/delete mode (WhatsApp-style). Long-press a bubble →
  // 'Select', then tap bubbles to toggle; the app bar switches to the
  // selection toolbar (Forward / Delete / Select all).
  bool _selectionMode = false;
  final Set<String> _selectedMessageIds = <String>{};
  // @mention overlay state (group conversations only). [_mentionToken] is the
  // text after the trailing '@' when the overlay is open, null when closed.
  List<ChatUserProfile> _mentionMembers = const <ChatUserProfile>[];
  bool _mentionLoaded = false;
  String? _mentionToken;
  int _mentionHighlight = 0;
  // Trailing "@token" right before the caret (group conversations). Group 1
  // is the partial name; group 0 includes the leading whitespace (or string
  // start) so emails like name@company.com never trigger the overlay. Kept
  // identical to the web composer regex in Chat.tsx (detectMentionToken).
  final RegExp _mentionPattern = RegExp(r'(?:^|\s)@([^\s@]{0,30})$');
  final FocusNode _composerFocus = FocusNode();
  // MetricAi chat intelligence (web Chat.tsx parity). [_aiAvailable] gates
  // every entry point — probed once from GET /ai/status; when the caller's
  // plan lacks MetricAi all three features stay hidden (soft gating, the UI
  // simply never shows them).
  bool _aiAvailable = false;
  List<String> _smartReplies = const <String>[];
  bool _smartRepliesLoading = false;
  /// The incoming message the current chips were built for — guards against
  /// duplicate /chat/ai/smart-replies calls on every socket echo.
  String? _smartRepliesForMessageId;
  final Map<String, String> _translations = <String, String>{};
  String? _translatingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ChatDetailScreen.activeConversationId = widget.conversation.id;
    // Seed the read receipt from the conversation object (its enriched
    // participants already expose lastReadAt) — refreshed by the loaders.
    _participantReadEntries = widget.conversation.participants
        .where((p) => p.userId.isNotEmpty)
        .map((p) => MapEntry(p.userId, p.lastReadAt))
        .toList();
    _refreshPeerLastRead();
    _loadCurrentUser();
    _loadMessages();
    _checkGifsConfigured();
    // MetricAi chat intelligence — probe availability, then (when enabled)
    // fetch smart replies for the latest incoming message (web parity).
    _probeMetricAiStatus();
    _socket.joinConversation(widget.conversation.id);
    // Reconnect hook (registered AFTER the join): fired once the socket
    // (re)connects and the service re-joined every remembered room — the
    // handler below backfills anything missed while offline. Lifecycle/
    // reconnect-driven only: NO timers, NO polling.
    _socket.addOnReconnected(_handleSocketReconnected);
    if (widget.conversation.type == 'group') {
      _loadMentionMembers();
    }
    // Blur closes the mention overlay (with a small grace period so tapping a
    // candidate row — which blurs the field first — still inserts).
    _composerFocus.addListener(_handleComposerFocusChange);
    // Mark as read on open so the unread badge clears everywhere (web included)
    _markConversationRead();

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

    _messageUpdatedHandler = (data) {
      // `message:updated` payload: { conversationId, message: { ...row } } —
      // edit + delete-for-everyone echo. Upsert keeps ids stable.
      try {
        if (!mounted || data is! Map) return;
        final payload = Map<String, dynamic>.from(data);
        final cid = (payload['conversationId'] ?? payload['conversation_id'] ?? '').toString();
        if (cid.isNotEmpty && cid != widget.conversation.id) return;
        final raw = payload['message'] is Map
            ? Map<String, dynamic>.from(payload['message'] as Map)
            : payload;
        if (cid.isEmpty) {
          final innerCid = (raw['conversationId'] ?? raw['conversation_id'] ?? '').toString();
          if (innerCid.isNotEmpty && innerCid != widget.conversation.id) return;
        }
        final message = Message.fromJson(raw);
        if (message.id.isEmpty) return;
        setState(() => _upsertMessage(message));
      } catch (e) {
        Logger.error('message:updated handler failed: $e');
      }
    };
    _socket.onMessageUpdated = _messageUpdatedHandler;

    _presenceHandler = (data) {
      // `presence:update` { userId, lastSeenAt, presenceStatus } (or the
      // legacy `user-presence-updated` { userId, status }). Only the chat
      // partner's presence updates the header.
      try {
        if (!mounted || data is! Map) return;
        final payload = Map<String, dynamic>.from(data);
        final userId = (payload['userId'] ?? payload['user_id'] ?? '').toString();
        final other = widget.conversation.otherParticipant(_currentUserId);
        if (userId.isEmpty || other == null || userId != other.userId) return;
        final seen = _parsePresenceTime(payload['lastSeenAt'] ?? payload['last_seen_at']);
        final status = (payload['presenceStatus'] ??
                    payload['presence_status'] ??
                    payload['status'])
                ?.toString() ??
            '';
        setState(() {
          if (seen != null) _peerLastSeenAt = seen;
          _peerPresenceStatus = status.trim().isEmpty ? null : status.trim();
        });
      } catch (e) {
        Logger.error('presence:update handler failed: $e');
      }
    };
    _socket.onPresenceUpdate = _presenceHandler;

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

    // Read receipts: `conversation:read`
    // { conversationId, userId, lastReadAt } and the newer
    // `chat:conversation-read` { conversationId, userId, readAt }. Only a
    // PEER's read instant advances the double tick.
    _conversationReadHandler = (data) {
      try {
        if (!mounted || data is! Map) return;
        final payload = Map<String, dynamic>.from(data);
        final cid = (payload['conversationId'] ?? payload['conversation_id'] ?? '').toString();
        if (cid.isEmpty || cid != widget.conversation.id) return;
        final userId = (payload['userId'] ?? payload['user_id'] ?? '').toString();
        if (userId.isNotEmpty && userId == _currentUserId) return;
        final at = _parseReadInstant(payload['readAt'] ??
            payload['lastReadAt'] ??
            payload['read_at'] ??
            payload['last_read_at']);
        if (at == null) return;
        final current = _peerLastReadAt;
        if (current != null && !at.isAfter(current)) return;
        setState(() => _peerLastReadAt = at);
      } catch (e) {
        Logger.error('conversation read handler failed: $e');
      }
    };
    _socket.onConversationRead = _conversationReadHandler;
    _socket.onChatConversationRead = _conversationReadHandler;
  }

  void _upsertMessage(Message message) {
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      _messages.add(message);
    } else {
      _messages[index] = message;
    }
    // A brand-new incoming message changes the smart-reply context (web
    // parity: chips recompute for the newest incoming). Cheap-guarded inside
    // _refreshSmartReplies by [_smartRepliesForMessageId].
    unawaited(_refreshSmartReplies());
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
      // GROUP EXTRAS: tappable member rows → DM, add-members picker and the
      // shareable invite link (only mounted when this is a group chat).
      conversationId: conversation.type == 'group' ? conversation.id : null,
      isGroup: conversation.type == 'group',
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
        // Links the call to this conversation so the backend posts a
        // call-log message when the call ends (renders via CallLogRow).
        'conversationId': widget.conversation.id,
      });
      if (response.data['success'] != true || !mounted) return;
      final data = response.data['data'];
      if (data is! Map) return;
      final call = Call.fromJson(Map<String, dynamic>.from(data));

      // We are now DIALING OUT: loop the ringback until the callee accepts
      // (call:accepted), declines (call:rejected), the call ends, or we leave
      // the room (see CallNotifier.stopOutboundRing).
      ref.read(callProvider.notifier).startOutboundRing(call.id);

      // REST-join is a REGISTRATION step, not a gate: the callee's phone is
      // already ringing at this point, and the call room itself is opened via
      // the socket `call:join` handshake inside VideoCallScreen (which mints
      // its own provider credentials). A join failure (500/410 race, duplicate
      // participant row) used to be rethrown here and surfaced as
      // "failed to join call" — stranding the caller even though the room was
      // joinable. Web NEVER REST-joins before entering the room; match that:
      // attempt it (with ONE retry on transient failures) but treat every
      // failure as non-fatal and open the room anyway.
      Map<String, dynamic>? callingCredentials;
      try {
        Response joinResponse;
        try {
          joinResponse = await _api.joinCall(call.id);
        } on DioException catch (joinErr) {
          final transient = joinErr.type == DioExceptionType.connectionError ||
              joinErr.type == DioExceptionType.connectionTimeout ||
              (joinErr.response?.statusCode ?? 0) >= 500;
          if (!transient) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 900));
          joinResponse = await _api.joinCall(call.id);
        }
        final joinData = joinResponse.data['data'];
        final callingRaw = joinData is Map ? joinData['calling'] : null;
        if (callingRaw is Map) {
          callingCredentials = Map<String, dynamic>.from(callingRaw);
        }
      } catch (joinErr) {
        Logger.error('Caller REST join failed (non-fatal): $joinErr');
      }
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
        calling: callingCredentials,
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

  /// Fire-and-forget read receipt so the unread badge clears on every device
  /// (web included) as soon as the conversation is opened.
  Future<void> _markConversationRead() async {
    try {
      await _api.markConversationAsRead(widget.conversation.id);
    } catch (e) {
      Logger.error('markConversationAsRead failed: $e');
    }
  }

  /// Parses a read-receipt instant (ISO string or epoch) as UTC so the
  /// comparison with message.createdAt never flips on local offsets/DST.
  DateTime? _parseReadInstant(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc();
    if (raw is num && raw > 0) {
      final ms = raw >= 100000000000 ? raw.toInt() : (raw.toInt() * 1000);
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    final s = raw.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toUtc();
  }

  /// Recomputes [_peerLastReadAt] = MAX non-null lastReadAt among
  /// participants whose userId != my user id. Monotonic: never lowers a
  /// value already delivered by a live socket event.
  void _refreshPeerLastRead() {
    var latest = _peerLastReadAt;
    final myId = _currentUserId;
    for (final entry in _participantReadEntries) {
      if (myId != null && myId.isNotEmpty && entry.key == myId) continue;
      final at = entry.value;
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    _peerLastReadAt = latest;
  }

  Future<void> _loadCurrentUser() async {
    final userId = await _storage.getUserId();
    if (mounted) {
      setState(() {
        _currentUserId = userId;
        // _currentUserId may have arrived after the participants payload —
        // recompute which entries count as "peers" now.
        _refreshPeerLastRead();
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
        // Read receipts: the messages payload also carries
        // `participants: [{ userId, userName?, lastReadAt }]` — capture each
        // member's lastReadAt for the double-tick indicator.
        final readEntries = responseData is Map && responseData['participants'] is List
            ? (responseData['participants'] as List)
                .whereType<Map>()
                .map((raw) {
                  final map = Map<String, dynamic>.from(raw);
                  final uid = (map['userId'] ?? map['user_id'] ?? '').toString();
                  final at = _parseReadInstant(map['lastReadAt'] ??
                      map['last_read_at'] ??
                      map['readAt'] ??
                      map['read_at']);
                  return MapEntry(uid, at);
                })
                .where((entry) => entry.key.isNotEmpty)
                .toList()
            : _participantReadEntries;
        setState(() {
          _messages = data
              .whereType<Map>()
              .map((json) => Message.fromJson(Map<String, dynamic>.from(json)))
              .toList();
          _participantReadEntries = readEntries;
          _refreshPeerLastRead();
        });
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
        // First fill of the list — compute the smart replies for whatever is
        // already the newest incoming message.
        unawaited(_refreshSmartReplies());
      }
    } catch (e) {
      Logger.error('Error loading messages: $e');
      // A silent catch here rendered the EMPTY STATE for every failure (403
      // dead session, 500, network) — users concluded "the chat is empty"
      // while messages existed server-side. Surface the real reason.
      if (mounted) {
        setState(() => _loadError = ApiService.extractErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // -------------------------------------------------------------------------
  // MetricAi chat intelligence (web Chat.tsx parity) — availability probe,
  // smart replies above the composer, per-message translation and a
  // conversation summary sheet. Everything is soft-gated: when /ai/status
  // reports unavailable (plan without MetricAi, GLM unconfigured) the entry
  // points simply never render.
  // -------------------------------------------------------------------------

  Future<void> _probeMetricAiStatus() async {
    try {
      final response = await _api.getAiStatus();
      final data = response.data is Map ? response.data['data'] : null;
      if (!mounted) return;
      setState(() => _aiAvailable = data is Map && data['available'] == true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _aiAvailable = false);
    }
    if (_aiAvailable) await _refreshSmartReplies();
  }

  /// The newest visible message id when it was NOT sent by the current user
  /// (mirrors web's lastIncomingMessageId). Own messages, pending uploads,
  /// tombstones and call-log rows never count as incoming.
  String? get _lastIncomingMessageId {
    for (final message in _messages.reversed) {
      if (message.isPendingUpload || message.isTombstone) continue;
      final kind = (message.messageType ?? '').trim().toLowerCase();
      if (kind == 'call-log') continue;
      if (_currentUserId != null && message.senderId == _currentUserId) {
        return null;
      }
      return message.id;
    }
    return null;
  }

  /// (Re)fetches MetricAi smart replies for the latest incoming message.
  /// No-ops when MetricAi is unavailable or nothing new arrived.
  Future<void> _refreshSmartReplies() async {
    if (!_aiAvailable) return;
    final lastId = _lastIncomingMessageId;
    if (lastId == null) {
      if (mounted &&
          (_smartReplies.isNotEmpty ||
              _smartRepliesLoading ||
              _smartRepliesForMessageId != null)) {
        setState(() {
          _smartReplies = const <String>[];
          _smartRepliesLoading = false;
          _smartRepliesForMessageId = null;
        });
      }
      return;
    }
    if (_smartRepliesForMessageId == lastId) {
      // Already fetched (or fetching) for this exact incoming message —
      // socket echoes must not re-trigger the AI call, even when the
      // previous result came back empty.
      return;
    }
    if (!mounted) return;
    setState(() {
      _smartRepliesLoading = true;
      _smartRepliesForMessageId = lastId;
    });
    try {
      final response = await _api.getChatSmartReplies(widget.conversation.id);
      final data = response.data is Map ? response.data['data'] : null;
      final raw = data is Map && data['suggestions'] is List
          ? data['suggestions'] as List
          : const <dynamic>[];
      final list = raw
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .take(3)
          .toList();
      if (!mounted) return;
      setState(() {
        _smartReplies = list;
        _smartRepliesLoading = false;
      });
    } catch (_) {
      // Soft feature — silently drop the chips on any failure.
      if (!mounted) return;
      setState(() => _smartRepliesLoading = false);
    }
  }

  /// Sends a tapped suggestion chip as a normal message.
  Future<void> _sendSmartReply(String suggestion) async {
    final text = suggestion.trim();
    if (text.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _smartReplies = const <String>[];
      _smartRepliesForMessageId = null;
    });
    await _sendMessage(overrides: {'content': text});
  }

  /// MetricAi translation for one message (target = device language, web
  /// uses navigator.language). Result renders under the bubble body.
  Future<void> _translateMessage(Message message) async {
    final text = message.content.trim();
    if (text.isEmpty) {
      AppToast.show('Only text messages can be translated',
          type: AppToastType.info);
      return;
    }
    if (_translatingId != null) return;
    final target = Platform.localeName
        .split('_')
        .first
        .split('.')
        .first
        .toLowerCase();
    setState(() => _translatingId = message.id);
    try {
      final response = await _api.aiTranslateText(text, targetLanguage: target);
      final data = response.data is Map ? response.data['data'] : null;
      final translation =
          data is Map && data['translation'] != null
              ? data['translation'].toString().trim()
              : '';
      if (!mounted) return;
      if (translation.isEmpty) {
        AppToast.show('MetricAi could not translate this message',
            type: AppToastType.error);
      } else {
        setState(() => _translations[message.id] = translation);
      }
    } catch (e) {
      Logger.error('MetricAi translate failed: $e');
      if (mounted) {
        AppToast.show(ApiService.extractErrorMessage(e),
            type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _translatingId = null);
    }
  }

  /// Conversation summary sheet (web parity: "Summarize with MetricAi" in
  /// the header). The request runs inside a FutureBuilder so the sheet shows
  /// a reading state, then the summary; 409 "Nothing to summarize yet"
  /// surfaces as plain guidance instead of an error.
  void _showSummarizeSheet() {
    final colors = AppTheme.colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 16, color: kMetricAiViolet),
                  const SizedBox(width: 6),
                  Text(
                    'MetricAi summary',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.text,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: colors.textSecondary),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.55,
                ),
                child: FutureBuilder<dynamic>(
                  future: _api.summarizeConversation(widget.conversation.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 26),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kMetricAiViolet,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'MetricAi is reading the chat…',
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      // 409 "Nothing to summarize yet" and other soft cases
                      // read as guidance, hard failures surface their reason.
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          ApiService.extractErrorMessage(snapshot.error!),
                          style: TextStyle(
                            fontSize: 13.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      );
                    }
                    final res = snapshot.data;
                    final body =
                        res?.data is Map ? (res!.data as Map)['data'] : null;
                    final summary = body is Map && body['summary'] != null
                        ? body['summary'].toString().trim()
                        : '';
                    if (summary.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No summary available.',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      );
                    }
                    return SingleChildScrollView(
                      child: SelectableText(
                        summary,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          color: colors.text,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Smart-reply chips row (web Chat.tsx parity): "MetricAi is thinking…"
  /// while loading, then up to 3 violet pills. Tapping one sends it as a
  /// normal message. Returns shrink whenever any gate hides it.
  Widget _buildSmartRepliesRow(ThemeColors colors) {
    final show = _aiAvailable &&
        !_selectionMode &&
        _editingMessage == null &&
        !_isRecordingVoice &&
        (_smartRepliesLoading || _smartReplies.isNotEmpty);
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount:
              _smartRepliesLoading ? 1 : _smartReplies.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            if (_smartRepliesLoading) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: kMetricAiVioletSoft.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: kMetricAiVioletSoft.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: kMetricAiVioletSoft,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'MetricAi is thinking…',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: kMetricAiViolet,
                      ),
                    ),
                  ],
                ),
              );
            }
            if (index == 0) {
              return Icon(Icons.auto_awesome,
                  size: 14, color: kMetricAiVioletSoft);
            }
            final suggestion = _smartReplies[index - 1];
            return GestureDetector(
              onTap: () => unawaited(_sendSmartReply(suggestion)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: kMetricAiVioletSoft.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: kMetricAiVioletSoft.withValues(alpha: 0.4)),
                ),
                child: Text(
                  suggestion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kMetricAiViolet,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Lifecycle / reconnect resync (NO timers, NO polling — event-driven only)
  // -------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Android routinely kills background sockets: on resume, make sure the
    // connection is alive, re-join the room and backfill missed messages.
    _resyncAfterReconnect();
  }

  /// Fired by SocketService after a (re)connect + conversation re-join. The
  /// server drops `conversation:<id>` rooms on every reconnect, so the open
  /// thread must re-join (the service already did, via its registry) and
  /// silently refetch anything delivered while we were offline.
  void _handleSocketReconnected() {
    _resyncAfterReconnect();
  }

  /// Best-effort realtime resync for THIS conversation: reconnect when the
  /// socket died, re-emit the room join, then silently refetch the message
  /// list. Never toasts, never shows the error state, keeps optimistic /
  /// pending rows intact. Coalesced so resume + reconnect firing together
  /// still runs one refetch.
  Future<void> _resyncAfterReconnect() async {
    if (!mounted || _resyncInFlight || _isLoading) return;
    _resyncInFlight = true;
    try {
      if (!_socket.isConnected) {
        // waitForConnection nudges the socket manager (same helper the call
        // screens use after a cold push-tap start) and waits for the
        // reconnect to land — a plain `connect()` here would need the auth
        // identity, which this screen does not own.
        try {
          await _socket.waitForConnection();
        } catch (_) {}
      }
      if (!mounted) return;
      try {
        // Registers the room again if the fresh socket forgot it (a no-op
        // when the registry already holds it) and emits while connected.
        _socket.joinConversation(widget.conversation.id);
      } catch (_) {}
      await _resyncMessages();
    } catch (e) {
      Logger.error('Chat resync failed: $e');
    } finally {
      _resyncInFlight = false;
    }
  }

  /// Silent variant of [_loadMessages]: same loader + read-receipt capture,
  /// but failures are swallowed (whatever list the user already sees stays
  /// untouched) and optimistic pending rows survive — the server cannot know
  /// about an in-flight upload.
  Future<void> _resyncMessages() async {
    try {
      final response = await _api.getConversationMessages(widget.conversation.id);
      if (response.data['success'] != true || !mounted) return;
      final responseData = response.data['data'];
      final data = responseData is Map && responseData['messages'] is List
          ? responseData['messages'] as List
          : responseData is List
              ? responseData
              : <dynamic>[];
      final readEntries = responseData is Map && responseData['participants'] is List
          ? (responseData['participants'] as List)
              .whereType<Map>()
              .map((raw) {
                final map = Map<String, dynamic>.from(raw);
                final uid = (map['userId'] ?? map['user_id'] ?? '').toString();
                final at = _parseReadInstant(map['lastReadAt'] ??
                    map['last_read_at'] ??
                    map['readAt'] ??
                    map['read_at']);
                return MapEntry(uid, at);
              })
              .where((entry) => entry.key.isNotEmpty)
              .toList()
          : _participantReadEntries;
      final fetched = data
          .whereType<Map>()
          .map((json) => Message.fromJson(Map<String, dynamic>.from(json)))
          .toList();
      // Keep optimistic rows the fresh list cannot contain yet.
      final pending = _messages
          .where((m) =>
              m.isPendingUpload &&
              !fetched.any((f) => f.id == m.id))
          .toList();
      // Only auto-scroll when the user was already reading the tail.
      final shouldStick = !_scrollController.hasClients ||
          _scrollController.position.maxScrollExtent <= 0 ||
          _scrollController.offset >=
              _scrollController.position.maxScrollExtent - 120;
      setState(() {
        _messages = [...fetched, ...pending];
        _participantReadEntries = readEntries;
        _refreshPeerLastRead();
      });
      if (shouldStick) {
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    } catch (e) {
      Logger.error('Silent message resync failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // @mention (group conversations only)
  // -------------------------------------------------------------------------

  /// One-time participant fetch powering the mention overlay. Falls back to
  /// the conversation payload's enriched participants when the roster
  /// endpoint is unavailable (older backend).
  Future<void> _loadMentionMembers() async {
    try {
      final response = await _api.getConversationParticipants(widget.conversation.id);
      final data = response.data is Map ? response.data['data'] : null;
      final rows = data is Map && data['participants'] is List
          ? data['participants'] as List
          : const <dynamic>[];
      final members = rows
          .whereType<Map>()
          .map((raw) {
            final map = Map<String, dynamic>.from(raw);
            final userId = (map['userId'] ?? map['user_id'] ?? '').toString();
            final name = (map['name'] ?? '').toString().trim();
            final email = (map['email'] ?? '').toString().trim();
            return ChatUserProfile(
              userId: userId,
              name: name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Member'),
              email: email,
              avatarUrl: map['avatarUrl']?.toString(),
              role: map['role']?.toString(),
            );
          })
          .where((m) => m.userId.isNotEmpty)
          .toList();
      if (!mounted || members.isEmpty) return;
      setState(() {
        _mentionMembers = members;
        _mentionLoaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _mentionMembers = widget.conversation.participants
              .where((p) => p.userId.isNotEmpty)
              .map((p) => ChatUserProfile(
                    userId: p.userId,
                    name: p.name.trim().isNotEmpty
                        ? p.name.trim()
                        : (p.email.isNotEmpty ? p.email : 'Member'),
                    email: p.email,
                    avatarUrl: p.avatarUrl,
                  ))
              .toList();
          _mentionLoaded = true;
        });
      }
    }
  }

  /// Re-evaluates the trailing '@token' before the caret. Opens/closes the
  /// mention overlay and (re)computes the filtered candidate list.
  void _updateMentionState() {
    if (widget.conversation.type != 'group' || !_mentionLoaded) return;
    final text = _messageController.text;
    var caret = _messageController.selection.baseOffset;
    if (caret < 0 || caret > text.length) caret = text.length;
    final before = text.substring(0, caret);
    final match = _mentionPattern.firstMatch(before);
    if (match == null) {
      if (_mentionToken != null && mounted) {
        setState(() {
          _mentionToken = null;
          _mentionHighlight = 0;
        });
      }
      return;
    }
    final token = match.group(1) ?? '';
    if (_mentionToken != token && mounted) {
      setState(() {
        _mentionToken = token;
        _mentionHighlight = 0;
      });
    }
  }

  List<ChatUserProfile> get _mentionCandidates {
    final token = (_mentionToken ?? '').toLowerCase();
    final me = _currentUserId;
    return _mentionMembers
        .where((m) => me == null || m.userId != me)
        .where((m) => token.isEmpty || m.displayName.toLowerCase().contains(token))
        .take(6)
        .toList();
  }

  /// Inserts '@Name ' replacing the partial token, closes the overlay and
  /// restores focus + caret position after the inserted mention.
  void _insertMention(ChatUserProfile member) {
    final text = _messageController.text;
    var caret = _messageController.selection.baseOffset;
    if (caret < 0 || caret > text.length) caret = text.length;
    final before = text.substring(0, caret);
    final match = _mentionPattern.firstMatch(before);
    if (match == null) {
      if (mounted) setState(() => _mentionToken = null);
      return;
    }
    // Group 0 starts with the leading whitespace (or string start); the '@'
    // itself sits right after it.
    final atStart = match.start == 0 ? 0 : match.start + 1;
    final insertion = '@${member.displayName} ';
    final newText = text.replaceRange(atStart, caret, insertion);
    final newCaret = atStart + insertion.length;
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCaret),
    );
    if (mounted) {
      setState(() {
        _mentionToken = null;
        _mentionHighlight = 0;
      });
    }
    if (!_composerFocus.hasFocus) {
      _composerFocus.requestFocus();
    }
  }

  void _closeMentionOverlay() {
    if (_mentionToken == null) return;
    if (mounted) {
      setState(() {
        _mentionToken = null;
        _mentionHighlight = 0;
      });
    }
  }

  /// Blur closes the overlay — delayed a beat so tapping a candidate row
  /// (which blurs the field before the InkWell tap lands) still inserts.
  void _handleComposerFocusChange() {
    if (_composerFocus.hasFocus) return;
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted && !_composerFocus.hasFocus) {
        _closeMentionOverlay();
      }
    });
  }

  /// Enter/Tab insert the highlighted mention, ArrowUp/Down move the
  /// highlight, Escape closes — only while the overlay is open, everything
  /// else (including the newline Enter) passes through untouched.
  KeyEventResult _handleComposerKeyEvent(FocusNode node, KeyEvent event) {
    final candidates = _mentionCandidates;
    final overlayOpen = _mentionToken != null && candidates.isNotEmpty;
    if (!overlayOpen) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _closeMentionOverlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      final index = _mentionHighlight.clamp(0, candidates.length - 1).toInt();
      _insertMention(candidates[index]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (mounted) {
        setState(() => _mentionHighlight =
            (_mentionHighlight + 1).clamp(0, candidates.length - 1).toInt());
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (mounted) {
        setState(() => _mentionHighlight =
            (_mentionHighlight - 1).clamp(0, candidates.length - 1).toInt());
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Candidate list floating directly above the composer (WhatsApp-style),
  /// rendered inside the existing body column — no overlay machinery.
  Widget _buildMentionOverlay(ThemeColors colors) {
    final candidates = _mentionCandidates;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      constraints: const BoxConstraints(maxHeight: 236),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: candidates.length,
        itemBuilder: (context, index) {
          final member = candidates[index];
          final highlighted = index == _mentionHighlight;
          return InkWell(
            onTap: () => _insertMention(member),
            child: Container(
              color: highlighted ? colors.primaryBg : Colors.transparent,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  AvatarWithInitials(
                    name: member.displayName,
                    imageUrl: member.avatarUrl,
                    radius: 14,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                  ),
                  if (member.roleLabel != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      member.roleLabel!,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _onTextChanged(String text) {
    // Refresh the send-button gradient as the composer empties/fills
    if (mounted) setState(() {});
    // @mention detection: trailing '@token' before the caret (groups only).
    _updateMentionState();
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

  /// Text path: reads the composer (or an explicit override) and forwards to
  /// [_sendPayload]. Text messages only — attachments use _sendPayload
  /// directly after their upload resolves. [force] bypasses the sending lock
  /// for flows that already hold it (voice notes).
  Future<void> _sendMessage({Map<String, dynamic>? overrides, bool force = false}) async {
    final content = (overrides?['content'] as String?) ?? _messageController.text.trim();
    if (content.isEmpty) return;
    if (_isSending && !force) return;
    await _sendPayload({
      'content': content,
      ...?overrides,
    }, force: force);
    if (overrides == null) _messageController.clear();
  }

  /// Core send: posts the payload to POST /chat/conversations/:id/messages,
  /// upserts the returned message and surfaces errors. Shared by text,
  /// stickers, GIFs, attachments and voice notes. [force] bypasses the
  /// _isSending guard for flows that already hold the lock (voice notes set
  /// it themselves while recording/uploading — without this the guard
  /// silently swallowed every voice-note send).
  Future<void> _sendPayload(Map<String, dynamic> payload, {bool force = false}) async {
    if (_isSending && !force) return;

    _typingStopTimer?.cancel();
    _socket.emitChatStopTyping({
      'conversationId': widget.conversation.id,
      'userId': _currentUserId,
    });

    // Reply quoting: the backend validates `replyToId` against the same
    // conversation (server/routes/chat.ts sendMessage).
    final reply = _replyTo;
    final payloadWithReply = <String, dynamic>{
      ...payload,
      if (reply != null) 'replyToId': reply.id,
    };

    setState(() => _isSending = true);
    try {
      final response = await _api.sendMessage(widget.conversation.id, payloadWithReply);
      if (response.data['success'] == true && mounted) {
        final message = _extractMessage(response.data);
        setState(() {
          _upsertMessage(message);
          _replyTo = null;
        });
        _scrollToBottom();
        // Outgoing-message blip (WhatsApp-style). Voice notes played their own
        // sound on the recorder path; this covers text/sticker/GIF/attachment.
        AppFeedback.playSentSound();
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

  // -----------------------------------------------------------------------
  // Message actions (long-press): reply / copy / edit / delete — plus
  // multi-select (Forward / Delete N / Select all) and Share for attachments.
  // -----------------------------------------------------------------------

  void _clearComposerContext() {
    if (!mounted) return;
    setState(() {
      _replyTo = null;
      _editingMessage = null;
      _messageController.clear();
    });
  }

  void _enterSelectionMode(String messageId) {
    setState(() {
      _selectionMode = true;
      _selectedMessageIds
        ..clear()
        ..add(messageId);
    });
  }

  void _exitSelectionMode() {
    if (!_selectionMode && _selectedMessageIds.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _toggleSelected(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        // Deselecting the last bubble drops out of selection mode (WhatsApp
        // behaviour — the toolbar has nothing left to act on).
        if (_selectedMessageIds.isEmpty) _selectionMode = false;
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  /// Tap behaviour on a bubble: selection mode toggles, otherwise no-op (the
  /// long-press sheet is the entry point).
  void _handleBubbleTap(Message message) {
    if (_selectionMode) _toggleSelected(message.id);
  }

  void _selectAllSelectable() {
    setState(() {
      for (final message in _messages) {
        if (_isSelectable(message)) _selectedMessageIds.add(message.id);
      }
    });
  }

  /// The rows eligible for long-press actions — also the selection universe
  /// (call-logs have their own tap-through, tombstones/pending rows aren't
  /// real content).
  bool _isSelectable(Message message) {
    return !message.isPendingUpload &&
        !message.isTombstone &&
        (message.messageType ?? '').trim().toLowerCase() != 'call-log';
  }

  /// Delete every selected message. Own messages tombstone for everyone,
  /// others delete for me only (mirrors the single-message rules). One
  /// failure never aborts the batch.
  Future<void> _deleteSelected() async {
    if (_selectedMessageIds.isEmpty) return;
    final count = _selectedMessageIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete $count message${count == 1 ? '' : 's'}?'),
        content: const Text(
            'Your own messages are removed for everyone; received ones only for you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final targets = _messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    _exitSelectionMode();
    for (final message in targets) {
      final isMine = _currentUserId != null && message.senderId == _currentUserId;
      try {
        await _api.deleteChatMessage(
          widget.conversation.id,
          message.id,
          scope: isMine ? 'everyone' : 'me',
        );
        if (!mounted) return;
        setState(() {
          if (isMine) {
            _upsertMessage(message.copyWith(
              content: '',
              deletedForEveryone: true,
              isPendingDelete: true,
            ));
          } else {
            _messages.removeWhere((m) => m.id == message.id);
          }
        });
      } catch (e) {
        Logger.error('deleteSelected(${message.id}) failed: $e');
      }
    }
  }

  /// Body forwarded to the target conversations: the ORIGINAL message fields
  /// (content, attachment url/type/name/size, messageType) + forwarded: true
  /// (api.sendMessage adds the flag).
  Map<String, dynamic> _forwardPayloadFor(Message message) {
    final kind = (message.messageType ?? '').trim().toLowerCase();
    final url = ApiService.resolveMediaUrl(message.attachmentUrl);
    return <String, dynamic>{
      if (message.content.trim().isNotEmpty) 'content': message.content,
      if (url != null) 'attachmentUrl': url,
      if ((message.attachmentType ?? '').isNotEmpty)
        'attachmentType': message.attachmentType,
      if ((message.attachmentName ?? '').isNotEmpty)
        'attachmentName': message.attachmentName,
      if ((message.attachmentSize ?? 0) > 0) 'attachmentSize': message.attachmentSize,
      if (kind.isNotEmpty && kind != 'text') 'messageType': kind,
    };
  }

  /// Opens the target picker (search + conversations list, multi-select) and
  /// re-sends every selected message into each chosen chat.
  void _showForwardSheet() {
    final messages = _messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    if (messages.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _ForwardSheet(
        messages: messages,
        currentUserId: _currentUserId,
        payloadFor: _forwardPayloadFor,
      ),
    ).then((_) => _exitSelectionMode());
  }

  /// WhatsApp-style long-press sheet. Edit is limited to the sender's own
  /// TEXT messages within 24h (mirrors the backend's MESSAGE_EDIT_WINDOW_MS);
  /// delete-for-everyone is sender-only, delete-for-me is always available.
  void _showMessageActions(Message message) {
    final colors = AppTheme.colors;
    final isMine = _currentUserId != null && message.senderId == _currentUserId;
    final kind = (message.messageType ?? 'text').trim().toLowerCase();
    final isText = kind.isEmpty || kind == 'text';
    final canEdit = isMine &&
        isText &&
        DateTime.now().difference(message.createdAt.toLocal()) <=
            const Duration(hours: 24);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            _MessageActionTile(
              icon: Icons.reply_rounded,
              color: colors.primary,
              title: 'Reply',
              colors: colors,
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() {
                  _replyTo = message;
                  _editingMessage = null;
                });
              },
            ),
            _MessageActionTile(
              icon: Icons.copy_rounded,
              color: colors.primary,
              title: 'Copy',
              colors: colors,
              onTap: () {
                Navigator.pop(sheetContext);
                Clipboard.setData(ClipboardData(text: message.content));
              },
            ),
            // MetricAi translate (web Chat.tsx parity): any message carrying
            // text — captions included — translated to the device language;
            // the result renders under the bubble body.
            if (message.content.trim().isNotEmpty && _aiAvailable)
              _MessageActionTile(
                icon: Icons.translate_rounded,
                color: kMetricAiViolet,
                title: _translatingId == message.id
                    ? 'Translating…'
                    : 'Translate',
                colors: colors,
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_translateMessage(message));
                },
              ),
            // Share an attachment out of the app (system share sheet). The
            // helper downloads via the same authenticated path the document
            // tile uses, then hands the local file to SharePlus.
            if ((message.attachmentUrl ?? '').trim().isNotEmpty)
              _MessageActionTile(
                icon: Icons.share_rounded,
                color: colors.primary,
                title: 'Share',
                colors: colors,
                onTap: () {
                  Navigator.pop(sheetContext);
                  final url = message.attachmentUrl!.trim();
                  unawaited(shareChatAttachment(
                    url,
                    attachmentDisplayName(message.attachmentName, url),
                  ));
                },
              ),
            _MessageActionTile(
              icon: Icons.shortcut_rounded,
              color: colors.primary,
              title: 'Forward',
              colors: colors,
              onTap: () {
                Navigator.pop(sheetContext);
                _enterSelectionMode(message.id);
                _showForwardSheet();
              },
            ),
            _MessageActionTile(
              icon: Icons.checklist_rounded,
              color: colors.primary,
              title: 'Select',
              colors: colors,
              onTap: () {
                Navigator.pop(sheetContext);
                _enterSelectionMode(message.id);
              },
            ),
            if (canEdit)
              _MessageActionTile(
                icon: Icons.edit_rounded,
                color: colors.primary,
                title: 'Edit',
                colors: colors,
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() {
                    _editingMessage = message;
                    _replyTo = null;
                    _messageController.text = message.content;
                  });
                },
              ),
            _MessageActionTile(
              icon: Icons.visibility_off_rounded,
              color: colors.warning,
              title: 'Delete for me',
              colors: colors,
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_deleteMessage(message, scope: 'me'));
              },
            ),
            if (isMine)
              _MessageActionTile(
                icon: Icons.delete_rounded,
                color: colors.error,
                title: 'Delete for everyone',
                colors: colors,
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_deleteMessage(message, scope: 'everyone'));
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// PATCH /chat/conversations/:cid/messages/:mid { content } then mirror
  /// locally (the socket `message:updated` echo also upserts — same id).
  Future<void> _submitEdit() async {
    final editing = _editingMessage;
    if (editing == null || _isSending) return;
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    setState(() => _isSending = true);
    try {
      final response = await _api.editChatMessage(
        widget.conversation.id,
        editing.id,
        content: content,
      );
      if (response.data['success'] == true && mounted) {
        setState(() {
          _upsertMessage(editing.copyWith(content: content, editedAt: DateTime.now()));
          _editingMessage = null;
          _messageController.clear();
        });
      }
    } catch (e) {
      Logger.error('editMessage failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// DELETE /chat/conversations/:cid/messages/:mid?scope=me|everyone.
  /// scope=everyone optimistically tombstones (the server echo upserts the
  /// authoritative row); scope=me removes the row locally (no broadcast —
  /// it only disappears for THIS user).
  Future<void> _deleteMessage(Message message, {required String scope}) async {
    try {
      await _api.deleteChatMessage(widget.conversation.id, message.id, scope: scope);
      if (!mounted) return;
      setState(() {
        if (scope == 'everyone') {
          _upsertMessage(message.copyWith(
            content: '',
            deletedForEveryone: true,
            isPendingDelete: true,
          ));
        } else {
          _messages.removeWhere((m) => m.id == message.id);
        }
      });
    } catch (e) {
      Logger.error('deleteMessage($scope) failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    }
  }

  /// Reply/edit context pill above the composer.
  Widget _buildContextPill(ThemeColors colors) {
    final editing = _editingMessage;
    final reply = _replyTo;
    final isEdit = editing != null;
    final subject = isEdit ? editing : reply;
    final title = isEdit
        ? 'Editing message'
        : 'Replying to ${subject?.senderName ?? (subject?.senderId == _currentUserId ? 'yourself' : 'message')}';
    final snippet = subject?.content.trim() ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: colors.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isEdit ? Icons.edit_rounded : Icons.reply_rounded,
            size: 18,
            color: colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
                if (snippet.isNotEmpty)
                  Text(
                    snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel',
            icon: Icon(Icons.close_rounded, size: 18, color: colors.textSecondary),
            onPressed: _clearComposerContext,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Attachments (paperclip) — pick → optimistic pending bubble → POST
  // /chat/media → send message with attachmentUrl/name/size/messageType.
  // -------------------------------------------------------------------------

  /// Best-effort check whether the Tenor GIF proxy is configured server-side;
  /// drives GIF-tab visibility in the picker panel. Never surfaces errors.
  Future<void> _checkGifsConfigured() async {
    try {
      final result = await _api.getChatGifs(limit: 4);
      if (mounted) setState(() => _gifsConfigured = result.configured);
    } catch (_) {
      if (mounted) setState(() => _gifsConfigured = false);
    }
  }

  /// Tolerant parse of presence timestamps: ISO strings or epoch
  /// seconds/millis (the exact UTC-vs-millis bug class the last-seen header
  /// used to hit — see worklog).
  DateTime? _parsePresenceTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is num && value > 0) {
      final ms = value >= 100000000000 ? value.toInt() : (value.toInt() * 1000);
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    final raw = value.toString().trim();
    if (raw.isEmpty || raw == 'null') return null;
    return DateTime.tryParse(raw);
  }

  /// Header subtitle for direct chats: "online" or "last seen today at
  /// 19:46" — relative day + wall clock in the DEVICE timezone, honouring
  /// the app's 12/24h preference. Falls back to 'Direct message' when the
  /// backend has no presence data.
  String? _lastSeenLabel() {
    final status = _peerPresenceStatus?.toLowerCase();
    if (status == 'online' || status == 'available') return 'online';
    if (status == 'offline' && _peerLastSeenAt == null) return null;
    final seen =
        _peerLastSeenAt ?? widget.conversation.otherLastSeen(_currentUserId);
    if (seen == null) return null;
    final local = seen.toLocal();
    final now = DateUtils.dateOnly(DateTime.now());
    final that = DateUtils.dateOnly(local);
    final String day;
    if (that == now) {
      day = 'today';
    } else if (that == now.subtract(const Duration(days: 1))) {
      day = 'yesterday';
    } else {
      day = DateFormat.MMMEd().format(local);
    }
    final pattern = AppTimezone.instance.is24h ? 'HH:mm' : 'h:mm a';
    return 'last seen $day at ${DateFormat(pattern).format(local)}';
  }

  void _openAttachmentSheet() {
    final colors = AppTheme.colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            _AttachmentOption(
              icon: Icons.photo_library_outlined,
              color: colors.primary,
              title: 'Photo or Video',
              subtitle: 'Share images and videos from your gallery',
              colors: colors,
              onTap: () {
                Navigator.pop(sheetContext);
                _pickMediaAndUpload();
              },
            ),
            _AttachmentOption(
              icon: Icons.description_outlined,
              color: colors.success,
              title: 'Document',
              subtitle: 'PDF, Word, Excel, ZIP and more (up to 100 MB)',
              colors: colors,
              onTap: () {
                Navigator.pop(sheetContext);
                _pickDocumentAndUpload();
              },
            ),
            _AttachmentOption(
              icon: Icons.emoji_emotions_outlined,
              color: colors.warning,
              title: 'Stickers, Emoji & GIF',
              subtitle: 'Send stickers, emoji and animated GIFs',
              colors: colors,
              onTap: () {
                Navigator.pop(sheetContext);
                _openEmojiPanel();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _openEmojiPanel() {
    EmojiStickerGifPanel.show(
      context,
      colors: AppTheme.colors,
      gifsConfigured: _gifsConfigured,
      onEmojiSelected: (emoji) {
        if (_isSending) return;
        _sendMessage(overrides: {'content': emoji});
      },
      onStickerSelected: (emoji) {
        if (_isSending) return;
        _sendPayload({'content': emoji, 'messageType': 'sticker'});
      },
      onGifSelected: (gif) {
        if (_isSending) return;
        _sendPayload(<String, dynamic>{
          'attachmentUrl': gif.url,
          'attachmentType': 'gif',
          'attachmentName': gif.description,
          'messageType': 'gif',
        });
      },
    );
  }

  /// Gallery pick of an image OR video (image_picker pickMedia), then upload.
  Future<void> _pickMediaAndUpload() async {
    try {
      final media = await _imagePicker.pickMedia(
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (media == null || !mounted) return;
      final lowerPath = media.path.toLowerCase();
      final isVideo = (media.mimeType?.startsWith('video/') ?? false) ||
          const ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp']
              .any(lowerPath.endsWith);
      await _uploadAndSendAttachment(
        File(media.path),
        name: media.name,
        attachmentType: isVideo ? 'video' : 'image',
      );
    } catch (e) {
      Logger.error('Media pick failed: $e');
    }
  }

  /// Native document picker (any type — the backend filters/limits).
  Future<void> _pickDocumentAndUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      final picked = result?.files.single;
      if (picked == null || picked.path == null || !mounted) return;
      await _uploadAndSendAttachment(
        File(picked.path!),
        name: picked.name,
        size: picked.size,
        attachmentType: 'document',
      );
    } catch (e) {
      Logger.error('Document pick failed: $e');
    }
  }

  /// Shared upload flow: 100MB guard → optimistic pending bubble → POST
  /// /chat/media → send the real message → remove pending. On failure the
  /// pending bubble is removed and a SnackBar explains why.
  Future<void> _uploadAndSendAttachment(
    File file, {
    String? name,
    int? size,
    String? attachmentType,
  }) async {
    if (_isUploadingAttachment) return;
    final resolvedName = (name != null && name.isNotEmpty)
        ? name
        : file.path.split(Platform.pathSeparator).last;
    final kind = guessMediaKind(attachmentType, resolvedName);
    int bytes = size ?? 0;
    if (bytes <= 0) {
      try {
        bytes = await file.length();
      } catch (_) {}
    }
    if (bytes > 100 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachments are limited to 100 MB')),
        );
      }
      return;
    }
    final caption = _messageController.text.trim();

    final pendingId = 'upload-${DateTime.now().millisecondsSinceEpoch}';
    final pending = Message(
      id: pendingId,
      conversationId: widget.conversation.id,
      senderId: _currentUserId ?? '',
      content: caption,
      attachmentType: kind,
      attachmentName: resolvedName,
      attachmentSize: bytes > 0 ? bytes : null,
      createdAt: DateTime.now(),
      isPendingUpload: true,
    );
    setState(() {
      _isUploadingAttachment = true;
      _upsertMessage(pending);
    });
    _scrollToBottom();
    try {
      final upload = await _api.uploadChatMediaDetailed(file);
      if (upload == null || upload.url.isEmpty) {
        throw const FormatException('Upload failed. Please try again.');
      }
      // Tolerate relative URLs from the local-disk upload fallback.
      final url = ApiService.resolveMediaUrl(upload.url) ?? upload.url;
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == pendingId));
      }
      await _sendPayload(<String, dynamic>{
        if (caption.isNotEmpty) 'content': caption,
        'attachmentUrl': url,
        'attachmentType': kind,
        'attachmentName': upload.filename ?? resolvedName,
        if ((upload.size ?? bytes) > 0) 'attachmentSize': upload.size ?? bytes,
        'messageType': kind,
      });
      if (caption.isNotEmpty && mounted) _messageController.clear();
    } catch (e) {
      Logger.error('Attachment upload failed: $e');
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == pendingId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is FormatException
                ? e.message
                : ApiService.extractErrorMessage(e)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAttachment = false);
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
      final file = File(filePath);
      final upload = await _api.uploadChatMediaDetailed(file);
      if (upload == null || upload.url.isEmpty) {
        throw const FormatException('Voice note upload failed');
      }
      // Tolerate relative URLs from the local-disk upload fallback.
      final url = ApiService.resolveMediaUrl(upload.url) ?? upload.url;
      int bytes = upload.size ?? 0;
      if (bytes <= 0) {
        try {
          bytes = await file.length();
        } catch (_) {}
      }
      await _sendMessage(overrides: <String, dynamic>{
        'content': '🎤 Voice note',
        'attachmentUrl': url,
        'attachmentType': 'audio',
        'attachmentName': upload.filename ?? 'Voice note.m4a',
        if (bytes > 0) 'attachmentSize': bytes,
        'messageType': 'voice',
      }, force: true);
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
    WidgetsBinding.instance.removeObserver(this);
    _socket.removeOnReconnected(_handleSocketReconnected);
    // Leave the room locally: stops the service re-joining this conversation
    // after future reconnects (fire-and-forget emit kept for the backend).
    _socket.leaveConversation(widget.conversation.id);
    _composerFocus.removeListener(_handleComposerFocusChange);
    _composerFocus.dispose();
    if (ChatDetailScreen.activeConversationId == widget.conversation.id) {
      ChatDetailScreen.activeConversationId = null;
    }
    if (_socket.onMessageCreated == _messageCreatedHandler) {
      _socket.onMessageCreated = null;
    }
    if (_socket.onMessageUpdated == _messageUpdatedHandler) {
      _socket.onMessageUpdated = null;
    }
    if (_socket.onPresenceUpdate == _presenceHandler) {
      _socket.onPresenceUpdate = null;
    }
    if (_socket.onChatTyping == _typingHandler) {
      _socket.onChatTyping = null;
    }
    if (_socket.onChatStopTyping == _stopTypingHandler) {
      _socket.onChatStopTyping = null;
    }
    if (_socket.onConversationRead == _conversationReadHandler) {
      _socket.onConversationRead = null;
    }
    if (_socket.onChatConversationRead == _conversationReadHandler) {
      _socket.onChatConversationRead = null;
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

  /// Normal chat app bar (avatar + title + call actions). Hidden while the
  /// message-selection toolbar is active.
  PreferredSizeWidget _buildChatAppBar(ThemeColors colors) {
    final isDirect = widget.conversation.type != 'group';
    final memberCount = widget.conversation.participants.length;
    return AppBar(
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
                    isDirect
                        ? (_lastSeenLabel() ?? 'Direct message')
                        : '$memberCount members',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
        // MetricAi conversation summary (web parity: header dropdown item).
        if (_aiAvailable)
          _RoundIconAction(
            icon: Icons.auto_awesome_outlined,
            color: kMetricAiViolet,
            tooltip: 'Summarize with MetricAi',
            onTap: _showSummarizeSheet,
          ),
        const SizedBox(width: 6),
      ],
    );
  }

  /// WhatsApp-style selection toolbar: close, "<n> selected", select-all,
  /// forward and delete.
  PreferredSizeWidget _buildSelectionAppBar(ThemeColors colors) {
    final count = _selectedMessageIds.length;
    final allSelected = count > 0 &&
        count == _messages.where(_isSelectable).length;
    return AppBar(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      shadowColor: colors.border,
      iconTheme: IconThemeData(color: colors.text),
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: Icon(Icons.close_rounded, color: colors.text),
        onPressed: _exitSelectionMode,
      ),
      title: Text(
        '$count selected',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
      ),
      actions: [
        IconButton(
          tooltip: allSelected ? 'Deselect all' : 'Select all',
          icon: Icon(
            allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
            color: colors.primary,
          ),
          onPressed:
              allSelected ? _exitSelectionMode : _selectAllSelectable,
        ),
        IconButton(
          tooltip: 'Forward',
          icon: Icon(Icons.shortcut_rounded,
              color: count > 0 ? colors.primary : colors.textSecondary),
          onPressed: count > 0 ? _showForwardSheet : null,
        ),
        IconButton(
          tooltip: 'Delete',
          icon: Icon(Icons.delete_outline_rounded,
              color: count > 0 ? colors.error : colors.textSecondary),
          onPressed: count > 0
              ? () {
                  unawaited(_deleteSelected());
                }
              : null,
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isCurrentUser(String senderId) => senderId == _currentUserId;
    final colors = AppTheme.colors;
    final isDirect = widget.conversation.type != 'group';

    return Scaffold(
      backgroundColor: colors.background,
      appBar: _selectionMode
          ? _buildSelectionAppBar(colors)
          : _buildChatAppBar(colors),
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
                              child: Icon(
                                  _loadError != null
                                      ? Icons.cloud_off_rounded
                                      : Icons.chat_bubble_outline_rounded,
                                  size: 38, color: colors.primary),
                            ),
                            const SizedBox(height: 16),
                            Text(
                                _loadError != null
                                    ? 'Couldn\'t load messages'
                                    : 'No messages yet',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colors.text)),
                            const SizedBox(height: 6),
                            Text(
                                _loadError != null
                                    ? _loadError!
                                    : 'Say hello — send the first message!',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colors.textSecondary)),
                            if (_loadError != null) ...[
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isLoading = true;
                                    _loadError = null;
                                  });
                                  _loadMessages();
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('Try again'),
                              ),
                            ],
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
                          // Long-press actions (reply/edit/delete) — skipped
                          // for call-log rows (they have their own tap-
                          // through) and for tombstones.
                          final canShowActions = !message.isPendingUpload &&
                              !message.isTombstone &&
                              (message.messageType ?? '').trim().toLowerCase() !=
                                  'call-log';
                          final nameMap = <String, String>{
                            for (final p in widget.conversation.participants)
                              p.userId: p.name.trim().isNotEmpty
                                  ? p.name.trim()
                                  : (p.email.isNotEmpty ? p.email : 'Member'),
                          };

                          final isSelected =
                              _selectedMessageIds.contains(message.id);

                          Widget bubble = _MessageBubble(
                            message: message,
                            isMe: isMe,
                            showSenderName:
                                !isDirect && showHeader,
                            colors: colors,
                            participantNames: nameMap,
                            peerReadAt: _peerLastReadAt,
                            translatedText: _translations[message.id],
                          );
                          if (_selectionMode) {
                            // WhatsApp-style leading check for selected rows.
                            bubble = Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    size: 20,
                                    color: isSelected
                                        ? colors.primary
                                        : colors.textSecondary,
                                  ),
                                ),
                                Expanded(child: bubble),
                              ],
                            );
                          }

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
                              GestureDetector(
                                onTap: () => _handleBubbleTap(message),
                                onLongPress: canShowActions
                                    ? () => _showMessageActions(message)
                                    : null,
                                child: bubble,
                              ),
                            ],
                          );
                        },
                      ),
          ),
          // Reply/edit context pill (WhatsApp-style quote above composer)
          if (_replyTo != null || _editingMessage != null)
            _buildContextPill(colors),
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
          // @mention candidates (group conversations only) — sits directly
          // above the composer inside the existing column.
          if (_mentionToken != null && _mentionCandidates.isNotEmpty)
            _buildMentionOverlay(colors),
          // MetricAi smart replies (web Chat.tsx parity) — chips row above
          // the composer; the builder returns shrink when hidden.
          if (!_selectionMode) _buildSmartRepliesRow(colors),
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

  /// Normal text composer. A paperclip (attachments), emoji panel button and
  /// — while the field is empty — a mic button sit to the LEFT of the text
  /// field; once the user types, the send button takes over on the right.
  /// While EDITING a message the send button confirms the edit instead.
  Widget _buildTextComposer(ThemeColors colors) {
    final hasText = _messageController.text.trim().isNotEmpty;
    final isEditing = _editingMessage != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: 'Attach',
            style: IconButton.styleFrom(
              backgroundColor: colors.primaryBg,
              shape: const CircleBorder(),
            ),
            icon: Icon(Icons.attach_file_rounded, color: colors.primary, size: 21),
            onPressed: _openAttachmentSheet,
          ),
        ),
        const SizedBox(width: 8),
        if (!hasText && !isEditing) ...[
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Emoji, stickers & GIFs',
              style: IconButton.styleFrom(
                backgroundColor: colors.primaryBg,
                shape: const CircleBorder(),
              ),
              icon: Icon(Icons.emoji_emotions_outlined, color: colors.primary, size: 21),
              onPressed: _openEmojiPanel,
            ),
          ),
          const SizedBox(width: 8),
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
          child: Focus(
            onKeyEvent: _handleComposerKeyEvent,
            child: TextField(
              controller: _messageController,
              focusNode: _composerFocus,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 5,
              onChanged: _onTextChanged,
              style: TextStyle(color: colors.text, fontSize: 14.5),
              decoration: InputDecoration(
                hintText: isEditing ? 'Update message…' : 'Type a message...',
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
              // Enter/newline on the keyboard inserts a line break (paragraph);
              // sending happens via the send button only. While the mention
              // overlay is open Enter/Tab insert the highlighted member.
            ),
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
            tooltip: isEditing ? 'Confirm edit' : 'Send',
            icon: _isSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(isEditing ? Icons.check_rounded : Icons.send_rounded,
                    color: Colors.white, size: 20),
            onPressed: _isSending
                ? null
                : (isEditing ? _submitEdit : () => _sendMessage()),
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

  /// conversationId → display name (from the conversation's enriched
  /// participants) for the call-log summary sheet.
  final Map<String, String> participantNames;

  /// Latest instant a peer read the conversation (read receipts). Null when
  /// unknown — own bubbles then show a single sent tick.
  final DateTime? peerReadAt;

  /// MetricAi translation of the message body (device language). Null when
  /// not requested yet — web Chat.tsx parity ("translatedText").
  final String? translatedText;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showSenderName,
    required this.colors,
    this.participantNames = const {},
    this.peerReadAt,
    this.translatedText,
  });

  /// Teams-style read state for OWN messages: the message was created at or
  /// before the peer's latest lastReadAt. Compared in UTC — createdAt is UTC
  /// and lastReadAt is parsed toUtc — so DST/local offsets can't flip it.
  bool get _isReadByPeer {
    final read = peerReadAt;
    if (read == null) return false;
    return !message.createdAt.toUtc().isAfter(read.toUtc());
  }

  /// Resolved presentation kind. Prefers the explicit messageType from the
  /// batch-3 backend, falls back to attachmentType (tolerating legacy raw
  /// MIME types like `image/png`), then to plain text.
  String get _kind {
    final explicit = message.messageType?.trim().toLowerCase() ?? '';
    if (explicit.isNotEmpty && explicit != 'text') return explicit;
    if (message.attachmentUrl?.isNotEmpty ?? false) {
      return guessMediaKind(message.attachmentType,
          message.attachmentName ?? message.attachmentUrl);
    }
    return 'text';
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;

    // Deleted tombstone (WhatsApp-style) — wins over every other layout.
    if (message.isTombstone) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block_rounded, size: 14, color: colors.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  isMe ? 'You deleted this message' : 'This message was deleted',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Call-log rows are slim centered entries without a bubble.
    if (kind == 'call-log') {
      return CallLogRow(
        message: message,
        isMe: isMe,
        colors: colors,
        participantNames: participantNames,
      );
    }

    // Optimistic pending bubble while POST /chat/media is in flight.
    if (message.isPendingUpload) {
      return _UploadingBubble(message: message, isMe: isMe, colors: colors);
    }

    // Sticker: single emoji at ~96px, no bubble background.
    if (kind == 'sticker') {
      return _TransparentMessage(
        message: message,
        isMe: isMe,
        showSenderName: showSenderName,
        colors: colors,
        child: Text(
          message.content,
          style: const TextStyle(fontSize: 96, height: 1.15),
        ),
      );
    }

    // GIF: large image, no bubble background (caption kept as small text).
    if (kind == 'gif') {
      final url = ApiService.resolveMediaUrl(message.attachmentUrl);
      if (url == null) return _regularBubble(context, 'text');
      return _TransparentMessage(
        message: message,
        isMe: isMe,
        showSenderName: showSenderName,
        colors: colors,
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            ChatGifView(url: url, colors: colors),
            if (message.content.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                message.content,
                style: TextStyle(fontSize: 12.5, color: colors.text),
              ),
            ],
          ],
        ),
      );
    }

    // Big emoji: content is ONLY 1-3 emoji (hardened regex — "123" or words
    // never match) → giant glyph, no bubble.
    if (kind == 'text' && isSoloEmojiMessage(message.content)) {
      return _TransparentMessage(
        message: message,
        isMe: isMe,
        showSenderName: showSenderName,
        colors: colors,
        child: Text(
          message.content,
          style: const TextStyle(fontSize: 64, height: 1.2),
        ),
      );
    }

    return _regularBubble(context, kind);
  }

  /// Quoted reply preview inside the bubble (from message.replyTo — the
  /// backend hydrates { id, senderName, content, messageType }).
  Widget _quoteBlock(ThemeColors colors) {
    final reply = message.replyTo!;
    final name = (reply.senderName?.trim().isNotEmpty ?? false)
        ? reply.senderName!.trim()
        : 'Message';
    final snippet = reply.content.trim().isEmpty ? 'Media' : reply.content.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.16)
            : colors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white70 : colors.primary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isMe ? Colors.white : colors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            snippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: isMe ? Colors.white70 : colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _regularBubble(BuildContext context, String kind) {
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMe ? 16 : 4),
      topRight: Radius.circular(isMe ? 4 : 16),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );

    final url = ApiService.resolveMediaUrl(message.attachmentUrl);
    final caption = message.content.trim();

    Widget? media;
    switch (kind) {
      case 'image':
        media = url == null
            ? null
            : ChatImageView(url: url, isMe: isMe, colors: colors);
        break;
      case 'video':
        media = url == null
            ? null
            : ChatVideoCard(
                url: url,
                name: message.attachmentName,
                size: message.attachmentSize,
                isMe: isMe,
                colors: colors,
              );
        break;
      case 'audio':
      case 'voice':
        media = url == null
            ? null
            : _VoiceNoteBubble(url: url, isMe: isMe, colors: colors);
        break;
      case 'document':
        media = url == null
            ? null
            : ChatDocumentTile(
                url: url,
                name: message.attachmentName ?? caption,
                size: message.attachmentSize,
                isMe: isMe,
                colors: colors,
              );
        break;
    }

    final bool hasMedia = media != null;
    // Voice notes carry the '🎤 Voice note' label already — don't double it.
    final showCaption =
        hasMedia && caption.isNotEmpty && kind != 'audio' && kind != 'voice';

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
            if (message.replyTo != null) _quoteBlock(colors),
            if (media == null)
              StyledText(
                message.content,
                baseStyle: TextStyle(
                  color: isMe ? Colors.white : colors.text,
                  fontSize: 14.5,
                  height: 1.35,
                ),
              )
            else ...[
              media,
              if (showCaption) ...[
                const SizedBox(height: 4),
                StyledText(
                  caption,
                  baseStyle: TextStyle(
                    color: isMe ? Colors.white : colors.text,
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
              ],
            ],
            // MetricAi translation (web Chat.tsx parity) — small violet-
            // labelled card under the body, matching the bubble's palette.
            if (translatedText != null && translatedText!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
                decoration: BoxDecoration(
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.12)
                      : colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: kMetricAiVioletSoft.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome,
                            size: 10, color: kMetricAiVioletSoft),
                        const SizedBox(width: 4),
                        Text(
                          'MetricAi',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: isMe
                                ? const Color(0xFFDDD6FE)
                                : kMetricAiViolet,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      translatedText!.trim(),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: isMe ? Colors.white : colors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Read receipt (own messages only; pending uploads keep their
                // spinner look — they never reach this branch anyway).
                if (isMe) ...[
                  Icon(
                    _isReadByPeer ? Icons.done_all : Icons.done,
                    size: _isReadByPeer ? 14 : 13,
                    color: _isReadByPeer
                        ? const Color(0xFF7DD3FC)
                        : (isMe ? Colors.white70 : colors.textSecondary),
                  ),
                  const SizedBox(width: 3),
                ],
                Text(
                  '${DateFormat.Hm().format(message.createdAt.toLocal())}'
                  '${message.editedAt != null ? ' · edited' : ''}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white70 : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bubble-less message wrapper (stickers, GIFs, solo emoji): keeps the row
/// alignment, group sender name and timestamp but no bubble chrome.
class _TransparentMessage extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool showSenderName;
  final ThemeColors colors;
  final Widget child;

  const _TransparentMessage({
    required this.message,
    required this.isMe,
    required this.showSenderName,
    required this.colors,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
            child,
            const SizedBox(height: 2),
            Text(
              DateFormat.Hm().format(message.createdAt.toLocal()),
              style: TextStyle(fontSize: 10, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Optimistic pending bubble shown while an attachment uploads via POST
/// /chat/media (removed on failure with a SnackBar, replaced by the real
/// message once the upload + send complete).
class _UploadingBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final ThemeColors colors;

  const _UploadingBubble({
    required this.message,
    required this.isMe,
    required this.colors,
  });

  String get _label {
    switch (message.attachmentType) {
      case 'image':
        return 'Sending photo…';
      case 'video':
        return 'Sending video…';
      case 'audio':
      case 'voice':
        return 'Sending voice note…';
      case 'gif':
        return 'Sending GIF…';
      case 'sticker':
        return 'Sending sticker…';
      default:
        return 'Uploading ${message.attachmentName ?? 'document'}…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          gradient: isMe
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.primary, colors.primaryDark],
                )
              : null,
          color: isMe ? null : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: isMe ? null : Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isMe ? Colors.white : colors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isMe ? Colors.white : colors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the attachment bottom sheet (Photo or Video / Document /
/// Stickers, Emoji & GIF).
class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final ThemeColors colors;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
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

/// One row of the long-press message actions sheet (Reply / Copy / Share /
/// Forward / Select / Edit / Delete for me / Delete for everyone).
class _MessageActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final ThemeColors colors;
  final VoidCallback onTap;

  const _MessageActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Forward target picker: search + the user's conversations (multi-select),
/// then re-sends every selected message into each chosen chat via
/// POST /chat/conversations/:id/messages with the ORIGINAL body fields +
/// forwarded: true. Sequential with per-message try/catch — one failure never
/// aborts the batch — and a progress indicator while sending.
class _ForwardSheet extends StatefulWidget {
  final List<Message> messages;
  final String? currentUserId;
  final Map<String, dynamic> Function(Message message) payloadFor;

  const _ForwardSheet({
    required this.messages,
    required this.currentUserId,
    required this.payloadFor,
  });

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  List<Conversation> _conversations = [];
  bool _loading = true;
  String? _loadError;
  String _query = '';
  final Set<String> _selectedIds = <String>{};
  bool _forwarding = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response = await _api.getConversations();
      if (response.data['success'] == true && mounted) {
        final responseData = response.data['data'];
        final data = responseData is Map && responseData['conversations'] is List
            ? responseData['conversations'] as List
            : responseData is List
                ? responseData
                : <dynamic>[];
        setState(() {
          _conversations = data
              .whereType<Map>()
              .map((json) =>
                  Conversation.fromJson(Map<String, dynamic>.from(json)))
              .toList();
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      Logger.error('Forward sheet: loading conversations failed: $e');
      if (mounted) {
        setState(() {
          _loadError = ApiService.extractErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  List<Conversation> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _conversations;
    return _conversations
        .where((c) => c.displayTitle(widget.currentUserId).toLowerCase().contains(query))
        .toList();
  }

  Future<void> _forward() async {
    if (_selectedIds.isEmpty || _forwarding) return;
    final targets = _conversations
        .where((c) => _selectedIds.contains(c.id))
        .toList();
    setState(() {
      _forwarding = true;
      _total = targets.length * widget.messages.length;
      _done = 0;
    });
    // chatId -> succeeded message count
    final okPerChat = <String, int>{};
    var failures = 0;
    for (final conversation in targets) {
      var okCount = 0;
      for (final message in widget.messages) {
        try {
          final response = await _api.sendMessage(
            conversation.id,
            widget.payloadFor(message),
            forwarded: true,
          );
          if (response.data['success'] == true) {
            okCount += 1;
          } else {
            failures += 1;
          }
        } catch (e) {
          Logger.error('Forward to ${conversation.id} failed: $e');
          failures += 1;
        }
        if (mounted) setState(() => _done += 1);
      }
      if (okCount > 0) okPerChat[conversation.id] = okCount;
    }
    if (!mounted) return;
    final chats = okPerChat.length;
    Navigator.of(context).pop();
    if (failures == 0) {
      AppToast.show(
        'Forwarded to $chats ${chats == 1 ? 'chat' : 'chats'}',
        type: AppToastType.success,
      );
    } else if (chats > 0) {
      AppToast.show(
        'Forwarded to $chats ${chats == 1 ? 'chat' : 'chats'} — $failures failed',
        type: AppToastType.warning,
        isLong: true,
      );
    } else {
      AppToast.show('Couldn\'t forward — please try again', type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final filtered = _filtered;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                margin: const EdgeInsets.only(top: 0),
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: colors.borderVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Text(
                      'Forward to',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: colors.text,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.messages.length} message${widget.messages.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  style: TextStyle(color: colors.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search chats',
                    hintStyle: TextStyle(color: colors.textSecondary),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 20, color: colors.textSecondary),
                    filled: true,
                    fillColor: colors.surfaceVariant,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: _loading
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: CircularProgressIndicator(color: colors.primary),
                        ),
                      )
                    : _loadError != null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _loadError!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13, color: colors.error),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _loadConversations,
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : filtered.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No chats found',
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      color: colors.textSecondary),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final conversation = filtered[index];
                                  final selected =
                                      _selectedIds.contains(conversation.id);
                                  return InkWell(
                                    onTap: _forwarding
                                        ? null
                                        : () => setState(() {
                                              if (selected) {
                                                _selectedIds
                                                    .remove(conversation.id);
                                              } else {
                                                _selectedIds
                                                    .add(conversation.id);
                                              }
                                            }),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      child: Row(
                                        children: [
                                          AvatarWithInitials(
                                            name: conversation
                                                .displayTitle(widget.currentUserId),
                                            imageUrl: conversation
                                                .displayAvatar(widget.currentUserId),
                                            radius: 19,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              conversation.displayTitle(
                                                  widget.currentUserId),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w600,
                                                color: colors.text,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            selected
                                                ? Icons.check_circle_rounded
                                                : Icons.circle_outlined,
                                            size: 22,
                                            color: selected
                                                ? colors.primary
                                                : colors.textSecondary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      disabledBackgroundColor:
                          colors.textSecondary.withValues(alpha: 0.3),
                    ),
                    onPressed: (_selectedIds.isEmpty || _forwarding)
                        ? null
                        : _forward,
                    child: _forwarding
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Forwarding… $_done/$_total',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          )
                        : Text(
                            'Forward to ${_selectedIds.length} '
                            '${_selectedIds.length == 1 ? 'chat' : 'chats'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
