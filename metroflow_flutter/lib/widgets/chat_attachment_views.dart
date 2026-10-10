import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../models/message.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/chat_media_utils.dart';
import '../utils/app_toast.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../utils/logger.dart';

// =============================================================================
// Shared download helper
// =============================================================================

/// Downloads a chat attachment into the app documents /downloads folder with
/// progress reporting, then returns the saved file path. Throws on failure —
/// callers surface SnackBars.
Future<String> downloadAttachment(
  BuildContext context, {
  required String url,
  required String fileName,
  void Function(double progress)? onProgress,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final downloads = Directory('${dir.path}/downloads');
  if (!await downloads.exists()) {
    await downloads.create(recursive: true);
  }
  final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final savePath = '${downloads.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
  await ApiService().downloadFile(url, savePath, onProgress: (received, total) {
    if (onProgress != null && total > 0) onProgress(received / total);
  });
  return savePath;
}

/// Shares a chat attachment OUT of the app via the system share sheet.
///
/// Local file paths are used as-is; anything else is downloaded with the SAME
/// authenticated mechanism the document/image tiles use
/// ([ApiService.downloadFile] — the auth header rides the interceptor) into a
/// temp file, then handed to SharePlus as an XFile. Any failure falls back to
/// sharing the URL itself. NEVER throws — best-effort by design.
Future<void> shareChatAttachment(String url, String fileName) async {
  try {
    if (url.isEmpty) return;
    String? path;
    // Already-local file (voice-note recordings, cached media) — share it
    // directly instead of re-downloading.
    if (!url.startsWith('http://') &&
        !url.startsWith('https://') &&
        !url.startsWith('data:')) {
      final file = File(url);
      if (await file.exists()) path = url;
    }
    if (path == null) {
      path = await _downloadForShare(url, fileName);
    }
    if (path != null && path.isNotEmpty) {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: fileName),
      );
      return;
    }
  } catch (_) {
    // Fall through to the URL share below.
  }
  try {
    final parsed = Uri.tryParse(url);
    if (parsed != null) {
      await SharePlus.instance.share(ShareParams(uri: parsed));
    }
  } catch (_) {
    // Never throw — sharing is best-effort.
  }
}

/// Downloads [url] into the temp chat-share dir with the authenticated
/// download path. Returns null on any failure (the caller falls back to
/// sharing the URL itself).
Future<String?> _downloadForShare(String url, String fileName) async {
  try {
    final dir = await getTemporaryDirectory();
    final downloads = Directory('${dir.path}/chat-share');
    if (!await downloads.exists()) {
      await downloads.create(recursive: true);
    }
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final savePath =
        '${downloads.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await ApiService().downloadFile(url, savePath);
    return savePath;
  } catch (_) {
    return null;
  }
}

/// Small translucent share button overlaid on media views (busy state built
/// in). Calls [shareChatAttachment] — fire-and-forget, never throws.
class ChatShareButton extends StatefulWidget {
  final String url;
  final String fileName;
  final bool onDark;

  const ChatShareButton({
    super.key,
    required this.url,
    required this.fileName,
    this.onDark = true,
  });

  @override
  State<ChatShareButton> createState() => _ChatShareButtonState();
}

class _ChatShareButtonState extends State<ChatShareButton> {
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    await shareChatAttachment(widget.url, widget.fileName);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.onDark ? Colors.white : Colors.white;
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _busy ? null : _share,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: _busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: iconColor,
                  ),
                )
              : Icon(Icons.share_rounded, size: 16, color: iconColor),
        ),
      ),
    );
  }
}

// =============================================================================
// Image (and GIF) attachments
// =============================================================================

/// Rounded in-bubble network image. Tap -> full-screen zoomable viewer.
class ChatImageView extends StatelessWidget {
  final String url;
  final bool isMe;
  final ThemeColors colors;
  final double maxWidth;
  final double maxHeight;

  const ChatImageView({
    super.key,
    required this.url,
    required this.isMe,
    required this.colors,
    this.maxWidth = 260,
    this.maxHeight = 320,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: () => _openViewer(context),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 180,
                  height: 180,
                  color: colors.surfaceVariant,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 180,
                  height: 120,
                  color: colors.surfaceVariant,
                  child: Icon(Icons.broken_image_rounded, color: colors.textSecondary),
                ),
              ),
            ),
            // Share out of the app (system share sheet) — top-right,
            // translucent circle, same authenticated download path.
            Positioned(
              top: 6,
              right: 6,
              child: ChatShareButton(
                url: url,
                fileName: attachmentDisplayName(null, url),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openViewer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => FullScreenImageViewer(url: url),
      ),
    );
  }
}

/// GIF attachments render bigger with no bubble chrome (handled by the bubble
/// layout) — this is just the image widget.
class ChatGifView extends StatelessWidget {
  final String url;
  final ThemeColors colors;

  const ChatGifView({super.key, required this.url, required this.colors});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => FullScreenImageViewer(url: url),
            ),
          );
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170, maxHeight: 170),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 140,
              height: 120,
              color: colors.surfaceVariant,
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 140,
              height: 100,
              color: colors.surfaceVariant,
              child: Icon(Icons.gif_rounded, color: colors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen zoomable image viewer: dark backdrop + InteractiveViewer +
/// Download button. URLs are public (no auth header needed to display).
class FullScreenImageViewer extends StatefulWidget {
  final String url;

  const FullScreenImageViewer({super.key, required this.url});

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  bool _downloading = false;
  double _progress = 0;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final fileName = attachmentDisplayName(null, widget.url);
      final path = await downloadAttachment(
        context,
        url: widget.url,
        fileName: fileName,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${attachmentDisplayName(null, widget.url)}')),
      );
      await OpenFilex.open(path);
    } catch (e) {
      Logger.error('Attachment download failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Download',
            onPressed: _downloading ? null : _download,
            icon: _downloading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: _progress > 0 ? _progress : null,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: CachedNetworkImage(
            imageUrl: widget.url,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorWidget: (_, __, ___) => const Icon(
              Icons.broken_image_rounded,
              color: Colors.white54,
              size: 56,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Video attachments
// =============================================================================

/// Inline video card (filmstrip-style tile with a play overlay — generating
/// real thumbnails requires decoding the video, so we use the icon card the
/// task allows). Tap -> full-screen player page.
class ChatVideoCard extends StatelessWidget {
  final String url;
  final String? name;
  final num? size;
  final bool isMe;
  final ThemeColors colors;

  const ChatVideoCard({
    super.key,
    required this.url,
    this.name,
    this.size,
    required this.isMe,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isMe ? Colors.white : colors.text;
    final subColor = isMe ? Colors.white70 : colors.textSecondary;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => FullScreenVideoPlayerScreen(url: url, title: attachmentDisplayName(name, url)),
          ),
        );
      },
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withValues(alpha: 0.14) : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 96,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        (isMe ? Colors.white : colors.primary).withValues(alpha: isMe ? 0.24 : 0.22),
                        (isMe ? Colors.white : colors.primaryDark).withValues(alpha: isMe ? 0.10 : 0.30),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.movie_creation_outlined,
                      size: 34, color: isMe ? Colors.white : colors.primary),
                ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    attachmentDisplayName(name, url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: textColor),
                  ),
                ),
                if (size != null && size! > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    formatFileSize(size),
                    style: TextStyle(fontSize: 10.5, color: subColor),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen video player page (video_player package) with a Download
/// button in the app bar.
class FullScreenVideoPlayerScreen extends StatefulWidget {
  final String url;
  final String title;

  const FullScreenVideoPlayerScreen({super.key, required this.url, required this.title});

  @override
  State<FullScreenVideoPlayerScreen> createState() => _FullScreenVideoPlayerScreenState();
}

class _FullScreenVideoPlayerScreenState extends State<FullScreenVideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _downloading = false;
  double _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.play();
      controller.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      Logger.error('Video player init failed: $e');
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final fileName = attachmentDisplayName(null, widget.url);
      final path = await downloadAttachment(
        context,
        url: widget.url,
        fileName: fileName,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${attachmentDisplayName(null, widget.url)}')),
      );
      await OpenFilex.open(path);
    } catch (e) {
      Logger.error('Video download failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: 'Download',
            onPressed: _downloading ? null : _download,
            icon: _downloading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: _progress > 0 ? _progress : null,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: Center(
        child: _failed
            ? const Text(
                'Could not play this video.\nUse the download button to save it instead.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              )
            : !initialized
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: controller.value.aspectRatio == 0
                            ? 16 / 9
                            : controller.value.aspectRatio,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            VideoPlayer(controller),
                            // Buffering spinner: while the stream is still
                            // filling, show WHY the frame is frozen instead
                            // of a silent black box (perceived slowness fix).
                            if (!controller.value.isPlaying &&
                                controller.value.isBuffering)
                              const CircularProgressIndicator(
                                  color: Colors.white70),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                if (controller.value.isPlaying) {
                                  controller.pause();
                                } else {
                                  controller.play();
                                }
                                if (mounted) setState(() {});
                              },
                              icon: Icon(
                                controller.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${_fmt(controller.value.position)} / ${_fmt(controller.value.duration)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            Expanded(
                              child: Slider(
                                activeColor: Colors.white,
                                inactiveColor: Colors.white24,
                                value: controller.value.duration.inMilliseconds > 0
                                    ? controller.value.position.inMilliseconds
                                        .clamp(0, controller.value.duration.inMilliseconds)
                                        .toDouble()
                                    : 0,
                                max: controller.value.duration.inMilliseconds > 0
                                    ? controller.value.duration.inMilliseconds.toDouble()
                                    : 1,
                                onChanged: (value) {
                                  controller.seekTo(Duration(milliseconds: value.round()));
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// =============================================================================
// Document attachments
// =============================================================================

/// File card tile: colored extension icon, file name, formatted size. Tap ->
/// download (with in-tile progress, auth header via ApiService) -> open with
/// OpenFilex.
class ChatDocumentTile extends StatefulWidget {
  final String url;
  final String? name;
  final num? size;
  final bool isMe;
  final ThemeColors colors;

  const ChatDocumentTile({
    super.key,
    required this.url,
    this.name,
    this.size,
    required this.isMe,
    required this.colors,
  });

  @override
  State<ChatDocumentTile> createState() => _ChatDocumentTileState();
}

class _ChatDocumentTileState extends State<ChatDocumentTile> {
  bool _downloading = false;
  double _progress = 0;

  String get _displayName => attachmentDisplayName(widget.name, widget.url);

  Future<void> _downloadAndOpen() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      final path = await downloadAttachment(
        context,
        url: widget.url,
        fileName: _displayName,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded $_displayName')),
      );
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app found to open this file')),
        );
      }
    } catch (e) {
      Logger.error('Document download failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final isMe = widget.isMe;
    final meta = documentIconMeta(_displayName);
    final textColor = isMe ? Colors.white : colors.text;
    final subColor = isMe ? Colors.white70 : colors.textSecondary;

    return GestureDetector(
      onTap: _downloading ? null : _downloadAndOpen,
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withValues(alpha: 0.14) : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: meta.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(meta.icon, color: meta.color, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _downloading
                        ? 'Downloading ${(_progress * 100).toStringAsFixed(0)}%'
                        : (widget.size != null && widget.size! > 0
                            ? formatFileSize(widget.size)
                            : 'Tap to download'),
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                  if (_downloading) ...[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 3,
                        backgroundColor: (isMe ? Colors.white : colors.primary).withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(isMe ? Colors.white : colors.primary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              _downloading ? Icons.downloading_rounded : Icons.download_rounded,
              size: 20,
              color: isMe ? Colors.white : colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Call-log messages
// =============================================================================

/// Slim centered row for messageType == 'call-log'. No bubble background:
/// direction-aware phone/video icon (green completed / red missed-cancelled-
/// declined), WhatsApp-style in/out arrow, direction-aware title, status
/// subtitle ("Ended · 12:34" / "Cancelled" / "Missed" / "Declined") + time.
/// Tapping opens the call summary sheet (participants + transcript when the
/// backend stored one).
class CallLogRow extends StatelessWidget {
  final Message message;
  final bool isMe;
  final ThemeColors colors;

  /// conversationId → display name, used by the summary sheet to label the
  /// participant ids the backend returns (which carry no names).
  final Map<String, String> participantNames;

  const CallLogRow({
    super.key,
    required this.message,
    required this.isMe,
    required this.colors,
    this.participantNames = const {},
  });

  @override
  Widget build(BuildContext context) {
    final meta = ChatCallLogMeta.tryParse(message.content);
    final missed = meta == null || meta.isUnsuccessful;
    final accent = missed ? colors.error : colors.success;

    final String title;
    if (meta == null) {
      title = 'Call record';
    } else {
      final direction = isMe ? 'Outgoing' : 'Incoming';
      title = '$direction ${meta.callType == 'video' ? 'video call' : 'voice call'}';
    }

    String statusLabel;
    if (meta == null) {
      statusLabel = '';
    } else if (meta.status == 'completed') {
      statusLabel = 'Ended · ${formatCallDuration(meta.durationSeconds)}';
    } else if (meta.status == 'cancelled') {
      statusLabel = 'Cancelled';
    } else if (meta.status == 'missed') {
      statusLabel = 'Missed';
    } else if (meta.status == 'declined') {
      statusLabel = 'Declined';
    } else {
      statusLabel = meta.status;
    }

    final row = Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // WhatsApp-style direction arrow layered over the phone icon.
            Icon(
              meta?.callType == 'video'
                  ? Icons.videocam_rounded
                  : (isMe ? Icons.call_made_rounded : Icons.call_received_rounded),
              size: 18,
              color: accent,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                  if (statusLabel.isNotEmpty)
                    Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: missed ? colors.error : colors.textSecondary,
                        fontWeight: missed ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              DateFormat.Hm().format(message.createdAt.toLocal()),
              style: TextStyle(fontSize: 10.5, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );

    // Tap-through: call summary bottom sheet (participants + transcript).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => CallLogSummarySheet.show(
        context,
        message: message,
        isMe: isMe,
        colors: colors,
        participantNames: participantNames,
      ),
      child: row,
    );
  }
}

/// WhatsApp-style call summary bottom sheet, opened from a call-log row.
/// Shows the meta (initiator, type, status, duration) and — best-effort —
/// the participant join/leave list (GET /calls/:id) plus the stored live-
/// caption transcript (GET /calls/:id/transcript) when present.
///
/// Deliberately defensive: every fetch failure degrades to the static meta
/// instead of an error screen (older backends have neither endpoint).
class CallLogSummarySheet extends StatefulWidget {
  final Message message;
  final bool isMe;
  final ThemeColors colors;
  final Map<String, String> participantNames;

  const CallLogSummarySheet({
    super.key,
    required this.message,
    required this.isMe,
    required this.colors,
    this.participantNames = const {},
  });

  static void show(
    BuildContext context, {
    required Message message,
    required bool isMe,
    required ThemeColors colors,
    Map<String, String> participantNames = const {},
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.75,
        child: CallLogSummarySheet(
          message: message,
          isMe: isMe,
          colors: colors,
          participantNames: participantNames,
        ),
      ),
    );
  }

  @override
  State<CallLogSummarySheet> createState() => _CallLogSummarySheetState();
}

class _CallLogSummarySheetState extends State<CallLogSummarySheet> {
  Map<String, dynamic>? _call;
  final List<_TranscriptLine> _transcript = [];
  bool _loading = true;
  bool _transcriptAvailable = false;
  /// Latest recording row for this call (from GET /calls/:id → `recording`).
  /// `storageUrl` is already resolved/presigned by the backend.
  Map<String, dynamic>? _recording;

  late final ChatCallLogMeta? _meta;

  @override
  void initState() {
    super.initState();
    _meta = ChatCallLogMeta.tryParse(widget.message.content);
    unawaited(_load());
  }

  String _nameFor(String userId) {
    final known = widget.participantNames[userId];
    if (known != null && known.trim().isNotEmpty) return known.trim();
    if (userId.length <= 10) return userId;
    return 'Guest ${userId.substring(userId.length - 4).toUpperCase()}';
  }

  Future<void> _load() async {
    final api = ApiService();
    final callId = _meta?.callId ?? '';
    if (callId.isNotEmpty) {
      try {
        final response = await api.getCallById(callId);
        if (response.data['success'] == true && response.data['data'] is Map) {
          _call = Map<String, dynamic>.from(response.data['data'] as Map);
          final rec = _call?['recording'];
          if (rec is Map) {
            final url = ApiService.resolveMediaUrl(rec['storageUrl']?.toString());
            if (url != null && url.isNotEmpty) {
              _recording = Map<String, dynamic>.from(rec);
              _recording!['storageUrl'] = url;
            }
          }
        }
      } catch (e) {
        Logger.error('CallLogSummarySheet: getCallById failed: $e');
      }
      final wantsTranscript = _meta?.hasTranscript == true ||
          _call?['hasTranscript'] == true;
      if (wantsTranscript) {
        try {
          final response = await api.getCallTranscript(callId);
          final data = response.data['data'];
          final List raw = data is List
              ? data
              : (data is Map && data['segments'] is List)
                  ? data['segments'] as List
                  : (data is Map && data['transcript'] is List)
                      ? data['transcript'] as List
                      : <dynamic>[];
          for (final entry in raw) {
            if (entry is! Map) continue;
            final text = (entry['text'] ?? entry['segment'] ?? '').toString();
            if (text.trim().isEmpty) continue;
            _transcript.add(_TranscriptLine(
              speaker: (entry['speakerName'] ?? entry['speaker_name'] ?? entry['speaker'] ?? 'Speaker')
                  .toString(),
              text: text,
            ));
          }
          _transcriptAvailable = _transcript.isNotEmpty;
        } catch (e) {
          // Transcript endpoint may not exist on the deployed backend yet —
          // degrade silently (the summary still renders).
          Logger.error('CallLogSummarySheet: transcript unavailable: $e');
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  String _statusLabel() {
    final status = _call?['status']?.toString() ?? _meta?.status ?? '';
    switch (status) {
      case 'completed':
        // `duration` arrives as a SQL numeric; never trust a raw `as num?`.
        final seconds = _call?['duration'] is num
            ? (_call?['duration'] as num).toInt()
            : _meta?.durationSeconds;
        return 'Ended · ${formatCallDuration(seconds)}';
      case 'cancelled':
        return 'Cancelled';
      case 'missed':
        return 'Missed';
      case 'declined':
        return 'Declined';
      case '':
        return '';
      default:
        return status;
    }
  }

  /// Recording block inside the call summary: play (in-app player with an
  /// external/download fallback), download, and processing/failed states.
  Widget _buildRecordingSection(ThemeColors colors) {
    final rec = _recording!;
    final recStatus = rec['status']?.toString() ?? 'completed';
    final url = rec['storageUrl']?.toString() ?? '';
    if (url.isEmpty) return const SizedBox.shrink();

    final seconds = rec['duration'] is num ? (rec['duration'] as num).toInt() : 0;
    final durationLabel = seconds > 0 ? ' · ${formatCallDuration(seconds)}' : '';
    final ext = url.split('?').first.split('.').last.toLowerCase();
    final fileName = 'metricorex-recording-${rec['id'] ?? DateTime.now().millisecondsSinceEpoch}'
        '${ext.length >= 2 && ext.length <= 5 ? '.$ext' : '.mp4'}';

    IconData statusIcon;
    String statusText;
    Color statusColor;
    switch (recStatus) {
      case 'completed':
        statusIcon = Icons.play_circle_fill_rounded;
        statusText = 'Play recording$durationLabel';
        statusColor = colors.success;
      case 'processing':
        statusIcon = Icons.hourglass_top_rounded;
        statusText = 'Recording is processing…';
        statusColor = colors.textSecondary;
      case 'failed':
        statusIcon = Icons.error_outline_rounded;
        statusText = 'Recording failed';
        statusColor = colors.error;
      default:
        statusIcon = Icons.graphic_eq_rounded;
        statusText = 'Recording$durationLabel';
        statusColor = colors.textSecondary;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recording',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: recStatus == 'completed'
                      ? () => unawaited(_playRecording(url, fileName))
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 22, color: statusColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: recStatus == 'completed'
                                  ? colors.text
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Download',
                icon: Icon(Icons.download_rounded, size: 20, color: colors.textSecondary),
                onPressed: recStatus == 'completed'
                    ? () => unawaited(_downloadRecording(url, fileName))
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _playRecording(String url, String fileName) async {
    final colors = AppTheme.colors;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RecordingPlayerSheet(url: url, fileName: fileName),
    );
  }
  Future<void> _downloadRecording(String url, String fileName) async {
    try {
      AppToast.show('Downloading recording…');
      final path = await downloadAttachment(context, url: url, fileName: fileName);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        AppToast.show('Saved to $fileName');
      }
    } catch (e) {
      Logger.error('CallLogSummarySheet: recording download failed: $e');
      AppToast.show('Could not download the recording', type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final meta = _meta;
    final missed = meta == null || meta.isUnsuccessful;
    final accent = missed ? colors.error : colors.success;
    final callType = meta?.callType ??
        (_call?['type']?.toString() == 'video' ? 'video' : 'audio');
    final title = widget.isMe
        ? 'Outgoing ${callType == 'video' ? 'video call' : 'voice call'}'
        : 'Incoming ${callType == 'video' ? 'video call' : 'voice call'}';

    final participants = _call?['participants'];
    final participantList =
        participants is List ? participants.whereType<Map>().toList() : <Map>[];

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: colors.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    callType == 'video'
                        ? Icons.videocam_rounded
                        : (widget.isMe
                            ? Icons.call_made_rounded
                            : Icons.call_received_rounded),
                    color: accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.text,
                        ),
                      ),
                      if (_statusLabel().isNotEmpty)
                        Text(
                          _statusLabel(),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight:
                                missed ? FontWeight.w600 : FontWeight.w400,
                            color: missed ? colors.error : colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (meta?.initiatorName?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Text(
                'Started by ${meta!.initiatorName}',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
            ),
          const SizedBox(height: 8),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    children: [
                      if (participantList.isNotEmpty) ...[
                        Text(
                          'Participants',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final p in participantList)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person_rounded,
                                  size: 16,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _nameFor(
                                        (p['userId'] ?? p['user_id'] ?? '').toString()),
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: colors.text,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${p['status'] ?? ''}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                      if (_recording != null) ...[
                        _buildRecordingSection(colors),
                        const SizedBox(height: 8),
                      ],
                      if (_transcriptAvailable) ...[
                        Text(
                          'Live transcript',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final line in _transcript)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.speaker,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: colors.primary,
                                  ),
                                ),
                                Text(
                                  line.text,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.3,
                                    color: colors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ] else if (!_loading &&
                          participantList.isEmpty &&
                          meta == null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'No call details available',
                              style: TextStyle(
                                  fontSize: 13, color: colors.textSecondary),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptLine {
  final String speaker;
  final String text;
  const _TranscriptLine({required this.speaker, required this.text});
}

// =============================================================================
// Recording player (call summary)
// =============================================================================

/// In-app playback for a call recording (video OR audio-only — the platform
/// players behind video_player, ExoPlayer/AVPlayer, handle both). If the
/// container is unsupported on the device (e.g. WEBM on iOS), the sheet
/// degrades to "Open externally" / "Download & open" fallbacks instead of a
/// dead player.
class _RecordingPlayerSheet extends StatefulWidget {
  final String url;
  final String fileName;
  const _RecordingPlayerSheet({required this.url, required this.fileName});

  @override
  State<_RecordingPlayerSheet> createState() => _RecordingPlayerSheetState();
}

class _RecordingPlayerSheetState extends State<_RecordingPlayerSheet> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _error;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initialized = true;
      });
      await controller.play();
    } catch (e) {
      Logger.error('RecordingPlayer: initialize failed: $e');
      try {
        await controller.dispose();
      } catch (_) {}
      if (mounted) setState(() => _error = "Couldn't play this recording in-app.");
    }
  }

  Future<void> _openExternally() async {
    try {
      await url_launcher.launchUrl(
        Uri.parse(widget.url),
        mode: url_launcher.LaunchMode.externalApplication,
      );
    } catch (_) {
      AppToast.show('Could not open the recording externally', type: AppToastType.error);
    }
  }

  Future<void> _downloadAndOpen() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final dir = await getTemporaryDirectory();
      final savePath =
          '${dir.path}/recording-${DateTime.now().millisecondsSinceEpoch}_${widget.fileName}';
      await ApiService().downloadFile(widget.url, savePath);
      final result = await OpenFilex.open(savePath);
      if (result.type != ResultType.done) {
        AppToast.show('Saved as ${widget.fileName}');
      }
    } catch (e) {
      Logger.error('RecordingPlayer: download failed: $e');
      AppToast.show('Could not download the recording', type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.graphic_eq_rounded, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Call recording',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.text,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: colors.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openExternally,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open externally'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _downloading ? null : _downloadAndOpen,
                      icon: _downloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download'),
                    ),
                  ),
                ],
              ),
            ] else if (!_initialized) ...[
              SizedBox(
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
                ),
              ),
            ] else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio == 0
                      ? 16 / 9
                      : _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              ),
              const SizedBox(height: 10),
              VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: colors.primary,
                  bufferedColor: colors.surfaceVariant,
                  backgroundColor: colors.border,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    _fmt(_controller!.value.position),
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  const Spacer(),
                  Text(
                    _fmt(_controller!.value.duration),
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: IconButton(
                  iconSize: 44,
                  icon: Icon(
                    _controller!.value.isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: colors.primary,
                  ),
                  onPressed: () {
                    setState(() {
                      _controller!.value.isPlaying
                          ? _controller!.pause()
                          : _controller!.play();
                    });
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
