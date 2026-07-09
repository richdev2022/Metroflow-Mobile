import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
import '../models/call.dart';
import '../models/user.dart';
import '../utils/logger.dart';
import 'jitsi_call_screen.dart';

class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();
  List<Call> _calls = [];
  List<User> _teamMembers = [];
  bool _isLoading = true;
  late final void Function(dynamic) _callCreatedHandler;
  late final void Function(dynamic) _callUpdatedHandler;
  late final void Function(dynamic) _callDeletedHandler;
  late final void Function(dynamic) _callParticipantChangedHandler;

  @override
  void initState() {
    super.initState();
    _loadCalls();
    _loadTeamMembers();
    _callCreatedHandler = (data) {
      if (!mounted) return;
      setState(() {
        _upsertCall(Call.fromJson(data));
      });
    };
    _callUpdatedHandler = (data) {
      if (!mounted) return;
      setState(() {
        _upsertCall(Call.fromJson(data));
      });
    };
    _callDeletedHandler = (callId) {
      if (!mounted) return;
      final id = callId is Map ? callId['id'] : callId;
      setState(() {
        _calls.removeWhere((c) => c.id == id);
      });
    };
    _callParticipantChangedHandler = (_) {
      if (!mounted) return;
      _loadCalls();
    };
    _socket.onCallCreated = _callCreatedHandler;
    _socket.onCallUpdated = _callUpdatedHandler;
    _socket.onCallDeleted = _callDeletedHandler;
    _socket.onCallParticipantJoined = _callParticipantChangedHandler;
    _socket.onCallParticipantLeft = _callParticipantChangedHandler;
  }

  @override
  void dispose() {
    if (_socket.onCallCreated == _callCreatedHandler) {
      _socket.onCallCreated = null;
    }
    if (_socket.onCallUpdated == _callUpdatedHandler) {
      _socket.onCallUpdated = null;
    }
    if (_socket.onCallDeleted == _callDeletedHandler) {
      _socket.onCallDeleted = null;
    }
    if (_socket.onCallParticipantJoined == _callParticipantChangedHandler) {
      _socket.onCallParticipantJoined = null;
    }
    if (_socket.onCallParticipantLeft == _callParticipantChangedHandler) {
      _socket.onCallParticipantLeft = null;
    }
    super.dispose();
  }

  Future<void> _deleteCall(Call call) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Call'),
        content: Text('Are you sure you want to delete this ${call.type} call?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _api.deleteCall(call.id);
        setState(() {
          _calls.remove(call);
        });
      } catch (e) {
        Logger.error('Error deleting call: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(ApiService.extractErrorMessage(e)),
  ),
);
        }
      }
    }
  }

  Future<void> _loadCalls() async {
    try {
      final response = await _api.getCalls();
      if (response.data['success'] == true) {
        final data = response.data['data']['calls'] as List;
        setState(() {
          _calls = data.map((json) => Call.fromJson(json)).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
      }
    } catch (e) {
      Logger.error('Error loading calls: $e');
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

  Future<void> _showCreateCallDialog() async {
    showDialog(
      context: context,
      builder: (context) => _CreateCallDialog(
        teamMembers: _teamMembers,
        onCreated: (call) {
          setState(() {
            _upsertCall(call);
          });
          _openCallModal(call);
        },
      ),
    );
  }

  void _upsertCall(Call call) {
    final index = _calls.indexWhere((item) => item.id == call.id);
    if (index == -1) {
      _calls.insert(0, call);
    } else {
      _calls[index] = call;
    }
    _calls.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _openCallModal(Call call) async {
    try {
      final response = await _api.joinCall(call.id);
      if (response.data['success'] == true && mounted) {
        final updatedCall = Call.fromJson(response.data['data']);
        setState(() {
          _upsertCall(updatedCall);
        });
        await JitsiCallScreen.showModal(
          context: context,
          roomId: updatedCall.jitsiRoomId,
          title: '${updatedCall.type.capitalize()} Call',
          onLeave: () => _leaveCall(updatedCall.id),
        );
      }
    } catch (e) {
      Logger.error('Error joining call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _leaveCall(String callId) async {
    try {
      final response = await _api.leaveCall(callId);
      if (response.data['success'] == true && mounted) {
        final updatedCall = Call.fromJson(response.data['data']);
        setState(() {
          _upsertCall(updatedCall);
        });
      }
    } catch (e) {
      Logger.error('Error leaving call: $e');
    }
  }

  IconData _getCallIcon(String type) {
    return type == 'video' ? Icons.videocam : Icons.call;
  }

  Color _getCallStatusColor(String status) {
    switch (status) {
      case 'ongoing':
        return Colors.green;
      case 'missed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _calls.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.call_outlined, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No calls yet', style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      Text('Start your first call!', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _calls.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final call = _calls[index];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _getCallIcon(call.type),
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${call.type.capitalize()} Call',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: _getCallStatusColor(call.status),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            call.status.capitalize(),
                                            style: TextStyle(
                                              color: _getCallStatusColor(call.status),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton(
                                  onSelected: (value) {
                                    if (value == 'delete') {
                                      _deleteCall(call);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                                if (call.status == 'ongoing')
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.call),
                                    label: const Text('Join'),
                                    onPressed: () => _openCallModal(call),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 6),
                                Text(
                                  DateFormat.yMMMd().add_Hm().format(call.createdAt),
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${call.participants.length} participant${call.participants.length > 1 ? 's' : ''}',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_call),
        label: const Text('New Call'),
        onPressed: _showCreateCallDialog,
      ),
    );
  }
}

class _CreateCallDialog extends StatefulWidget {
  final List<User> teamMembers;
  final Function(Call) onCreated;

  const _CreateCallDialog({
    required this.teamMembers,
    required this.onCreated,
  });

  @override
  State<_CreateCallDialog> createState() => _CreateCallDialogState();
}

class _CreateCallDialogState extends State<_CreateCallDialog> {
  final ApiService _api = ApiService();
  final List<String> _selectedMemberIds = [];
  String _callType = 'video';
  bool _isCreating = false;

  Future<void> _createCall() async {
    if (_selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one participant')),
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      final response = await _api.createCall({
        'type': _callType,
        'participant_ids': _selectedMemberIds,
      });
      if (response.data['success'] == true) {
        final call = Call.fromJson(response.data['data']);
        if (mounted) Navigator.pop(context);
        widget.onCreated(call);
      }
    } catch (e) {
      Logger.error('Error creating call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Call'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'video', icon: Icon(Icons.videocam), label: Text('Video')),
                ButtonSegment(value: 'audio', icon: Icon(Icons.call), label: Text('Audio')),
              ],
              selected: {_callType},
              onSelectionChanged: (newSelection) {
                setState(() {
                  _callType = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Participants', style: TextStyle(fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.teamMembers.length,
                itemBuilder: (context, index) {
                  final member = widget.teamMembers[index];
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isCreating ? null : _createCall,
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Start Call'),
        ),
      ],
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return substring(0, 1).toUpperCase() + substring(1).toLowerCase();
  }
}
