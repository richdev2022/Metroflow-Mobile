import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mediasoup_client_flutter/mediasoup_client_flutter.dart';

import '../utils/logger.dart';
import 'socket_service.dart';

class RemoteMediaStream {
  final String id;
  final String producerId;
  final String? peerId;
  final String kind;
  final String? source;
  final MediaStream stream;

  RemoteMediaStream({
    required this.id,
    required this.producerId,
    required this.kind,
    required this.stream,
    this.peerId,
    this.source,
  });
}

class MediasoupRoomService {
  MediasoupRoomService({
    required this.roomId,
    required this.socket,
    required this.produceVideo,
    required this.produceAudio,
    this.onRemoteStream,
    this.onConnectionStateChanged,
    this.onScreenShareStarted,
    this.onScreenShareStopped,
  });

  final String roomId;
  final SocketService socket;
  final bool produceVideo;
  final bool produceAudio;
  final void Function(RemoteMediaStream stream)? onRemoteStream;
  final void Function(String state)? onConnectionStateChanged;
  final void Function(MediaStream stream)? onScreenShareStarted;
  final void Function()? onScreenShareStopped;

  MediaStream? get screenStream => _screenStream;

  final Device _device = Device();
  final Map<String, Producer> _producers = {};
  final Map<String, Consumer> _consumers = {};

  Transport? _sendTransport;
  Transport? _recvTransport;
  MediaStream? localStream;
  MediaStream? _screenStream;
  Producer? _screenProducer;
  void Function(dynamic)? _previousNewProducerHandler;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _previousNewProducerHandler = socket.onMediasoupNewProducer;
    socket.onMediasoupNewProducer = _handleNewProducer;

    final routerResponse = await socket.mediasoupGetRouterRtpCapabilities();
    final routerCapabilities = _payload(routerResponse)['rtpCapabilities'] ?? routerResponse;
    await _device.load(
      routerRtpCapabilities: RtpCapabilities.fromMap(
        Map<String, dynamic>.from(routerCapabilities as Map),
      ),
    );

    await _createTransports();
    await _startLocalMedia();
  }

  Future<void> stop() async {
    socket.onMediasoupNewProducer = _previousNewProducerHandler;

    for (final producer in _producers.values) {
      producer.close();
    }
    for (final consumer in _consumers.values) {
      await consumer.close();
    }
    await _sendTransport?.close();
    await _recvTransport?.close();
    await localStream?.dispose();
    await _screenStream?.dispose();

    _producers.clear();
    _consumers.clear();
    _sendTransport = null;
    _recvTransport = null;
    localStream = null;
    _started = false;
  }

  Future<void> setAudioEnabled(bool enabled) async {
    for (final track in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<void> setVideoEnabled(bool enabled) async {
    for (final track in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    for (final track in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      await Helper.switchCamera(track);
    }
  }

  Future<void> startScreenShare() async {
    if (_screenProducer != null) return;
    final sendTransport = _sendTransport;
    if (sendTransport == null) return;

    _screenStream = await navigator.mediaDevices.getDisplayMedia({
      'audio': false,
      'video': true,
    });

    final track = _screenStream!.getVideoTracks().first;
    sendTransport.produce(
      stream: _screenStream!,
      track: track,
      source: 'screen',
      appData: {'source': 'screen'},
    );
    onScreenShareStarted?.call(_screenStream!);
  }

  Future<void> stopScreenShare() async {
    for (final producer in _producers.values.where((p) => p.source == 'screen').toList()) {
      producer.close();
      _producers.remove(producer.id);
    }
    for (final track in _screenStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _screenStream?.dispose();
    _screenStream = null;
    _screenProducer = null;
    onScreenShareStopped?.call();
  }

  Future<void> _createTransports() async {
    final sendInfo = _payload(await socket.mediasoupCreateWebRtcTransport({'roomId': roomId}));
    final recvInfo = _payload(await socket.mediasoupCreateWebRtcTransport({'roomId': roomId}));

    late final Transport sendTransport;
    sendTransport = _device.createSendTransportFromMap(
      sendInfo,
      producerCallback: (Producer producer) {
        _producers[producer.id] = producer;
        if (producer.source == 'screen') {
          _screenProducer = producer;
        }
      },
    );
    _wireTransport(sendTransport);
    sendTransport.on('produce', (Map data) async {
      try {
        final response = _payload(await socket.mediasoupProduce({
          'transportId': sendTransport.id,
          'kind': data['kind'],
          'rtpParameters': data['rtpParameters'].toMap(),
          'roomId': roomId,
          'appData': data['appData'],
        }));
        data['callback'](response['id']);
      } catch (error) {
        data['errback'](error);
      }
    });

    final recvTransport = _device.createRecvTransportFromMap(
      recvInfo,
      consumerCallback: (Consumer consumer) {
        _consumers[consumer.id] = consumer;
        onRemoteStream?.call(RemoteMediaStream(
          id: consumer.id,
          producerId: consumer.producerId,
          peerId: consumer.peerId,
          kind: consumer.kind ?? 'video',
          source: consumer.appData['source']?.toString(),
          stream: consumer.stream,
        ));
      },
    );
    _wireTransport(recvTransport);

    _sendTransport = sendTransport;
    _recvTransport = recvTransport;
  }

  void _wireTransport(Transport transport) {
    transport.on('connect', (Map data) async {
      try {
        await socket.mediasoupConnectWebRtcTransport({
          'transportId': transport.id,
          'dtlsParameters': data['dtlsParameters'].toMap(),
          'roomId': roomId,
        });
        data['callback']();
      } catch (error) {
        data['errback'](error);
      }
    });

    transport.on('connectionstatechange', (data) {
      if (data is Map && data['connectionState'] != null) {
        onConnectionStateChanged?.call(data['connectionState'].toString());
      } else {
        onConnectionStateChanged?.call(data.toString());
      }
    });
  }

  Future<void> _startLocalMedia() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': produceAudio,
      'video': produceVideo
          ? {
              'facingMode': 'user',
              'mandatory': {
                'minWidth': '640',
                'minHeight': '360',
                'minFrameRate': '24',
              },
            }
          : false,
    });

    if (produceAudio) {
      for (final track in localStream!.getAudioTracks()) {
        _sendTransport?.produce(
          stream: localStream!,
          track: track,
          source: 'microphone',
        );
      }
    }

    if (produceVideo) {
      for (final track in localStream!.getVideoTracks()) {
        _sendTransport?.produce(
          stream: localStream!,
          track: track,
          source: 'webcam',
        );
      }
    }
  }

  Future<void> _handleNewProducer(dynamic data) async {
    final payload = _payload(data);
    final producerId = payload['producerId']?.toString();
    if (producerId == null || _consumers.values.any((c) => c.producerId == producerId)) {
      return;
    }
    await consumeProducer(producerId, kind: payload['kind']?.toString());
  }

  Future<void> consumeProducer(String producerId, {String? kind}) async {
    final recvTransport = _recvTransport;
    if (recvTransport == null) return;

    try {
      final response = _payload(await socket.mediasoupConsume({
        'transportId': recvTransport.id,
        'producerId': producerId,
        'rtpCapabilities': _device.rtpCapabilities.toMap(),
        'roomId': roomId,
      }));

      final consumerId = response['id']?.toString();
      if (consumerId == null) return;

      recvTransport.consume(
        id: consumerId,
        producerId: response['producerId']?.toString() ?? producerId,
        peerId: response['peerId']?.toString() ?? response['userId']?.toString() ?? '',
        kind: _mediaKind(response['kind']?.toString() ?? kind ?? 'video'),
        appData: response['appData'] is Map
            ? Map<String, dynamic>.from(response['appData'] as Map)
            : <String, dynamic>{},
        rtpParameters: RtpParameters.fromMap(
          Map<String, dynamic>.from(response['rtpParameters'] as Map),
        ),
      );

      await socket.mediasoupResume({
        'consumerId': consumerId,
        'roomId': roomId,
      });
    } catch (error) {
      Logger.error('Error consuming mediasoup producer $producerId: $error');
      if (kDebugMode) rethrow;
    }
  }

  RTCRtpMediaType _mediaKind(String kind) {
    return kind == 'audio'
        ? RTCRtpMediaType.RTCRtpMediaTypeAudio
        : RTCRtpMediaType.RTCRtpMediaTypeVideo;
  }

  Map<String, dynamic> _payload(dynamic value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final data = map['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return map;
    }
    return <String, dynamic>{};
  }
}
