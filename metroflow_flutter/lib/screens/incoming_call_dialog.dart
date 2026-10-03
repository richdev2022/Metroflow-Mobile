import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/call_provider.dart';
import '../theme/app_theme.dart';
import 'video_call_screen.dart';
import '../services/api.dart';

class IncomingCallDialog extends ConsumerWidget {
  const IncomingCallDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callProvider);
    final callNotifier = ref.read(callProvider.notifier);

    if (!callState.isRinging || callState.call == null) {
      return const SizedBox.shrink();
    }

    final call = callState.call!;
    final callType = call.type == 'video' ? 'Video Call' : 'Audio Call';
    final callerName = callState.fromUserName ?? 'Unknown Caller';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          // Theme-aware (was hardcoded white with grey labels — unreadable
          // pairs depending on mode).
          color: AppTheme.colors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Caller info
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).primaryColor,
              ),
              child: Icon(
                call.type == 'video' ? Icons.videocam : Icons.call,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              callerName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.colors.text,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              callType,
              style: TextStyle(
                fontSize: 18,
                color: AppTheme.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 30),

            // Calling indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Calling',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < 3; i++)
                        _CallingDot(delay: i * 200),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline button
                Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.call_end, color: Colors.white, size: 35),
                    onPressed: () {
                      callNotifier.rejectCall(call);
                    },
                  ),
                ),

                // Accept button
                Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.call, color: Colors.white, size: 35),
                    onPressed: () async {
                      // Capture the ROOT navigator context BEFORE accepting:
                      // acceptCall clears the ringing state, which unmounts
                      // this overlay dialog — using `context` afterwards
                      // silently skipped opening the call screen.
                      final navContext = navigatorKey.currentContext;
                      // CALL WAITING: if another call is already open, END it
                      // for everyone first (its _leave emits call:leave +
                      // call:end and pops its screen), then hand the audio
                      // session to the new call.
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
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CallingDot extends StatefulWidget {
  final int delay;

  const _CallingDot({required this.delay});

  @override
  State<_CallingDot> createState() => _CallingDotState();
}

class _CallingDotState extends State<_CallingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    // Start animation with delay
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.grey,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
