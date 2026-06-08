import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api.dart';
import '../models/idea.dart';
import '../theme/app_theme.dart';

class IdeasScreen extends ConsumerStatefulWidget {
  const IdeasScreen({super.key});

  @override
  ConsumerState<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends ConsumerState<IdeasScreen> {
  List<Idea> _ideas = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isGeneratingDoc = false;
  bool _isFetchingDocs = false;
  Idea? _selectedIdea;
  List<dynamic> _docs = [];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchIdeas();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
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
          setState(() {
            _ideas = (data['data'] as List)
                .map((i) => Idea.fromJson(i as Map<String, dynamic>))
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch ideas: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleCreateIdea() async {
    if (_titleController.text.isEmpty || _descController.text.isEmpty) {
      Fluttertoast.showToast(msg: 'Please fill all fields');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final api = ApiService();
      await api.createIdea({
        'title': _titleController.text,
        'description': _descController.text,
      });
      setState(() {
        _titleController.clear();
        _descController.clear();
      });
      await _fetchIdeas();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Create idea error: $e');
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleOpenDocumentation(Idea idea) async {
    setState(() {
      _selectedIdea = idea;
      _isFetchingDocs = true;
    });
    try {
      final api = ApiService();
      final response = await api.getDocumentation(idea.id);
      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          _docs = data['data'] ?? [];
          _isFetchingDocs = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch documentation: $e');
      setState(() => _isFetchingDocs = false);
    }
  }

  Future<void> _handleGenerateDocumentation() async {
    if (_selectedIdea == null) return;
    setState(() => _isGeneratingDoc = true);
    try {
      final api = ApiService();
      await api.generateDocumentation(_selectedIdea!.id);
      await _handleOpenDocumentation(_selectedIdea!);
    } catch (e) {
      debugPrint('Generate documentation error: $e');
    } finally {
      setState(() => _isGeneratingDoc = false);
    }
  }

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
      builder: (context) => _CreateIdeaModal(
        titleController: _titleController,
        descController: _descController,
        onSubmit: _handleCreateIdea,
        isSubmitting: _isSubmitting,
      ),
    );
  }

  void _showDocModal(Idea idea) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DocModal(
        idea: idea,
        docs: _docs,
        isFetchingDocs: _isFetchingDocs,
        isGeneratingDoc: _isGeneratingDoc,
        onGenerate: _handleGenerateDocumentation,
      ),
    ).then((_) {
      setState(() {
        _selectedIdea = null;
        _docs = [];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => _fetchIdeas(showLoader: false),
                      child: _ideas.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.all(24),
                              children: [
                                const SizedBox(height: 80),
                                Icon(Icons.lightbulb_outline, size: 64, color: AppTheme.colors.textSecondary),
                                const SizedBox(height: 16),
                                Text(
                                  'No ideas yet. Be the first to suggest one!',
                                  style: TextStyle(fontSize: 16, color: AppTheme.colors.textSecondary),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(24),
                              itemCount: _ideas.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 16),
                              itemBuilder: (context, index) {
                                final idea = _ideas[index];
                                return _IdeaCard(
                                  idea: idea,
                                  statusColor: _getStatusColor(idea.status),
                                  onTap: () => context.go('/main/idea-detail', extra: idea),
                                  onDocTap: () async {
                                    await _handleOpenDocumentation(idea);
                                    if (mounted) _showDocModal(idea);
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateIdeaModal,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/main'),
          ),
          const Expanded(
            child: Text(
              'Ideas',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateIdeaModal extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController descController;
  final VoidCallback onSubmit;
  final bool isSubmitting;

  const _CreateIdeaModal({
    required this.titleController,
    required this.descController,
    required this.onSubmit,
    required this.isSubmitting,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Suggest an Idea',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: titleController,
            decoration: InputDecoration(
              hintText: 'Title',
              hintStyle: TextStyle(color: AppTheme.colors.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppTheme.colors.border),
              ),
              filled: true,
              fillColor: AppTheme.colors.surface,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: descController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Description',
              hintStyle: TextStyle(color: AppTheme.colors.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppTheme.colors.border),
              ),
              filled: true,
              fillColor: AppTheme.colors.surface,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isSubmitting ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'Submit Idea',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocModal extends StatefulWidget {
  final Idea idea;
  final List<dynamic> docs;
  final bool isFetchingDocs;
  final bool isGeneratingDoc;
  final VoidCallback onGenerate;

  const _DocModal({
    required this.idea,
    required this.docs,
    required this.isFetchingDocs,
    required this.isGeneratingDoc,
    required this.onGenerate,
  });

  @override
  State<_DocModal> createState() => _DocModalState();
}

class _DocModalState extends State<_DocModal> {
  final Map<int, bool> _expandedDocs = {};
  static const int _maxLines = 8;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppTheme.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Documentation',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.idea.title,
                        style: TextStyle(fontSize: 14, color: AppTheme.colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget.isFetchingDocs
                ? const Center(child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(),
                  ))
                : widget.docs.isNotEmpty
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: widget.docs.length,
                        itemBuilder: (context, index) {
                          final doc = widget.docs[index];
                          final isExpanded = _expandedDocs[index] ?? false;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppTheme.colors.background,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.colors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc['title'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  doc['content'] ?? '',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: AppTheme.colors.textSecondary,
                                    height: 1.6,
                                  ),
                                  maxLines: isExpanded ? null : _maxLines,
                                  overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => setState(() => _expandedDocs[index] = !isExpanded),
                                      child: Text(isExpanded ? 'Read Less' : 'Read More', style: const TextStyle(color: AppColors.primary)),
                                    ),
                                    const Spacer(),
                                    Text(
                                      doc['createdAt'] != null ? DateTime.tryParse(doc['createdAt'])?.toLocal().toString().split(' ')[0] ?? '' : '',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    IconButton(
                                      onPressed: () => SharePlus.instance.share(
                                        ShareParams(
                                          title: doc['title'] ?? widget.idea.title,
                                          text: '${doc['title'] ?? widget.idea.title}\n\n${doc['content'] ?? ''}',
                                        ),
                                      ),
                                      icon: const Icon(Icons.share_outlined, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(vertical: 60),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Icon(Icons.description_outlined, size: 64, color: AppTheme.colors.textSecondary),
                            const SizedBox(height: 16),
                            Text(
                              'No documentation generated for this idea yet.',
                              style: TextStyle(color: AppTheme.colors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.isGeneratingDoc ? null : widget.onGenerate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: widget.isGeneratingDoc
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        widget.docs.isNotEmpty ? 'Regenerate Documentation' : 'Generate Documentation',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  final Idea idea;
  final Color statusColor;
  final VoidCallback onTap;
  final VoidCallback onDocTap;

  const _IdeaCard({
    required this.idea,
    required this.statusColor,
    required this.onTap,
    required this.onDocTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    idea.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    idea.status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              idea.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: onDocTap,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.description_outlined, size: 16, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text(
                      'Product Documentation',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'By ${idea.userName ?? 'Anonymous'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  DateTime.tryParse(idea.createdAt)?.toLocal().toString().split(' ')[0] ?? idea.createdAt,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
