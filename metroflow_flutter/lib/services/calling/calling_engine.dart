import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../mediasoup_room_service.dart' show RemoteMediaStream;

/// Provider credentials + room context parsed from a join response's
/// `calling` object (REST join response or `call:join` socket ack).
///
/// The object is OPTIONAL on every join path: when absent, or when the
/// provider is not the secondary one with usable credentials, the app keeps
/// the existing socket MediaSoup flow unchanged (100% backward compatible).
class CallingSession {
  /// `'livekit'` or `'mediasoup'`.
  final String provider;

  /// Signaling URL (`wss://...`) — secondary provider only.
  final String? serverUrl;

  /// Pre-signed room token — secondary provider only. Never recreated
  /// client-side; the backend mints refreshes via its REST token endpoint.
  final String? token;

  /// Media room name — equals the call/meeting UUID.
  final String roomName;
  final String roomId;

  /// `'call'` or `'meeting'`.
  final String roomType;
  final String identity;
  final String displayName;
  final bool isHost;
  final bool audioStartEnabled;
  final bool videoStartEnabled;

  /// True when the backend wanted the secondary provider but could not
  /// configure it and degraded to the default flow.
  final bool fallback;
  final String? fallbackReason;

  const CallingSession({
    required this.provider,
    required this.roomName,
    required this.roomId,
    required this.roomType,
    required this.identity,
    required this.displayName,
    required this.isHost,
    required this.audioStartEnabled,
    required this.videoStartEnabled,
    this.serverUrl,
    this.token,
    this.fallback = false,
    this.fallbackReason,
  });

  /// Only a livekit session with a token + server URL switches engines;
  /// everything else (absent credentials, mediasoup, fallback) stays on the
  /// socket flow the app has always used.
  bool get isLiveKit =>
      provider == 'livekit' &&
      token != null &&
      token!.isNotEmpty &&
      serverUrl != null &&
      serverUrl!.isNotEmpty;

  /// Defensive parse — never throws on partial/legacy payloads.
  factory CallingSession.fromMap(
    Map<String, dynamic>? map, {
    required String roomId,
    required String roomType,
    required String identity,
    required String displayName,
    required bool isHost,
    required bool audioStartEnabled,
    required bool videoStartEnabled,
  }) {
    final roomName = map?['roomName']?.toString();
    return CallingSession(
      provider: map?['provider']?.toString() ?? 'mediasoup',
      serverUrl: map?['serverUrl']?.toString(),
      token: map?['token']?.toString(),
      roomName: (roomName == null || roomName.isEmpty) ? roomId : roomName,
      roomId: roomId,
      roomType: map?['roomType']?.toString() ?? roomType,
      identity: identity,
      displayName: displayName,
      isHost: isHost,
      audioStartEnabled: audioStartEnabled,
      videoStartEnabled: videoStartEnabled,
      fallback: map?['fallback'] == true,
      fallbackReason: map?['fallbackReason']?.toString(),
    );
  }
}

/// Engine-agnostic media session used by the call screen.
///
/// The screen consumes remote media through [RemoteMediaStream] — the exact
/// type the MediaSoup path already emits — and every [MediaStream] carried in
/// it is a plain `flutter_webrtc` stream, so one grid/renderer implementation
/// works for both engines without any provider-specific widgets.
abstract class CallingEngine {
  Future<void> connect(CallingSession session);

  /// Idempotent teardown (mic/camera release + signaling close).
  Future<void> disconnect();

  Future<void> setMicEnabled(bool enabled);
  Future<void> setCameraEnabled(bool enabled);
  Future<void> switchCamera();

  /// May be unsupported on some devices; implementations throw so the caller
  /// can surface its existing friendly failure message.
  Future<void> startScreenShare();
  Future<void> stopScreenShare();

  bool get isAudioEnabled;
  bool get isVideoEnabled;
  bool get isScreenSharing;

  /// Remote media arrived (audio or video track, [RemoteMediaStream.source]
  /// is `'screen'` for screen shares).
  void Function(RemoteMediaStream media)? onRemoteStream;

  /// Remote track gone (peer left / stopped mic, camera or share) — carries
  /// the id of the affected [RemoteMediaStream].
  void Function(String id)? onRemoteStreamRemoved;

  /// `'connecting' | 'connected' | 'reconnecting' | 'disconnected'` (plus the
  /// raw transport states the screen already tolerates).
  void Function(String state)? onConnectionStateChanged;

  /// Local camera preview stream. Re-emitted through [onLocalStreamReady]
  /// whenever the track is recreated (e.g. camera re-enabled).
  MediaStream? get localStream;
  void Function(MediaStream stream)? onLocalStreamReady;

  MediaStream? get screenStream;
  void Function(MediaStream stream)? onScreenShareStarted;
  void Function()? onScreenShareStopped;
}
