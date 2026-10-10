import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/recording.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/chat_attachment_views.dart';

/// The "Recordings" entrance tab on the Meetings screen — web parity for
/// app.metricorex.com/recordings. Lists the caller's meeting/call recordings
/// (playable in-app via [showRecordingPlayerSheet], download fallback inside
/// the player).
class RecordingsPane extends StatefulWidget {
  const RecordingsPane({super.key});

  @override
  State<RecordingsPane> createState() => _RecordingsPaneState();
}

class _RecordingsPaneState extends State<RecordingsPane> {
  List<Recording>? _recordings;
  bool _loading = true;
  String? _error;

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
      final response = await ApiService().getRecordings(page: 1, limit: 50);
      final data = response.data is Map ? response.data['data'] : null;
      final rows = data is Map && data['recordings'] is List
          ? data['recordings'] as List
          : const <dynamic>[];
      if (!mounted) return;
      setState(() {
        _recordings = rows
            .whereType<Map>()
            .map((r) {
              try {
                return Recording.fromJson(Map<String, dynamic>.from(r));
              } catch (_) {
                return null;
              }
            })
            .whereType<Recording>()
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.extractErrorMessage(e);
        _loading = false;
      });
    }
  }

  static String _fmtDuration(int seconds) {
    if (seconds <= 0) return '—';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  static String _fmtSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  static String _fmtDate(DateTime dt) {
    final local = dt.toLocal();
    return DateFormat('MMM d, yyyy · h:mm a').format(local);
  }

  bool _isVideo(Recording r) {
    final url = r.storageUrl.toLowerCase();
    return url.contains('.mp4') || url.contains('.webm') || url.contains('.mov');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colors.primary),
            const SizedBox(height: 12),
            Text('Loading recordings…',
                style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 48),
          Icon(Icons.cloud_off_rounded, size: 40, color: colors.textSecondary),
          const SizedBox(height: 10),
          Text("Couldn't load recordings",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: colors.text)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary)),
          ),
          const SizedBox(height: 14),
          Center(
            child: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    final recordings = _recordings ?? const <Recording>[];
    if (recordings.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.videocam_off_outlined,
                      size: 40, color: colors.primary),
                ),
                const SizedBox(height: 16),
                Text('No recordings yet',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: colors.text)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Start a meeting or call and tap Record — finished recordings appear here for 24-hour replay.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.5, color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: colors.primary,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
        itemCount: recordings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final r = recordings[index];
          final processing = r.status == 'processing' || r.status == 'pending';
          final failed = r.status == 'failed';
          final playable = !processing && !failed && r.storageUrl.isNotEmpty;
          return Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (failed ? colors.error : colors.primary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : processing
                          ? Icons.hourglass_top_rounded
                          : (_isVideo(r)
                              ? Icons.videocam_rounded
                              : Icons.mic_rounded),
                  size: 20,
                  color: failed ? colors.error : colors.primary,
                ),
              ),
              title: Text(
                r.recordedByName.isNotEmpty
                    ? '${r.recordedByName}${r.meetingId != null ? " · Meeting" : " · Call"}'
                    : (r.meetingId != null ? 'Meeting recording' : 'Call recording'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: colors.text),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    _fmtDate(r.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (processing)
                        _chip('Processing…', colors.warning, colors),
                      if (failed) _chip('Failed', colors.error, colors),
                      if (!processing && !failed) ...[
                        _chip(_fmtDuration(r.duration), colors.primary, colors),
                        if (_fmtSize(r.size).isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _chip(_fmtSize(r.size), colors.textSecondary, colors),
                        ],
                      ],
                    ],
                  ),
                ],
              ),
              trailing: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: playable ? colors.primary : colors.surfaceVariant,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color: playable ? Colors.white : colors.textSecondary,
                ),
              ),
              onTap: () {
                if (processing) {
                  AppToast.show('Recording is still processing — check back shortly');
                  return;
                }
                if (failed) {
                  AppToast.show('This recording failed to render', type: AppToastType.error);
                  return;
                }
                showRecordingPlayerSheet(
                  context,
                  url: ApiService.resolveMediaUrl(r.storageUrl) ?? r.storageUrl,
                  fileName:
                      'recording-${DateFormat('yyyyMMdd-HHmm').format(r.createdAt.toLocal())}.${_isVideo(r) ? 'mp4' : 'm4a'}',
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String label, Color color, ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
