import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import '../widgets/chat_attachment_views.dart';
import '../widgets/metric_ai_logo.dart';

/// MetricAi — the plan-gated built-in AI assistant (like Meta AI in
/// WhatsApp). Backed by GET /ai/status, POST /ai/chat, GET/DELETE /ai/history.
///
/// - If the caller's plan doesn't include MetricAi (available != true) the
///   screen shows a locked card with an Upgrade CTA and never calls the chat
///   endpoints.
/// - Replies arrive as markdown-ish text: rendered with paragraph/bullet/
///   **bold** handling. Generated images render as rounded images.
class MetricAiScreen extends StatefulWidget {
  const MetricAiScreen({super.key});

  @override
  State<MetricAiScreen> createState() => _MetricAiScreenState();
}

class _MetricAiScreenState extends State<MetricAiScreen> {
  final ApiService _api = ApiService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _checkingStatus = true;
  bool _available = false;
  String? _planName;
  String? _chatModel;

  bool _loadingHistory = false;
  bool _sending = false;
  bool _uploadingImage = false;
  String? _pendingImageUrl;
  File? _pendingImagePreview;
  final List<_AiMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _checkingStatus = true);
    try {
      final response = await _api.getAiStatus();
      final data = response.data is Map ? response.data['data'] : null;
      if (!mounted) return;
      if (data is Map) {
        setState(() {
          _available = data['available'] == true;
          _planName = data['planName']?.toString();
          _chatModel = data['chatModel']?.toString();
          _checkingStatus = false;
        });
      } else {
        setState(() {
          _available = false;
          _checkingStatus = false;
        });
      }
    } catch (e) {
      Logger.error('MetricAi status failed: $e');
      if (!mounted) return;
      setState(() {
        _available = false;
        _checkingStatus = false;
      });
      return;
    }
    if (_available) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final response = await _api.getAiHistory();
      final data = response.data is Map ? response.data['data'] : null;
      if (!mounted) return;
      final messages = data is Map ? data['messages'] : null;
      if (messages is List) {
        setState(() {
          _messages
            ..clear()
            ..addAll(messages.whereType<Map>().map((m) {
              final imageUrl = m['imageUrl']?.toString();
              return _AiMessage(
                role: m['role']?.toString() ?? 'assistant',
                content: m['content']?.toString() ?? '',
                imageUrl: (imageUrl != null && imageUrl.isNotEmpty)
                    ? ApiService.resolveMediaUrl(imageUrl)
                    : null,
              );
            }));
        });
        Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
      }
    } catch (e) {
      Logger.error('MetricAi history failed: $e');
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.colors.surface,
        title: const Text('Clear MetricAi history?'),
        content: const Text(
            'This permanently deletes your conversation with MetricAi. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteAiHistory();
      if (mounted) setState(() => _messages.clear());
    } catch (e) {
      Logger.error('MetricAi clear failed: $e');
    }
  }

  Future<void> _pickImage() async {
    if (_uploadingImage || _sending) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (picked == null || !mounted) return;
      setState(() => _uploadingImage = true);
      final upload = await _api.uploadChatMediaDetailed(File(picked.path));
      if (!mounted) return;
      if (upload == null || upload.url.isEmpty) {
        throw const FormatException('Image upload failed');
      }
      setState(() {
        _uploadingImage = false;
        _pendingImageUrl = ApiService.resolveMediaUrl(upload.url) ?? upload.url;
        _pendingImagePreview = File(picked.path);
      });
    } catch (e) {
      Logger.error('MetricAi image upload failed: $e');
      if (mounted) {
        setState(() => _uploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (_sending) return;
    if (text.isEmpty && _pendingImageUrl == null) return;
    final image = _pendingImageUrl;

    setState(() {
      _messages.add(_AiMessage(role: 'user', content: text, imageUrl: image));
      _sending = true;
      _pendingImageUrl = null;
      _pendingImagePreview = null;
      _messageController.clear();
    });
    _scrollToBottom();
    try {
      final response = await _api.sendAiChat(text, imageUrl: image);
      final data = response.data is Map ? response.data['data'] : null;
      if (!mounted) return;
      final reply = data is Map ? (data['reply']?.toString() ?? '') : '';
      final imageUrl = data is Map ? data['imageUrl']?.toString() : null;
      setState(() {
        _messages.add(_AiMessage(
          role: 'assistant',
          content: reply,
          imageUrl: (imageUrl != null && imageUrl.isNotEmpty)
              ? ApiService.resolveMediaUrl(imageUrl)
              : null,
        ));
        _sending = false;
      });
      _scrollToBottom();
    } on DioException catch (e) {
      final code = e.response?.data is Map
          ? (e.response!.data as Map)['code']?.toString()
          : null;
      Logger.error('MetricAi chat failed: $e');
      if (!mounted) return;
      setState(() => _sending = false);
      if (code == 'metric_ai_not_enabled') {
        // Plan changed mid-session → show the locked state.
        setState(() => _available = false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('MetricAi could not respond. Please try again.')),
        );
      }
    } catch (e) {
      Logger.error('MetricAi chat failed: $e');
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('MetricAi could not respond. Please try again.')),
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        shadowColor: colors.border,
        iconTheme: IconThemeData(color: colors.text),
        titleSpacing: 8,
        title: Row(
          children: [
            MetricAiGlowLogo(radius: 17),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MetricAi',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
                Text(
                  _chatModel != null ? 'Your AI assistant · $_chatModel' : 'Your AI assistant',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_available && _messages.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: Icon(Icons.delete_outline_rounded, color: colors.error),
              onPressed: _clearHistory,
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: _checkingStatus
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : !_available
              ? _buildLockedCard(colors)
              : _buildChatBody(colors),
    );
  }

  // -- Locked state ---------------------------------------------------------

  Widget _buildLockedCard(ThemeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.all(28),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline_rounded,
                    size: 32, color: colors.textSecondary),
              ),
              const SizedBox(height: 20),
              Text(
                'MetricAi is not part of your current plan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 8),
              if (_planName != null && _planName!.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.primaryBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$_planName plan',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                'Upgrade to a plan that includes MetricAi to chat with your built-in AI assistant, generate images and get platform help instantly.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => GoRouter.of(context).push('/main/subscription'),
                  child: const Text(
                    'Upgrade Plan',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- Chat body --------------------------------------------------------------

  Widget _buildChatBody(ThemeColors colors) {
    return Column(
      children: [
        Expanded(
          child: _loadingHistory && _messages.isEmpty
              ? Center(child: CircularProgressIndicator(color: colors.primary))
              : _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MetricAiGlowLogo(radius: 40),
                          const SizedBox(height: 16),
                          Text(
                            'Hi, I\'m MetricAi 👋',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: colors.text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ask me anything about Metricorex — or anything else.\nTry "Generate a logo for my bakery".',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(left: 44, bottom: 8),
                              child: _BouncingDots(color: colors.primary),
                            ),
                          );
                        }
                        final message = _messages[index];
                        final isUser = message.role == 'user';
                        return _AiBubble(
                          message: message,
                          isUser: isUser,
                          colors: colors,
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: _buildComposer(colors),
          ),
        ),
      ],
    );
  }

  Widget _buildComposer(ThemeColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_pendingImagePreview != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    _pendingImagePreview!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Image attached — it will be shared with MetricAi',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove image',
                  icon: Icon(Icons.close_rounded, color: colors.textSecondary),
                  onPressed: () {
                    setState(() {
                      _pendingImageUrl = null;
                      _pendingImagePreview = null;
                    });
                  },
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'Attach image',
                style: IconButton.styleFrom(
                  backgroundColor: colors.primaryBg,
                  shape: const CircleBorder(),
                ),
                icon: _uploadingImage
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: colors.primary),
                      )
                    : Icon(Icons.image_outlined,
                        color: colors.primary, size: 21),
                onPressed: _uploadingImage ? null : _pickImage,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 5,
                style: TextStyle(color: colors.text, fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Ask MetricAi anything...',
                  hintStyle: TextStyle(color: colors.textSecondary),
                  filled: true,
                  fillColor: colors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 11),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4F46E5), Color(0xFF2563EB)],
                ),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                onPressed: _sending ? null : _send,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Messages & rendering
// -----------------------------------------------------------------------------

class _AiMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final String? imageUrl;

  const _AiMessage({
    required this.role,
    required this.content,
    this.imageUrl,
  });
}

class _AiBubble extends StatelessWidget {
  final _AiMessage message;
  final bool isUser;
  final ThemeColors colors;

  const _AiBubble({
    required this.message,
    required this.isUser,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isUser) ...[
              const MetricAiGlowLogo(radius: 13, glowStrength: 0.6),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.74,
                ),
                decoration: BoxDecoration(
                  gradient: isUser
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF4F46E5), Color(0xFF2563EB)],
                        )
                      : null,
                  color: isUser ? null : colors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isUser ? 16 : 4),
                    topRight: Radius.circular(isUser ? 4 : 16),
                    bottomLeft: const Radius.circular(16),
                    bottomRight: const Radius.circular(16),
                  ),
                  border:
                      isUser ? null : Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (message.imageUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                fullscreenDialog: true,
                                builder: (_) => FullScreenImageViewer(
                                    url: message.imageUrl!),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: message.imageUrl!,
                              width: 220,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                width: 220,
                                height: 160,
                                color: colors.surfaceVariant,
                                child: Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: colors.primary),
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                width: 220,
                                height: 100,
                                color: colors.surfaceVariant,
                                child: Icon(Icons.broken_image_rounded,
                                    color: colors.textSecondary),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (message.content.isNotEmpty)
                      isUser
                          ? Text(
                              message.content,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                height: 1.4,
                              ),
                            )
                          : _RichReplyText(
                              text: message.content,
                              colors: colors,
                            ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight markdown-ish renderer for MetricAi replies: handles paragraphs,
/// bullets (-, *, •), numbered lines and **bold** spans. Deliberately simple —
/// no full markdown dependency.
class _RichReplyText extends StatelessWidget {
  final String text;
  final ThemeColors colors;

  const _RichReplyText({required this.text, required this.colors});

  static final RegExp _boldRe = RegExp(r'\*\*(.+?)\*\*');

  @override
  Widget build(BuildContext context) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final List<Widget> blocks = [];

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        blocks.add(const SizedBox(height: 6));
        continue;
      }
      final bulletMatch =
          RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+(.*)$').firstMatch(line);
      if (bulletMatch != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ',
                  style: TextStyle(
                      fontSize: 14, height: 1.4, color: colors.text)),
              Expanded(
                child: _boldText(bulletMatch.group(1) ?? ''),
              ),
            ],
          ),
        ));
        continue;
      }
      final headingMatch = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(line);
      if (headingMatch != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: Text(
            headingMatch.group(1) ?? '',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
        ));
        continue;
      }
      blocks.add(_boldText(line));
      blocks.add(const SizedBox(height: 4));
    }

    return DefaultTextStyle.merge(
      style: TextStyle(fontSize: 14.5, height: 1.45, color: colors.text),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks,
      ),
    );
  }

  Widget _boldText(String line) {
    final spans = <TextSpan>[];
    int cursor = 0;
    for (final match in _boldRe.allMatches(line)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: line.substring(cursor, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
      cursor = match.end;
    }
    if (cursor < line.length) {
      spans.add(TextSpan(text: line.substring(cursor)));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 14.5, height: 1.45, color: colors.text),
        children: spans,
      ),
    );
  }
}

/// Three bouncing dots — the "MetricAi is typing" indicator.
class _BouncingDots extends StatefulWidget {
  final Color color;

  const _BouncingDots({required this.color});

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) => _dot(i)),
      ),
    );
  }

  Widget _dot(int index) {
    final start = index * 0.2;
    final anim = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, start + 0.45, curve: Curves.easeInOut),
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(anim),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.75, end: 1.2).animate(anim),
        child: Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          decoration:
              BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
