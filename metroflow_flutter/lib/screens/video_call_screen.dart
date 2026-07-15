import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/mediasoup_room_service.dart';
import '../services/socket_service.dart';
import '../utils/logger.dart';

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final String title;
  final bool isMeeting;
  final bool enableVideo;
  final FutureOr<void> Function()? onLeave;

  const VideoCallScreen({
    super.key,
    required this.roomId,
    required this.title,
    this.isMeeting = false,
    this.enableVideo = true,
    this.onLeave,
  });

  static Future<void> showModal({
    required BuildContext context,
    required String roomId,
    required String title,
    bool isMeeting = false,
    bool enableVideo = true,
    FutureOr<void> Function()? onLeave,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: VideoCallScreen(
          roomId: roomId,
          title: title,
          isMeeting: isMeeting,
          enableVideo: enableVideo,
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
  bool _isConnecting = true;
  bool _isSwitchingScreenShare = false;
  String _connectionLabel = 'Connecting...';
  void Function(dynamic)? _previousChatHandler;
  void Function(dynamic)? _previousScreenStartHandler;
  void Function(dynamic)? _previousScreenStopHandler;
  void Function(dynamic)? _previousRecordingStartHandler;
  void Function(dynamic)? _previousRecordingStopHandler;
  void Function(dynamic)? _previousRecordingPauseHandler;

  @override
  void initState() {
    super.initState();
    _isVideoEnabled = widget.enableVideo;
    _initRoom();
  }

  @override
  void dispose() {
    unawaited(_cleanup());
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _initRoom() async {
    await _localRenderer.initialize();
    await _screenRenderer.initialize();
    _wireRoomEvents();

    try {
      if (widget.isMeeting) {
        _socket.emitMeetingJoin({'meetingId': widget.roomId});
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

    _socket.onMeetingChatMessage = (data) {
      _previousChatHandler?.call(data);
      final payload = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      if (payload['meetingId'] != null && payload['meetingId'] != widget.roomId) return;
      if (!mounted) return;
      setState(() {
        _chatLines.add(_ChatLine(
          userId: payload['userId']?.toString() ?? 'User',
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
    return id == null || id.toString() == widget.roomId;
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
    _socket.emitMeetingChatMessage({
      'meetingId': widget.roomId,
      'message': message,
    });
    setState(() {
      _chatLines.add(_ChatLine(
        userId: 'You',
        message: message,
        timestamp: DateTime.now(),
      ));
    });
    _chatController.clear();
  }

  Future<void> _leave() async {
    if (_hasLeft) return;
    _hasLeft = true;

    if (widget.isMeeting) {
      _socket.emitMeetingLeave({'meetingId': widget.roomId});
    }
    await Future<void>.sync(() => widget.onLeave?.call());

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title),
              Text(
                _connectionLabel,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _leave,
          ),
          actions: [
            if (widget.isMeeting)
              IconButton(
                tooltip: 'Chat',
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => setState(() => _showChat = !_showChat),
              ),
            IconButton(
              tooltip: _isRecording ? 'Stop recording' : 'Start recording',
              icon: Icon(_isRecording ? Icons.fiber_manual_record : Icons.radio_button_unchecked),
              color: _isRecording ? Colors.redAccent : Colors.white,
              onPressed: _toggleRecording,
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _buildVideoGrid()),
            Positioned(
              top: 16,
              right: 16,
              child: _buildLocalPreview(),
            ),
            if (_showChat) _buildChatPanel(),
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoGrid() {
    if (_isConnecting) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
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
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
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
        color: const Color(0xFF202124),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSpeaking ? const Color(0xFF34A853) : Colors.white12,
          width: isSpeaking ? 3 : 1,
        ),
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
              child: _statusChip(Icons.screen_share, participant.isLocal ? 'You are presenting' : 'Presenting'),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    participant.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: muted ? Colors.red : (active ? const Color(0xFF34A853) : Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        muted ? Icons.mic_off : Icons.mic,
        color: Colors.white,
        size: 16,
      ),
    );
  }

  Widget _buildAvatarFallback(String name, {bool large = false}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1F2937), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: CircleAvatar(
          radius: large ? 52 : 28,
          backgroundColor: Colors.white.withValues(alpha: 0.16),
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
    return SizedBox(
      width: 120,
      height: 160,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.grey[900],
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
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _controlButton(
          icon: _isAudioEnabled ? Icons.mic : Icons.mic_off,
          active: _isAudioEnabled,
          onPressed: _toggleAudio,
        ),
        const SizedBox(width: 12),
        if (widget.enableVideo) ...[
          _controlButton(
            icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
            active: _isVideoEnabled,
            onPressed: _toggleVideo,
          ),
          const SizedBox(width: 12),
          _controlButton(
            icon: Icons.flip_camera_ios,
            active: true,
            onPressed: _switchCamera,
          ),
          const SizedBox(width: 12),
        ],
        _controlButton(
          icon: _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
          active: _isScreenSharing,
          onPressed: _isSwitchingScreenShare ? null : _toggleScreenShare,
        ),
        const SizedBox(width: 12),
        _controlButton(
          icon: Icons.call_end,
          active: false,
          backgroundColor: Colors.red,
          size: 60,
          onPressed: _leave,
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required bool active,
    required FutureOr<void> Function()? onPressed,
    Color? backgroundColor,
    double size = 50,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton.filled(
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor ?? (active ? Colors.white24 : Colors.red.shade800),
          foregroundColor: Colors.white,
        ),
        icon: Icon(icon),
        onPressed: onPressed == null ? null : () async {
          await onPressed();
        },
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
          color: Colors.white,
          child: Column(
            children: [
              ListTile(
                title: const Text('Meeting chat'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _showChat = false),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _chatLines.length,
                  itemBuilder: (context, index) {
                    final line = _chatLines[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.userId,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          Text(line.message),
                          Text(
                            TimeOfDay.fromDateTime(line.timestamp).format(context),
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        decoration: const InputDecoration(hintText: 'Message'),
                        onSubmitted: (_) => _sendChatMessage(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _sendChatMessage,
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
