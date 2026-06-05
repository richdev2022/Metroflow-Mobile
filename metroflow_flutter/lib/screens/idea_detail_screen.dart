import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api.dart';
import '../models/idea.dart';
import '../theme/app_theme.dart';

class IdeaDetailScreen extends ConsumerStatefulWidget {
  const IdeaDetailScreen({super.key});

  @override
  ConsumerState<IdeaDetailScreen> createState() => _IdeaDetailScreenState();
}

class _IdeaDetailScreenState extends ConsumerState<IdeaDetailScreen> {
  Idea? _idea;
  bool _isGeneratingDoc = false;
  bool _isLoadingDocs = false;
  List<dynamic> _docs = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    if (extra is Idea && _idea == null) {
      _idea = extra;
      _fetchDocumentation();
    }
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
          _docs = data['data'] ?? [];
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
      Fluttertoast.showToast(msg: 'Documentation generated successfully!');
      await _fetchDocumentation();
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
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

  @override
  Widget build(BuildContext context) {
    if (_idea == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Idea Details'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/main/ideas'),
          ),
        ),
        body: const Center(child: Text('Idea not found')),
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
                  Expanded(
                    child: Text(
                      'Idea Details',
                      style: Theme.of(context).textTheme.displaySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            idea.status.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
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
                          Text(
                            doc['title'] ?? '',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            doc['content'] ?? '',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.colors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Generated: ${doc['createdAt'] != null ? DateTime.tryParse(doc['createdAt'])?.toLocal().toString().split(' ')[0] ?? '' : ''}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              IconButton(
                                onPressed: () => SharePlus.instance.share(
                                  ShareParams(
                                    title: '${doc['title'] ?? ''}',
                                    text: '${doc['content'] ?? ''}',
                                  ),
                                ),
                                icon: const Icon(Icons.share_outlined, size: 20, color: AppColors.primary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(
                    color: AppTheme.colors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.colors.border, style: BorderStyle.solid),
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
                            _docs.isNotEmpty ? 'Regenerate with AI' : 'Generate with AI',
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
