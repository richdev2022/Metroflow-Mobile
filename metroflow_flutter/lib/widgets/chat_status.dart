import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/auth_provider.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/app_feedback.dart';
import '../utils/app_toast.dart';

/// WHATSAPP-STYLE CHAT STATUS (24h stories) — mobile.
///
/// Backend contract (server/routes/statuses.ts): a status is a text card
/// (with a background colour) and/or an image, visible to the same business
/// for 24h. Members can VIEW (idempotent), LIKE (toggle), REPOST (attributed)
/// and DELETE their own. The poster additionally sees view/like counts.
/// Replying opens the poster's DM: an existing direct conversation is reused,
/// otherwise one is created — then the reply text is sent immediately.
///
/// Surfaces:
///   [ChatStatusRail]     — horizontal avatars row above the chat list
///   [showStatusComposer] — bottom sheet: text + palette + optional image
///   [StatusViewerScreen] — full-screen pager with progress bars + actions

/// The palette the backend accepts (mirrors BG_COLORS in statuses.ts).
const List<String> kStatusPalette = [
  '#1E3A8A', '#7C2D12', '#065F46', '#4C1D95', '#9D174D',
  '#0E7490', '#B45309', '#374151', '#B91C1C', '#1D4ED8',
];

Color statusColorFromHex(String hex, [Color fallback = const Color(0xFF1E3A8A)]) {
  final cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length != 6) return fallback;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return fallback;
  return Color(0xFF000000 | value);
}

class ChatStatusData {
  final String id;
  final String userId;
  final String authorName;
  final String? authorAvatar;
  final String? content;
  final String? mediaUrl;
  final String? mediaType;
  final String backgroundColor;
  final String? repostAuthor;
  final DateTime createdAt;
  final bool isMine;
  bool viewed;
  bool liked;
  int viewsCount;
  int likesCount;

  ChatStatusData({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.backgroundColor,
    required this.isMine,
    required this.viewed,
    required this.liked,
    required this.viewsCount,
    required this.likesCount,
    this.authorAvatar,
    this.content,
    this.mediaUrl,
    this.mediaType,
    this.repostAuthor,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ChatStatusData.fromJson(Map<String, dynamic> j) {
    return ChatStatusData(
      id: (j['id'] ?? '').toString(),
      userId: (j['userId'] ?? j['user_id'] ?? '').toString(),
      authorName: (j['authorName'] ?? j['author_name'] ?? 'Teammate').toString(),
      authorAvatar: j['authorAvatar']?.toString(),
      content: j['content']?.toString(),
      mediaUrl: j['mediaUrl']?.toString(),
      mediaType: j['mediaType']?.toString(),
      backgroundColor: (j['backgroundColor'] ?? '#1E3A8A').toString(),
      repostAuthor: j['repostAuthor']?.toString(),
      createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()) ?? DateTime.now(),
      isMine: j['isMine'] == true,
      viewed: j['viewed'] == true,
      liked: j['liked'] == true,
      viewsCount: (j['viewsCount'] as num?)?.toInt() ?? 0,
      likesCount: (j['likesCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatStatusGroup {
  final String userId;
  final String authorName;
  final String? authorAvatar;
  final bool isMine;
  bool allViewed = true;
  final List<ChatStatusData> statuses = [];

  ChatStatusGroup({
    required this.userId,
    required this.authorName,
    required this.isMine,
    this.authorAvatar,
  });
}

/// Group rows by author: mine first, then unseen authors, newest first.
List<ChatStatusGroup> groupStatuses(List<ChatStatusData> rows) {
  final map = <String, ChatStatusGroup>{};
  for (final s in rows) {
    final g = map.putIfAbsent(
      s.userId,
      () => ChatStatusGroup(
        userId: s.userId,
        authorName: s.authorName,
        isMine: s.isMine,
        authorAvatar: s.authorAvatar,
      ),
    );
    g.statuses.add(s);
    if (!s.viewed) g.allViewed = false;
  }
  final groups = map.values.toList();
  groups.sort((a, b) {
    if (a.isMine != b.isMine) return a.isMine ? -1 : 1;
    if (a.allViewed != b.allViewed) return a.allViewed ? 1 : -1;
    return b.statuses.first.createdAt.compareTo(a.statuses.first.createdAt);
  });
  for (final g in groups) {
    g.statuses.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
  return groups;
}

Future<List<ChatStatusData>> loadStatuses() async {
  final rows = await ApiService().listStatuses();
  return rows.map(ChatStatusData.fromJson).toList();
}

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

// ---------------------------------------------------------------------------
// RAIL
// ---------------------------------------------------------------------------

/// Horizontal status rail shown above the chat list. Pulls to refresh of the
/// chat screen also refreshes this rail (via [refreshKey]).
class ChatStatusRail extends ConsumerStatefulWidget {
  const ChatStatusRail({super.key, this.refreshKey = 0});

  /// Bump to force a refetch (e.g. after the composer posts or the viewer closes).
  final int refreshKey;

  @override
  ConsumerState<ChatStatusRail> createState() => _ChatStatusRailState();
}

class _ChatStatusRailState extends ConsumerState<ChatStatusRail> {
  List<ChatStatusGroup>? _groups;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ChatStatusRail old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await loadStatuses();
      if (!mounted) return;
      setState(() {
        _groups = groupStatuses(rows);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openComposer() async {
    await showStatusComposer(context);
    _load();
  }

  void _openViewer(ChatStatusGroup group) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StatusViewerScreen(
        initialGroupIndex: _groups!.indexOf(group),
        groups: _groups!,
        onChanged: _load,
      ),
      fullscreenDialog: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final myName = (auth.userName ?? 'Me').trim();
    final myId = auth.userId ?? '';
    final myGroup = (_groups ?? []).where((g) => g.isMine || g.userId == myId).toList();

    Widget content;
    if (_loading) {
      content = const SizedBox(
        height: 84,
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    } else {
      final groups = myGroup;
      content = SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            // MY STATUS — tap opens the viewer when I have statuses,
            // otherwise the composer.
            _StatusAvatar(
              name: myName.isEmpty ? 'Me' : myName,
              avatarUrl: auth.avatarUrl,
              ringSeen: groups.isNotEmpty && groups.first.allViewed,
              hasStatus: groups.isNotEmpty,
              isMine: true,
              onTap: () {
                if (groups.isNotEmpty) {
                  _openViewer(groups.first);
                } else {
                  _openComposer();
                }
              },
            ),
            // OTHERS
            ...groups.where((g) => !g.isMine).map(
                  (g) => _StatusAvatar(
                    name: g.authorName,
                    avatarUrl: g.authorAvatar != null
                        ? ApiService.resolveMediaUrl(g.authorAvatar)
                        : null,
                    ringSeen: g.allViewed,
                    hasStatus: true,
                    isMine: false,
                    onTap: () => _openViewer(g),
                  ),
                ),
          ],
        ),
      );
    }
    return content;
  }
}

class _StatusAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool ringSeen;
  final bool hasStatus;
  final bool isMine;
  final VoidCallback onTap;

  const _StatusAvatar({
    required this.name,
    required this.ringSeen,
    required this.hasStatus,
    required this.isMine,
    required this.onTap,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final ring = hasStatus
        ? (ringSeen ? colors.borderVariant : Colors.green)
        : colors.borderVariant;
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ring, width: hasStatus ? 2.4 : 1.4),
                    ),
                    padding: const EdgeInsets.all(2.4),
                    child: ClipOval(
                      child: (avatarUrl != null && avatarUrl!.isNotEmpty)
                          ? CachedNetworkImage(imageUrl: avatarUrl!, fit: BoxFit.cover)
                          : Container(
                              color: colors.surfaceVariant,
                              alignment: Alignment.center,
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (isMine && !hasStatus)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primary,
                          border: Border.all(color: colors.background, width: 2),
                        ),
                        child: const Icon(Icons.add, size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                isMine ? 'My status' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// COMPOSER
// ---------------------------------------------------------------------------

/// Compose a new status: text (≤700 chars) on a palette background, with an
/// optional image. Posts via POST /statuses. Returns when done (the rail
/// refreshes itself afterwards).
Future<void> showStatusComposer(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _StatusComposerSheet(),
  );
}

class _StatusComposerSheet extends ConsumerStatefulWidget {
  const _StatusComposerSheet();

  @override
  ConsumerState<_StatusComposerSheet> createState() => _StatusComposerSheetState();
}

class _StatusComposerSheetState extends ConsumerState<_StatusComposerSheet> {
  final TextEditingController _text = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  int _bgIndex = 0;
  String? _mediaUrl;
  bool _uploading = false;
  bool _posting = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 82, maxWidth: 1600);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final url = await ApiService().uploadChatMedia(File(picked.path));
      if (!mounted) return;
      setState(() {
        _mediaUrl = url;
        _uploading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      AppToast.show('Could not upload the image', type: AppToastType.error);
    }
  }

  Future<void> _post() async {
    final text = _text.text.trim();
    if (text.isEmpty && (_mediaUrl == null || _mediaUrl!.isEmpty)) return;
    if (text.length > 700) {
      AppToast.show('Status text is too long (max 700 characters)', type: AppToastType.error);
      return;
    }
    setState(() => _posting = true);
    try {
      await ApiService().createStatus(
        content: text.isEmpty ? null : text,
        mediaUrl: _mediaUrl,
        mediaType: (_mediaUrl != null && _mediaUrl!.isNotEmpty) ? 'image' : null,
        backgroundColor: kStatusPalette[_bgIndex],
      );
      if (!mounted) return;
      AppFeedback.playStatusPublishedSound();
      Navigator.of(context).pop();
      AppToast.show('Status posted');
    } catch (_) {
      if (!mounted) return;
      setState(() => _posting = false);
      AppToast.show('Could not post the status', type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final bg = statusColorFromHex(kStatusPalette[_bgIndex]);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('New status',
                      style: TextStyle(
                          color: colors.text, fontSize: 16, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: Icon(Icons.close_rounded, size: 18, color: colors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              // Preview card
              Container(
                height: 170,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _mediaUrl == null ? bg : colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(14),
                child: (_mediaUrl != null && _mediaUrl!.isNotEmpty)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: ApiService.resolveMediaUrl(_mediaUrl)!,
                          fit: BoxFit.contain,
                          height: 150,
                        ),
                      )
                    : TextField(
                        controller: _text,
                        maxLength: 700,
                        maxLines: 4,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          hintText: "What's on your mind?",
                          hintStyle: TextStyle(color: Colors.white60),
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              if (_mediaUrl == null)
                SizedBox(
                  height: 30,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kStatusPalette.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => setState(() => _bgIndex = i),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: statusColorFromHex(kStatusPalette[i]),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _bgIndex == i ? colors.text : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: (_uploading || _posting) ? null : _pickImage,
                    icon: _uploading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.image_outlined, size: 18),
                    label: Text(_mediaUrl == null ? 'Add image' : 'Replace image',
                        style: const TextStyle(fontSize: 13)),
                  ),
                  if (_mediaUrl != null)
                    TextButton(
                      onPressed: () => setState(() => _mediaUrl = null),
                      child: const Text('Remove image', style: TextStyle(fontSize: 13)),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _posting
                        ? null
                        : ((_text.text.trim().isNotEmpty || (_mediaUrl != null && _mediaUrl!.isNotEmpty))
                            ? _post
                            : null),
                    child: _posting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Post', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VIEWER
// ---------------------------------------------------------------------------

/// Full-screen story viewer: pages through every group's statuses with
/// auto-advance progress bars, records views, and offers Like / Reply / Repost
/// for others and Views/Likes/Delete for your own.
class StatusViewerScreen extends ConsumerStatefulWidget {
  const StatusViewerScreen({
    super.key,
    required this.groups,
    required this.initialGroupIndex,
    this.onChanged,
  });

  final List<ChatStatusGroup> groups;
  final int initialGroupIndex;

  /// Called when the viewer closes (so the rail refreshes).
  final VoidCallback? onChanged;

  @override
  ConsumerState<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends ConsumerState<StatusViewerScreen> {
  static const _slideDuration = Duration(seconds: 7);

  late final PageController _pageController;
  Timer? _advanceTimer;
  int _groupIndex = 0;
  int _slideIndex = 0;
  bool _deleting = false;

  ChatStatusGroup get _group => widget.groups[_groupIndex];
  ChatStatusData get _status => _group.statuses[_slideIndex];

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex.clamp(0, widget.groups.length - 1);
    _pageController = PageController(initialPage: _groupIndex);
    _markViewed();
    _scheduleNext();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _scheduleNext() {
    _advanceTimer?.cancel();
    _advanceTimer = Timer(_slideDuration, () {
      if (!mounted) return;
      _goNext();
    });
  }

  void _goNext() {
    if (_slideIndex + 1 < _group.statuses.length) {
      setState(() => _slideIndex += 1);
      _markViewed();
      _scheduleNext();
    } else if (_groupIndex + 1 < widget.groups.length) {
      _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _goPrev() {
    if (_slideIndex > 0) {
      setState(() => _slideIndex -= 1);
      _scheduleNext();
    } else if (_groupIndex > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _onGroupChanged(int newIndex) {
    _advanceTimer?.cancel();
    setState(() {
      _groupIndex = newIndex;
      _slideIndex = 0;
    });
    _markViewed();
    _scheduleNext();
  }

  Future<void> _markViewed() async {
    final s = _status;
    if (s.isMine || s.viewed) return;
    s.viewed = true;
    try {
      final res = await ApiService().viewStatus(s.id);
      final data = res.data is Map ? res.data['data'] : null;
      final views = data is Map && data['viewsCount'] is num ? (data['viewsCount'] as num).toInt() : null;
      if (!mounted) return;
      setState(() {
        if (views != null) s.viewsCount = views;
      });
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final s = _status;
    if (s.isMine) return;
    final wasLiked = s.liked;
    final wasCount = s.likesCount;
    setState(() {
      s.liked = !wasLiked;
      s.likesCount = wasCount + (wasLiked ? -1 : 1);
    });
    try {
      // likeStatus already unwraps response.data.data ({ liked, likesCount }).
      final data = await ApiService().likeStatus(s.id);
      if (!mounted || data == null) return;
      setState(() {
        s.liked = data['liked'] == true;
        if (data['likesCount'] is num) s.likesCount = (data['likesCount'] as num).toInt();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        s.liked = wasLiked;
        s.likesCount = wasCount;
      });
      AppToast.show('Could not update the like', type: AppToastType.error);
    }
  }

  Future<void> _repost() async {
    final s = _status;
    try {
      await ApiService().repostStatus(s.id);
      if (!mounted) return;
      AppToast.show('Status reposted to your rail');
      Navigator.of(context).pop();
    } catch (e) {
      final msg = e.toString();
      AppToast.show(
        msg.contains('own status') ? 'This is your own status' : 'Repost failed',
        type: AppToastType.error,
      );
    }
  }

  Future<void> _delete() async {
    if (_deleting) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete status'),
        content: const Text('This status disappears for everyone. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _deleting = true);
    try {
      await ApiService().deleteStatus(_status.id);
      if (!mounted) return;
      AppToast.show('Status deleted');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      AppToast.show('Delete failed', type: AppToastType.error);
    }
  }

  /// Reply: type a message → the DM with the author opens/gets created and
  /// the reply is sent immediately (WhatsApp parity for status replies).
  Future<void> _reply() async {
    final authorId = _group.userId;
    final controller = TextEditingController(
      text: _status.content == null || _status.content!.isEmpty
          ? 'Nice status!'
          : 'Replied to your status',
    );
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reply to ${_group.authorName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Your message'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Send')),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    try {
      // Find an existing direct conversation with the author.
      final convs = await ApiService().getConversations();
      final data = convs.data is Map ? convs.data['data'] : null;
      final list = data is Map && data['conversations'] is List
          ? data['conversations'] as List
          : (data is List ? data : const []);
      Map<String, dynamic>? dm;
      for (final c in list) {
        final map = Map<String, dynamic>.from(c as Map);
        if ((map['type'] ?? '').toString() != 'direct') continue;
        final participants = map['participants'];
        final ids = participants is List
            ? participants
                .whereType<Map>()
                .map((p) => (p['userId'] ?? p['user_id'] ?? '').toString())
                .toSet()
            : <String>{};
        if (ids.contains(authorId)) {
          dm = map;
          break;
        }
      }
      String? conversationId = dm != null ? (dm['id'] ?? '').toString() : null;
      conversationId = conversationId!.isEmpty ? null : conversationId;
      if (conversationId == null) {
        final created = await ApiService()
            .createConversation({'name': '', 'type': 'direct', 'participantIds': [authorId]});
        final cdata = created.data is Map ? created.data['data'] : created.data;
        conversationId = (cdata is Map ? cdata['id'] : null)?.toString();
        if (conversationId == null || conversationId.isEmpty) {
          throw Exception('Could not open the conversation');
        }
      }
      await ApiService().sendMessage(conversationId, {
        'content': text,
        'messageType': 'text',
      });
      if (!mounted) return;
      AppToast.show('Reply sent to ${_group.authorName}');
    } catch (_) {
      if (!mounted) return;
      AppToast.show('Reply failed — try again', type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final s = _status;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.groups.length,
          onPageChanged: _onGroupChanged,
          itemBuilder: (context, gi) {
            final group = widget.groups[gi];
            final slide = group.statuses[_slideIndex.clamp(0, group.statuses.length - 1)];
            return _buildGroupPage(group, slide);
          },
        ),
      ),
    );
  }

  Widget _buildGroupPage(ChatStatusGroup group, ChatStatusData s) {
    return Column(
      children: [
        // Progress bars
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: List.generate(group.statuses.length, (i) {
              return Expanded(
                child: Container(
                  height: 2.5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: i < _slideIndex
                          ? 1
                          : i == _slideIndex
                              ? 1 // active fills via Timer animation below
                              : 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: i <= _slideIndex ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white24,
                backgroundImage: (group.authorAvatar != null &&
                        group.authorAvatar!.isNotEmpty)
                    ? CachedNetworkImageProvider(
                        ApiService.resolveMediaUrl(group.authorAvatar)!)
                    : null,
                child: (group.authorAvatar == null || group.authorAvatar!.isEmpty)
                    ? Text(group.authorName.isNotEmpty ? group.authorName[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.isMine ? 'My status' : group.authorName,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                    Text('${_timeAgo(s.createdAt)} · expires ${_timeAgo(s.createdAt.add(const Duration(hours: 24)))}',
                        style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        // Body
        Expanded(
          child: GestureDetector(
            onTapUp: (d) {
              final w = MediaQuery.of(context).size.width;
              if (d.localPosition.dx < w * 0.3) {
                _goPrev();
              } else if (d.localPosition.dx > w * 0.7) {
                _goNext();
              }
            },
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: s.mediaUrl == null
                    ? statusColorFromHex(s.backgroundColor)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(18),
              child: (s.mediaUrl != null && s.mediaUrl!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: ApiService.resolveMediaUrl(s.mediaUrl)!,
                      fit: BoxFit.contain,
                    )
                  : SingleChildScrollView(
                      child: Text(
                        s.content ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.45,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        // Actions
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: s.isMine
                ? Row(
                    children: [
                      _pillButton(
                        icon: Icons.remove_red_eye_outlined,
                        label: '${s.viewsCount} views',
                        onTap: null,
                      ),
                      const SizedBox(width: 8),
                      _pillButton(
                        icon: Icons.favorite,
                        label: '${s.likesCount}',
                        iconColor: s.likesCount > 0 ? Colors.redAccent : Colors.white,
                        onTap: null,
                      ),
                      const Spacer(),
                      _pillButton(
                        icon: _deleting ? Icons.hourglass_empty : Icons.delete_outline,
                        label: 'Delete',
                        onTap: _deleting ? null : _delete,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      _pillButton(
                        icon: s.liked ? Icons.favorite : Icons.favorite_border,
                        label: s.liked ? 'Liked' : 'Like',
                        iconColor: s.liked ? Colors.redAccent : Colors.white,
                        onTap: _toggleLike,
                      ),
                      const SizedBox(width: 8),
                      _pillButton(icon: Icons.reply_outlined, label: 'Reply', onTap: _reply),
                      const SizedBox(width: 8),
                      _pillButton(icon: Icons.repeat_rounded, label: 'Repost', onTap: _repost),
                      const Spacer(),
                      Text('${s.viewsCount}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color iconColor = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
