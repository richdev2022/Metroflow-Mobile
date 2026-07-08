import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';
import '../models/conversation.dart';
import '../models/user.dart';
import '../utils/logger.dart';
import '../providers/auth_provider.dart';
import 'chat_detail_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ApiService _api = ApiService();
  List<Conversation> _conversations = [];
  List<User> _teamMembers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _loadTeamMembers();
  }

  Future<void> _loadConversations() async {
    try {
      final response = await _api.getConversations();
      if (response.data['success'] == true) {
        final data = response.data['data'] as List;
        setState(() {
          _conversations = data.map((json) => Conversation.fromJson(json)).toList();
        });
      }
    } catch (e) {
      Logger.error('Error loading conversations: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadTeamMembers() async {
    try {
      final response = await _api.getTeam();
      if (response.data['success'] == true) {
        final data = response.data['data'] as List;
        setState(() {
          _teamMembers = data.map((json) => User.fromJson(json)).toList();
        });
      }
    } catch (e) {
      Logger.error('Error loading team members: $e');
    }
  }

  Future<void> _showCreateConversationDialog() async {
    final authState = ref.read(authProvider);
    showDialog(
      context: context,
      builder: (context) => _CreateConversationDialog(
        teamMembers: _teamMembers,
        currentUserId: authState.userId,
        onCreated: (conversation) {
          _loadConversations();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No conversations yet', style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      Text('Start messaging your team', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _conversations.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final conversation = _conversations[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor,
                        child: Text(
                          (conversation.name ?? 'Direct').substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        conversation.name ?? 'Direct Chat',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        conversation.lastMessage ?? 'No messages yet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: conversation.lastMessageAt != null
                          ? Text(
                              DateFormat.Hm().format(conversation.lastMessageAt!),
                              style: TextStyle(color: Colors.grey[500], fontSize: 12),
                            )
                          : null,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatDetailScreen(conversation: conversation),
                          ),
                        ).then((_) => _loadConversations());
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Chat'),
        onPressed: _showCreateConversationDialog,
      ),
    );
  }
}

class _CreateConversationDialog extends StatefulWidget {
  final List<User> teamMembers;
  final String? currentUserId;
  final Function(Conversation) onCreated;

  const _CreateConversationDialog({
    required this.teamMembers,
    required this.currentUserId,
    required this.onCreated,
  });

  @override
  State<_CreateConversationDialog> createState() => _CreateConversationDialogState();
}

class _CreateConversationDialogState extends State<_CreateConversationDialog> {
  final ApiService _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final List<String> _selectedMemberIds = [];
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createConversation() async {
    if (_selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one member')),
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      final type = _selectedMemberIds.length == 1 ? 'direct' : 'group';
      final response = await _api.createConversation({
        if (type == 'group' && _nameController.text.isNotEmpty) 'name': _nameController.text,
        'type': type,
        'participant_ids': _selectedMemberIds,
      });
      if (response.data['success'] == true) {
        final conversation = Conversation.fromJson(response.data['data']);
        widget.onCreated(conversation);
        if (mounted) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatDetailScreen(conversation: conversation),
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Error creating conversation: $e');
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableMembers = widget.teamMembers.where((m) => m.id != widget.currentUserId).toList();
    return AlertDialog(
      title: const Text('New Conversation'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (availableMembers.length > 1)
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name (optional)',
                    hintText: 'e.g. Project Team',
                  ),
                ),
              const SizedBox(height: 16),
              const Text('Select Participants:'),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableMembers.length,
                  itemBuilder: (context, index) {
                    final member = availableMembers[index];
                    final isSelected = _selectedMemberIds.contains(member.id);
                    return CheckboxListTile(
                      title: Text(member.name),
                      subtitle: Text(member.email),
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedMemberIds.add(member.id);
                          } else {
                            _selectedMemberIds.remove(member.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isCreating ? null : _createConversation,
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
