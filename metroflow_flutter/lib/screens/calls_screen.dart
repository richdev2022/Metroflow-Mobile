import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
import '../models/call.dart';
import '../models/user.dart';
import '../utils/logger.dart';
import 'video_call_screen.dart';

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
      if (data is! Map) return;
      setState(() {
        _upsertCall(Call.fromJson(Map<String, dynamic>.from(data)));
      });
    };
    _callUpdatedHandler = (data) {
      if (!mounted) return;
      if (data is! Map) return;
      setState(() {
        _upsertCall(Call.fromJson(Map<String, dynamic>.from(data)));
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
        if (!mounted) return;
        setState(() {
          _calls.removeWhere((item) => item.id == call.id);
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
        if (!mounted) return;
        final responseData = response.data['data'];
        final data = responseData is Map && responseData['calls'] is List
            ? responseData['calls'] as List
            : responseData is List
                ? responseData
                : <dynamic>[];
        setState(() {
          _calls = data
              .whereType<Map>()
              .map((json) => Call.fromJson(Map<String, dynamic>.from(json)))
              .toList()
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
        if (!mounted) return;
        final data = response.data['data'] is List ? response.data['data'] as List : <dynamic>[];
        setState(() {
          _teamMembers = data
              .whereType<Map>()
              .map((json) => User.fromJson(Map<String, dynamic>.from(json)))
              .toList();
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
          if (!mounted) return;
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
        final responseData = response.data['data'];
        final updatedCall = responseData is Map
            ? Call.fromJson(Map<String, dynamic>.from(responseData))
            : call;
        setState(() {
          _upsertCall(updatedCall);
        });
        await VideoCallScreen.showModal(
          context: context,
          roomId: updatedCall.id,
          title: '${updatedCall.type.capitalize()} Call',
          enableVideo: updatedCall.type == 'video',
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
        final responseData = response.data['data'];
        if (responseData is! Map) return;
        final updatedCall = Call.fromJson(Map<String, dynamic>.from(responseData));
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
  final SocketService _socket = SocketService();
  final List<String> _selectedMemberIds = [];
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _maxParticipantsController = TextEditingController(text: '10');
  String _callType = 'video';
  bool _isCreating = false;
  bool _isGroupCall = false;
  bool _waitingRoomEnabled = false;
  bool _recordingEnabled = false;

  Future<void> _createCall() async {
    if (_selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one participant')),
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      final maxParticipants = int.tryParse(_maxParticipantsController.text.trim());
      if (maxParticipants == null || maxParticipants < 2) {
        throw const FormatException('Max participants must be at least 2');
      }

      final response = await _api.createCall({
        'type': _callType,
        'isGroupCall': _isGroupCall,
        'password': _passwordController.text.trim().isEmpty ? null : _passwordController.text.trim(),
        'maxParticipants': maxParticipants,
        'waitingRoomEnabled': _waitingRoomEnabled,
        'recordingEnabled': _recordingEnabled,
        'participantIds': _selectedMemberIds,
      });
      if (response.data['success'] == true) {
        final responseData = response.data['data'];
        if (responseData is! Map) {
          throw const FormatException('Invalid call response');
        }
        final call = Call.fromJson(Map<String, dynamic>.from(responseData));
        
        // Emit call invites to selected participants
        for (final userId in _selectedMemberIds) {
          _socket.emitCallInvite({
            'callId': call.id,
            'targetUserId': userId,
            'type': _callType,
          });
        }
        
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
  void dispose() {
    _passwordController.dispose();
    _maxParticipantsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Call'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              SwitchListTile(
                title: const Text('Group Call'),
                value: _isGroupCall,
                onChanged: (value) {
                  setState(() {
                    _isGroupCall = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Call Password (Optional)',
                  hintText: 'Enter password to secure the call',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _maxParticipantsController,
                decoration: const InputDecoration(
                  labelText: 'Max Participants',
                  hintText: '10',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Waiting Room'),
                subtitle: const Text('Participants wait in a room before joining'),
                value: _waitingRoomEnabled,
                onChanged: (value) {
                  setState(() {
                    _waitingRoomEnabled = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Enable Recording'),
                subtitle: const Text('Allow recording the call'),
                value: _recordingEnabled,
                onChanged: (value) {
                  setState(() {
                    _recordingEnabled = value;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              const Text('Participants', style: TextStyle(fontWeight: FontWeight.w500)),
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
