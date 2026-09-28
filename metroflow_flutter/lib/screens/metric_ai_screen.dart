import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/user_profile_provider.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
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
/// - When the AI flags `suggestHumanSupport` the reply is followed by a
///   "Talk to a human" card; escalating (POST /support/escalate with the
///   transcript) transforms this same screen into a live support
///   conversation (5s polling, customer/agent bubbles, conclude action).
class MetricAiScreen extends ConsumerStatefulWidget {
  const MetricAiScreen({super.key});

  @override
  ConsumerState<MetricAiScreen> createState() => _MetricAiScreenState();
}

class _MetricAiScreenState extends ConsumerState<MetricAiScreen> {
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

  // -- Support conversation mode (human handoff) ------------------------------
  bool _supportMode = false;
  bool _supportLoading = false;
  bool _supportPollBusy = false;
  bool _concludingSupport = false;
  bool _sendingSupport = false;
  String? _supportConversationId;
  String _supportStatus = 'open';
  final List<_SupportMessage> _supportMessages = [];
  Timer? _supportPollTimer;
  final TextEditingController _supportController = TextEditingController();
  final ScrollController _supportScrollController = ScrollController();

  bool get _supportConcluded =>
      _supportStatus == 'resolved' || _supportStatus == 'closed';

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _supportPollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _supportController.dispose();
    _supportScrollController.dispose();
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
      final suggestHumanSupport =
          data is Map && data['suggestHumanSupport'] == true;
      setState(() {
        _messages.add(_AiMessage(
          role: 'assistant',
          content: reply,
          imageUrl: (imageUrl != null && imageUrl.isNotEmpty)
              ? ApiService.resolveMediaUrl(imageUrl)
              : null,
          suggestHumanSupport: suggestHumanSupport,
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

  void _scrollSupportToBottom() {
    if (_supportScrollController.hasClients) {
      _supportScrollController.animateTo(
        _supportScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Human handoff — escalation + support conversation mode
  // ---------------------------------------------------------------------------

  /// The current AI conversation as a `{role, content}` transcript for the
  /// support agent's context.
  List<Map<String, dynamic>> _buildTranscript() {
    return _messages
        .where((m) => m.content.trim().isNotEmpty)
        .map((m) => {
              'role': m.role == 'user' ? 'user' : 'assistant',
              'content': m.content.trim(),
            })
        .toList();
  }

  void _showEscalationSheet() {
    final profile = ref.read(userProfileProvider);
    final nameController = TextEditingController(text: profile.name);
    final emailController = TextEditingController(text: profile.email);
    final messageController = TextEditingController();
    bool submitting = false;
    final colors = AppTheme.colors;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> submit() async {
                final name = nameController.text.trim();
                final email = emailController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter your name')));
                  return;
                }
                if (email.isEmpty || !email.contains('@')) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(const SnackBar(
                      content: Text('Please enter a valid email')));
                  return;
                }
                // Capture scaffold/navigator references before any await —
                // using contexts across the async gap is unsafe and flagged.
                final rootMessenger = ScaffoldMessenger.of(context);
                final sheetNavigator = Navigator.of(sheetContext);
                setSheetState(() => submitting = true);
                try {
                  final response = await _api.escalateToSupport(
                    name: name,
                    email: email,
                    message: messageController.text,
                    channel: 'mobile',
                    transcript: _buildTranscript(),
                  );
                  final data =
                      response.data is Map ? response.data['data'] : null;
                  final conversationId = data is Map
                      ? (data['conversationId'] ?? data['id'])?.toString()
                      : null;
                  final status = data is Map
                      ? (data['status']?.toString() ?? 'open')
                      : 'open';
                  if (!mounted) return;
                  sheetNavigator.pop();
                  if (conversationId == null || conversationId.isEmpty) {
                    rootMessenger.showSnackBar(const SnackBar(
                        content: Text(
                            'Support request received — but the conversation could not be opened in-app.')));
                    return;
                  }
                  _enterSupportMode(conversationId, status);
                } catch (e) {
                  Logger.error('Support escalation failed: $e');
                  setSheetState(() => submitting = false);
                  if (mounted) {
                    rootMessenger.showSnackBar(SnackBar(
                        content: Text(ApiService.extractErrorMessage(e))));
                  }
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.support_agent_rounded,
                            size: 22, color: AppColors.warning),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Talk to a human',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: colors.text)),
                            const SizedBox(height: 2),
                            Text(
                                'A support agent will pick up your conversation.',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: colors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    style: TextStyle(color: colors.text, fontSize: 14.5),
                    decoration: InputDecoration(
                      labelText: 'Your name *',
                      labelStyle:
                          TextStyle(color: colors.textSecondary, fontSize: 13),
                      filled: true,
                      fillColor: colors.surfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: colors.text, fontSize: 14.5),
                    decoration: InputDecoration(
                      labelText: 'Email *',
                      labelStyle:
                          TextStyle(color: colors.textSecondary, fontSize: 13),
                      filled: true,
                      fillColor: colors.surfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: messageController,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(color: colors.text, fontSize: 14.5),
                    decoration: InputDecoration(
                      labelText:
                          'Describe the issue (optional — the AI transcript is attached)',
                      labelStyle:
                          TextStyle(color: colors.textSecondary, fontSize: 13),
                      filled: true,
                      fillColor: colors.surfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: submitting ? null : submit,
                      child: submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Start support chat',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _enterSupportMode(String conversationId, String status) {
    _supportPollTimer?.cancel();
    setState(() {
      _supportMode = true;
      _supportConversationId = conversationId;
      _supportStatus = status;
      _supportMessages.clear();
      _supportMessages.add(_SupportMessage(
        id: 'local-system-${DateTime.now().millisecondsSinceEpoch}',
        senderType: 'system',
        senderName: 'System',
        body: 'You are now chatting with our support team. MetricAi is paused for this conversation.',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));
    });
    _loadSupportMessages();
    _supportPollTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _pollSupportMessages());
  }

  /// Back to MetricAi: stop polling and restore the AI view (history intact).
  void _exitSupportMode() {
    _supportPollTimer?.cancel();
    _supportPollTimer = null;
    setState(() {
      _supportMode = false;
      _supportConversationId = null;
      _supportMessages.clear();
      _supportStatus = 'open';
    });
  }

  Future<void> _loadSupportMessages() async {
    final conversationId = _supportConversationId;
    if (conversationId == null) return;
    setState(() => _supportLoading = true);
    try {
      final response = await _api.getMySupportMessages(conversationId);
      final data = response.data is Map ? response.data['data'] : null;
      if (!mounted) return;
      final messages = data is Map ? data['messages'] : null;
      final status = data is Map ? data['status']?.toString() : null;
      setState(() {
        if (messages is List) {
          _supportMessages
            ..removeWhere((m) => m.id.startsWith('local-system-'))
            ..addAll(messages
                .whereType<Map>()
                .map((m) => _SupportMessage.fromMap(Map<String, dynamic>.from(m)))
                .toList());
        }
        if (status != null && status.isNotEmpty) _supportStatus = status;
        _supportLoading = false;
      });
      Future.delayed(const Duration(milliseconds: 80), _scrollSupportToBottom);
    } catch (e) {
      Logger.error('Support messages load failed: $e');
      if (mounted) setState(() => _supportLoading = false);
    }
  }

  /// Incremental 5s poll — only messages newer than the last known one.
  Future<void> _pollSupportMessages() async {
    if (_supportPollBusy || !_supportMode || _supportConversationId == null) {
      return;
    }
    _supportPollBusy = true;
    final before = _supportMessages.length;
    try {
      final after = _supportMessages.isNotEmpty
          ? _supportMessages.last.createdAt
          : null;
      final response =
          await _api.getMySupportMessages(_supportConversationId!, after: after);
      final data = response.data is Map ? response.data['data'] : null;
      if (!mounted) return;
      final messages = data is Map ? data['messages'] : null;
      final status = data is Map ? data['status']?.toString() : null;
      if (messages is List && messages.isNotEmpty) {
        final existing = _supportMessages.map((m) => m.id).toSet();
        final fresh = messages
            .whereType<Map>()
            .map((m) => _SupportMessage.fromMap(Map<String, dynamic>.from(m)))
            .where((m) => !existing.contains(m.id))
            .toList();
        if (fresh.isNotEmpty) {
          setState(() => _supportMessages.addAll(fresh));
        }
      }
      if (status != null && status.isNotEmpty && status != _supportStatus) {
        setState(() => _supportStatus = status);
        if (_supportConcluded) _supportPollTimer?.cancel();
      }
      if (_supportMessages.length != before) {
        _scrollSupportToBottom();
      }
    } catch (e) {
      // Polling failures are silent — the next tick retries.
    } finally {
      _supportPollBusy = false;
    }
  }

  Future<void> _sendSupportMessage() async {
    final text = _supportController.text.trim();
    final conversationId = _supportConversationId;
    if (text.isEmpty || _sendingSupport || conversationId == null) return;
    if (_supportConcluded) return;

    setState(() {
      _sendingSupport = true;
      _supportController.clear();
      _supportMessages.add(_SupportMessage(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        senderType: 'customer',
        senderName: 'You',
        body: text,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));
    });
    _scrollSupportToBottom();
    try {
      await _api.sendMySupportMessage(conversationId, text);
      await _pollSupportMessages();
    } on DioException catch (e) {
      Logger.error('Support send failed: $e');
      if (!mounted) return;
      setState(() => _sendingSupport = false);
      if (e.response?.statusCode == 400) {
        // Concluded server-side — sync status and disable the composer.
        setState(() => _supportStatus = 'resolved');
        _supportPollTimer?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('This conversation has already been concluded.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Message could not be sent. Please try again.')));
      }
    } catch (e) {
      Logger.error('Support send failed: $e');
      if (mounted) {
        setState(() => _sendingSupport = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Message could not be sent. Please try again.')));
      }
    }
  }

  Future<void> _concludeSupport() async {
    final conversationId = _supportConversationId;
    if (conversationId == null || _concludingSupport) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.colors.surface,
        title: const Text('Conclude chat?'),
        content: const Text(
            'This ends the support conversation. You won\'t be able to send further messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Conclude'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _concludingSupport = true);
    try {
      final response = await _api.closeMySupportConversation(conversationId);
      final data = response.data is Map ? response.data['data'] : null;
      final status = data is Map ? data['status']?.toString() : null;
      if (!mounted) return;
      setState(() {
        _supportStatus = (status != null && status.isNotEmpty)
            ? status
            : 'resolved';
        _concludingSupport = false;
      });
      _supportPollTimer?.cancel();
      AppToast.show('Support chat concluded', type: AppToastType.success);
    } catch (e) {
      Logger.error('Support close failed: $e');
      if (mounted) {
        setState(() => _concludingSupport = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ApiService.extractErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return PopScope(
      canPop: !_supportMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _supportMode) _exitSupportMode();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: _supportMode
            ? _buildSupportAppBar(colors)
            : _buildAiAppBar(colors),
        body: _checkingStatus
            ? Center(child: CircularProgressIndicator(color: colors.primary))
            : !_available
                ? _buildLockedCard(colors)
                : _supportMode
                    ? _buildSupportBody(colors)
                    : _buildChatBody(colors),
      ),
    );
  }

  PreferredSizeWidget _buildAiAppBar(ThemeColors colors) {
    return AppBar(
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
                _chatModel != null
                    ? 'Your AI assistant · $_chatModel'
                    : 'Your AI assistant',
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
    );
  }

  PreferredSizeWidget _buildSupportAppBar(ThemeColors colors) {
    return AppBar(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      shadowColor: colors.border,
      iconTheme: IconThemeData(color: colors.text),
      titleSpacing: 8,
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent_rounded,
                size: 19, color: AppColors.warning),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Support',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
              Text(
                _supportConcluded
                    ? 'Conversation concluded'
                    : 'Chatting with Support',
                style: TextStyle(
                  fontSize: 11,
                  color: _supportConcluded
                      ? colors.textSecondary
                      : AppColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (!_supportConcluded)
          PopupMenuButton<String>(
            tooltip: 'Options',
            icon: Icon(Icons.more_vert_rounded, color: colors.text),
            onSelected: (value) {
              if (value == 'conclude') _concludeSupport();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'conclude',
                enabled: !_concludingSupport,
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 20, color: AppColors.warning),
                    SizedBox(width: 10),
                    Text('Conclude chat'),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(width: 6),
      ],
    );
  }

  // -- Support conversation body ----------------------------------------------

  Widget _buildSupportBody(ThemeColors colors) {
    return Column(
      children: [
        Expanded(
          child: _supportLoading && _supportMessages.isEmpty
              ? Center(
                  child: CircularProgressIndicator(color: colors.primary))
              : ListView.builder(
                  controller: _supportScrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  itemCount: _supportMessages.length,
                  itemBuilder: (context, index) {
                    final message = _supportMessages[index];
                    return _SupportBubble(
                      message: message,
                      colors: colors,
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: _supportConcluded
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(top: BorderSide(color: colors.border)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded,
                          size: 28, color: colors.success),
                      const SizedBox(height: 8),
                      Text(
                        'This conversation has been concluded. Thanks for reaching out!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13.5, color: colors.textSecondary),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _exitSupportMode,
                          child: const Text('Back to MetricAi',
                              style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(top: BorderSide(color: colors.border)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _supportController,
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 5,
                          style:
                              TextStyle(color: colors.text, fontSize: 14.5),
                          decoration: InputDecoration(
                            hintText: 'Message Support…',
                            hintStyle:
                                TextStyle(color: colors.textSecondary),
                            filled: true,
                            fillColor: colors.surfaceVariant,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 11),
                          ),
                          onSubmitted: (_) => _sendSupportMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: AppColors.warning,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: _sendingSupport
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 20),
                          onPressed: _sendingSupport
                              ? null
                              : _sendSupportMessage,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
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
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _AiBubble(
                              message: message,
                              isUser: isUser,
                              colors: colors,
                            ),
                            if (!isUser && message.suggestHumanSupport)
                              _HumanHandoffCard(
                                colors: colors,
                                onTap: _showEscalationSheet,
                              ),
                          ],
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
  final bool suggestHumanSupport;

  const _AiMessage({
    required this.role,
    required this.content,
    this.imageUrl,
    this.suggestHumanSupport = false,
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

/// Highlighted "Talk to a human" card rendered right below an assistant reply
/// that asked the user to escalate (`suggestHumanSupport == true`).
class _HumanHandoffCard extends StatelessWidget {
  final ThemeColors colors;
  final VoidCallback onTap;

  const _HumanHandoffCard({required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 21, bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                const Icon(Icons.support_agent_rounded,
                    size: 22, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              size: 13, color: AppColors.warning),
                          const SizedBox(width: 4),
                          Text(
                            'Talk to a human',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: colors.text,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'MetricAi suggests a human agent can help with this. Tap to continue with Support.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppColors.warning),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Support conversation messages
// -----------------------------------------------------------------------------

class _SupportMessage {
  final String id;
  final String senderType; // 'customer' | 'agent' | 'system' | 'ai'
  final String senderName;
  final String body;
  final String createdAt; // ISO

  const _SupportMessage({
    required this.id,
    required this.senderType,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  /// Tolerant parse of
  /// `{ id, sender_type, sender_name, body, created_at }` (snake_case per the
  /// support desk API; camelCase tolerated defensively).
  factory _SupportMessage.fromMap(Map<String, dynamic> map) {
    String asString(dynamic v) => v == null ? '' : v.toString();
    return _SupportMessage(
      id: asString(map['id'] ??
          'remote-${map['created_at'] ?? map['createdAt'] ?? map['body'] ?? ''}'),
      senderType: asString(map['sender_type'] ?? map['senderType'])
          .toLowerCase(),
      senderName: asString(map['sender_name'] ?? map['senderName']),
      body: asString(map['body'] ?? map['message']),
      createdAt: asString(map['created_at'] ?? map['createdAt']),
    );
  }

  bool get isCustomer => senderType == 'customer';
  bool get isAgent => senderType == 'agent';
  bool get isCentered => senderType == 'system' || senderType == 'ai';
}

class _SupportBubble extends StatelessWidget {
  final _SupportMessage message;
  final ThemeColors colors;

  const _SupportBubble({required this.message, required this.colors});

  @override
  Widget build(BuildContext context) {
    // System / AI notes: centered, gray, no bubble.
    if (message.isCentered) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              message.body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: colors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }

    final isCustomer = message.isCustomer;
    final name = message.senderName.isNotEmpty
        ? message.senderName
        : (isCustomer ? 'You' : 'Support agent');
    final time = _formatTime(message.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isCustomer ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isCustomer) ...[
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.warning.withValues(alpha: 0.16),
              child: const Icon(Icons.support_agent_rounded,
                  size: 14, color: AppColors.warning),
            ),
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
                color: isCustomer ? colors.primary : colors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isCustomer ? 16 : 4),
                  topRight: Radius.circular(isCustomer ? 4 : 16),
                  bottomLeft: const Radius.circular(16),
                  bottomRight: const Radius.circular(16),
                ),
                border: isCustomer
                    ? null
                    : Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isCustomer)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  Text(
                    message.body,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.4,
                      color: isCustomer ? Colors.white : colors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 10,
                      color: isCustomer
                          ? Colors.white70
                          : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    if (date == null) return '';
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '$h:$m';
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
