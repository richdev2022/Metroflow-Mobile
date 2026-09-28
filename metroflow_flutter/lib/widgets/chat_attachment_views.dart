import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/message.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/chat_media_utils.dart';
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
        child: ConstrainedBox(
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
                        child: VideoPlayer(controller),
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
/// phone/video icon (green completed / red missed-cancelled), direction-aware
/// title, status subtitle ("Ended · 12:34" / "Cancelled" / "Missed") + time.
class CallLogRow extends StatelessWidget {
  final Message message;
  final bool isMe;
  final ThemeColors colors;

  const CallLogRow({
    super.key,
    required this.message,
    required this.isMe,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final meta = ChatCallLogMeta.tryParse(message.content);
    final missed = meta == null ||
        meta.status == 'missed' ||
        meta.status == 'cancelled';
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
    } else {
      statusLabel = meta.status;
    }

    return Center(
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
            Icon(
              meta?.callType == 'video'
                  ? Icons.videocam_rounded
                  : Icons.call_rounded,
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
  }
}
