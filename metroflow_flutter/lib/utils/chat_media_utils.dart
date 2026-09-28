import 'dart:convert';

import 'package:flutter/material.dart';

/// Shared helpers for WhatsApp-style chat attachments: media-kind detection,
/// human file sizes, solo-emoji detection (big-emoji rendering), document
/// icon/color mapping and call-log message parsing.

/// Guess the attachment kind from a MIME type / file extension. Tolerates the
/// backend's batch-3 kinds (`image`, `video`, `audio`, `document`, `gif`)
/// AND legacy raw MIME types (`image/png`, `video/mp4`, ...).
String guessMediaKind(String? attachmentType, [String? filename]) {
  final kind = (attachmentType ?? '').trim().toLowerCase();
  switch (kind) {
    case 'image':
    case 'video':
    case 'audio':
    case 'document':
    case 'gif':
    case 'sticker':
    case 'voice':
      return kind;
  }
  final mime = kind;
  final ext = _extensionOf(filename);
  bool mimeStarts(String prefix) => mime.startsWith(prefix);
  if (mimeStarts('image/')) return ext == 'gif' ? 'gif' : 'image';
  if (mimeStarts('video/')) return 'video';
  if (mimeStarts('audio/')) return 'audio';
  switch (ext) {
    case 'gif':
      return 'gif';
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'webp':
    case 'heic':
    case 'bmp':
      return 'image';
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
    case 'webm':
    case '3gp':
      return 'video';
    case 'mp3':
    case 'm4a':
    case 'aac':
    case 'wav':
    case 'ogg':
    case 'opus':
      return 'audio';
    default:
      return 'document';
  }
}

String _extensionOf(String? filename) {
  if (filename == null) return '';
  final clean = filename.split('?').first.split('#').first;
  final dot = clean.lastIndexOf('.');
  if (dot == -1 || dot == clean.length - 1) return '';
  return clean.substring(dot + 1).toLowerCase();
}

/// 1234567 -> "1.2 MB"; <1024 -> "B"; larger units as needed.
String formatFileSize(num? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text} ${units[unit]}';
}

/// Friendly display name for an attachment: prefer attachmentName, then the
/// URL's last path segment, then a generic label.
String attachmentDisplayName(String? name, String? url) {
  if (name != null && name.trim().isNotEmpty) return name.trim();
  if (url != null && url.isNotEmpty) {
    try {
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      final decoded = Uri.decodeComponent(last);
      if (decoded.isNotEmpty) return decoded;
    } catch (_) {}
    return 'Attachment';
  }
  return 'Attachment';
}

// -------------------------------------------------------------------------
// Big-emoji detection (1-3 emoji-only messages render without a bubble).
// -------------------------------------------------------------------------

/// Any remaining rune must be: an Extended_Pictographic, a variation
/// selector, a zero-width joiner, a skin-tone modifier, a regional indicator
/// (flags) or an enclosing keycap — or horizontal whitespace.
final RegExp _emojiOnlyRe = RegExp(
  r'^(?:\s|[\p{Extended_Pictographic}\u{FE0F}\u{FE0E}\u{200D}\u{1F3FB}-\u{1F3FF}\u{1F1E6}-\u{1F1FF}\u{20E3}])+$',
  unicode: true,
);
final RegExp _pictographicRe = RegExp(r'\p{Extended_Pictographic}', unicode: true);
final RegExp _regionalIndicatorRe = RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true);

/// True when [text] consists ONLY of 1-3 emoji clusters (pictographics,
/// ZWJ sequences, flags). Deliberately rejects plain digits/"123": the
/// keycap base characters (0-9#*) are NOT Extended_Pictographic and are
/// rejected outright, so "1️⃣" is not treated as a giant emoji either.
bool isSoloEmojiMessage(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.length > 48) return false;
  if (!_emojiOnlyRe.hasMatch(trimmed)) return false;
  final pictographic = _pictographicRe.allMatches(trimmed).length;
  final indicators = _regionalIndicatorRe.allMatches(trimmed).length;
  // Regional indicator pairs form flags; each pair counts as one cluster.
  final clusters = pictographic + (indicators ~/ 2);
  return clusters >= 1 && clusters <= 3;
}

// -------------------------------------------------------------------------
// Document tile metadata (extension -> icon + color).
// -------------------------------------------------------------------------

class DocumentIconMeta {
  final IconData icon;
  final Color color;

  const DocumentIconMeta(this.icon, this.color);
}

DocumentIconMeta documentIconMeta(String? filename) {
  final ext = _extensionOf(filename);
  switch (ext) {
    case 'pdf':
      return const DocumentIconMeta(Icons.picture_as_pdf_rounded, Color(0xFFEF4444));
    case 'doc':
    case 'docx':
    case 'rtf':
    case 'odt':
      return const DocumentIconMeta(Icons.description_rounded, Color(0xFF2563EB));
    case 'xls':
    case 'xlsx':
    case 'csv':
    case 'ods':
      return const DocumentIconMeta(Icons.table_chart_rounded, Color(0xFF10B981));
    case 'ppt':
    case 'pptx':
    case 'odp':
      return const DocumentIconMeta(Icons.slideshow_rounded, Color(0xFFF97316));
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return const DocumentIconMeta(Icons.folder_zip_rounded, Color(0xFFD97706));
    case 'txt':
    case 'md':
      return const DocumentIconMeta(Icons.article_rounded, Color(0xFF64748B));
    default:
      return const DocumentIconMeta(Icons.insert_drive_file_rounded, Color(0xFF64748B));
  }
}

// -------------------------------------------------------------------------
// Call-log messages (messageType == 'call-log').
// -------------------------------------------------------------------------

class ChatCallLogMeta {
  final String callType; // 'audio' | 'video'
  final String status; // 'completed' | 'missed' | 'cancelled'
  final int? durationSeconds;
  final String? initiatorName;
  final String? callCode;

  const ChatCallLogMeta({
    this.callType = 'audio',
    this.status = 'completed',
    this.durationSeconds,
    this.initiatorName,
    this.callCode,
  });

  /// Defensive parse: content is a JSON string produced by the backend's
  /// postCallLogMessage(). Garbage in -> null (caller renders a fallback).
  static ChatCallLogMeta? tryParse(String? content) {
    if (content == null || content.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) return null;
      return ChatCallLogMeta(
        callType: decoded['callType'] == 'video' ? 'video' : 'audio',
        status: (decoded['status'] ?? 'completed').toString(),
        durationSeconds: decoded['durationSeconds'] is num
            ? (decoded['durationSeconds'] as num).toInt()
            : int.tryParse('${decoded['durationSeconds']}'),
        initiatorName: decoded['initiatorName']?.toString(),
        callCode: decoded['callCode']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// 754 -> "12:34".
String formatCallDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '00:00';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
