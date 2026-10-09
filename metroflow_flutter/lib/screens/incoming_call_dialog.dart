import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../services/biometrics.dart';
import '../services/push_notification_service.dart';
import '../widgets/avatar_with_initials.dart';
import 'video_call_screen.dart';
import '../services/api.dart';

/// GLOBAL incoming-call overlay (mounted once in main.dart's builder Stack,
/// below the maintenance gate). WHATSAPP-STYLE FULL-SCREEN RINGING PAGE:
/// dark gradient, pulsing avatar ring, big caller name, Decline / Accept
/// circles — replacing the old small centered dialog.
///
/// BEHAVIOUR CONTRACT (unchanged):
/// - The 45s auto-dismiss timer + ringtone start/stop live in callProvider
///   (started by _handleIncomingCall, stopped by accept/reject/clear) — this
///   widget only renders state and calls the notifier.
/// - Call waiting: accepting while another call room is open ENDS the old
///   call first (VideoCallScreen.endActiveCall), then hands the audio
///   session to the new one.
/// - Accept → callProvider.acceptCall (emits call:accept + REST join) →
///   VideoCallScreen.showModal. Reject → callProvider.rejectCall (emits
///   call:reject).
/// - BIOMETRIC GATE: when the user is NOT authenticated (e.g. the app was
///   killed and reopened by a notification), accepting asks for the device
///   biometric/PIN, then attempts the server-backed biometric restore. If
///   the session still cannot be recovered, the call payload is parked in
///   SharedPreferences (kPendingIncomingCallPrefKey), the overlay dismisses
///   and the user is routed to /login — main.dart re-presents the ring right
///   after a successful login. A signed-in user NEVER sees a prompt.
class IncomingCallDialog extends ConsumerStatefulWidget {
  const IncomingCallDialog({super.key});

  @override
  ConsumerState<IncomingCallDialog> createState() =>
      _IncomingCallDialogState();
}

class _IncomingCallDialogState extends ConsumerState<IncomingCallDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _handlingAccept = false;

  @override
  void initState() {
    super.initState();
    // One repeated controller drives BOTH pulsing rings (scale + opacity).
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  bool get _isCallWaiting {
    final call = ref.read(callProvider).call;
    return VideoCallScreen.activeCallRoomId != null &&
        call != null &&
        VideoCallScreen.activeCallRoomId != call.id;
  }

  /// ACCEPT (with the biometric gate for signed-out users).
  Future<void> _handleAccept() async {
    if (_handlingAccept) return;
    _handlingAccept = true;
    final callState = ref.read(callProvider);
    final call = callState.call;
    if (call == null) {
      _handlingAccept = false;
      return;
    }
    final callNotifier = ref.read(callProvider.notifier);
    final callType = call.type == 'video' ? 'Video Call' : 'Audio Call';
    final callerName = callState.fromUserName ?? 'Unknown Caller';
    try {
      // Capture the ROOT navigator context BEFORE accepting: acceptCall
      // clears the ringing state, which unmounts this overlay — using
      // `context` afterwards silently skipped opening the call screen.
      final navContext = navigatorKey.currentContext;

      // ---- BIOMETRIC GATE (unauthenticated devices only) ----------------
      final token = await StorageService().getToken();
      if (!mounted) return; // call timed out / dismissed while checking
      if (token == null || token.isEmpty) {
        final biometric = await BiometricService.authenticate(
            'Authenticate to answer the call');
        if (!mounted) return;
        if (biometric.success) {
          // Best-effort server-backed restore (per-device biometric token).
          // The auth listener in main.dart also fires on success — but no
          // call is parked yet, so nothing double-rings.
          try {
            await ref.read(authProvider.notifier).loginWithBiometrics();
          } catch (_) {
            // Restore unreachable from here — fall through to the re-check.
          }
          if (!mounted) return;
        }
        final restored = await StorageService().getToken();
        if (restored == null || restored.isEmpty) {
          // Park the call: after the next login main.dart re-presents it
          // via callProvider.presentIncomingCall (same payload shape).
          try {
            await PushNotificationService.persistPendingIncomingCall(
              <String, dynamic>{
                'type': 'incoming_call',
                'callId': call.id,
                'callCode': call.callCode,
                'callerName': callerName,
                'callType': call.type,
                'isGroupCall': call.isGroupCall,
              },
            );
          } catch (_) {}
          callNotifier.clearIncomingCall();
          if (navContext != null && navContext.mounted) {
            GoRouter.of(navContext).go('/login');
          }
          return;
        }
      }
      // -------------------------------------------------------------------

      // CALL WAITING: if another call is already open, END it for everyone
      // first (its _leave emits call:leave + call:end and pops its screen),
      // then hand the audio session to the new call.
      final hadPreviousCall =
          VideoCallScreen.activeCallRoomId != null &&
              VideoCallScreen.activeCallRoomId != call.id;
      if (hadPreviousCall) {
        VideoCallScreen.endActiveCall();
        // Give the previous screen one frame to pop + dispose.
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      Map<String, dynamic>? calling;
      try {
        calling = await callNotifier.acceptCall(call);
      } catch (e) {
        debugPrint('Error accepting call: $e');
      }
      if (navContext == null || !navContext.mounted) return;
      try {
        await VideoCallScreen.showModal(
          context: navContext,
          roomId: call.id,
          title: hadPreviousCall
              ? '$callType with $callerName (previous call ended)'
              : '$callType with $callerName',
          isMeeting: false,
          enableVideo: call.type == 'video',
          isHost: false,
          isGroupCall: call.isGroupCall,
          onLeave: () async {
            try {
              await ApiService().leaveCall(call.id);
            } catch (e) {
              debugPrint('leaveCall failed (non-fatal): $e');
            }
          },
          calling: calling,
        );
      } catch (e) {
        debugPrint('Error opening call screen: $e');
      }
    } finally {
      _handlingAccept = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);

    if (!callState.isRinging || callState.call == null) {
      return const SizedBox.shrink();
    }

    final call = callState.call!;
    final isVideo = call.type == 'video';
    final callerName = callState.fromUserName ?? 'Unknown Caller';
    final waiting = _isCallWaiting;

    return Positioned.fill(
      child: Material(
        color: Colors.black,
        child: Container(
          // Full-bleed dark gradient — reads as a native call screen.
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0F172A),
                Color(0xFF111827),
                Color(0xFF020617),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  // Status caption
                  Text(
                    'Metricorex',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.4,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 26),
                  // Pulsing caller avatar
                  _PulsingAvatar(
                    controller: _pulseController,
                    name: callerName,
                    imageUrl: null,
                    icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  ),
                  const SizedBox(height: 28),
                  // Caller name
                  Text(
                    callerName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Incoming ${isVideo ? 'video' : 'audio'} call…',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  // Call-waiting notice (subtle)
                  if (waiting) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border:
                            Border.all(color: Colors.white.withValues(alpha: 0.16)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_calls_rounded,
                              size: 15, color: Colors.amber.shade300),
                          const SizedBox(width: 7),
                          Text(
                            'Your current call will end',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(flex: 4),
                  // Actions: Decline (red) + Accept (green)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CallActionCircle(
                          icon: Icons.call_end_rounded,
                          label: 'Decline',
                          color: const Color(0xFFEF4444),
                          onTap: () {
                            ref.read(callProvider.notifier).rejectCall(call);
                          },
                        ),
                        _CallActionCircle(
                          icon: Icons.call_rounded,
                          label: 'Accept',
                          color: const Color(0xFF22C55E),
                          onTap: _handleAccept,
                        ),
                      ],
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
}

/// Caller avatar wrapped in two expanding/fading pulse rings (one shared
/// AnimationController — dependency-free).
class _PulsingAvatar extends StatelessWidget {
  final AnimationController controller;
  final String name;
  final String? imageUrl;
  final IconData icon;

  const _PulsingAvatar({
    required this.controller,
    required this.name,
    required this.imageUrl,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          // Ring A runs the full cycle; Ring B runs it half a period behind.
          final t1 = controller.value;
          final t2 = (controller.value + 0.5) % 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              _pulseRing(t1, 220, 0.30),
              _pulseRing(t2, 190, 0.22),
              child!,
            ],
          );
        },
        child: Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipOval(
            child: Container(
              color: const Color(0xFF1E293B),
              child: (imageUrl != null && imageUrl!.isNotEmpty)
                  ? AvatarWithInitials(name: name, imageUrl: imageUrl, radius: 64)
                  : AvatarWithInitials(name: name, imageUrl: null, radius: 64),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pulseRing(double t, double size, double maxOpacity) {
    // 0 → fully tight/opaque, 1 → expanded/invisible (outgoing wave).
    final scale = 1.0 + t * 0.55;
    final opacity = (1.0 - t) * maxOpacity;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: opacity),
            width: 2.5,
          ),
        ),
      ),
    );
  }
}

/// 72dp circular action button with a label underneath (WhatsApp style).
class _CallActionCircle extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallActionCircle({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Center(
                child: Icon(icon, color: Colors.white, size: 32),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}
