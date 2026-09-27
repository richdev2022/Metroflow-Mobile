import 'dart:async';
import 'package:flutter/services.dart';

/// Lightweight in-app feedback without extra dependencies:
/// - alert sound via [SystemSound] (built into Flutter services)
/// - haptics via [HapticFeedback]
/// - a repeating incoming-call ringtone loop via a Timer.
class AppFeedback {
  AppFeedback._();

  static Timer? _ringTimer;

  /// Short message/notification blip + light haptic.
  static void playMessageSound() {
    try {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Single heavy impact for incoming calls.
  static void heavyImpact() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Start the looping incoming-call ring (platform alert sound every ~1.4s
  /// with a strong haptic pulse). Safe to call repeatedly.
  static void startRingtone() {
    stopRingtone();
    try {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    } catch (_) {}
    _ringTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      try {
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.heavyImpact();
      } catch (_) {}
    });
  }

  /// Stop the looping ring.
  static void stopRingtone() {
    _ringTimer?.cancel();
    _ringTimer = null;
  }
}
