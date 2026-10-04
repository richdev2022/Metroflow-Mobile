/// AI meeting notes — backend contract:
/// - `GET /meetings/{id}/notes` → `{ success, data: { meetingId, notes } }`
/// - `POST /meetings/{id}/notes/generate` (409 + `no_transcript` when the
///   meeting has no usable transcript yet)
/// - socket `meeting:notes_updated` → `{ meetingId, notes }`
///
/// The API has shipped both key styles over time (DB column aliases are
/// camelCase, the socket payload uses the model shape), so the parser accepts
/// camelCase AND snake_case keys defensively and never throws on partial data.
class MeetingNotesData {
  final String summary;
  final List<String> keyPoints;
  final List<String> decisions;
  final List<MeetingActionItem> actionItems;
  final List<MeetingTimestamp> importantTimestamps;
  final String? model;
  final DateTime? generatedAt;

  const MeetingNotesData({
    required this.summary,
    required this.keyPoints,
    required this.decisions,
    required this.actionItems,
    required this.importantTimestamps,
    this.model,
    this.generatedAt,
  });

  /// True when the payload carries nothing worth rendering.
  bool get isEmpty =>
      summary.trim().isEmpty &&
      keyPoints.isEmpty &&
      decisions.isEmpty &&
      actionItems.isEmpty &&
      importantTimestamps.isEmpty;

  /// Defensive parse — never throws on partial/legacy payloads.
  factory MeetingNotesData.fromJson(Map<String, dynamic> map) {
    String? model;
    DateTime? generatedAt;
    final actionItems = <MeetingActionItem>[];
    final timestamps = <MeetingTimestamp>[];

    final rawActions = _pick(map, 'actionItems', 'action_items');
    if (rawActions is List) {
      for (final item in rawActions) {
        if (item is! Map) continue;
        actionItems.add(MeetingActionItem.fromJson(
          Map<String, dynamic>.from(item),
        ));
      }
    }

    final rawTimestamps = _pick(map, 'importantTimestamps', 'important_timestamps');
    if (rawTimestamps is List) {
      for (final item in rawTimestamps) {
        if (item is! Map) continue;
        timestamps.add(MeetingTimestamp.fromJson(
          Map<String, dynamic>.from(item),
        ));
      }
    }

    final modelRaw = _pick(map, 'model', 'model_name');
    if (modelRaw != null) model = modelRaw.toString();
    final generatedRaw = _pick(map, 'generatedAt', 'generated_at');
    if (generatedRaw != null) generatedAt = DateTime.tryParse(generatedRaw.toString());

    return MeetingNotesData(
      summary: _pick(map, 'summary', 'summary_text')?.toString() ?? '',
      keyPoints: _stringList(_pick(map, 'keyPoints', 'key_points')),
      decisions: _stringList(_pick(map, 'decisions', 'decisions')),
      actionItems: actionItems,
      importantTimestamps: timestamps,
      model: model,
      generatedAt: generatedAt,
    );
  }

  static dynamic _pick(Map<String, dynamic> map, String camel, String snake) {
    final value = map[camel] ?? map[snake];
    return value;
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Object>()
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}

/// One action item of the AI meeting notes.
class MeetingActionItem {
  final String title;
  final String? description;
  final String? assignedTo;
  final String? dueDate;

  /// `'open' | 'in_progress' | 'done'` (anything else renders as 'open').
  final String status;

  const MeetingActionItem({
    required this.title,
    required this.status,
    this.description,
    this.assignedTo,
    this.dueDate,
  });

  bool get isDone => status == 'done';
  bool get isInProgress => status == 'in_progress';

  String get statusLabel {
    if (isDone) return 'Done';
    if (isInProgress) return 'In progress';
    return 'Open';
  }

  factory MeetingActionItem.fromJson(Map<String, dynamic> map) {
    String? text(String camel, String snake) {
      final value = map[camel] ?? map[snake];
      if (value == null) return null;
      final s = value.toString().trim();
      return s.isEmpty ? null : s;
    }

    return MeetingActionItem(
      title: text('title', 'title') ?? 'Action item',
      description: text('description', 'description'),
      assignedTo: text('assignedTo', 'assigned_to'),
      dueDate: text('dueDate', 'due_date'),
      status: (text('status', 'status') ?? 'open').toLowerCase(),
    );
  }
}

/// One important moment of the meeting referenced from the transcript.
class MeetingTimestamp {
  final String ts;
  final String description;

  const MeetingTimestamp({required this.ts, required this.description});

  factory MeetingTimestamp.fromJson(Map<String, dynamic> map) {
    String? text(String camel, String snake) {
      final value = map[camel] ?? map[snake];
      if (value == null) return null;
      final s = value.toString().trim();
      return s.isEmpty ? null : s;
    }

    return MeetingTimestamp(
      ts: text('ts', 'ts') ?? '',
      description: text('description', 'description') ?? '',
    );
  }
}
