import 'dart:async';

import 'package:flutter/foundation.dart';

import 'socket_service.dart';

/// One live-caption segment as relayed by the backend (`caption:updated`).
///
/// Provider-agnostic: captions ride the app's Socket.IO connection, so this
/// works identically regardless of which media provider backs the room.
class CaptionSegment {
  final String roomId;

  /// `'call'` or `'meeting'`.
  final String roomType;
  final String speakerId;
  final String speakerName;
  final String text;
  final bool isFinal;
  final String? language;
  final DateTime ts;

  const CaptionSegment({
    required this.roomId,
    required this.roomType,
    required this.speakerId,
    required this.speakerName,
    required this.text,
    required this.isFinal,
    required this.ts,
    this.language,
  });

  /// Defensive parse — never throws on partial/legacy payloads.
  factory CaptionSegment.fromMap(Map<String, dynamic> map) {
    return CaptionSegment(
      roomId: map['roomId']?.toString() ?? '',
      roomType: map['roomType']?.toString() ?? 'call',
      speakerId: map['speakerId']?.toString() ?? '',
      speakerName: (map['speakerName']?.toString() ?? '').trim().isEmpty
          ? 'Speaker'
          : map['speakerName'].toString(),
      text: map['text']?.toString() ?? '',
      isFinal: map['isFinal'] != false,
      language: map['language']?.toString(),
      ts: DateTime.tryParse(map['ts']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// A segment plus the stable identity of the utterance it belongs to.
///
/// Interim (non-final) updates of the same utterance keep the same [key], so
/// the overlay updates the text in place instead of re-animating a new row.
class CaptionsEntry {
  final String key;
  final CaptionSegment segment;

  const CaptionsEntry({required this.key, required this.segment});
}

/// Keeps the most recent caption segments for the room currently joined and
/// prunes them automatically ~6s after they arrive (the overlay "fades" them
/// by scaling opacity down over the last quarter of that window).
///
/// Attach exactly one controller per call/meeting screen instance — it chains
/// the socket callback slot the same way every other room-scoped handler in
/// the app does (save previous → restore on detach).
class CaptionsController extends ChangeNotifier {
  CaptionsController({
    this.maxSegments = 3,
    this.fadeAfter = const Duration(seconds: 6),
  });

  /// Last N segments kept visible (newest last).
  final int maxSegments;

  /// How long a segment stays on screen before it auto-fades away.
  final Duration fadeAfter;

  final List<CaptionsEntry> _entries = [];
  final Map<String, String> _openUtterances = {}; // speakerId → utterance key
  // Meeting rooms can deliver `caption:updated` TWICE per segment (the relay
  // targets both room:{id} and meeting:{id}, and a meeting socket sits in
  // both). Track recently-closed finals so a duplicate final is dropped
  // instead of appended as a second row.
  final Map<String, DateTime> _recentFinals = {};
  int _utteranceCounter = 0;
  Timer? _pruneTimer;
  String? _roomId;
  SocketService? _socket;
  void Function(dynamic)? _previousHandler;

  bool get hasSegments => _entries.isNotEmpty;

  /// Newest last — the overlay renders top-down in arrival order.
  List<CaptionsEntry> get entries => List.unmodifiable(_entries);

  /// Start listening to `caption:updated` for [roomId] only.
  void attach(SocketService socket, {required String roomId}) {
    detach();
    _socket = socket;
    _roomId = roomId;
    _previousHandler = socket.onCaptionUpdated;
    socket.onCaptionUpdated = _handleCaption;
    // Sub-second tick keeps the fade-out smooth.
    _pruneTimer = Timer.periodic(const Duration(milliseconds: 400), (_) => _prune());
  }

  /// Restore the previous socket handler and clear state (idempotent).
  void detach() {
    final socket = _socket;
    if (socket != null && socket.onCaptionUpdated == _handleCaption) {
      socket.onCaptionUpdated = _previousHandler;
    }
    _previousHandler = null;
    _socket = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    if (_entries.isNotEmpty || _openUtterances.isNotEmpty) {
      _entries.clear();
      _openUtterances.clear();
      notifyListeners();
    }
  }

  String _nextKey() => 'cap-${_utteranceCounter++}';

  /// True when an identical final from this speaker was closed very recently
  /// (relay double-delivery echo). Window is short — 3s — so genuine repeats
  /// of the same words still render.
  bool _isDuplicateFinal(CaptionSegment segment) {
    final key = '${segment.speakerId}|${segment.text}';
    final seen = _recentFinals[key];
    if (seen != null && DateTime.now().difference(seen).inMilliseconds < 3000) {
      return true;
    }
    _recentFinals[key] = DateTime.now();
    if (_recentFinals.length > 64) {
      _recentFinals.removeWhere(
        (_, ts) => DateTime.now().difference(ts).inMilliseconds >= 3000,
      );
    }
    return false;
  }

  void _handleCaption(dynamic data) {
    // Preserve whatever handler was installed before us (global pattern).
    _previousHandler?.call(data);
    if (data is! Map) return;
    if (_roomId == null) return;

    final segment = CaptionSegment.fromMap(Map<String, dynamic>.from(data));
    // Only captions for the room we are currently joined to.
    if (segment.roomId != _roomId || segment.text.trim().isEmpty) return;

    final openKey = _openUtterances[segment.speakerId];
    if (segment.isFinal) {
      // Drop relay double-delivery echoes (same speaker + text within 3s).
      if (_isDuplicateFinal(segment)) {
        _openUtterances.remove(segment.speakerId);
        return;
      }
      // A final segment completes the open utterance (if any) — replace it in
      // place under the same key, then close the utterance.
      _openUtterances.remove(segment.speakerId);
      if (openKey != null) {
        _replaceEntry(openKey, segment);
        return;
      }
      _addEntry(segment);
      return;
    }

    // Interim update for an utterance already on screen → update in place.
    if (openKey != null && _replaceEntry(openKey, segment)) return;
    // New utterance from this speaker.
    final key = _nextKey();
    _openUtterances[segment.speakerId] = key;
    _addEntry(segment, key: key);
  }

  bool _replaceEntry(String key, CaptionSegment segment) {
    final index = _entries.indexWhere((entry) => entry.key == key);
    if (index == -1) return false;
    _entries[index] = CaptionsEntry(key: key, segment: segment);
    notifyListeners();
    return true;
  }

  void _addEntry(CaptionSegment segment, {String? key}) {
    _entries.add(CaptionsEntry(key: key ?? _nextKey(), segment: segment));
    while (_entries.length > maxSegments) {
      _dropEntryAt(0);
    }
    notifyListeners();
  }

  void _dropEntryAt(int index) {
    final key = _entries[index].key;
    _entries.removeAt(index);
    _openUtterances.removeWhere((_, value) => value == key);
  }

  void _prune() {
    if (_entries.isEmpty) return;
    final now = DateTime.now();
    final before = _entries.length;
    _entries.removeWhere((entry) => now.difference(entry.segment.ts) >= fadeAfter);
    if (_entries.length != before) {
      _openUtterances.removeWhere(
        (speakerId, key) => !_entries.any((entry) => entry.key == key),
      );
      notifyListeners();
    }
  }

  /// 1.0 while fresh, easing to 0.0 across the final quarter of [fadeAfter].
  double opacityFor(CaptionSegment segment) {
    // Duration defines no `/` operator — compute the fade window in ms.
    final fadeStartMs = (fadeAfter.inMilliseconds * 0.75).round();
    final ageMs = DateTime.now().difference(segment.ts).inMilliseconds;
    if (ageMs <= fadeStartMs) return 1.0;
    final t = (ageMs - fadeStartMs) / (fadeAfter.inMilliseconds - fadeStartMs);
    return 1.0 - t.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
