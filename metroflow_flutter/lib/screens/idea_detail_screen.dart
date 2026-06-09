import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import '../services/api.dart';
import '../models/idea.dart';
import '../models/product_documentation.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

class IdeaDetailScreen extends ConsumerStatefulWidget {
  const IdeaDetailScreen({super.key});

  @override
  ConsumerState<IdeaDetailScreen> createState() => _IdeaDetailScreenState();
}

class _IdeaDetailScreenState extends ConsumerState<IdeaDetailScreen> {
  Idea? _idea;
  bool _isGeneratingDoc = false;
  bool _isLoadingDocs = false;
  bool _isUpdatingIdea = false;
  bool _isDeletingIdea = false;
  bool _isUpdatingDoc = false;
  bool _isDeletingDoc = false;
  List<ProductDocumentation> _docs = [];
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _regenerateConcernController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    if (extra is Idea && _idea == null) {
      _idea = extra;
      _fetchDocumentation();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _regenerateConcernController.dispose();
    super.dispose();
  }

  Future<void> _fetchDocumentation() async {
    if (_idea == null) return;
    setState(() => _isLoadingDocs = true);
    try {
      final api = ApiService();
      final response = await api.getDocumentation(_idea!.id);
      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          _docs = (data['data'] as List? ?? [])
              .map((d) => ProductDocumentation.fromJson(d as Map<String, dynamic>))
              .toList();
          _isLoadingDocs = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch documentation: $e');
      setState(() => _isLoadingDocs = false);
    }
  }

  Future<void> _handleGenerateDoc() async {
    if (_idea == null) return;
    setState(() => _isGeneratingDoc = true);
    try {
      final api = ApiService();
      await api.generateDocumentation(_idea!.id);
      AppToast.show('Documentation generated successfully!', type: AppToastType.success);
      await _fetchDocumentation();
    } catch (e) {
      debugPrint('Failed to generate doc: $e');
    } finally {
      setState(() => _isGeneratingDoc = false);
    }
  }

  Future<void> _handleRegenerateDoc(ProductDocumentation doc) async {
    setState(() => _isGeneratingDoc = true);
    try {
      final api = ApiService();
      await api.regenerateDocumentation(doc.id, _regenerateConcernController.text);
      AppToast.show('Documentation regenerated successfully!', type: AppToastType.success);
      _regenerateConcernController.clear();
      await _fetchDocumentation();
    } catch (e) {
      debugPrint('Failed to regenerate doc: $e');
    } finally {
      setState(() => _isGeneratingDoc = false);
    }
  }

  Future<void> _handleUpdateIdea() async {
    if (_idea == null) return;
    if (_titleController.text.isEmpty || _descController.text.isEmpty) {
      AppToast.show('Please fill all fields');
      return;
    }
    setState(() => _isUpdatingIdea = true);
    try {
      final api = ApiService();
      final response = await api.updateIdea(_idea!.id, {
        'title': _titleController.text,
        'description': _descController.text,
      });
      if (response.statusCode == 200 && response.data['success'] == true) {
        final updatedIdea = Idea.fromJson(response.data['data']);
        setState(() {
          _idea = updatedIdea;
        });
        AppToast.show('Idea updated successfully!', type: AppToastType.success);
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Failed to update idea: $e');
    } finally {
      setState(() => _isUpdatingIdea = false);
    }
  }

  Future<void> _handleDeleteIdea() async {
    if (_idea == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Idea'),
        content: const Text('Are you sure you want to delete this idea?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeletingIdea = true);
    try {
      final api = ApiService();
      await api.deleteIdea(_idea!.id);
      AppToast.show('Idea deleted successfully!', type: AppToastType.success);
      if (mounted) context.go('/main/ideas');
    } catch (e) {
      debugPrint('Failed to delete idea: $e');
    } finally {
      setState(() => _isDeletingIdea = false);
    }
  }

  Future<void> _handleUpdateStatus(String newStatus) async {
    if (_idea == null) return;
    try {
      final api = ApiService();
      final response = await api.updateIdeaStatus(_idea!.id, newStatus);
      if (response.statusCode == 200 && response.data['success'] == true) {
        setState(() {
          _idea = Idea(
            id: _idea!.id,
            businessId: _idea!.businessId,
            userId: _idea!.userId,
            userName: _idea!.userName,
            title: _idea!.title,
            description: _idea!.description,
            status: newStatus,
            createdAt: _idea!.createdAt,
            updatedAt: DateTime.now().toIso8601String(),
          );
        });
        AppToast.show('Status updated successfully!', type: AppToastType.success);
      }
    } catch (e) {
      debugPrint('Failed to update status: $e');
    }
  }

  Future<void> _handleUpdateDoc(ProductDocumentation doc) async {
    setState(() => _isUpdatingDoc = true);
    try {
      final api = ApiService();
      await api.updateDocumentation(doc.id, {
        'title': _titleController.text,
        'content': _descController.text,
      });
      AppToast.show('Documentation updated successfully!', type: AppToastType.success);
      _titleController.clear();
      _descController.clear();
      await _fetchDocumentation();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Failed: $e');
    } finally {
      setState(() => _isUpdatingDoc = false);
    }
  }

  Future<void> _handleDeleteDoc(ProductDocumentation doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Documentation'),
        content: const Text('Are you sure you want to delete this documentation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeletingDoc = true);
    try {
      final api = ApiService();
      await api.deleteDocumentation(doc.id);
      AppToast.show('Documentation deleted successfully!', type: AppToastType.success);
      await _fetchDocumentation();
    } catch (e) {
      debugPrint('Failed: $e');
    } finally {
      setState(() => _isDeletingDoc = false);
    }
  }

  Future<void> _handleDownloadPdf(ProductDocumentation doc) async {
    try {
      final api = ApiService();
      final response = await api.getDocumentationPdf(doc.id);
      
      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final fileName = '${doc.title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final filePath = path.join(dir.path, fileName);
        final file = File(filePath);
        await file.writeAsBytes(response.data);
        
        // Open the PDF file
        if (await canLaunchUrl(Uri.file(filePath))) {
          await launchUrl(Uri.file(filePath), mode: LaunchMode.externalApplication);
        } else {
          // If can't open, share it instead
          await SharePlus.instance.share(
            ShareParams(
              text: doc.title,
              files: [XFile(filePath, mimeType: 'application/pdf')],
            ),
          );
        }
        
        AppToast.show('PDF downloaded successfully!', type: AppToastType.success);
      }
    } catch (e) {
      debugPrint('Download PDF failed: $e');
      AppToast.show(e.toString().replaceAll('Exception: ', ''), type: AppToastType.error);
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

  void _showEditIdeaModal() {
    if (_idea == null) return;
    _titleController.text = _idea!.title;
    _descController.text = _idea!.description;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: AppTheme.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Edit Idea', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'Title',
                hintStyle: TextStyle(color: AppTheme.colors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppTheme.colors.border),
                ),
                filled: true,
                fillColor: AppTheme.colors.background,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Description',
                hintStyle: TextStyle(color: AppTheme.colors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppTheme.colors.border),
                ),
                filled: true,
                fillColor: AppTheme.colors.background,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isUpdatingIdea ? null : _handleUpdateIdea,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isUpdatingIdea
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Update Idea', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDocModal(ProductDocumentation doc) {
    _titleController.text = doc.title;
    _descController.text = doc.content;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: AppTheme.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Edit Documentation', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'Title',
                hintStyle: TextStyle(color: AppTheme.colors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppTheme.colors.border),
                ),
                filled: true,
                fillColor: AppTheme.colors.background,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Content',
                hintStyle: TextStyle(color: AppTheme.colors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppTheme.colors.border),
                ),
                filled: true,
                fillColor: AppTheme.colors.background,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isUpdatingDoc ? null : () => _handleUpdateDoc(doc),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isUpdatingDoc
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Update Documentation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRegenerateModal(ProductDocumentation doc) {
    _regenerateConcernController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        decoration: BoxDecoration(
          color: AppTheme.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Regenerate Documentation', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Any specific areas you want to focus on? (Optional)', style: TextStyle(color: AppTheme.colors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: _regenerateConcernController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'E.g., focus more on user experience',
                hintStyle: TextStyle(color: AppTheme.colors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppTheme.colors.border),
                ),
                filled: true,
                fillColor: AppTheme.colors.background,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isGeneratingDoc ? null : () {
                  Navigator.pop(context);
                  _handleRegenerateDoc(doc);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isGeneratingDoc
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Regenerate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStatusModal() {
    if (_idea == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        decoration: BoxDecoration(
          color: AppTheme.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Update Status', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _StatusOption(
              status: 'under_review',
              label: 'Under Review',
              color: AppColors.warning,
              isSelected: _idea!.status == 'under_review',
              onTap: () {
                Navigator.pop(context);
                _handleUpdateStatus('under_review');
              },
            ),
            const SizedBox(height: 12),
            _StatusOption(
              status: 'executed',
              label: 'Executed',
              color: AppColors.success,
              isSelected: _idea!.status == 'executed',
              onTap: () {
                Navigator.pop(context);
                _handleUpdateStatus('executed');
              },
            ),
            const SizedBox(height: 12),
            _StatusOption(
              status: 'rejected',
              label: 'Rejected',
              color: AppColors.error,
              isSelected: _idea!.status == 'rejected',
              onTap: () {
                Navigator.pop(context);
                _handleUpdateStatus('rejected');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_idea == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Idea not found')),
        ),
      );
    }
    final idea = _idea!;
    final statusColor = _getStatusColor(idea.status);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.go('/main/ideas'),
                  ),
                  const Expanded(
                    child: Text(
                      'Idea Details',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: _showEditIdeaModal,
                    icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                  ),
                  IconButton(
                    onPressed: _isDeletingIdea ? null : _handleDeleteIdea,
                    icon: _isDeletingIdea ? const CircularProgressIndicator(color: AppColors.error) : const Icon(Icons.delete_outline, color: AppColors.error),
                  ),
                  IconButton(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        title: idea.title,
                        text: '${idea.title}\n\n${idea.description}\n\nStatus: ${idea.status.toUpperCase()}',
                      ),
                    ),
                    icon: const Icon(Icons.share_outlined, color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.colors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: _showStatusModal,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: statusColor, width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  idea.status.replaceAll('_', ' ').toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_drop_down, color: statusColor, size: 16),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          DateTime.tryParse(idea.createdAt)?.toLocal().toString().split(' ')[0] ?? idea.createdAt,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      idea.title,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      idea.description,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.colors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              (idea.userName ?? 'A').toUpperCase().characters.first,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'By ${idea.userName ?? 'Anonymous'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                'Product Documentation',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (_isLoadingDocs)
                const Center(child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: CircularProgressIndicator(),
                ))
              else if (_docs.isNotEmpty)
                Column(
                  children: _docs.map((doc) {
                    return _DocumentationCard(
                      doc: doc,
                      onEdit: () => _showEditDocModal(doc),
                      onDelete: () => _handleDeleteDoc(doc),
                      onRegenerate: () => _showRegenerateModal(doc),
                      onDownloadPdf: () => _handleDownloadPdf(doc),
                      onShare: () => SharePlus.instance.share(
                        ShareParams(
                          title: doc.title,
                          text: '${doc.title}\n\n${doc.content}',
                        ),
                      ),
                      isDeleting: _isDeletingDoc,
                    );
                  }).toList(),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(
                    color: AppTheme.colors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.colors.border),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.description_outlined, size: 48, color: AppTheme.colors.textSecondary),
                      const SizedBox(height: 12),
                      Text(
                        'No documentation yet.',
                        style: TextStyle(color: AppTheme.colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isGeneratingDoc ? null : _handleGenerateDoc,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isGeneratingDoc
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_awesome, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            _docs.isNotEmpty ? 'Generate New' : 'Generate with AI',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusOption extends StatelessWidget {
  final String status;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusOption({
    required this.status,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : AppTheme.colors.background,
          border: Border.all(color: isSelected ? color : AppTheme.colors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? color : AppTheme.colors.textSecondary, width: 2),
                color: isSelected ? color : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isSelected ? color : AppTheme.colors.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentationCard extends StatefulWidget {
  final ProductDocumentation doc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRegenerate;
  final VoidCallback onDownloadPdf;
  final VoidCallback onShare;
  final bool isDeleting;

  const _DocumentationCard({
    required this.doc,
    required this.onEdit,
    required this.onDelete,
    required this.onRegenerate,
    required this.onDownloadPdf,
    required this.onShare,
    this.isDeleting = false,
  });

  @override
  State<_DocumentationCard> createState() => _DocumentationCardState();
}

class _DocumentationCardState extends State<_DocumentationCard> {
  bool _isExpanded = false;
  static const int _maxLines = 8;

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      widget.doc.content,
      style: TextStyle(
        fontSize: 14,
        color: AppTheme.colors.textSecondary,
        height: 1.5,
      ),
      maxLines: _isExpanded ? null : _maxLines,
      overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.doc.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      widget.onEdit();
                      break;
                    case 'regenerate':
                      widget.onRegenerate();
                      break;
                    case 'download':
                      widget.onDownloadPdf();
                      break;
                    case 'delete':
                      widget.onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'regenerate',
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 18),
                        SizedBox(width: 8),
                        Text('Regenerate'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf, size: 18),
                        SizedBox(width: 8),
                        Text('Download PDF'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: !widget.isDeleting,
                    child: widget.isDeleting
                        ? const Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Deleting...'),
                            ],
                          )
                        : const Row(
                            children: [
                              Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: AppColors.error)),
                            ],
                          ),
                  ),
                ],
                child: const Icon(Icons.more_vert_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          textWidget,
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
                child: Text(_isExpanded ? 'Read Less' : 'Read More', style: const TextStyle(color: AppColors.primary)),
              ),
              const Spacer(),
              Text(
                DateTime.tryParse(widget.doc.createdAt)?.toLocal().toString().split(' ')[0] ?? widget.doc.createdAt,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.onShare,
                icon: const Icon(Icons.share_outlined, size: 20, color: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
