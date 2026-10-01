import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/audio_route_service.dart';
import '../services/mediasoup_room_service.dart';
import '../services/calling/calling_engine.dart';
import '../services/calling/livekit_engine.dart';
import '../services/captions_service.dart';
import '../services/socket_service.dart';
import '../services/api.dart' show ApiService, StorageService;
import '../utils/app_feedback.dart';
import '../utils/logger.dart';
import '../widgets/captions_overlay.dart';
import 'meeting_notes_screen.dart';

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final String title;
  final bool isMeeting;
  final bool enableVideo;
  final String? userName;
  final bool isHost;
  final bool isGroupCall;
  final FutureOr<void> Function()? onLeave;

  /// Provider credentials from the REST join response (`data.calling`).
  /// Optional: when null the screen falls back to the `call:join` ack, and
  /// when both are absent the socket media flow is used unchanged.
  final Map<String, dynamic>? calling;

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
    this.calling,
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
    Map<String, dynamic>? calling,
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
          calling: calling,
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
  CallingEngine? _engine;

  /// Provider credentials for this room — from the REST join response
  /// (widget.calling) or, for entry points without one (incoming call
  /// accept), from the `call:join` ack.
  Map<String, dynamic>? _effectiveCalling;
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

  // Live captions (provider-agnostic — they ride the app's own socket
  // connection, so they behave identically for every media provider).
  final CaptionsController _captions = CaptionsController();
  bool _showCaptions = false;
  // On-device speech recognition so THIS device broadcasts captions to the
  // room (web↔mobile + mobile↔web). Best-effort: some Android builds cannot
  // open a second AudioRecord while WebRTC owns the mic — in that case we
  // silently degrade to receive-only captions.
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _sttInitialized = false;
  bool _captionBroadcastActive = false;
  bool _sttRestartPending = false;

  // Real audio-level active speakers (LiveKit engine). Empty when nobody is
  // speaking or the engine doesn't report levels (MediaSoup → legacy glow).
  Set<String> _activeSpeakerIds = {};

  // Audio output routing (Google-Dialer style earpiece/speaker/bluetooth).
  // Both engines end up on the flutter_webrtc native layer, so one service
  // drives the route for LiveKit AND MediaSoup rooms.
  final AudioRouteService _audioRoutes = AudioRouteService.instance;
  bool _routeInitialized = false;
  bool _switchingAudioRoute = false;
  AudioRoute get _audioRoute => _audioRoutes.route;

  // Google Meet-style pin: tap a tile to make it the big stage tile; tap
  // again (or tap the stage) to unpin. Screen shares always take the stage.
  String? _pinnedPeerId;

  // AI meeting notes: notified while a meeting room is open when the backend
  // finishes generating notes for THIS meeting.
  void Function(dynamic)? _previousNotesHandler;
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

  // Media connect resilience: when the secondary-provider engine fails to
  // connect, we refresh credentials ONCE via `POST /rtc/token` and retry —
  // possibly switching engines if the backend hands back default-provider
  // credentials. Max 1 automatic retry per join flow.
  bool _liveKitRefreshAttempted = false;
  bool _mediaFailed = false;

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
    _captions.attach(_socket, roomId: widget.roomId);
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds += 1);
    });
    _initRoom();
  }

  @override
  void dispose() {
    _stopCaptionBroadcast();
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

    _effectiveCalling = widget.calling;

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
      await _startMediaSession();
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
    _mediaFailed = false;
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
      // Newer backends attach provider credentials to the join ack — this
      // covers entry points without a REST join response (incoming accept).
      final calling = ack['calling'];
      if (_effectiveCalling == null && calling is Map) {
        _effectiveCalling = Map<String, dynamic>.from(calling);
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
    await _startMediaSession();
  }

  /// Marks the media path as fully connected and clears the watchdog/banner.
  void _onMediaConnected() {
    _mediaConnected = true;
    _cancelJoinWatchdog();
    // (Re-)assert the audio output route: a fresh connect must seed the
    // per-call default (video → speaker, audio → earpiece) and a reconnect
    // must not silently fall back to the platform default once the user has
    // picked a route. Runs after the connection settles — see
    // AudioRouteService for the Android audio-focus settle notes.
    unawaited(_ensureAudioRoute());
    if (!mounted) return;
    if (_isConnecting || _showJoinRetry) {
      setState(() {
        _isConnecting = false;
        _showJoinRetry = false;
      });
    }
  }

  /// First media connect: seed the per-call default route. Later (re)connects
  /// re-assert whatever the user picked. Never throws (service is guarded).
  Future<void> _ensureAudioRoute() async {
    if (!_routeInitialized) {
      _routeInitialized = true;
      await _audioRoutes.resetForCall(isVideoCall: widget.enableVideo);
    } else {
      await _audioRoutes.reapply();
    }
    if (mounted) setState(() {});
  }

  /// Apply a route picked from the bottom sheet. [apply] already waits out
  /// the Android audio-focus settle before refreshing the device list
  /// (AudioManager can take 1-3s to settle the communication route).
  Future<void> _selectAudioRoute(AudioRoute route) async {
    if (_switchingAudioRoute) return;
    setState(() => _switchingAudioRoute = true);
    try {
      await _audioRoutes.apply(route, settleDelay: const Duration(milliseconds: 1200));
    } finally {
      if (mounted) setState(() => _switchingAudioRoute = false);
    }
  }

  /// Refresh the device list (so the sheet knows about headsets attached
  /// mid-call), then show the Google-Dialer-style radio sheet.
  Future<void> _showAudioRouteSheet() async {
    await _audioRoutes.refreshOutputs();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(
              'Audio output',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            _audioRouteOption(
              sheetContext: sheetContext,
              route: AudioRoute.earpiece,
              icon: Icons.volume_down_rounded,
              title: 'Earpiece',
            ),
            _audioRouteOption(
              sheetContext: sheetContext,
              route: AudioRoute.speaker,
              icon: Icons.volume_up_rounded,
              title: 'Speaker',
            ),
            _audioRouteOption(
              sheetContext: sheetContext,
              route: AudioRoute.bluetooth,
              icon: Icons.bluetooth_audio_rounded,
              title: _audioRoutes.bluetoothName ?? 'Bluetooth',
              enabled: _audioRoutes.hasBluetooth,
              subtitle: _audioRoutes.hasBluetooth
                  ? null
                  : 'No Bluetooth device connected',
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _audioRouteOption({
    required BuildContext sheetContext,
    required AudioRoute route,
    required IconData icon,
    required String title,
    bool enabled = true,
    String? subtitle,
  }) {
    final selected = _audioRoute == route && (enabled || route != AudioRoute.bluetooth);
    final accent = selected ? const Color(0xFF22C55E) : Colors.white70;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: ListTile(
        leading: Icon(icon, color: accent),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
        trailing: selected
            ? const Icon(Icons.check_rounded, color: Color(0xFF22C55E))
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        minVerticalPadding: 6,
        onTap: !enabled
            ? null
            : () {
              Navigator.of(sheetContext).pop();
              unawaited(_selectAudioRoute(route));
            },
      ),
    );
  }

  IconData get _audioRouteIcon {
    switch (_audioRoute) {
      case AudioRoute.speaker:
        return Icons.volume_up_rounded;
      case AudioRoute.bluetooth:
        return Icons.bluetooth_audio_rounded;
      case AudioRoute.earpiece:
        return Icons.volume_down_rounded;
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
      _mediaFailed = false;
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
      await _startMediaSession();
    } else {
      await _joinCallRoom();
    }
  }

  /// Provider-aware start: when the join credentials point at the secondary
  /// provider the session runs through [LiveKitEngine]; every other case
  /// (credentials absent, degraded, legacy backend) keeps the socket
  /// MediaSoup flow below untouched.
  Future<void> _startMediaSession() async {
    // Each new join flow gets one automatic credential-refresh retry.
    _liveKitRefreshAttempted = false;
    if (_isLiveKit) {
      await _startLiveKitSession();
    } else {
      await _startMediasoupSession();
    }
  }

  static bool _mapIsLiveKit(Map<String, dynamic>? calling) {
    if (calling == null) return false;
    return calling['provider']?.toString() == 'livekit' &&
        (calling['token']?.toString() ?? '').isNotEmpty &&
        (calling['serverUrl']?.toString() ?? '').isNotEmpty;
  }

  bool get _isLiveKit => _mapIsLiveKit(_effectiveCalling);

  Future<void> _startLiveKitSession() async {
    try {
      await _connectLiveKit(_effectiveCalling);
    } catch (e) {
      if (!mounted || _hasLeft) return;
      // Media connect failed — mint fresh credentials ONCE and retry. The
      // backend health-checks its media servers, so the refresh may return a
      // re-minted token for the same provider (stale/expired credentials) or
      // credentials for the default provider (secondary provider down).
      if (_liveKitRefreshAttempted) {
        _surfaceMediaFailure(e);
        return;
      }
      _liveKitRefreshAttempted = true;
      Logger.error('Media connect failed, refreshing credentials once: $e');
      final refreshed = await _refreshCallingCredentials();
      if (!mounted || _hasLeft) return;
      if (refreshed == null) {
        _surfaceMediaFailure(e);
        return;
      }
      setState(() {
        _effectiveCalling = refreshed;
        _connectionLabel = 'Reconnecting…';
      });
      if (_mapIsLiveKit(refreshed)) {
        // Same provider again — retry once with the re-minted credentials.
        try {
          await _connectLiveKit(refreshed);
        } catch (retryError) {
          _surfaceMediaFailure(retryError);
        }
      } else {
        // Default-provider credentials — switch engines (the CallingEngine
        // abstraction already supports both providers on this screen).
        try {
          await _startMediasoupSession();
        } catch (retryError) {
          _surfaceMediaFailure(retryError);
        }
      }
    }
  }

  /// Builds the engine for the given credentials, wires its callbacks and
  /// connects to the room.
  Future<void> _connectLiveKit(Map<String, dynamic>? calling) async {
    final session = CallingSession.fromMap(
      calling,
      roomId: widget.roomId,
      roomType: widget.isMeeting ? 'meeting' : 'call',
      identity: _resolvedUserId,
      displayName: _resolvedUserName,
      isHost: _isCallHost,
      audioStartEnabled: true,
      videoStartEnabled: widget.enableVideo,
    );
    if (session.fallback) {
      Logger.log('Calling provider degraded: ${session.fallbackReason}');
    }

    final engine = LiveKitEngine();
    engine.onConnectionStateChanged = (state) {
      if (!mounted) return;
      setState(() => _connectionLabel = state);
      if (state.toLowerCase() == 'connected') {
        _onMediaConnected();
      }
    };
    engine.onRemoteStream = _addRemoteStream;
    engine.onRemoteStreamRemoved = _removeRemoteStream;
    engine.onLocalStreamReady = (stream) {
      if (!mounted) return;
      setState(() => _localRenderer.srcObject = stream);
    };
    engine.onScreenShareStarted = (stream) {
      if (!mounted) return;
      setState(() => _screenRenderer.srcObject = stream);
    };
    engine.onScreenShareStopped = () {
      if (!mounted) return;
      setState(() => _screenRenderer.srcObject = null);
    };
    engine.onActiveSpeakers = (ids) {
      if (!mounted) return;
      setState(() => _activeSpeakerIds = ids.toSet());
    };

    _engine = engine;
    await engine.connect(session);
    if (!mounted) return;
    final localStream = engine.localStream;
    setState(() {
      if (localStream != null) _localRenderer.srcObject = localStream;
      _isConnecting = false;
      _connectionLabel = 'Connected';
    });
    _onMediaConnected();
  }

  /// One-shot credential refresh (`POST /rtc/token` through the API client).
  /// Returns the refreshed credentials map, or null on any failure.
  Future<Map<String, dynamic>?> _refreshCallingCredentials() async {
    try {
      final response = await ApiService().refreshRtcToken(
        roomType: widget.isMeeting ? 'meeting' : 'call',
        roomId: widget.roomId,
      );
      if (response.data['success'] != true) return null;
      final data = response.data['data'];
      final credentials = data is Map ? data['credentials'] : null;
      return credentials is Map ? Map<String, dynamic>.from(credentials) : null;
    } catch (e) {
      Logger.error('Error refreshing media credentials: $e');
      return null;
    }
  }

  /// Friendly terminal failure: drop the connecting overlay, surface the
  /// retry banner (with a "Retry" action) and a clear message. The room is
  /// never wiped silently — the user can always attempt the join again.
  void _surfaceMediaFailure(Object error) {
    Logger.error('Error joining room: $error');
    if (!mounted) return;
    setState(() {
      _isConnecting = false;
      _showJoinRetry = true;
      _mediaFailed = true;
      _connectionLabel = 'Unable to connect media';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not connect to the room media. Please try again.'),
      ),
    );
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
    _previousNotesHandler = _socket.onMeetingNotesUpdated;

    // AI meeting notes became ready while we are in the room → subtle
    // snackbar that opens the notes view on top of the call screen.
    _socket.onMeetingNotesUpdated = (data) {
      _previousNotesHandler?.call(data);
      if (!widget.isMeeting || !mounted || data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      if (payload['meetingId']?.toString() != widget.roomId) return;
      if (payload['notes'] is! Map) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: const Text('Meeting notes are ready'),
          action: SnackBarAction(label: 'View', onPressed: _openMeetingNotes),
        ),
      );
    };

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

  /// Opens the AI notes view for the meeting room on top of the call screen.
  void _openMeetingNotes() {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MeetingNotesScreen(
        meetingId: widget.roomId,
        meetingTitle: widget.title,
      ),
    ));
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
    _captions.detach();
    _captions.dispose();
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
    _socket.onMeetingNotesUpdated = _previousNotesHandler;
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
    await _engine?.disconnect();
    _engine = null;
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
      if (_isLiveKit) {
        await _engine?.setMicEnabled(enabled);
      } else {
        await _room?.setAudioEnabled(enabled);
      }
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
      if (_isLiveKit) {
        await _engine?.setCameraEnabled(enabled);
      } else {
        await _room?.setVideoEnabled(enabled);
      }
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
      if (_isLiveKit) {
        await _engine?.switchCamera();
      } else {
        await _room?.switchCamera();
      }
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
        if (_isLiveKit) {
          await _engine?.stopScreenShare();
        } else {
          await _room?.stopScreenShare();
        }
        _socket.emitScreenShareStop({roomKey: widget.roomId});
      } else {
        if (_isLiveKit) {
          await _engine?.startScreenShare();
        } else {
          await _room?.startScreenShare();
        }
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

  // -------------------------------------------------------------------------
  // Live captions — display (receive) + broadcast (on-device speech-to-text).
  // The backend relays `caption:segment` to everyone in the room and persists
  // finals into the transcript, feeding AI notes; identical behaviour to web.
  // -------------------------------------------------------------------------
  Future<void> _toggleCaptions() async {
    final next = !_showCaptions;
    setState(() => _showCaptions = next);
    if (next) {
      await _startCaptionBroadcast();
    } else {
      _stopCaptionBroadcast();
    }
  }

  Future<void> _startCaptionBroadcast() async {
    if (_captionBroadcastActive) return;
    try {
      if (!_sttInitialized) {
        _sttInitialized = await _stt.initialize(
          onResult: _onSttResult,
          onError: (error) {
            AppLogger.log('Captions STT error: $error');
            _captionBroadcastActive = false;
          },
          onStatus: (status) {
            // Android/iOS end a listen session after each utterance — restart
            // while captions remain on so recognition is continuous.
            if (status == 'done' || status == 'notListening') {
              _scheduleSttRestart();
            }
          },
        );
        if (!_sttInitialized) {
          AppLogger.log('Captions STT unavailable on this device — receive-only');
          return;
        }
      }
      _captionBroadcastActive = true;
      await _listenOnce();
    } catch (e) {
      // WebRTC owns the mic on some builds — degrade to receive-only captions.
      AppLogger.log('Captions STT failed to start: $e');
      _captionBroadcastActive = false;
    }
  }

  Future<void> _listenOnce() async {
    if (!_captionBroadcastActive || !_sttInitialized) return;
    try {
      await _stt.listen(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
        localeId: Platform.localeName.split('_').first,
      );
    } catch (e) {
      AppLogger.log('Captions STT listen failed: $e');
    }
  }

  void _scheduleSttRestart() {
    if (!_captionBroadcastActive || !_showCaptions || _sttRestartPending) return;
    _sttRestartPending = true;
    Future.delayed(const Duration(milliseconds: 250), () async {
      _sttRestartPending = false;
      if (_captionBroadcastActive && _showCaptions) {
        await _listenOnce();
      }
    });
  }

  void _stopCaptionBroadcast() {
    _captionBroadcastActive = false;
    try {
      _stt.stop();
    } catch (_) {}
  }

  void _onSttResult(stt.SpeechResult result) {
    final text = result.recognizedWords.trim();
    if (text.isEmpty || !_captionBroadcastActive) return;
    _socket.emitCaptionSegment({
      'roomId': widget.roomId,
      'roomType': widget.isMeeting ? 'meeting' : 'call',
      'speakerName': _resolvedUserName,
      'text': text.length > 600 ? text.substring(0, 600) : text,
      'isFinal': result.finalResult,
      'language': Platform.localeName.split('_').first,
    });
    if (result.finalResult) {
      // Session ended with this utterance — keep the loop alive.
      _scheduleSttRestart();
    }
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
            // Live captions overlay — bottom of the room, above the control
            // dock. Only rendered while the user toggled captions on.
            if (_showCaptions && !_isWaitingForAdmission)
              CaptionsOverlay(controller: _captions),
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

  /// Participant count chip for the top bar ("N" with a people icon) —
  /// parity with the web CallRoom header. Reuses the same tile builder that
  /// feeds the video grid, so screen shares count like the web does.
  Widget _buildParticipantCountChip() {
    final count = _buildParticipantTiles().length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_alt_rounded,
              size: 12, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
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
                      const SizedBox(width: 6),
                      _buildParticipantCountChip(),
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

    // Stage + filmstrip: screen shares always take the stage; a tapped tile
    // is pinned to it (tap again to release). Mirrors the web app behaviour.
    _ParticipantTileData? stageTile;
    for (final p in participants) {
      if (p.isScreenShare) {
        stageTile = p;
        break;
      }
    }
    if (stageTile == null && _pinnedPeerId != null) {
      for (final p in participants) {
        if (p.id == _pinnedPeerId) {
          stageTile = p;
          break;
        }
      }
      // The pinned participant left — clear the pin.
      if (stageTile == null) _pinnedPeerId = null;
    }

    if (stageTile != null) {
      final stage = stageTile;
      final strip = participants.where((p) => p.id != stage.id).toList();
      return Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: _buildParticipantTile(stage, pinned: stage.id == _pinnedPeerId),
            ),
          ),
          if (strip.isNotEmpty)
            SizedBox(
              height: 118,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                scrollDirection: Axis.horizontal,
                itemCount: strip.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) => SizedBox(
                  width: 168,
                  child: _buildParticipantTile(strip[index], filmstrip: true),
                ),
              ),
            ),
        ],
      );
    }

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isLandscape
            ? 2
            : (participants.length <= 2 ? 1 : 2),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: isLandscape && participants.length == 2 ? 1.5 : 1.0,
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

  /// True when this participant is actively speaking. With the LiveKit engine
  /// we know exactly who is speaking (audio level events); with MediaSoup we
  /// fall back to "has an open audio stream".
  bool _isSpeaking(_ParticipantTileData participant) {
    if (_isLiveKit) {
      if (participant.isLocal) {
        return _activeSpeakerIds.contains(_resolvedUserId) && _isAudioEnabled;
      }
      return _activeSpeakerIds.contains(participant.id);
    }
    return participant.hasAudioActivity && !participant.isMuted;
  }

  Widget _buildParticipantTile(
    _ParticipantTileData participant, {
    bool pinned = false,
    bool filmstrip = false,
  }) {
    final isSpeaking = _isSpeaking(participant);
    return GestureDetector(
      onTap: participant.isScreenShare
          ? null
          : () => setState(() {
                _pinnedPeerId = _pinnedPeerId == participant.id ? null : participant.id;
              }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSpeaking
                ? const Color(0xFF22C55E)
                : pinned
                    ? const Color(0xFF60A5FA)
                    : Colors.white12,
            width: isSpeaking || pinned ? 2 : 1,
          ),
          boxShadow: [
            // Speaking glow: soft pulsing-ish emerald aura (stronger while
            // the participant is talking, per Google Meet).
            if (isSpeaking)
              BoxShadow(
                color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                blurRadius: 22,
                spreadRadius: 2,
              ),
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
              _buildAvatarFallback(participant.displayName, large: !filmstrip),
            if (participant.isScreenShare)
              Positioned(
                left: 12,
                top: 12,
                child: _statusChip(
                  Icons.screen_share,
                  participant.isLocal ? 'You are presenting' : 'Presenting',
                ),
              ),
            if (pinned)
              Positioned(
                left: 12,
                top: 12,
                child: _statusChip(Icons.push_pin, 'Pinned'),
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
              // Spinner while the join is still in progress; a warning icon
              // once the media connection has definitively failed.
              if (!_mediaFailed)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFBBF24),
                  ),
                )
              else
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 18,
                  color: Color(0xFFFBBF24),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _mediaFailed
                      ? 'Having trouble connecting to the room'
                      : 'Still connecting to the call…',
                  style: const TextStyle(
                    color: Color(0xFFFDE68A),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
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
            // Audio output route (earpiece / speaker / bluetooth) — opens the
            // Google-Dialer-style picker sheet.
            _dockButton(
              icon: _audioRouteIcon,
              active: _audioRoute != AudioRoute.earpiece,
              onPressed: _switchingAudioRoute ? null : _showAudioRouteSheet,
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
              icon: _showCaptions ? Icons.closed_caption : Icons.closed_caption_off,
              active: _showCaptions,
              onPressed: _toggleCaptions,
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
