import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import '../utils/logger.dart';

/// Logical audio output routes for an active call (Google-Dialer style).
enum AudioRoute { earpiece, speaker, bluetooth }

/// A physical output device discovered on the device (Bluetooth headsets).
class AudioOutputDevice {
  final String id;
  final String label;
  final bool isBluetooth;

  const AudioOutputDevice({
    required this.id,
    required this.label,
    this.isBluetooth = false,
  });
}

/// Engine-agnostic audio output routing for calls.
///
/// The LiveKit engine and the MediaSoup engine both end up on the same
/// `flutter_webrtc` native layer, so routing through either the native
/// channel below or the WebRTC helper lands on the same audio stack.
///
/// PRIMARY LEVER — native MethodChannel `metricorex/audio` (MainActivity.kt /
/// AppDelegate.swift):
/// - Android: `AudioManager.setCommunicationDevice` (API 31+) pins the
///   communication route to the EXACT device — built-in speaker, earpiece or
///   the connected Bluetooth SCO/BLE headset. Pre-31 falls back to
///   isSpeakerphoneOn + Bluetooth SCO.
/// - iOS: `AVAudioSession.overrideOutputAudioPort(.speaker/.none)`; iOS does
///   not allow selecting a SPECIFIC BT device from app code, so BT is the
///   OS default route when the override is removed.
///
/// FALLBACK LEVER (channel unavailable / refused): the previous behavior —
/// `rtc.Helper.setSpeakerphoneOn(bool)` — still applies, so a route can never
/// be WORSE than before this service existed.
///
/// Bluetooth device discovery: the native `listOutputs` first (authoritative
/// output devices); if the channel is unavailable, falls back to
/// `navigator.mediaDevices.enumerateDevices()` label matching.
class AudioRouteService {
  AudioRouteService._();
  static final AudioRouteService instance = AudioRouteService._();

  static const MethodChannel _channel = MethodChannel('metricorex/audio');
  static bool? _channelAvailable;

  /// Selected route for the CURRENT call. The call screen resets it via
  /// [initialRouteFor] when a new session starts.
  AudioRoute _route = AudioRoute.earpiece;
  AudioRoute get route => _route;

  List<AudioOutputDevice> _bluetoothOutputs = const [];
  List<AudioOutputDevice> get bluetoothOutputs => _bluetoothOutputs;

  bool get hasBluetooth => _bluetoothOutputs.isNotEmpty;

  /// Friendly name of the first discovered Bluetooth device (sheet subtitle).
  String? get bluetoothName {
    for (final device in _bluetoothOutputs) {
      final label = device.label.trim();
      if (label.isNotEmpty) return label;
    }
    return null;
  }

  /// Heuristic Bluetooth-label match (fallback path only). Kept deliberately
  /// broad: OEMs report wildly different device names ("BT SCO", "Jabra
  /// Evolve", "AirPods Pro", "Wireless Headset", ...).
  static bool _looksLikeBluetooth(String label) {
    final lower = label.toLowerCase();
    return lower.contains('bluetooth') ||
        lower.contains('btsco') ||
        lower.contains('sco ') ||
        lower.contains('airpod') ||
        lower.contains('wireless') ||
        lower.contains('headset');
  }

  static String _routeName(AudioRoute route) {
    switch (route) {
      case AudioRoute.speaker:
        return 'speaker';
      case AudioRoute.earpiece:
        return 'earpiece';
      case AudioRoute.bluetooth:
        return 'bluetooth';
    }
  }

  /// Default route for a freshly joined call: video calls open on the
  /// speaker (group/screen-sharing UX), audio calls on the earpiece —
  /// matching the phone-dialer convention.
  AudioRoute initialRouteFor({required bool isVideoCall}) =>
      isVideoCall ? AudioRoute.speaker : AudioRoute.earpiece;

  /// Re-enumerate audio devices (best-effort) and keep the Bluetooth subset.
  /// Native channel first, WebRTC device labels as fallback. Never throws.
  Future<List<AudioOutputDevice>> refreshOutputs() async {
    if (kIsWeb) return _bluetoothOutputs;
    try {
      if (_channelAvailable != false) {
        final rows = await _channel.invokeMethod<List<dynamic>>('listOutputs');
        _channelAvailable = true;
        final found = <AudioOutputDevice>[];
        for (final row in rows ?? const <dynamic>[]) {
          if (row is! Map) continue;
          final isBt = row['isBluetooth'] == true;
          final label = '${row['productName'] ?? ''}'.trim();
          final type = '${row['type'] ?? ''}';
          if (!isBt) continue;
          found.add(AudioOutputDevice(
            id: '${row['id'] ?? label}',
            label: label.isEmpty ? 'Bluetooth $type' : label,
            isBluetooth: true,
          ));
        }
        _bluetoothOutputs = found;
        return _bluetoothOutputs;
      }
    } on MissingPluginException {
      _channelAvailable = false;
    } catch (e) {
      // Native enumeration failed — fall through to the WebRTC labels.
      Logger.error('AudioRouteService native refreshOutputs failed: $e');
    }
    try {
      final devices = await rtc.navigator.mediaDevices.enumerateDevices();
      final found = <AudioOutputDevice>[];
      for (final device in devices) {
        // String interpolation (instead of `??` / `== null`) keeps this
        // correct whether the underlying fields are nullable or not.
        final kind = '${device.kind}'.toLowerCase();
        // WebRTC on mobile exposes the BT SCO headset on the INPUT side;
        // outputs may also carry it on some OEMs — scan both.
        if (kind != 'audioinput' && kind != 'audiooutput') continue;
        final label = device.label.trim();
        if (label.isEmpty || label == 'null') continue;
        if (_looksLikeBluetooth(label)) {
          found.add(AudioOutputDevice(
            id: device.deviceId,
            label: label,
            isBluetooth: true,
          ));
        }
      }
      _bluetoothOutputs = found;
    } catch (e) {
      // Enumeration is best-effort: an OEM quirk must never break a call.
      Logger.error('AudioRouteService.refreshOutputs failed: $e');
      _bluetoothOutputs = const [];
    }
    return _bluetoothOutputs;
  }

  /// Switch the active output to [route]. Applies through the native channel
  /// when available, then always re-asserts through the WebRTC helper so the
  /// speakerphone bit agrees with the requested route on every platform.
  /// Refreshes the discovered outputs after [settleDelay] so the Android
  /// audio-focus settle doesn't leave the UI showing stale device info.
  /// Never throws.
  Future<void> apply(
    AudioRoute route, {
    Duration settleDelay = const Duration(milliseconds: 400),
  }) async {
    _route = route;
    if (kIsWeb) return;
    final name = _routeName(route);

    // 1) Native pin (authoritative on Android 12+; speaker/earpiece on iOS).
    try {
      if (_channelAvailable != false) {
        final ok = await _channel.invokeMethod<bool>(
          'setRoute',
          {'route': name},
        );
        if (_channelAvailable == null) _channelAvailable = true;
        if (ok == true) {
          Logger.log('AudioRouteService: native route applied: $name');
        }
      }
    } on MissingPluginException {
      _channelAvailable = false;
    } catch (e) {
      Logger.error('AudioRouteService native apply($name) failed: $e');
    }

    // 2) WebRTC agreement: speaker true/false. For BT the OS picks the
    // headset once the speakerphone is off (both native paths above make
    // that happen; on Android setCommunicationDevice already pinned it).
    try {
      await rtc.Helper.setSpeakerphoneOn(route == AudioRoute.speaker);
    } catch (e) {
      Logger.error('AudioRouteService.apply($route) webrtc fallback failed: $e');
    }

    if (settleDelay > Duration.zero) {
      await Future<void>.delayed(settleDelay);
      await refreshOutputs();
    }
  }

  /// Re-assert the current route (media reconnect / engine re-create can
  /// reset the platform route to defaults). Never throws.
  Future<void> reapply() => apply(_route, settleDelay: Duration.zero);

  /// Reset to the given default at the start of a call session.
  Future<void> resetForCall({required bool isVideoCall}) async {
    _route = initialRouteFor(isVideoCall: isVideoCall);
    await refreshOutputs();
    await reapply();
  }
}
