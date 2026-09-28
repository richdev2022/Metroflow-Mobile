import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Centralised audio + haptic feedback.
///
/// All sounds are bundled WAV assets under `assets/sounds/` played through
/// `audioplayers` (replaces the old SystemSound.alert beeps which could not
/// be customised and were inaudible on many Android devices).
///
/// Every audio call is wrapped in try/catch — a missing/broken asset must
/// never crash the app; haptics still run as a fallback.
///
/// NOTE (Android/iOS session config): the ringtone/ringback players use
/// `AndroidAudioFocus.none` (+ iOS mix-with-others behaviour via the default
/// playback category) so an incoming ring still plays while other audio
/// (music, another call) holds the audio focus.
///
/// NOTE (background playback): as long as the Dart/Flutter process is alive
/// (app backgrounded but not killed), these sounds keep playing — that is
/// what powers incoming-call ringing while the app is not focused. Full
/// background delivery after process death requires FCM later.
class AppFeedback {
  AppFeedback._();

  /// Looping incoming-call ringtone player.
  static AudioPlayer? _ringtonePlayer;
  static Timer? _ringHapticTimer;

  /// Looping outbound ringback player.
  static AudioPlayer? _ringbackPlayer;

  /// Audio session config for looping rings: do NOT steal audio focus so the
  /// ring plays even during other audio. Wrapped in try/catch at every use —
  /// platform quirks must never crash the app.
  // NOTE: AudioContext's constructor is NOT const in audioplayers 6.x, so
  // this getter constructs a fresh instance each call (cheap, config-only).
  static AudioContext get _ringAudioContext => AudioContext(
        android: AudioContextAndroid(
          audioFocus: AndroidAudioFocus.none,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          stayAwake: true,
        ),
      );

  // -------------------------------------------------------------------------
  // One-shot sounds
  // -------------------------------------------------------------------------

  /// Short message/notification blip + light haptic.
  static void playMessageSound() {
    HapticFeedback.lightImpact();
    _playOnce('sounds/message-received.wav');
  }

  /// Subtle confirmation for outgoing messages.
  static void playSentSound() {
    _playOnce('sounds/message-sent.wav');
  }

  /// "Call ended" blip (remote end / hang-up).
  static void playCallEndedSound() {
    _playOnce('sounds/call-ended.wav');
  }

  /// Fire-and-forget single-shot playback with a dedicated player instance
  /// that releases itself on completion. Safe to call from anywhere; never
  /// throws even if the asset is missing.
  static void _playOnce(String assetPath) {
    final player = AudioPlayer();
    Future<void>(() async {
      try {
        await player.play(AssetSource(assetPath));
      } catch (_) {
        // Missing/broken asset — clean up and give up silently.
        try {
          await player.dispose();
        } catch (_) {}
        return;
      }
      // Release native resources once the clip finishes playing.
      unawaited(player.onPlayerComplete.first.then((_) async {
        try {
          await player.dispose();
        } catch (_) {}
      }).catchError((_) async {
        try {
          await player.dispose();
        } catch (_) {}
      }));
    });
  }

  // -------------------------------------------------------------------------
  // Incoming-call ringtone (looping)
  // -------------------------------------------------------------------------

  /// Start the looping incoming-call ringtone + a strong haptic pulse every
  /// ~1.4s. Idempotent: calling it again restarts cleanly instead of stacking
  /// players/timers.
  static void startRingtone() {
    stopRingtone();
    final player = AudioPlayer();
    _ringtonePlayer = player;
    unawaited(Future<void>(() async {
      try {
        await player.setPlayerMode(PlayerMode.mediaPlayer);
        await player.setAudioContext(_ringAudioContext);
        await player.setReleaseMode(ReleaseMode.loop);
        await player.setVolume(1.0);
        await player.play(AssetSource('sounds/ringtone.wav'));
      } catch (_) {
        // Asset missing or platform audio error — haptics below still run.
      }
    }));
    HapticFeedback.heavyImpact();
    _ringHapticTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
    });
  }

  /// Stop the looping ringtone and release its player. Safe to call multiple
  /// times / when not ringing.
  static void stopRingtone() {
    _ringHapticTimer?.cancel();
    _ringHapticTimer = null;
    final player = _ringtonePlayer;
    _ringtonePlayer = null;
    if (player == null) return;
    unawaited(Future<void>(() async {
      try {
        await player.stop();
        await player.release();
        await player.dispose();
      } catch (_) {}
    }));
  }

  // -------------------------------------------------------------------------
  // Outbound ringback (looping)
  // -------------------------------------------------------------------------

  /// Start the looping ringback tone for OUTBOUND calls (we are waiting for
  /// the other party to accept). Idempotent like [startRingtone].
  static void startRingback() {
    stopRingback();
    final player = AudioPlayer();
    _ringbackPlayer = player;
    unawaited(Future<void>(() async {
      try {
        await player.setPlayerMode(PlayerMode.mediaPlayer);
        await player.setAudioContext(_ringAudioContext);
        await player.setReleaseMode(ReleaseMode.loop);
        await player.setVolume(0.9);
        await player.play(AssetSource('sounds/ringback.wav'));
      } catch (_) {
        // Asset missing — silent dialing is better than crashing.
      }
    }));
  }

  /// Stop the looped ringback. Safe to call multiple times.
  static void stopRingback() {
    final player = _ringbackPlayer;
    _ringbackPlayer = null;
    if (player == null) return;
    unawaited(Future<void>(() async {
      try {
        await player.stop();
        await player.release();
        await player.dispose();
      } catch (_) {}
    }));
  }

  // -------------------------------------------------------------------------
  // Haptics
  // -------------------------------------------------------------------------

  /// Single heavy impact for incoming calls.
  static void heavyImpact() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
