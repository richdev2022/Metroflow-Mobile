import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/meeting.dart';
import '../providers/auth_provider.dart';
import '../services/api.dart';
import '../utils/logger.dart';
import '../theme/app_theme.dart';
import 'video_call_screen.dart';

/// Deep-link landing for `metricorex://meetings/<code>` (and future host
/// paths): validates the meeting code, shows what/when, and joins straight
/// into the call room — the in-app counterpart of the web meeting-link
/// interstitial.
class MeetingDeepLinkScreen extends ConsumerStatefulWidget {
  final String meetingCode;
  const MeetingDeepLinkScreen({super.key, required this.meetingCode});

  static Future<void> open(BuildContext context, String code) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => MeetingDeepLinkScreen(meetingCode: code)),
    );
  }

  @override
  ConsumerState<MeetingDeepLinkScreen> createState() => _MeetingDeepLinkScreenState();
}

class _MeetingDeepLinkScreenState extends ConsumerState<MeetingDeepLinkScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _joining = false;
  String? _error;
  Meeting? _meeting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.getMeetingByCode(widget.meetingCode);
      if (response.data['success'] == true && response.data['data'] is Map) {
        if (!mounted) return;
        setState(() {
          _meeting = Meeting.fromJson(Map<String, dynamic>.from(response.data['data']));
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'Meeting not found. Ask the host to share the link again.';
          _loading = false;
        });
      }
    } catch (e) {
      Logger.error('Meeting deep link lookup failed: $e');
      if (!mounted) return;
      setState(() {
        _error = ApiService.extractErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _join() async {
    final meeting = _meeting;
    if (meeting == null || _joining) return;
    setState(() => _joining = true);
    try {
      final response = await _api.joinMeeting(meeting.id);
      if (response.data['success'] == true && mounted) {
        final userName = await StorageService().getUserName();
        final joinData = response.data['data'];
        final callingRaw = joinData is Map ? joinData['calling'] : null;
        await VideoCallScreen.showModal(
          context: context,
          roomId: meeting.id,
          title: meeting.title,
          isMeeting: true,
          userName: userName,
          calling: callingRaw is Map ? Map<String, dynamic>.from(callingRaw) : null,
        );
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      Logger.error('Error joining meeting from deep link: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final authState = ref.read(authProvider);
    final signedIn = (authState.token ?? '').isNotEmpty;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Meeting Link'),
      ),
      body: SafeArea(
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_off_rounded, size: 48, color: colors.textSecondary),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: signedIn ? _load : () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(signedIn ? 'Retry' : 'Go back'),
                          ),
                          if (!signedIn) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Sign in to the Metroflow app first, then tap the link again.',
                              style: TextStyle(fontSize: 12, color: colors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: colors.primaryBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: colors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _meeting?.title.isNotEmpty == true
                                      ? _meeting!.title
                                      : 'Metroflow Meeting',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: colors.text,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Code: ${widget.meetingCode}',
                                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                                ),
                                if ((_meeting?.description ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _meeting!.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _joining ? null : _join,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: _joining
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.videocam_rounded),
                            label: Text(_joining ? 'Joining…' : 'Join meeting'),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}
