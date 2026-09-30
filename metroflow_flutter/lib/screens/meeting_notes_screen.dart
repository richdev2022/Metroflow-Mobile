import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/meeting_notes.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import '../widgets/modern_ui.dart';

/// AI meeting notes for one meeting: summary, key points, decisions, action
/// items and important timestamps (backend: GET/POST /meetings/{id}/notes*).
///
/// - Pull-to-refresh + loading skeletons
/// - Empty state with a "Generate now" action (409 `no_transcript` handled
///   with a friendly message)
/// - Refreshes live while open when the backend pushes
///   `meeting:notes_updated` for this meeting
class MeetingNotesScreen extends StatefulWidget {
  final String meetingId;
  final String meetingTitle;

  const MeetingNotesScreen({
    super.key,
    required this.meetingId,
    required this.meetingTitle,
  });

  @override
  State<MeetingNotesScreen> createState() => _MeetingNotesScreenState();
}

class _MeetingNotesScreenState extends State<MeetingNotesScreen> {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();

  MeetingNotesData? _notes;
  bool _isLoading = true;
  bool _isGenerating = false;
  String? _loadError;
  void Function(dynamic)? _previousNotesHandler;

  @override
  void initState() {
    super.initState();
    _loadNotes();
    // Live updates while the view is open (meeting ended → notes generated).
    _previousNotesHandler = _socket.onMeetingNotesUpdated;
    _socket.onMeetingNotesUpdated = _handleNotesUpdated;
  }

  @override
  void dispose() {
    if (_socket.onMeetingNotesUpdated == _handleNotesUpdated) {
      _socket.onMeetingNotesUpdated = _previousNotesHandler;
    }
    super.dispose();
  }

  void _handleNotesUpdated(dynamic data) {
    _previousNotesHandler?.call(data);
    if (!mounted || data is! Map) return;
    final payload = Map<String, dynamic>.from(data);
    if (payload['meetingId']?.toString() != widget.meetingId) return;
    final raw = payload['notes'];
    if (raw is! Map) return;
    setState(() {
      _notes = MeetingNotesData.fromJson(Map<String, dynamic>.from(raw));
      _loadError = null;
    });
  }

  Future<void> _loadNotes({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final response = await _api.getMeetingNotes(widget.meetingId);
      if (response.data['success'] != true) {
        throw StateError(ApiService.extractResponseMessage(response.data) ?? 'Unable to load notes');
      }
      final data = response.data['data'];
      final raw = data is Map ? data['notes'] : null;
      if (!mounted) return;
      setState(() {
        _notes = raw is Map
            ? MeetingNotesData.fromJson(Map<String, dynamic>.from(raw))
            : null;
        _loadError = null;
      });
    } catch (e) {
      Logger.error('Error loading meeting notes: $e');
      if (!mounted) return;
      setState(() => _loadError = ApiService.extractErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateNotes() async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);
    try {
      final response = await _api.generateMeetingNotes(widget.meetingId);
      if (response.data['success'] == true) {
        final data = response.data['data'];
        final raw = data is Map ? data['notes'] : null;
        if (!mounted) return;
        setState(() {
          if (raw is Map) {
            _notes = MeetingNotesData.fromJson(Map<String, dynamic>.from(raw));
          }
          _loadError = null;
        });
      }
    } on DioException catch (e) {
      Logger.error('Error generating meeting notes: $e');
      if (!mounted) return;
      final data = e.response?.data;
      final errorCode = data is Map ? data['errorCode']?.toString() : null;
      if (e.response?.statusCode == 409 || errorCode == 'no_transcript') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'Not enough transcript yet — captions recorded during the meeting are needed to generate notes.',
          ),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    } catch (e) {
      Logger.error('Error generating meeting notes: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.extractErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.text),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meeting notes',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colors.text,
              ),
            ),
            Text(
              widget.meetingTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          if (_notes != null && !_notes!.isEmpty)
            IconButton(
              tooltip: 'Regenerate notes',
              icon: Icon(Icons.refresh_rounded, color: colors.textSecondary),
              onPressed: _isGenerating ? null : _generateNotes,
            ),
        ],
      ),
      body: _isLoading
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: const [
                SkeletonCard(height: 140),
                SkeletonCard(height: 140),
                SkeletonCard(height: 180),
                SkeletonCard(height: 140),
              ],
            )
          : RefreshIndicator(
              color: colors.primary,
              onRefresh: () => _loadNotes(showSpinner: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
                children: [
                  if (_loadError != null && _notes == null)
                    _buildErrorState(colors)
                  else if (_notes == null || _notes!.isEmpty)
                    _buildEmptyState(colors)
                  else
                    ..._buildNotesSections(colors, _notes!),
                ],
              ),
            ),
    );
  }

  // -------------------------------------------------------------------------
  // States
  // -------------------------------------------------------------------------

  Widget _buildErrorState(ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load notes',
        subtitle: _loadError,
        actionLabel: 'Try again',
        onAction: () => _loadNotes(),
        tint: colors.error,
      ),
    );
  }

  Widget _buildEmptyState(ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          EmptyState(
            icon: Icons.edit_note_rounded,
            title: 'No notes yet',
            subtitle:
                'Notes will be generated automatically after the meeting ends. You can also generate them now from the live-caption transcript.',
            tint: colors.primary,
          ),
          const SizedBox(height: 8),
          if (_isGenerating) ...[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 10),
            Text(
              'Generating notes…',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ] else
            ElevatedButton.icon(
              onPressed: _generateNotes,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text(
                'Generate now',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Notes content
  // -------------------------------------------------------------------------

  List<Widget> _buildNotesSections(ThemeColors colors, MeetingNotesData notes) {
    return [
      if (notes.summary.trim().isNotEmpty)
        _sectionCard(
          colors: colors,
          icon: Icons.auto_awesome_rounded,
          tint: colors.primary,
          title: 'Summary',
          child: Text(
            notes.summary,
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: colors.text,
            ),
          ),
        ),
      if (notes.keyPoints.isNotEmpty)
        _sectionCard(
          colors: colors,
          icon: Icons.format_list_bulleted_rounded,
          tint: colors.primary,
          title: 'Key points',
          child: Column(
            children: [
              for (final point in notes.keyPoints)
                _bulletRow(
                  colors: colors,
                  icon: Icons.circle,
                  iconSize: 6,
                  iconColor: colors.primary,
                  text: point,
                ),
            ],
          ),
        ),
      if (notes.decisions.isNotEmpty)
        _sectionCard(
          colors: colors,
          icon: Icons.gavel_rounded,
          tint: colors.success,
          title: 'Decisions',
          child: Column(
            children: [
              for (final decision in notes.decisions)
                _bulletRow(
                  colors: colors,
                  icon: Icons.check_circle_outline_rounded,
                  iconSize: 15,
                  iconColor: colors.success,
                  text: decision,
                ),
            ],
          ),
        ),
      if (notes.actionItems.isNotEmpty)
        _sectionCard(
          colors: colors,
          icon: Icons.fact_check_outlined,
          tint: colors.warning,
          title: 'Action items',
          child: Column(
            children: [
              for (final item in notes.actionItems)
                _actionItemTile(colors, item),
            ],
          ),
        ),
      if (notes.importantTimestamps.isNotEmpty)
        _sectionCard(
          colors: colors,
          icon: Icons.schedule_rounded,
          tint: AppColors.primaryLight,
          title: 'Important moments',
          child: Column(
            children: [
              for (final moment in notes.importantTimestamps)
                _bulletRow(
                  colors: colors,
                  icon: Icons.schedule_rounded,
                  iconSize: 14,
                  iconColor: AppColors.primaryLight,
                  text: moment.description.isEmpty
                      ? moment.ts
                      : (moment.ts.isEmpty
                          ? moment.description
                          : '${moment.ts} — ${moment.description}'),
                ),
            ],
          ),
        ),
      if (notes.generatedAt != null || (notes.model ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _footerText(notes),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: colors.textSecondary,
            ),
          ),
        ),
    ];
  }

  String _footerText(MeetingNotesData notes) {
    final parts = <String>['Generated by Metricorex AI'];
    if (notes.generatedAt != null) {
      parts.add(DateFormat('d MMM yyyy · HH:mm').format(notes.generatedAt!));
    }
    final model = notes.model ?? '';
    if (model.isNotEmpty) parts.add(model);
    return parts.join(' · ');
  }

  Widget _sectionCard({
    required ThemeColors colors,
    required IconData icon,
    required Color tint,
    required String title,
    required Widget child,
  }) {
    return ModernCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _bulletRow({
    required ThemeColors colors,
    required IconData icon,
    required double iconSize,
    required Color iconColor,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: iconSize <= 8
                ? Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: iconColor,
                      shape: BoxShape.circle,
                    ),
                  )
                : Icon(icon, size: iconSize, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionItemTile(ThemeColors colors, MeetingActionItem item) {
    final statusColor = item.isDone
        ? colors.success
        : item.isInProgress
            ? colors.primary
            : colors.warning;
    final dueDate = _formatDueDate(item.dueDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                    decoration: item.isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ModernBadge(
                label: item.statusLabel,
                color: statusColor,
                icon: item.isDone
                    ? Icons.check_rounded
                    : item.isInProgress
                        ? Icons.timelapse_rounded
                        : Icons.radio_button_unchecked,
              ),
            ],
          ),
          if (item.description != null && item.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.description!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: colors.textSecondary,
              ),
            ),
          ],
          if ((item.assignedTo != null && item.assignedTo!.isNotEmpty) ||
              (dueDate != null && dueDate.isNotEmpty)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (item.assignedTo != null && item.assignedTo!.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline_rounded,
                          size: 13, color: colors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        item.assignedTo!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                if (dueDate != null && dueDate.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_outlined,
                          size: 13, color: colors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        dueDate,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String? _formatDueDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return DateFormat('d MMM yyyy').format(parsed);
    }
    return raw;
  }
}
