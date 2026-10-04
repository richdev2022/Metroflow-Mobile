import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api.dart';
import '../models/idea.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/modern_ui.dart';

/// Ideas — redesigned on the shared [modern_ui] design system:
/// gradient hero header, tappable stat tiles, search + status filters +
/// sorting, shimmer skeletons and friendly empty states. All API flows
/// and navigation routes are unchanged.
class IdeasScreen extends ConsumerStatefulWidget {
  const IdeasScreen({super.key});

  @override
  ConsumerState<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends ConsumerState<IdeasScreen> {
  List<Idea> _ideas = [];
  bool _isLoading = true;

  // Search / filter / sort state.
  String _query = '';
  String _statusFilter = 'all'; // all | under_review | executed | rejected
  String _sortKey = 'newest'; // newest | oldest | title

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchIdeas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchIdeas({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final response = await api.getIdeas();
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true && data['data'] != null) {
          if (!mounted) return;
          setState(() {
            _ideas = (data['data'] as List)
                .map((i) => Idea.fromJson(i as Map<String, dynamic>))
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch ideas: $e');
      if (mounted) {
        AppToast.show('Failed to load ideas — pull down to retry.',
            type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Idea> get _visibleIdeas {
    final q = _query.trim().toLowerCase();
    final list = _ideas.where((i) {
      if (_statusFilter != 'all' && i.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return i.title.toLowerCase().contains(q) ||
          i.description.toLowerCase().contains(q) ||
          (i.userName ?? '').toLowerCase().contains(q);
    }).toList();
    int ts(Idea i) =>
        DateTime.tryParse(i.createdAt)?.millisecondsSinceEpoch ?? 0;
    list.sort((a, b) {
      switch (_sortKey) {
        case 'title':
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'oldest':
          return ts(a).compareTo(ts(b));
        default:
          return ts(b).compareTo(ts(a));
      }
    });
    return list;
  }

  int _countByStatus(String status) =>
      _ideas.where((i) => i.status == status).length;

  Color _getStatusColor(String status) {
    switch (status) {
      case 'executed':
        return AppColors.success;
      case 'under_review':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      default:
        return AppTheme.colors.textSecondary;
    }
  }

  void _showCreateIdeaModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _CreateIdeaModal(),
    ).then((created) {
      if (created == true) _fetchIdeas(showLoader: false);
    });
  }

  void _showDocModal(Idea idea) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DocModal(idea: idea),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _SortSheet(
        current: _sortKey,
        onSelected: (key) => setState(() => _sortKey = key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [
                  ShimmerBox(height: 148, radius: 24),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: SkeletonCard(height: 96)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonCard(height: 96)),
                    ],
                  ),
                  SizedBox(height: 6),
                  ShimmerBox(height: 48, radius: 16),
                  SizedBox(height: 16),
                  SkeletonCard(height: 190),
                  SkeletonCard(height: 190),
                  SkeletonCard(height: 190),
                ],
              )
            : RefreshIndicator(
                color: colors.primary,
                onRefresh: () => _fetchIdeas(showLoader: false),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    _buildHero(),
                    if (_ideas.isNotEmpty) ...[
                      _buildStats(),
                      _buildToolbar(),
                    ],
                    if (_ideas.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 56),
                        child: EmptyState(
                          icon: Icons.lightbulb_outline,
                          title: 'No ideas yet',
                          subtitle:
                              'Every great product started as an idea. Capture your first one and share it with your team.',
                          actionLabel: 'Suggest an Idea',
                          onAction: _showCreateIdeaModal,
                        ),
                      )
                    else if (_visibleIdeas.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 56),
                        child: EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No matching ideas',
                          subtitle:
                              'Nothing matches your search or filters. Try different keywords or clear the filters.',
                          actionLabel: 'Clear filters',
                          onAction: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                              _statusFilter = 'all';
                            });
                          },
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Column(
                          children: [
                            for (final idea in _visibleIdeas)
                              _IdeaCard(
                                idea: idea,
                                statusColor: _getStatusColor(idea.status),
                                statusLabel: _statusLabel(idea.status),
                                onTap: () =>
                                    context.go('/main/idea-detail', extra: idea),
                                onDocTap: () => _showDocModal(idea),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      floatingActionButton: ModernFab(
        icon: Icons.add,
        label: 'New Idea',
        onPressed: _showCreateIdeaModal,
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'executed':
        return 'Executed';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Under review';
    }
  }

  Widget _buildHero() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
      decoration: BoxDecoration(
        gradient: BrandGradient.deep,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HeroIconButton(
                icon: Icons.arrow_back,
                onTap: () => context.go('/main'),
              ),
              const Spacer(),
              _HeroIconButton(
                icon: Icons.refresh_rounded,
                onTap: () => _fetchIdeas(showLoader: false),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: const Icon(
                  Icons.lightbulb_rounded,
                  color: Color(0xFFFDE68A),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ideas',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Capture sparks and track them to execution.',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final tiles = <(String, IconData, Color, String)>[
      ('all', Icons.all_inclusive_rounded, AppColors.primary, 'All ideas'),
      (
        'under_review',
        Icons.hourglass_top_rounded,
        AppColors.warning,
        'Under review'
      ),
      ('executed', Icons.check_circle_rounded, AppColors.success, 'Executed'),
      ('rejected', Icons.cancel_rounded, AppColors.error, 'Rejected'),
    ];
    return SizedBox(
      height: 118,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final (key, icon, tint, label) = tiles[index];
          final value = key == 'all' ? _ideas.length : _countByStatus(key);
          return StatCard(
            icon: icon,
            label: label,
            value: '$value',
            tint: tint,
            onTap: () => setState(() => _statusFilter = key),
          );
        },
      ),
    );
  }

  Widget _buildToolbar() {
    final colors = AppTheme.colors;
    final chips = <(String, String, IconData?)>[
      ('all', 'All', null),
      ('under_review', 'Under review', Icons.hourglass_top_rounded),
      ('executed', 'Executed', Icons.check_circle_rounded),
      ('rejected', 'Rejected', Icons.cancel_rounded),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ModernSearchField(
                  controller: _searchController,
                  hintText: 'Search ideas…',
                  onChanged: (v) => setState(() => _query = v),
                  onClear: _query.isEmpty
                      ? null
                      : () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _showSortSheet,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(
                    Icons.sort_rounded,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final (key, label, icon) = chips[index];
                return ModernFilterChip(
                  label: label,
                  icon: icon,
                  selected: _statusFilter == key,
                  onTap: () => setState(() => _statusFilter = key),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Small circular glass button used inside the gradient hero.
class _HeroIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeroIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white24),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

/// Modern idea card: accent strip, status badge, doc row, author footer.
class _IdeaCard extends StatelessWidget {
  final Idea idea;
  final Color statusColor;
  final String statusLabel;
  final VoidCallback onTap;
  final VoidCallback onDocTap;

  const _IdeaCard({
    required this.idea,
    required this.statusColor,
    required this.statusLabel,
    required this.onTap,
    required this.onDocTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final date = DateTime.tryParse(idea.createdAt);
    final dateLabel = date != null ? DateFormat('d MMM y').format(date) : '';
    return ModernCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status accent strip.
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [statusColor, statusColor.withValues(alpha: 0.35)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TintedCircleIcon(
                      icon: Icons.lightbulb_rounded,
                      tint: statusColor,
                      size: 38,
                      iconSize: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        idea.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ModernBadge(
                      label: statusLabel,
                      color: statusColor,
                    ),
                  ],
                ),
                if (idea.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    idea.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: onDocTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Product Documentation',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.primary.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: colors.border),
                const SizedBox(height: 12),
                Row(
                  children: [
                    AvatarInitials(
                      name: idea.userName ?? 'Anonymous',
                      radius: 12,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'By ${idea.userName ?? 'Anonymous'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    if (dateLabel.isNotEmpty)
                      Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sorting options bottom sheet.
class _SortSheet extends StatelessWidget {
  final String current;
  final ValueChanged<String> onSelected;

  const _SortSheet({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final options = <(String, String, IconData)>[
      ('newest', 'Newest first', Icons.schedule_rounded),
      ('oldest', 'Oldest first', Icons.history_rounded),
      ('title', 'Title A–Z', Icons.sort_by_alpha_rounded),
    ];
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            for (final (key, label, icon) in options)
              ListTile(
                leading: Icon(
                  icon,
                  color: current == key ? colors.primary : colors.textSecondary,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    color: current == key ? colors.primary : colors.text,
                    fontWeight:
                        current == key ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                trailing: current == key
                    ? Icon(Icons.check_rounded, color: colors.primary)
                    : null,
                onTap: () {
                  onSelected(key);
                  Navigator.of(context).pop();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Create-idea bottom sheet. Owns its controllers + submitting state so the
/// progress indicator actually rebuilds (the old shared-parent version never
/// re-rendered the spinner because the sheet is a separate route).
class _CreateIdeaModal extends StatefulWidget {
  const _CreateIdeaModal();

  @override
  State<_CreateIdeaModal> createState() => _CreateIdeaModalState();
}

class _CreateIdeaModalState extends State<_CreateIdeaModal> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty ||
        _descController.text.trim().isEmpty) {
      AppToast.show('Please fill in a title and description.',
          type: AppToastType.warning);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final api = ApiService();
      await api.createIdea({
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppToast.show('Idea submitted — it is now under review.',
          type: AppToastType.success);
    } catch (e) {
      debugPrint('Create idea error: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppToast.show(ApiService.extractErrorMessage(e),
            type: AppToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: BrandGradient.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.30),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.lightbulb_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Suggest an Idea',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded,
                        color: colors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Give it a clear title and enough detail for your team to run with it.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleController,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: colors.text, fontSize: 15),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Idea title *',
                  hintStyle: TextStyle(color: colors.textSecondary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.6,
                    ),
                  ),
                  filled: true,
                  fillColor: colors.background,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descController,
                maxLines: 5,
                minLines: 3,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: colors.text, fontSize: 15, height: 1.5),
                decoration: InputDecoration(
                  counterText: '',
                  hintText:
                      "What's the idea? Who is it for and what problem does it solve?",
                  hintStyle: TextStyle(color: colors.textSecondary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.6,
                    ),
                  ),
                  filled: true,
                  fillColor: colors.background,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.4,
                          ),
                        )
                      : const Text(
                          'Submit Idea',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Product-documentation bottom sheet. Owns fetching + generating so the
/// spinners rebuild correctly (previously driven by unrefreshed parent state).
class _DocModal extends StatefulWidget {
  final Idea idea;

  const _DocModal({required this.idea});

  @override
  State<_DocModal> createState() => _DocModalState();
}

class _DocModalState extends State<_DocModal> {
  List<dynamic> _docs = [];
  bool _isFetching = true;
  bool _isGenerating = false;
  final Map<int, bool> _expandedDocs = {};
  static const int _maxLines = 8;

  @override
  void initState() {
    super.initState();
    _fetchDocs();
  }

  Future<void> _fetchDocs() async {
    setState(() => _isFetching = true);
    try {
      final api = ApiService();
      final response = await api.getDocumentation(widget.idea.id);
      if (response.statusCode == 200 && mounted) {
        setState(() => _docs = response.data['data'] ?? []);
      }
    } catch (e) {
      debugPrint('Failed to fetch documentation: $e');
      if (mounted) {
        AppToast.show('Failed to load documentation.', type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  Future<void> _generate() async {
    setState(() => _isGenerating = true);
    try {
      final api = ApiService();
      await api.generateDocumentation(widget.idea.id);
      await _fetchDocs();
      if (mounted) AppToast.show('Documentation ready.', type: AppToastType.success);
    } catch (e) {
      debugPrint('Generate documentation error: $e');
      if (mounted) {
        AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: BrandGradient.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Documentation',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Text(
                          widget.idea.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          Flexible(
            child: _isFetching
                ? ListView(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: const [
                      SkeletonCard(height: 150),
                      SkeletonCard(height: 150),
                    ],
                  )
                : _docs.isNotEmpty
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        itemCount: _docs.length,
                        itemBuilder: (context, index) {
                          final doc = _docs[index];
                          final isExpanded = _expandedDocs[index] ?? false;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: colors.background,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: colors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        doc['title'] ?? '',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: colors.text,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => SharePlus.instance.share(
                                        ShareParams(
                                          title: doc['title'] ??
                                              widget.idea.title,
                                          text:
                                              '${doc['title'] ?? widget.idea.title}\n\n${doc['content'] ?? ''}',
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.share_outlined,
                                        size: 19,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  doc['content'] ?? '',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.textSecondary,
                                    height: 1.6,
                                  ),
                                  maxLines:
                                      isExpanded ? null : _maxLines,
                                  overflow: isExpanded
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => setState(() =>
                                          _expandedDocs[index] = !isExpanded),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6),
                                        minimumSize: const Size(0, 32),
                                      ),
                                      child: Text(
                                        isExpanded ? 'Read Less' : 'Read More',
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      doc['createdAt'] != null
                                          ? DateTime.tryParse(doc['createdAt'])
                                                  ?.toLocal()
                                                  .toString()
                                                  .split(' ')[0] ??
                                              ''
                                          : '',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: EmptyState(
                          icon: Icons.description_outlined,
                          title: 'No documentation yet',
                          subtitle:
                              'Generate AI documentation for this idea with one tap below.',
                        ),
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isGenerating ? null : _generate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isGenerating
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _docs.isNotEmpty
                                ? Icons.refresh_rounded
                                : Icons.auto_awesome_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _docs.isNotEmpty
                                ? 'Regenerate Documentation'
                                : 'Generate with AI',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
