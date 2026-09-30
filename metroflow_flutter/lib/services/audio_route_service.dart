import 'dart:async';

import 'package:flutter/foundation.dart';
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
/// WHY THIS WORKS FOR BOTH PROVIDERS: the LiveKit engine and the MediaSoup
/// engine both end up on the same `flutter_webrtc` native layer, so the
/// speakerphone toggle below routes call audio identically no matter which
/// engine is driving the room.
///
/// PRIMARY LEVER (Android): `Helper.setSpeakerphoneOn(bool)` on the
/// AudioManager communication audio stream:
/// - speaker   → setSpeakerphoneOn(true)
/// - earpiece  → setSpeakerphoneOn(false) — audio falls back to the default
///   communication device, which is the earpiece (or the connected Bluetooth
///   headset, which is also what the user expects when BT is attached).
/// - bluetooth → setSpeakerphoneOn(false) while a BT SCO headset is connected
///   (the platform routes communication audio to it automatically).
///
/// iOS: `Helper.setSpeakerphoneOn` maps to the WebRTC audio session's
/// `overrideOutputAudioPort` in the native layer, so the earpiece/speaker
/// distinction works the same way. KNOWN LIMITATION (documented in the
/// worklog): iOS cannot enumerate/select a SPECIFIC Bluetooth device from
/// Dart — when a BT headset is attached the OS decides between BT and the
/// earpiece; the sheet still offers the toggle and the speaker always wins.
/// `audio_session` is intentionally NOT used: it is not a locked dependency
/// of this app (absent from pubspec.lock) and the task forbids speculative
/// new dependencies.
///
/// Bluetooth device discovery: `navigator.mediaDevices.enumerateDevices()`.
/// On Android a connected BT headset shows up with a label like "Bluetooth
/// headset"/"BT SCO" (WebRTC exposes it on the input side); we match by label
/// keywords. On iOS labels are typically generic — the sheet hides the BT
/// entry when discovery finds nothing.
///
/// NOTE (Android audio-focus settle): after toggling the speakerphone the
/// AudioManager takes a moment (up to ~2-3s on some devices) to settle the
/// communication route. [apply] therefore refreshes the discovered outputs
/// after a short delay instead of reading state synchronously.
class AudioRouteService {
  AudioRouteService._();
  static final AudioRouteService instance = AudioRouteService._();

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

  /// Heuristic Bluetooth-label match. Kept deliberately broad: OEMs report
  /// wildly different device names ("BT SCO", "Jabra Evolve", "AirPods Pro",
  /// "Wireless Headset", ...).
  static bool _looksLikeBluetooth(String label) {
    final lower = label.toLowerCase();
    return lower.contains('bluetooth') ||
        lower.contains('btsco') ||
        lower.contains('sco ') ||
        lower.contains('airpod') ||
        lower.contains('wireless') ||
        lower.contains('headset');
  }

  /// Default route for a freshly joined call: video calls open on the
  /// speaker (group/screen-sharing UX), audio calls on the earpiece —
  /// matching the phone-dialer convention.
  AudioRoute initialRouteFor({required bool isVideoCall}) =>
      isVideoCall ? AudioRoute.speaker : AudioRoute.earpiece;

  /// Re-enumerate audio devices (best-effort) and keep the Bluetooth subset.
  /// Never throws.
  Future<List<AudioOutputDevice>> refreshOutputs() async {
    if (kIsWeb) return _bluetoothOutputs;
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
        final label = '${device.label}'.trim();
        if (label.isEmpty || label == 'null') continue;
        if (_looksLikeBluetooth(label)) {
          found.add(AudioOutputDevice(
            id: '${device.deviceId}',
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

  /// Switch the active output to [route]. Applies immediately through the
  /// native layer, then refreshes the discovered outputs after
  /// [settleDelay] so the Android audio-focus settle doesn't leave the UI
  /// showing stale device info. Never throws.
  Future<void> apply(
    AudioRoute route, {
    Duration settleDelay = const Duration(milliseconds: 400),
  }) async {
    _route = route;
    if (kIsWeb) return;
    try {
      // THE one primitive both engines share. Wrapped — a phone whose
      // AudioManager rejects the toggle must not crash the call.
      await rtc.Helper.setSpeakerphoneOn(route == AudioRoute.speaker);
    } catch (e) {
      Logger.error('AudioRouteService.apply($route) failed: $e');
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
