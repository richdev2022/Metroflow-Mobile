import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/mediasoup_room_service.dart';
import '../services/socket_service.dart';
import '../services/api.dart' show StorageService;
import '../utils/app_feedback.dart';
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
  void Function(dynamic)? _previousMultiDeviceHandler;
  int? _multiDeviceCount;
  String? _multiDeviceMessage;

  // Waiting room (rooms with waiting_room_enabled): while parked, mediasoup
  // is NOT started — only after the host admits us.
  bool _isWaitingForAdmission = false;
  bool _waitedLong = false;
  Timer? _waitingHintTimer;
  void Function(dynamic)? _previousWaitingAdmittedHandler;
  void Function(dynamic)? _previousWaitingDeniedHandler;

  // Join hardening ("preparing to join" forever fix):
  // - 15s after emitting call:join with media still not connected → re-emit
  //   the join ONCE;
  // - 12s later → non-blocking "Still connecting… Retry" banner (the room is
  //   never silently wiped).
  // The connecting OVERLAY is dismissed independently on: join ack success,
  // waiting-room admitted, transport connected, or call ended.
  Timer? _joinWatchdog;
  bool _joinReEmitted = false;
  bool _showJoinRetry = false;
  bool _mediaConnected = false;

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

    if (widget.isMeeting) {
      _socket.emitMeetingJoin({
        'meetingId': widget.roomId,
        'userId': _resolvedUserId,
        'userName': _resolvedUserName,
        'isHost': false,
      });
      await _startMediasoupSession();
      return;
    }

    // Calls join with an ack so the server can park us in the waiting room
    // (rooms with waiting_room_enabled) instead of letting us straight in.
    await _joinCallRoom();
  }

  /// Call-side join with waiting-room support:
  /// 1. emit `call:join` (with `waitingRoomSupport: true`) and read the ack;
  /// 2. ack `waitingRoom: true` → show the waiting overlay, (re-)enqueue via
  ///    `waiting-room:request`, and wait for `waiting-room:admitted` (→
  ///    re-join) or `waiting-room:denied` (→ leave);
  /// 3. otherwise → dismiss the connecting overlay immediately (ack success
  ///    IS the join confirmation) and start the mediasoup session.
  /// A watchdog re-emits the join once after 15s and surfaces a retry banner
  /// after 12s more if media never connects.
  Future<void> _joinCallRoom() async {
    _cancelJoinWatchdog();
    _joinReEmitted = false;
    _mediaConnected = false;
    if (mounted && _showJoinRetry) {
      setState(() => _showJoinRetry = false);
    }

    final payload = <String, dynamic>{
      'roomId': widget.roomId,
      'userId': _resolvedUserId,
      'userName': _resolvedUserName,
      'isHost': _isCallHost,
      'audioEnabled': _isAudioEnabled,
      'videoEnabled': _isVideoEnabled,
    };

    dynamic ack;
    var ackFailed = false;
    try {
      ack = await _socket.emitCallJoinWithAck(payload);
    } catch (e) {
      // No ack (socket hiccup / very old backend). Fall back to the legacy
      // fire-and-forget join so an ack outage can never trap users outside
      // the room — the server join handler is idempotent.
      ackFailed = true;
      Logger.error('call:join ack unavailable, continuing without it: $e');
    }

    if (!ackFailed && ack is Map) {
      if (ack['waitingRoom'] == true) {
        _enterWaitingRoom();
        return;
      }
      if (ack['success'] == false) {
        // Server explicitly refused (room not found / ended / ...).
        Logger.error('call:join refused: ${ack['error']}');
        _cancelJoinWatchdog();
        if (!mounted) return;
        setState(() {
          _isConnecting = false;
          _connectionLabel = 'Unable to join';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ack['error']?.toString() ?? 'Unable to join the call')),
        );
        return;
      }
    }

    if (ackFailed) {
      _socket.emitCallJoin(payload);
    }
    // Ack success (or legacy join emitted): the server accepted us — drop
    // the "Preparing to join" overlay now; the connection chip keeps showing
    // transport-level progress until 'connected'. The join watchdog below
    // tracks the MEDIA connection, not the overlay.
    _dismissConnectingOverlay();
    _armJoinWatchdog(payload);
    await _startMediasoupSession();
  }

  /// Marks the media path as fully connected and clears the watchdog/banner.
  void _onMediaConnected() {
    _mediaConnected = true;
    _cancelJoinWatchdog();
    if (!mounted) return;
    if (_isConnecting || _showJoinRetry) {
      setState(() {
        _isConnecting = false;
        _showJoinRetry = false;
      });
    }
  }

  /// Drops the "Preparing to join" overlay + retry banner (no watchdog
  /// implications). Called on join ack success and waiting-room admitted.
  void _dismissConnectingOverlay() {
    if (!mounted) return;
    if (_isConnecting || _showJoinRetry) {
      setState(() {
        _isConnecting = false;
        _showJoinRetry = false;
      });
    }
  }

  void _cancelJoinWatchdog() {
    _joinWatchdog?.cancel();
    _joinWatchdog = null;
  }

  /// 15s with media still unconnected → re-emit `call:join` once (idempotent
  /// server side). 12s more → non-blocking retry banner.
  void _armJoinWatchdog(Map<String, dynamic> payload) {
    _cancelJoinWatchdog();
    _joinWatchdog = Timer(const Duration(seconds: 15), () {
      if (!mounted || _hasLeft || _mediaConnected || _isWaitingForAdmission) return;
      if (!_joinReEmitted) {
        _joinReEmitted = true;
        Logger.log('call:join watchdog — media not connected after 15s, re-emitting join');
        _socket.emitCallJoin(payload);
        _joinWatchdog = Timer(const Duration(seconds: 12), () {
          if (!mounted || _hasLeft || _mediaConnected || _isWaitingForAdmission) return;
          setState(() => _showJoinRetry = true);
        });
      } else {
        setState(() => _showJoinRetry = true);
      }
    });
  }

  /// Retry button of the "Still connecting…" banner: reset the overlay and
  /// run the whole join flow again. Never wipes the room silently.
  Future<void> _retryJoin() async {
    if (!mounted) return;
    setState(() {
      _showJoinRetry = false;
      _isConnecting = true;
      _connectionLabel = 'Reconnecting…';
    });
    _mediaConnected = false;
    if (widget.isMeeting) {
      _socket.emitMeetingJoin({
        'meetingId': widget.roomId,
        'userId': _resolvedUserId,
        'userName': _resolvedUserName,
        'isHost': _isCallHost,
      });
      await _startMediasoupSession();
    } else {
      await _joinCallRoom();
    }
  }

  /// The normal mediasoup start sequence (device load → transports →
  /// produce → consume existing). Shared by both join paths: straight-in and
  /// post-admission.
  Future<void> _startMediasoupSession() async {
    try {
      final room = MediasoupRoomService(
        roomId: widget.roomId,
        socket: _socket,
        produceAudio: true,
        produceVideo: widget.enableVideo,
        onConnectionStateChanged: (connectionState) {
          if (!mounted) return;
          setState(() => _connectionLabel = connectionState);
          // Transport actually connected → the join is fully done.
          if (connectionState.toLowerCase() == 'connected') {
            _onMediaConnected();
          }
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
      // The mediasoup sequence completed (device load → transports →
      // produce → consume): treat the media path as connected.
      _onMediaConnected();
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

  // -------------------------------------------------------------------------
  // Waiting room (rooms with waiting_room_enabled, non-host joiners)
  // -------------------------------------------------------------------------

  void _enterWaitingRoom() {
    if (!mounted) return;
    _previousWaitingAdmittedHandler = _socket.onWaitingRoomAdmitted;
    _previousWaitingDeniedHandler = _socket.onWaitingRoomDenied;
    _socket.onWaitingRoomAdmitted = _handleWaitingAdmitted;
    _socket.onWaitingRoomDenied = _handleWaitingDenied;
    setState(() {
      _isWaitingForAdmission = true;
      _waitedLong = false;
      _isConnecting = false;
      _connectionLabel = 'Waiting for the host…';
    });
    // Belt & braces: explicitly (re-)enqueue ourselves in case the join-time
    // queue entry was lost (reconnect, race with the host's queue sync).
    _socket.emitWaitingRoomRequest({
      'roomId': widget.roomId,
      'userId': _resolvedUserId,
      'userName': _resolvedUserName,
    });
    // Long-wait hint after 2 minutes — we keep waiting, never auto-leave.
    _waitingHintTimer = Timer(const Duration(minutes: 2), () {
      if (mounted && _isWaitingForAdmission) {
        setState(() => _waitedLong = true);
      }
    });
  }

  void _clearWaitingRoom() {
    _waitingHintTimer?.cancel();
    _waitingHintTimer = null;
    _socket.onWaitingRoomAdmitted = _previousWaitingAdmittedHandler;
    _socket.onWaitingRoomDenied = _previousWaitingDeniedHandler;
    _previousWaitingAdmittedHandler = null;
    _previousWaitingDeniedHandler = null;
    if (mounted && _isWaitingForAdmission) {
      setState(() => _isWaitingForAdmission = false);
    }
  }

  /// Host admitted us — dismiss the overlay and run the normal join again.
  /// This time the server consumes the admission grant and lets us through
  /// into the mediasoup room.
  void _handleWaitingAdmitted(dynamic data) {
    _previousWaitingAdmittedHandler?.call(data);
    if (data is! Map) return;
    final payload = Map<String, dynamic>.from(data);
    final roomId = (payload['roomId'] ?? payload['meetingId'])?.toString();
    if (roomId != null && roomId.isNotEmpty && roomId != widget.roomId) return;
    _clearWaitingRoom();
    _dismissConnectingOverlay();
    _joinCallRoom();
  }

  /// Host declined — tell the user and leave.
  void _handleWaitingDenied(dynamic data) {
    _previousWaitingDeniedHandler?.call(data);
    if (data is! Map) return;
    final payload = Map<String, dynamic>.from(data);
    final roomId = (payload['roomId'] ?? payload['meetingId'])?.toString();
    if (roomId != null && roomId.isNotEmpty && roomId != widget.roomId) return;
    _clearWaitingRoom();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Host declined your request')),
    );
    _leave();
  }

  /// Waiting-room overlay: elegant spinner + room name + cancel/leave.
  Widget _buildWaitingRoomOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xFF05070D),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const SizedBox(
                          width: 76,
                          height: 76,
                          child: CircularProgressIndicator(
                            color: Color(0x33FFFFFF),
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(
                          width: 46,
                          height: 46,
                          child: CircularProgressIndicator(
                            color: Color(0xFF22C55E),
                            strokeWidth: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'Waiting for the host to admit you',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                  if (_waitedLong) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF451A03).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                      ),
                      child: const Text(
                        'Still waiting… the host has been notified.',
                        style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 34),
                  OutlinedButton.icon(
                    onPressed: _leave,
                    icon: const Icon(Icons.call_end, size: 18),
                    label: const Text('Cancel & leave'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    _previousMultiDeviceHandler = _socket.onCallMultiDevice;

    // Server-verified echo-risk alert (same account on multiple devices).
    // Shows a persistent in-room banner — the user must know WHY they hear
    // themselves echoed and which device to drop.
    _socket.onCallMultiDevice = (data) {
      _previousMultiDeviceHandler?.call(data);
      if (!mounted || data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final count = payload['deviceCount'] is num ? (payload['deviceCount'] as num).toInt() : 2;
      final name = payload['userName']?.toString() ?? 'This account';
      setState(() {
        _multiDeviceCount = count;
        _multiDeviceMessage = payload['message']?.toString() ??
            '$name is in this room on $count devices — leave on all but one or use headphones.';
      });
    };

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
      // Kill the join watchdog + any looping ring on this transition.
      _cancelJoinWatchdog();
      _mediaConnected = false;
      AppFeedback.stopRingtone();
      AppFeedback.stopRingback();
      AppFeedback.playCallEndedSound();
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
    _socket.onCallMultiDevice = _previousMultiDeviceHandler;
    _socket.onCallCountdownWarning = _previousCountdownWarnHandler;
    _socket.onWaitingRoomAdmitted = _previousWaitingAdmittedHandler;
    _socket.onWaitingRoomDenied = _previousWaitingDeniedHandler;
    _waitingHintTimer?.cancel();
    _waitingHintTimer = null;
    _joinWatchdog?.cancel();
    _joinWatchdog = null;
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

    // Leaving from the waiting room is NOT leaving the call: we were never
    // added to the room, so we must not end it for everybody else.
    final wasWaitingInRoom = _isWaitingForAdmission;
    _clearWaitingRoom();
    // Belt & braces: stop ANY looping ring (incoming ring or outbound
    // ringback) on every leave transition — silence is non-negotiable once
    // the call screen closes.
    AppFeedback.stopRingtone();
    AppFeedback.stopRingback();

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
        // kill the call for everybody else — and someone leaving from the
        // waiting room was never in the call at all.
        final isOneToOne = !widget.isGroupCall;
        if (!wasWaitingInRoom && (_isCallHost || isOneToOne)) {
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
            // Server-verified multi-device (echo risk) banner
            if (_multiDeviceCount != null && _multiDeviceCount! >= 2)
              Positioned(
                top: 86,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF451A03).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _multiDeviceMessage ?? '',
                          style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 12, height: 1.3),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _multiDeviceCount = null),
                        child: const Icon(Icons.close, color: Color(0xFFFDE68A), size: 16),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              right: 16,
              top: 96,
              child: _buildLocalPreview(),
            ),
            if (_showChat) _buildChatPanel(),
            if (_showJoinRetry && !_isWaitingForAdmission) _buildJoinRetryBanner(),
            // Bottom control bar — SafeArea(bottom) guarantees the hang-up
            // button is NEVER clipped by gesture bars / home indicators, and
            // the Wrap layout keeps every control reachable down to 320dp.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _buildControls(),
                ),
              ),
            ),
            // Waiting room (rooms with waiting_room_enabled): covers everything
            // until the host admits us (or we cancel & leave).
            if (_isWaitingForAdmission) _buildWaitingRoomOverlay(),
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

  /// Non-blocking "Still connecting…" banner shown by the join watchdog —
  /// offers a manual retry; the room is never silently wiped.
  Widget _buildJoinRetryBanner() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 120,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF451A03).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFBBF24),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Still connecting to the call…',
                  style: TextStyle(color: Color(0xFFFDE68A), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: _retryJoin,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFBBF24),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(48, 48),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    // Wrap (not Row): on narrow screens (320dp) the controls flow onto a
    // second line instead of overflowing — the hang-up button ALWAYS stays
    // visible. Minimum touch target is 48dp via _dockButton/_leaveButton.
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1220).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            _dockButton(
              icon: _isAudioEnabled ? Icons.mic : Icons.mic_off,
              active: _isAudioEnabled,
              onPressed: _toggleAudio,
            ),
            if (widget.enableVideo)
              _dockButton(
                icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                active: _isVideoEnabled,
                onPressed: _toggleVideo,
              ),
            if (widget.enableVideo)
              _dockButton(
                icon: Icons.flip_camera_ios,
                active: true,
                onPressed: _switchCamera,
              ),
            _dockButton(
              icon: _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
              active: _isScreenSharing,
              onPressed: _isSwitchingScreenShare ? null : _toggleScreenShare,
            ),
            if (widget.isMeeting)
              _dockButton(
                icon: Icons.chat_bubble_outline_rounded,
                active: _showChat,
                onPressed: () => setState(() => _showChat = !_showChat),
              ),
            _dockButton(
              icon: _isRecording ? Icons.fiber_manual_record : Icons.radio_button_unchecked,
              active: _isRecording,
              activeColor: const Color(0xFFEF4444),
              onPressed: _toggleRecording,
            ),
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
