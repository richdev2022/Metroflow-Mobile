import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/mediasoup_room_service.dart';
import '../services/socket_service.dart';
import '../services/api.dart' show StorageService;
import '../utils/logger.dart';

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final String title;
  final bool isMeeting;
  final bool enableVideo;
  final String? userName;
  final bool isHost;
  final bool isGroupCall;
  final FutureOr<void> Function()? onLeave;

  const VideoCallScreen({
    super.key,
    required this.roomId,
    required this.title,
    this.isMeeting = false,
    this.enableVideo = true,
    this.userName,
    this.isHost = false,
    this.isGroupCall = false,
    this.onLeave,
  });

  static Future<void> showModal({
    required BuildContext context,
    required String roomId,
    required String title,
    bool isMeeting = false,
    bool enableVideo = true,
    String? userName,
    bool isHost = false,
    bool isGroupCall = false,
    FutureOr<void> Function()? onLeave,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF05070D),
        child: VideoCallScreen(
          roomId: roomId,
          title: title,
          isMeeting: isMeeting,
          enableVideo: enableVideo,
          userName: userName,
          isHost: isHost,
          isGroupCall: isGroupCall,
          onLeave: onLeave,
        ),
      ),
    );
  }

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _RemoteTile {
  final RemoteMediaStream media;
  final RTCVideoRenderer renderer;

  _RemoteTile({required this.media, required this.renderer});
}

class _ChatLine {
  final String userId;
  final String message;
  final DateTime timestamp;

  _ChatLine({
    required this.userId,
    required this.message,
    required this.timestamp,
  });
}

class _ParticipantTileData {
  final String id;
  final String displayName;
  final RTCVideoRenderer? renderer;
  final bool hasVideo;
  final bool isMuted;
  final bool isScreenShare;
  final bool hasAudioActivity;
  final bool isLocal;

  const _ParticipantTileData({
    required this.id,
    required this.displayName,
    this.renderer,
    required this.hasVideo,
    required this.isMuted,
    required this.isScreenShare,
    required this.hasAudioActivity,
    required this.isLocal,
  });
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final SocketService _socket = SocketService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _screenRenderer = RTCVideoRenderer();
  final TextEditingController _chatController = TextEditingController();
  final List<_RemoteTile> _remoteTiles = [];
  final List<_ChatLine> _chatLines = [];

  MediasoupRoomService? _room;
  bool _isAudioEnabled = true;
  bool _isVideoEnabled = true;
  bool _isScreenSharing = false;
  bool _isRecording = false;
  bool _showChat = false;
  bool _hasLeft = false;
  bool _cleanupDone = false;
  bool _isConnecting = true;
  bool _isSwitchingScreenShare = false;
  String _connectionLabel = 'Connecting...';
  String _resolvedUserId = '';
  String _resolvedUserName = 'User';
  bool _isCallHost = false;
  void Function(dynamic)? _previousChatHandler;
  void Function(dynamic)? _previousScreenStartHandler;
  void Function(dynamic)? _previousScreenStopHandler;
  void Function(dynamic)? _previousRecordingStartHandler;
  void Function(dynamic)? _previousRecordingStopHandler;
  void Function(dynamic)? _previousRecordingPauseHandler;
  void Function(dynamic)? _previousCallEndedHandler;
  void Function(dynamic)? _previousDurationStartHandler;
  void Function(dynamic)? _previousDurationActiveHandler;
  void Function(dynamic)? _previousCountdownWarnHandler;

  // Live duration tracking: elapsed since joining + plan cap remaining.
  Timer? _elapsedTicker;
  int _elapsedSeconds = 0;
  DateTime? _planEndsAt;
  int? _planMaxMinutes;

  @override
  void initState() {
    super.initState();
    _isVideoEnabled = widget.enableVideo;
    _isCallHost = widget.isHost;
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds += 1);
    });
    _initRoom();
  }

  @override
  void dispose() {
    unawaited(_cleanup());
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _initRoom() async {
    // Resolve identity once — used for socket room join + participant events.
    try {
      final storage = StorageService();
      _resolvedUserId = await storage.getUserId() ?? '';
      _resolvedUserName = await storage.getUserName() ?? widget.userName ?? 'User';
    } catch (_) {
      _resolvedUserName = widget.userName ?? 'User';
    }
    if (_resolvedUserName.trim().isEmpty) _resolvedUserName = widget.userName ?? 'User';

    await _localRenderer.initialize();
    await _screenRenderer.initialize();
    _wireRoomEvents();

    try {
      if (widget.isMeeting) {
        _socket.emitMeetingJoin({
          'meetingId': widget.roomId,
          'userId': _resolvedUserId,
          'userName': _resolvedUserName,
          'isHost': false,
        });
      } else {
        // CRITICAL for calls: the socket must join the server-side room
        // (`room:{id}`) — without `call:join` no mediasoup events (newProducer,
        // participant-joined, ...) are ever delivered and remote media stays
        // blank. Meetings join via `meeting:join` instead.
        _socket.emitCallJoin({
          'roomId': widget.roomId,
          'userId': _resolvedUserId,
          'userName': _resolvedUserName,
          'isHost': _isCallHost,
          'audioEnabled': _isAudioEnabled,
          'videoEnabled': _isVideoEnabled,
        });
      }

      final room = MediasoupRoomService(
        roomId: widget.roomId,
        socket: _socket,
        produceAudio: true,
        produceVideo: widget.enableVideo,
        onConnectionStateChanged: (state) {
          if (!mounted) return;
          setState(() => _connectionLabel = state);
        },
        onRemoteStream: _addRemoteStream,
        onRemoteStreamRemoved: _removeRemoteStream,
        onScreenShareStarted: (stream) {
          if (!mounted) return;
          setState(() {
            _screenRenderer.srcObject = stream;
          });
        },
        onScreenShareStopped: () {
          if (!mounted) return;
          setState(() {
            _screenRenderer.srcObject = null;
          });
        },
      );

      _room = room;
      await room.start();
      if (!mounted) return;
      setState(() {
        _localRenderer.srcObject = room.localStream;
        _isConnecting = false;
        _connectionLabel = 'Connected';
      });
    } catch (e) {
      Logger.error('Error joining room: $e');
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _connectionLabel = 'Unable to connect media';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to connect media: $e')),
      );
    }
  }

  void _wireRoomEvents() {
    _previousChatHandler = _socket.onMeetingChatMessage;
    _previousScreenStartHandler = _socket.onScreenShareStarted;
    _previousScreenStopHandler = _socket.onScreenShareStopped;
    _previousRecordingStartHandler = _socket.onRecordingStarted;
    _previousRecordingStopHandler = _socket.onRecordingStopped;
    _previousRecordingPauseHandler = _socket.onRecordingPaused;
    _previousCallEndedHandler = _socket.onCallEnded;
    _previousDurationStartHandler = _socket.onCallDurationStarted;
    _previousDurationActiveHandler = _socket.onCallDurationActive;
    _previousCountdownWarnHandler = _socket.onCallCountdownWarning;

    // Plan-based duration tracking (see FRONTEND_CALL_DURATION_GUIDE.md):
    // duration-started fires when the 2nd participant joins, duration-active
    // on late joins, countdown-warning at the 5-min/1-min marks.
    void applyEndsAt(dynamic data) {
      if (!mounted || data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      if (!widget.isMeeting) {
        final roomId = payload['roomId']?.toString();
        if (roomId != null && roomId.isNotEmpty && roomId != widget.roomId) return;
      }
      final endsAtRaw = payload['endsAt'] ?? payload['ends_at'];
      final maxRaw = payload['maxMeetingDuration'] ?? payload['max_meeting_duration'];
      DateTime? endsAt;
      if (endsAtRaw is String) endsAt = DateTime.tryParse(endsAtRaw);
      final int? maxMinutes = maxRaw is num ? maxRaw.toInt() : int.tryParse(maxRaw?.toString() ?? '');
      setState(() {
        _planEndsAt = endsAt ?? _planEndsAt;
        _planMaxMinutes = maxMinutes ?? _planMaxMinutes;
      });
    }

    _socket.onCallDurationStarted = applyEndsAt;
    _socket.onCallDurationActive = applyEndsAt;
    _socket.onCallCountdownWarning = (data) {
      _previousCountdownWarnHandler?.call(data);
      // The payload carries remainingMs; recompute the visible remaining time.
      if (!mounted || data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final remainingMs = payload['remainingMs'] is num
          ? (payload['remainingMs'] as num).toInt()
          : int.tryParse(payload['remainingMs']?.toString() ?? '');
      if (remainingMs != null) {
        setState(() => _planEndsAt = DateTime.now().add(Duration(milliseconds: remainingMs)));
      }
    };

    // Someone ended the call remotely (host / other party / plan limit) —
    // tear the room down and exit instead of hanging on a dead call.
    _socket.onCallEnded = (data) {
      _previousCallEndedHandler?.call(data);
      final payload = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final endedCallId = payload['callId']?.toString();
      if (widget.isMeeting) return;
      if (endedCallId != null && endedCallId != widget.roomId) return;
      if (_hasLeft) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call ended')),
      );
      _leave();
    };

    _socket.onMeetingChatMessage = (data) {
      _previousChatHandler?.call(data);
      final payload = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      if (payload['meetingId'] != null && payload['meetingId'] != widget.roomId) return;
      if (!mounted) return;
      setState(() {
        _chatLines.add(_ChatLine(
          userId: payload['senderName']?.toString() ?? payload['userId']?.toString() ?? 'User',
          message: payload['message']?.toString() ?? '',
          timestamp: DateTime.tryParse(payload['timestamp']?.toString() ?? '') ?? DateTime.now(),
        ));
      });
    };

    _socket.onScreenShareStarted = (data) {
      _previousScreenStartHandler?.call(data);
      final payload = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      if (!_isRoomPayload(payload)) return;
      if (mounted) setState(() => _connectionLabel = 'Screen sharing started');
    };
    _socket.onScreenShareStopped = (data) {
      _previousScreenStopHandler?.call(data);
      final payload = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      if (!_isRoomPayload(payload)) return;
      if (mounted) setState(() => _connectionLabel = 'Screen sharing stopped');
    };
    _socket.onRecordingStarted = (data) {
      _previousRecordingStartHandler?.call(data);
      if (mounted) {
        setState(() {
          _isRecording = true;
        });
      }
    };
    _socket.onRecordingStopped = (data) async {
      _previousRecordingStopHandler?.call(data);
      if (mounted) {
        setState(() {
          _isRecording = false;
        });
      }
    };
    _socket.onRecordingPaused = (data) {
      _previousRecordingPauseHandler?.call(data);
      if (mounted) setState(() => _isRecording = false);
    };
  }

  bool _isRoomPayload(Map<String, dynamic> payload) {
    final id = payload['meetingId'] ?? payload['callId'] ?? payload['roomId'];
    // STRICT match: a null id is NOT ours. Treating null as "mine" leaked
    // chats/notifications from other rooms into this room's panels.
    return id != null && id.toString() == widget.roomId;
  }

  Future<void> _removeRemoteStream(String consumerId) async {
    _RemoteTile? tile;
    for (final t in _remoteTiles) {
      if (t.media.id == consumerId) {
        tile = t;
        break;
      }
    }
    if (tile == null) return;
    if (!mounted) {
      await tile.renderer.dispose();
      return;
    }
    setState(() {
      _remoteTiles.remove(tile);
    });
    await tile.renderer.dispose();
  }

  Future<void> _addRemoteStream(RemoteMediaStream media) async {
    if (_remoteTiles.any((tile) => tile.media.id == media.id)) return;
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    renderer.srcObject = media.stream;
    if (!mounted) {
      await renderer.dispose();
      return;
    }
    setState(() {
      _remoteTiles.add(_RemoteTile(media: media, renderer: renderer));
    });
  }

  Future<void> _cleanup() async {
    _socket.onMeetingChatMessage = _previousChatHandler;
    _socket.onScreenShareStarted = _previousScreenStartHandler;
    _socket.onScreenShareStopped = _previousScreenStopHandler;
    _socket.onRecordingStarted = _previousRecordingStartHandler;
    _socket.onRecordingStopped = _previousRecordingStopHandler;
    _socket.onRecordingPaused = _previousRecordingPauseHandler;
    _socket.onCallEnded = _previousCallEndedHandler;
    _socket.onCallDurationStarted = _previousDurationStartHandler;
    _socket.onCallDurationActive = _previousDurationActiveHandler;
    _socket.onCallCountdownWarning = _previousCountdownWarnHandler;
    _elapsedTicker?.cancel();
    _elapsedTicker = null;

    if (_cleanupDone) return;
    _cleanupDone = true;
    await _room?.stop();
    for (final tile in _remoteTiles) {
      await tile.renderer.dispose();
    }
    _remoteTiles.clear();
    await _localRenderer.dispose();
    await _screenRenderer.dispose();
  }

  Future<void> _toggleAudio() async {
    final enabled = !_isAudioEnabled;
    setState(() => _isAudioEnabled = enabled);
    try {
      await _room?.setAudioEnabled(enabled);
    } catch (e) {
      Logger.error('Error toggling microphone: $e');
      if (!mounted) return;
      setState(() => _isAudioEnabled = !enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Microphone toggle failed: $e')),
      );
    }
  }

  Future<void> _toggleVideo() async {
    final enabled = !_isVideoEnabled;
    setState(() => _isVideoEnabled = enabled);
    try {
      await _room?.setVideoEnabled(enabled);
    } catch (e) {
      Logger.error('Error toggling camera: $e');
      if (!mounted) return;
      setState(() => _isVideoEnabled = !enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera toggle failed: $e')),
      );
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _room?.switchCamera();
    } catch (e) {
      Logger.error('Error switching camera: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to switch camera: $e')),
      );
    }
  }

  Future<void> _toggleScreenShare() async {
    if (_isSwitchingScreenShare) return;
    setState(() => _isSwitchingScreenShare = true);
    try {
      final roomKey = widget.isMeeting ? 'meetingId' : 'callId';
      if (_isScreenSharing) {
        await _room?.stopScreenShare();
        _socket.emitScreenShareStop({roomKey: widget.roomId});
      } else {
        await _room?.startScreenShare();
        _socket.emitScreenShareStart({roomKey: widget.roomId});
      }
      if (mounted) setState(() => _isScreenSharing = !_isScreenSharing);
    } catch (e) {
      Logger.error('Error toggling screen share: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Screen sharing failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSwitchingScreenShare = false);
    }
  }

  void _toggleRecording() {
    if (_isRecording) {
      _socket.emitRecordingStop({
        widget.isMeeting ? 'meetingId' : 'callId': widget.roomId,
      });
    } else {
      _socket.emitRecordingStart({
        widget.isMeeting ? 'meetingId' : 'callId': widget.roomId,
      });
    }
    setState(() => _isRecording = !_isRecording);
  }

  void _sendChatMessage() {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;
    // Backend broadcasts `meeting-chat:message` to the whole room (including
    // the sender) with the resolved identity, so we no longer optimistically
    // add the message locally. The room key must match what the server
    // resolves: `meetingId` for meetings, `roomId`/`callId` for calls.
    _socket.emitMeetingChatMessage({
      if (widget.isMeeting) 'meetingId': widget.roomId else 'roomId': widget.roomId,
      'message': message,
      'senderName': _resolvedUserName,
      'userId': _resolvedUserId,
    });
    _chatController.clear();
  }

  Future<void> _leave() async {
    if (_hasLeft) return;
    _hasLeft = true;

    // POP FIRST: previously we awaited onLeave (a REST call that could throw,
    // e.g. joining with an empty id) before popping, which trapped the user on
    // a dead call screen with canPop:false. Navigation must never depend on a
    // network round-trip.
    if (mounted) {
      Navigator.of(context).pop();
    }

    try {
      if (widget.isMeeting) {
        _socket.emitMeetingLeave({'meetingId': widget.roomId});
      } else {
        // Announce our own leave so the server drops us from the room.
        _socket.emitCallLeave({
          'roomId': widget.roomId,
          'userId': _resolvedUserId,
          'userName': _resolvedUserName,
        });
        // End the call for everyone ONLY when it makes sense: 1:1 calls or the
        // host leaving. In group calls a single participant leaving must not
        // kill the call for everybody else.
        final isOneToOne = !widget.isGroupCall;
        if (_isCallHost || isOneToOne) {
          _socket.emitCallEnd({'callId': widget.roomId});
        }
      }
    } catch (e) {
      Logger.error('Error during call leave: $e');
    }

    try {
      await Future<void>.sync(() => widget.onLeave?.call());
    } catch (e) {
      Logger.error('onLeave callback failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  Color _connectionColor() {
    final label = _connectionLabel.toLowerCase();
    if (label.contains('fail') ||
        label.contains('unable') ||
        label.contains('error') ||
        label.contains('closed')) {
      return const Color(0xFFEF4444);
    }
    if (label.contains('connected')) {
      return const Color(0xFF22C55E);
    }
    if (label.contains('connect') || label.contains('new')) {
      return const Color(0xFFF59E0B);
    }
    return const Color(0xFF94A3B8);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF05070D),
        body: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(top: 86, bottom: 112),
                child: _buildVideoGrid(),
              ),
            ),
            _buildTopBar(),
            Positioned(
              right: 16,
              top: 96,
              child: _buildLocalPreview(),
            ),
            if (_showChat) _buildChatPanel(),
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatClock(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Elapsed time chip + optional plan-limit remaining countdown.
  Widget _buildDurationChip() {
    final remaining = _planEndsAt != null
        ? _planEndsAt!.difference(DateTime.now()).inSeconds
        : null;
    final urgent = remaining != null && remaining <= 60;
    final warning = remaining != null && remaining <= 5 * 60;
    final color = urgent
        ? const Color(0xFFEF4444)
        : warning
            ? const Color(0xFFF59E0B)
            : Colors.white.withValues(alpha: 0.85);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: urgent
            ? const Color(0xFFEF4444).withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: urgent
              ? const Color(0xFFEF4444).withValues(alpha: 0.6)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            _formatClock(_elapsedSeconds),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: color,
            ),
          ),
          if (remaining != null) ...[
            Text(' / ',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
            Text(
              _formatClock(remaining < 0 ? 0 : remaining),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 10, 12, 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC05070D), Color(0x0005070D)],
          ),
        ),
        child: Row(
          children: [
            _roundIconButton(
              icon: Icons.close_rounded,
              onTap: _leave,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: _connectionColor(),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _connectionLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildDurationChip(),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (widget.isMeeting)
              _roundIconButton(
                icon: _showChat ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                active: _showChat,
                onTap: () => setState(() => _showChat = !_showChat),
              ),
            if (widget.isMeeting) const SizedBox(width: 8),
            _roundIconButton(
              icon: _isRecording ? Icons.fiber_manual_record : Icons.radio_button_unchecked,
              iconColor: _isRecording ? const Color(0xFFEF4444) : Colors.white,
              onTap: _toggleRecording,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoGrid() {
    if (_isConnecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Connecting to the room…',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final participants = _buildParticipantTiles();
    if (participants.length == 1) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
          child: _buildParticipantTile(participants.first),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: participants.length <= 2 ? 1 : 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        return _buildParticipantTile(participants[index]);
      },
    );
  }

  List<_ParticipantTileData> _buildParticipantTiles() {
    final tiles = <_ParticipantTileData>[
      _ParticipantTileData(
        id: 'local',
        displayName: 'You',
        renderer: _isScreenSharing ? _screenRenderer : _localRenderer,
        hasVideo: _isScreenSharing
            ? _screenRenderer.srcObject != null
            : (_localRenderer.srcObject != null && _isVideoEnabled && widget.enableVideo),
        isMuted: !_isAudioEnabled,
        isScreenShare: _isScreenSharing,
        hasAudioActivity: _isAudioEnabled,
        isLocal: true,
      ),
    ];

    final remoteIds = _remoteTiles
        .map((tile) => tile.media.peerId?.isNotEmpty == true ? tile.media.peerId! : tile.media.producerId)
        .toSet()
        .toList();

    for (final id in remoteIds) {
      final streams = _remoteTiles.where((tile) {
        final tileId = tile.media.peerId?.isNotEmpty == true ? tile.media.peerId! : tile.media.producerId;
        return tileId == id;
      }).toList();
      final screenVideo = streams.where((tile) {
        final source = tile.media.source?.toLowerCase() ?? '';
        return tile.media.kind == 'video' && source == 'screen';
      }).cast<_RemoteTile?>().firstWhere((tile) => tile != null, orElse: () => null);
      final cameraVideo = streams.where((tile) => tile.media.kind == 'video').cast<_RemoteTile?>().firstWhere(
            (tile) => tile != null,
            orElse: () => null,
          );
      final audio = streams.any((tile) => tile.media.kind == 'audio');
      final selectedVideo = screenVideo ?? cameraVideo;

      tiles.add(_ParticipantTileData(
        id: id,
        displayName: _displayNameForPeer(id),
        renderer: selectedVideo?.renderer,
        hasVideo: selectedVideo != null,
        isMuted: !audio,
        isScreenShare: screenVideo != null,
        hasAudioActivity: audio,
        isLocal: false,
      ));
    }

    return tiles;
  }

  String _displayNameForPeer(String id) {
    if (id.isEmpty) return 'Guest';
    if (id.length <= 10) return id;
    return 'Guest ${id.substring(id.length - 4).toUpperCase()}';
  }

  Widget _buildParticipantTile(_ParticipantTileData participant) {
    final isSpeaking = participant.hasAudioActivity && !participant.isMuted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSpeaking ? const Color(0xFF22C55E) : Colors.white12,
          width: isSpeaking ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (participant.hasVideo && participant.renderer != null)
            RTCVideoView(
              participant.renderer!,
              mirror: participant.isLocal && !participant.isScreenShare,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            _buildAvatarFallback(participant.displayName, large: true),
          if (participant.isScreenShare)
            Positioned(
              left: 12,
              top: 12,
              child: _statusChip(
                Icons.screen_share,
                participant.isLocal ? 'You are presenting' : 'Presenting',
              ),
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            participant.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (participant.isScreenShare) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.screen_share,
                              size: 13, color: Colors.white70),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildMicIndicator(
                  muted: participant.isMuted,
                  active: isSpeaking,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicIndicator({required bool muted, required bool active}) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: muted
            ? const Color(0xFFEF4444)
            : (active ? const Color(0xFF22C55E) : Colors.black.withValues(alpha: 0.55)),
        shape: BoxShape.circle,
      ),
      child: Icon(
        muted ? Icons.mic_off : Icons.mic,
        color: Colors.white,
        size: 15,
      ),
    );
  }

  Widget _buildAvatarFallback(String name, {bool large = false}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          width: large ? 104 : 56,
          height: large ? 104 : 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              _initials(name),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: large ? 34 : 18,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Widget _statusChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalPreview() {
    return Container(
      width: 110,
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _isScreenSharing && _screenRenderer.srcObject != null
            ? RTCVideoView(
                _screenRenderer,
                mirror: false,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : (_localRenderer.srcObject != null && _isVideoEnabled && widget.enableVideo)
                ? RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : _buildAvatarFallback('You'),
      ),
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    Color? iconColor,
    Color? background,
    double size = 42,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        style: IconButton.styleFrom(
          backgroundColor:
              background ?? (active ? Colors.white24 : Colors.white.withValues(alpha: 0.10)),
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, color: iconColor ?? Colors.white, size: 20),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildControls() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1220).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dockButton(
              icon: _isAudioEnabled ? Icons.mic : Icons.mic_off,
              active: _isAudioEnabled,
              onPressed: _toggleAudio,
            ),
            if (widget.enableVideo) ...[
              const SizedBox(width: 10),
              _dockButton(
                icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                active: _isVideoEnabled,
                onPressed: _toggleVideo,
              ),
              const SizedBox(width: 10),
              _dockButton(
                icon: Icons.flip_camera_ios,
                active: true,
                onPressed: _switchCamera,
              ),
            ],
            const SizedBox(width: 10),
            _dockButton(
              icon: _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
              active: _isScreenSharing,
              onPressed: _isSwitchingScreenShare ? null : _toggleScreenShare,
            ),
            if (widget.isMeeting) ...[
              const SizedBox(width: 10),
              _dockButton(
                icon: Icons.chat_bubble_outline_rounded,
                active: _showChat,
                onPressed: () => setState(() => _showChat = !_showChat),
              ),
            ],
            const SizedBox(width: 10),
            _dockButton(
              icon: _isRecording ? Icons.fiber_manual_record : Icons.radio_button_unchecked,
              active: _isRecording,
              activeColor: const Color(0xFFEF4444),
              onPressed: _toggleRecording,
            ),
            const SizedBox(width: 14),
            _leaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _dockButton({
    required IconData icon,
    required bool active,
    required FutureOr<void> Function()? onPressed,
    Color? activeColor,
    double size = 48,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: active
              ? (activeColor ?? Colors.white.withValues(alpha: 0.20))
              : Colors.white.withValues(alpha: 0.10),
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, size: 21),
        onPressed: onPressed == null
            ? null
            : () async {
                await onPressed();
              },
      ),
    );
  }

  Widget _leaveButton() {
    return SizedBox(
      width: 58,
      height: 58,
      child: IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFEF4444),
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
        ),
        icon: const Icon(Icons.call_end, size: 26),
        onPressed: _leave,
      ),
    );
  }

  Widget _buildChatPanel() {
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: 320,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(-6, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded,
                        size: 18, color: Colors.white70),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Meeting chat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: Colors.white70,
                      onPressed: () => setState(() => _showChat = false),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              Expanded(
                child: _chatLines.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forum_outlined,
                                size: 40, color: Colors.white.withValues(alpha: 0.25)),
                            const SizedBox(height: 10),
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _chatLines.length,
                        itemBuilder: (context, index) {
                          final line = _chatLines[index];
                          final isMe = widget.userName != null &&
                              line.userId == widget.userName;
                          return Align(
                            alignment:
                                isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              constraints: BoxConstraints(
                                maxWidth: 220,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft:
                                      isMe ? const Radius.circular(14) : Radius.zero,
                                  bottomRight:
                                      isMe ? Radius.zero : const Radius.circular(14),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (!isMe)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Text(
                                        line.userId,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF60A5FA),
                                        ),
                                      ),
                                    ),
                                  Text(
                                    line.message,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    TimeOfDay.fromDateTime(line.timestamp)
                                        .format(context),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => _sendChatMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF2563EB),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded,
                            color: Colors.white, size: 19),
                        onPressed: _sendChatMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
