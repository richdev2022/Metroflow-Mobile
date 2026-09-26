import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
import '../models/call.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import '../widgets/modern_ui.dart';
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
  String _filterType = 'all';
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

  Future<void> _openCallModal(Call call, {String? password}) async {
    try {
      final response = await _api.joinCall(call.id, password: password);
      if (response.data['success'] == true && mounted) {
        final responseData = response.data['data'];
        final updatedCall = responseData is Map
            ? Call.fromJson(Map<String, dynamic>.from(responseData))
            : call;
        setState(() {
          _upsertCall(updatedCall);
        });
        final userName = await StorageService().getUserName();
        await VideoCallScreen.showModal(
          context: context,
          roomId: updatedCall.id,
          title: '${updatedCall.type.capitalize()} Call',
          enableVideo: updatedCall.type == 'video',
          userName: userName,
          onLeave: () => _leaveCall(updatedCall.id),
        );
      }
    } catch (e) {
      // Password-protected call → prompt and retry with the entered password
      final isPasswordError = e is DioException &&
          e.response?.statusCode == 403 &&
          e.response?.data is Map &&
          (e.response!.data['errorCode'] == 'invalid_password' ||
              (e.response!.data['error']?.toString().toLowerCase() ?? '').contains('password'));
      if (isPasswordError && mounted) {
        final entered = await _promptForCallPassword(call);
        if (entered != null && entered.isNotEmpty) {
          await _openCallModal(call, password: entered);
        }
        return;
      }
      Logger.error('Error joining call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    }
  }

  /// Shows a password dialog for protected calls. Returns null when cancelled.
  Future<String?> _promptForCallPassword(Call call) async {
    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Call password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('This call is protected. Enter the password to join.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Password',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    return entered;
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

  Color _getCallTint(ThemeColors colors, String type) {
    return type == 'video' ? colors.primary : colors.success;
  }

  Color _getCallStatusColor(ThemeColors colors, String status) {
    switch (status) {
      case 'ongoing':
        return colors.success;
      case 'missed':
        return colors.error;
      default:
        return colors.textSecondary;
    }
  }

  String _durationLabel(Call call) {
    final started = call.startedAt;
    final ended = call.endedAt;
    if (started == null) return '';
    final end = ended ?? DateTime.now();
    final minutes = end.difference(started).inMinutes;
    if (minutes <= 0) return '';
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  List<Call> get _filteredCalls {
    if (_filterType == 'all') return _calls;
    return _calls.where((call) => call.type == _filterType).toList();
  }

  int _countForType(String type) {
    if (type == 'all') return _calls.length;
    return _calls.where((call) => call.type == type).length;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final filtered = _filteredCalls;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Calls',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: colors.text,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.primaryBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_calls.length} calls',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: ModernFilterChip(
                      label: 'All (${_countForType('all')})',
                      selected: _filterType == 'all',
                      onTap: () => setState(() => _filterType = 'all'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ModernFilterChip(
                      label: 'Video (${_countForType('video')})',
                      selected: _filterType == 'video',
                      onTap: () => setState(() => _filterType = 'video'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ModernFilterChip(
                      label: 'Audio (${_countForType('audio')})',
                      selected: _filterType == 'audio',
                      onTap: () => setState(() => _filterType = 'audio'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      children: const [
                        SkeletonCard(height: 110),
                        SkeletonCard(height: 110),
                        SkeletonCard(height: 110),
                      ],
                    )
                  : RefreshIndicator(
                      onRefresh: _loadCalls,
                      color: colors.primary,
                      child: _calls.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 40),
                                EmptyState(
                                  icon: Icons.call_outlined,
                                  title: 'No calls yet',
                                  subtitle: 'Start your first call and your history will appear here.',
                                  actionLabel: 'New Call',
                                  onAction: _showCreateCallDialog,
                                ),
                              ],
                            )
                          : filtered.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    const SizedBox(height: 40),
                                    EmptyState(
                                      icon: _filterType == 'video'
                                          ? Icons.videocam_off_outlined
                                          : Icons.call_end_outlined,
                                      title: 'No ${_filterType} calls',
                                      subtitle:
                                          'You have no ${_filterType} calls in your history yet.',
                                      tint: _filterType == 'video'
                                          ? colors.primary
                                          : colors.success,
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
                                  itemCount: filtered.length,
                                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final call = filtered[index];
                                    return _CallCard(
                                      call: call,
                                      colors: colors,
                                      tint: _getCallTint(colors, call.type),
                                      statusColor:
                                          _getCallStatusColor(colors, call.status),
                                      durationLabel: _durationLabel(call),
                                      onJoin: () => _openCallModal(call),
                                      onDelete: () => _deleteCall(call),
                                    );
                                  },
                                ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: ModernFab(
        icon: Icons.add_call,
        label: 'New Call',
        onPressed: _showCreateCallDialog,
      ),
    );
  }
}

class _CallCard extends StatelessWidget {
  final Call call;
  final ThemeColors colors;
  final Color tint;
  final Color statusColor;
  final String durationLabel;
  final VoidCallback onJoin;
  final VoidCallback onDelete;

  const _CallCard({
    required this.call,
    required this.colors,
    required this.tint,
    required this.statusColor,
    required this.durationLabel,
    required this.onJoin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isOngoing = call.status == 'ongoing';
    final participantCount = call.participants.length;

    return ModernCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      onTap: isOngoing ? onJoin : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TintedCircleIcon(
            icon: call.type == 'video' ? Icons.videocam : Icons.call,
            tint: tint,
            size: 46,
            iconSize: 21,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${call.type.capitalize()} Call',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                        ),
                      ),
                    ),
                    ModernBadge(
                      label: call.status.capitalize(),
                      color: statusColor,
                      icon: isOngoing ? Icons.fiber_manual_record : null,
                    ),
                  ],
                ),
                if (call.callCode.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Code · ${call.callCode}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: colors.textSecondary),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        DateFormat.yMMMd().add_Hm().format(call.createdAt),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    if (durationLabel.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      ModernBadge(
                        label: durationLabel,
                        color: colors.textSecondary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.people_outline, size: 14, color: colors.textSecondary),
                    const SizedBox(width: 5),
                    Text(
                      '$participantCount participant${participantCount > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    if (call.isGroupCall) ...[
                      const SizedBox(width: 8),
                      ModernBadge(
                        label: 'Group',
                        color: colors.primary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') {
                    onDelete();
                  }
                },
                icon: Icon(Icons.more_vert_rounded,
                    size: 20, color: colors.textSecondary),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
              if (isOngoing)
                SizedBox(
                  height: 34,
                  child: ElevatedButton.icon(
                    onPressed: onJoin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.call, size: 15),
                    label: const Text(
                      'Join',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
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
    final colors = AppTheme.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
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
              Text(
                'Participants',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      title: Text(
                        member.name,
                        style: TextStyle(color: colors.text),
                      ),
                      subtitle: Text(
                        member.email,
                        style: TextStyle(color: colors.textSecondary),
                      ),
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
