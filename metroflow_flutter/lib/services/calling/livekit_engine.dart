import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../utils/logger.dart';
import '../mediasoup_room_service.dart' show RemoteMediaStream;
import 'calling_engine.dart';

/// [CallingEngine] backed by the secondary calling provider.
///
/// Remote tracks are surfaced as [RemoteMediaStream] (the exact type the
/// MediaSoup path emits) wrapping the underlying `flutter_webrtc` streams the
/// SDK exposes on every track — so the call screen renders both providers
/// with the same `RTCVideoView` grid, no provider-specific widgets.
class LiveKitEngine implements CallingEngine {
  static const _connectTimeout = Duration(seconds: 20);

  lk.Room? _room;
  final List<lk.CancelListenFunc> _listeners = [];
  bool _disconnecting = false;
  bool _audioEnabled = false;
  bool _videoEnabled = false;
  bool _screenSharing = false;
  rtc.MediaStream? _localStream;
  rtc.MediaStream? _screenStream;

  @override
  bool get isAudioEnabled => _audioEnabled;
  @override
  bool get isVideoEnabled => _videoEnabled;
  @override
  bool get isScreenSharing => _screenSharing;

  @override
  rtc.MediaStream? get localStream => _localStream;
  @override
  rtc.MediaStream? get screenStream => _screenStream;

  @override
  void Function(RemoteMediaStream media)? onRemoteStream;
  @override
  void Function(String id)? onRemoteStreamRemoved;
  @override
  void Function(String state)? onConnectionStateChanged;
  @override
  void Function(rtc.MediaStream stream)? onLocalStreamReady;
  @override
  void Function(rtc.MediaStream stream)? onScreenShareStarted;
  @override
  void Function()? onScreenShareStopped;

  @override
  Future<void> connect(CallingSession session) async {
    _disconnecting = false;
    _audioEnabled = false;
    _videoEnabled = false;
    _screenSharing = false;
    await _currentRoom()?.dispose();

    final room = lk.Room();
    _room = room;
    _wireRoomEvents(room);

    try {
      await room
          .connect(session.serverUrl!, session.token!)
          .timeout(_connectTimeout);
    } catch (error) {
      Logger.error('Error connecting to the media room: $error');
      await _teardown();
      rethrow;
    }

    try {
      // Same capture constraints as the MediaSoup path: without explicit
      // AEC/NS/AGC the speaker output is re-captured by the mic and every
      // remote participant hears themselves echoed back.
      final local = room.localParticipant;
      if (local != null && session.audioStartEnabled) {
        await local.setMicrophoneEnabled(
          true,
          audioCaptureOptions: const lk.AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          ),
        );
        _audioEnabled = true;
      }
      if (local != null && session.videoStartEnabled) {
        await local.setCameraEnabled(
          true,
          cameraCaptureOptions: const lk.CameraCaptureOptions(
            cameraPosition: lk.CameraPosition.front,
          ),
        );
        _videoEnabled = true;
      }
    } catch (error) {
      Logger.error('Error publishing local media: $error');
      await _teardown();
      rethrow;
    }

    // Late-joiner discovery: surface tracks that were published before we
    // connected (the subscribe events only fire for later publications).
    for (final participant in room.remoteParticipants.values) {
      _emitExistingTracks(participant);
    }
    _notifyState('connected');
  }

  @override
  Future<void> disconnect() async {
    _disconnecting = true;
    await _teardown();
    _notifyState('disconnected');
  }

  @override
  Future<void> setMicEnabled(bool enabled) async {
    final local = _room?.localParticipant;
    if (local == null) return;
    await local.setMicrophoneEnabled(
      enabled,
      audioCaptureOptions: const lk.AudioCaptureOptions(
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      ),
    );
    _audioEnabled = enabled;
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    final local = _room?.localParticipant;
    if (local == null) return;
    await local.setCameraEnabled(
      enabled,
      cameraCaptureOptions: const lk.CameraCaptureOptions(
        cameraPosition: lk.CameraPosition.front,
      ),
    );
    _videoEnabled = enabled;
  }

  @override
  Future<void> switchCamera() async {
    final track = _cameraTrack();
    if (track == null) return;
    await rtc.Helper.switchCamera(track.mediaStreamTrack);
  }

  @override
  Future<void> startScreenShare() async {
    final local = _room?.localParticipant;
    if (local == null || _screenSharing) return;
    try {
      await local.setScreenShareEnabled(true);
    } catch (error) {
      Logger.error('Error starting screen share: $error');
      // Mobile devices usually cannot capture the screen without extra
      // setup — rethrow a user-friendly message for the call screen snackbar.
      throw Exception('Screen sharing is not available on this device');
    }
  }

  @override
  Future<void> stopScreenShare() async {
    final local = _room?.localParticipant;
    if (local == null || !_screenSharing) return;
    try {
      await local.setScreenShareEnabled(false);
    } finally {
      _screenSharing = false;
      _screenStream = null;
      onScreenShareStopped?.call();
    }
  }

  // -----------------------------------------------------------------------

  lk.Room? _currentRoom() => _room;

  void _wireRoomEvents(lk.Room room) {
    void keep(lk.CancelListenFunc cancel) => _listeners.add(cancel);

    keep(room.events.on<lk.TrackSubscribedEvent>((event) {
      _emitRemoteTrack(event.participant, event.publication, event.track);
    }));
    keep(room.events.on<lk.TrackUnsubscribedEvent>((event) {
      onRemoteStreamRemoved?.call(event.publication.sid);
    }));
    keep(room.events.on<lk.ParticipantConnectedEvent>((event) {
      _emitExistingTracks(event.participant);
    }));
    keep(room.events.on<lk.ParticipantDisconnectedEvent>((event) {
      for (final publication in event.participant.trackPublications.values) {
        onRemoteStreamRemoved?.call(publication.sid);
      }
    }));
    // A muted mic keeps its track in the media room, but the grid treats a
    // missing audio stream as "muted" (MediaSoup closes muted producers) —
    // mirror that behavior by dropping/re-adding the audio tile.
    keep(room.events.on<lk.TrackMutedEvent>((event) {
      if (event.participant is! lk.RemoteParticipant) return;
      onRemoteStreamRemoved?.call(event.publication.sid);
    }));
    keep(room.events.on<lk.TrackUnmutedEvent>((event) {
      final participant = event.participant;
      final publication = event.publication;
      final track = publication.track;
      if (participant is! lk.RemoteParticipant ||
          publication is! lk.RemoteTrackPublication ||
          track == null) {
        return;
      }
      _emitRemoteTrack(participant, publication, track);
    }));
    keep(room.events.on<lk.LocalTrackPublishedEvent>((event) {
      _handleLocalTrackPublished(event);
    }));
    keep(room.events.on<lk.LocalTrackUnpublishedEvent>((event) {
      _handleLocalTrackUnpublished(event);
    }));
    keep(room.events.on<lk.RoomReconnectingEvent>((_) {
      _notifyState('reconnecting');
    }));
    keep(room.events.on<lk.RoomReconnectedEvent>((_) {
      _notifyState('connected');
    }));
    keep(room.events.on<lk.RoomDisconnectedEvent>((event) {
      Logger.log('Media room disconnected: ${event.reason}');
      if (_disconnecting) return;
      _notifyState('disconnected');
    }));
    keep(room.events.on<lk.TrackSubscriptionExceptionEvent>((event) {
      Logger.error('Error subscribing to a remote track: '
          '${event.reason} (sid: ${event.sid})');
    }));
  }

  void _emitExistingTracks(lk.RemoteParticipant participant) {
    for (final publication in participant.trackPublications.values) {
      final track = publication.track;
      if (track != null) {
        _emitRemoteTrack(participant, publication, track);
      }
    }
  }

  void _emitRemoteTrack(
    lk.RemoteParticipant participant,
    lk.RemoteTrackPublication publication,
    lk.Track track,
  ) {
    final isAudio = track.kind == lk.TrackType.AUDIO;
    final isScreen = publication.source == lk.TrackSource.screenShareVideo ||
        publication.source == lk.TrackSource.screenShareAudio;
    onRemoteStream?.call(RemoteMediaStream(
      id: publication.sid,
      producerId: publication.sid,
      peerId: participant.identity,
      kind: isAudio ? 'audio' : 'video',
      source: isScreen
          ? 'screen'
          : isAudio
              ? 'microphone'
              : 'webcam',
      stream: track.mediaStream,
    ));
  }

  void _handleLocalTrackPublished(lk.LocalTrackPublishedEvent event) {
    final track = event.publication.track;
    if (track == null) return;
    if (event.publication.source == lk.TrackSource.camera) {
      _localStream = track.mediaStream;
      onLocalStreamReady?.call(track.mediaStream);
    } else if (event.publication.source == lk.TrackSource.screenShareVideo) {
      _screenStream = track.mediaStream;
      _screenSharing = true;
      onScreenShareStarted?.call(track.mediaStream);
    }
  }

  void _handleLocalTrackUnpublished(lk.LocalTrackUnpublishedEvent event) {
    if (event.publication.source == lk.TrackSource.screenShareVideo) {
      _screenSharing = false;
      _screenStream = null;
      onScreenShareStopped?.call();
    } else if (event.publication.source == lk.TrackSource.camera) {
      _localStream = null;
    }
  }

  lk.LocalVideoTrack? _cameraTrack() {
    final room = _room;
    final local = room?.localParticipant;
    if (local == null) return null;
    for (final publication in local.trackPublications.values) {
      final track = publication.track;
      if (publication.source == lk.TrackSource.camera && track is lk.LocalVideoTrack) {
        return track;
      }
    }
    return null;
  }

  Future<void> _teardown() async {
    for (final cancel in _listeners) {
      try {
        await cancel();
      } catch (_) {}
    }
    _listeners.clear();

    final room = _room;
    _room = null;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
    }
    _localStream = null;
    _screenStream = null;
    _screenSharing = false;
    _audioEnabled = false;
    _videoEnabled = false;
  }

  void _notifyState(String state) {
    onConnectionStateChanged?.call(state);
  }
}
