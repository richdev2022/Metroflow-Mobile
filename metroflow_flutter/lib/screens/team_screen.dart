import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import '../models/team_member.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  List<TeamMember> _teamMembers = [];
  // Custom workspace roles loaded from /roles (Role Management)
  List<Map<String, dynamic>> _roles = [];
  // Permission catalog from /roles/permissions (pretty names for chips)
  List<Map<String, dynamic>> _permissionCatalog = [];
  bool _isLoading = true;
  bool _isInviting = false;
  String _inviteRole = 'member';
  String? _inviteRoleId; // non-null => custom role selected

  @override
  void initState() {
    super.initState();
    _fetchTeam();
    _fetchRoles();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _fetchTeam() async {
    try {
      final response = await ApiService().getTeam();
      final data = response.data;
      if (data['success'] == true && mounted) {
        final members = (data['data'] as List<dynamic>? ?? [])
            .map((item) => TeamMember.fromJson(item as Map<String, dynamic>))
            .toList();
        setState(() => _teamMembers = members);
      }
    } catch (e) {
      debugPrint('Failed to fetch team: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchRoles() async {
    try {
      final response = await ApiService().getRoles();
      final data = response.data;
      if (data['success'] == true && mounted) {
        setState(() {
          _roles = (data['data']?['roles'] as List<dynamic>? ?? [])
              .map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch roles: $e');
    }
    try {
      final response = await ApiService().getRolePermissions();
      final data = response.data;
      if (data['success'] == true && mounted) {
        setState(() {
          _permissionCatalog =
              (data['data']?['permissions'] as List<dynamic>? ?? [])
                  .map((p) => Map<String, dynamic>.from(p as Map<String, dynamic>))
                  .toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch permission catalog: $e');
    }
  }

  String _permissionLabel(String id) {
    for (final p in _permissionCatalog) {
      if (p['id'] == id) return (p['name'] as String?) ?? id;
    }
    return id.replaceAll('_', ' ').replaceAll('rtc.', '');
  }

  Future<void> _handleInvite() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || email.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Please fill in all fields',
        backgroundColor: AppColors.error,
      );
      return;
    }

    setState(() => _isInviting = true);
    try {
      final payload = <String, dynamic>{
        'name': name,
        'email': email,
        'role': _inviteRole,
      };
      // Custom workspace role wins over the legacy role when selected.
      if (_inviteRoleId != null) {
        payload['roleId'] = _inviteRoleId;
      }
      await ApiService().inviteMember(payload);
      Fluttertoast.showToast(msg: 'Invitation sent successfully');
      _nameController.clear();
      _emailController.clear();
      if (mounted) Navigator.of(context).pop();
      await _fetchTeam();
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    } finally {
      if (mounted) setState(() => _isInviting = false);
    }
  }

  Future<void> _handleToggleStatus(TeamMember member) async {
    final newStatus = member.status == 'active' ? 'inactive' : 'active';
    try {
      await ApiService().updateMemberStatus(member.id, newStatus);
      await _fetchTeam();
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    }
  }

  Future<void> _handleUpdateRole(
    TeamMember member,
    String? roleId,
    String legacyRole,
  ) async {
    try {
      if (roleId != null) {
        await ApiService().updateMemberRoleById(member.id, roleId);
      } else {
        await ApiService().updateMemberRole(member.id, legacyRole);
      }
      await _fetchTeam();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    }
  }

  void _showPermissionsSheet(TeamMember member) {
    final permissions = member.permissions;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = AppTheme.colors;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${member.name}'s permissions",
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  member.roleId != null && member.roleName != null
                      ? 'Custom role · ${member.roleName}'
                      : 'Default role · ${_titleCase(member.role)}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: permissions
                          .map(
                            (p) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: colors.background,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: colors.border),
                              ),
                              child: Text(
                                p == '*' ? 'Full access' : _permissionLabel(p),
                                style: TextStyle(
                                  color: colors.text,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRoleModal(TeamMember member) {
    String selectedRole = member.role;
    String? selectedRoleId = member.roleId;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final colors = AppTheme.colors;
            final customRoles = _roles;
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Update Role',
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: colors.text),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select a new role for ${member.name}',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ...['admin', 'manager', 'member'].map((role) {
                        final selected =
                            selectedRoleId == null && selectedRole == role;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setModalState(() {
                                selectedRole = role;
                                selectedRoleId = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 16),
                              decoration: BoxDecoration(
                                color: selected
                                    ? colors.primary.withValues(alpha: 0.12)
                                    : colors.background,
                                border: Border.all(
                                  color: selected
                                      ? colors.primary
                                      : colors.border,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(_getRoleIcon(role),
                                      color: selected
                                          ? colors.primary
                                          : colors.textSecondary,
                                      size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _titleCase(role),
                                      style: TextStyle(
                                        color: selected
                                            ? colors.primary
                                            : colors.text,
                                        fontWeight: selected
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    Icon(Icons.check_circle,
                                        color: colors.primary),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      if (customRoles.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Custom roles',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...customRoles.map((role) {
                          final roleId = role['id'] as String?;
                          final roleName = (role['name'] as String?) ?? '';
                          final selected = selectedRoleId != null &&
                              selectedRoleId == roleId;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                setModalState(() {
                                  selectedRoleId = roleId;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? colors.primary.withValues(alpha: 0.12)
                                      : colors.background,
                                  border: Border.all(
                                    color: selected
                                        ? colors.primary
                                        : colors.border,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.shield_outlined,
                                        color: selected
                                            ? colors.primary
                                            : colors.textSecondary,
                                        size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        roleName,
                                        style: TextStyle(
                                          color: selected
                                              ? colors.primary
                                              : colors.text,
                                          fontWeight: selected
                                              ? FontWeight.w500
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      Icon(Icons.check_circle,
                                          color: colors.primary),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => _handleUpdateRole(
                            member, selectedRoleId, selectedRole),
                        child: const Text('Update Role'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleDelete(TeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Are you sure you want to remove ${member.name} from the team?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService().deleteMember(member.id);
      await _fetchTeam();
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF4CAF50);
      case 'invited':
        return const Color(0xFFFF9800);
      case 'inactive':
        return const Color(0xFF9E9E9E);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.shield_outlined;
      case 'manager':
        return Icons.people_outline;
      case 'member':
        return Icons.person_outline;
      default:
        return Icons.person_outline;
    }
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  /// Badge color per role: Owner amber/gold, Admin red, Manager blue,
  /// Member grey, custom roles use the primary color.
  Color _roleBadgeColor(String displayRole) {
    switch (displayRole.toLowerCase()) {
      case 'owner':
        return const Color(0xFFF59E0B);
      case 'admin':
        return const Color(0xFFEF4444);
      case 'manager':
        return const Color(0xFF3B82F6);
      case 'member':
        return const Color(0xFF94A3B8);
      default:
        return AppColors.primary;
    }
  }

  /// Resolved badge label: custom roleName when a roleId is set, else the
  /// title-cased legacy role.
  String _roleBadgeLabel(TeamMember member) {
    if (member.roleId != null && member.roleName != null) {
      return member.roleName!;
    }
    return _titleCase(member.role);
  }

  String? _formatJoinedDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return '${parsed.month}/${parsed.day}/${parsed.year}';
  }

  void _showInviteModal() {
    // Reset the custom-role selection each time the sheet opens.
    _inviteRoleId = null;
    _inviteRole = 'member';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final colors = AppTheme.colors;
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final customRoles = _roles;
            return Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 24),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Invite Team Member',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.text),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(hintText: 'Name'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(hintText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      textCapitalization: TextCapitalization.none,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Role',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: ['admin', 'manager', 'member'].map((role) {
                        final selected =
                            _inviteRoleId == null && _inviteRole == role;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                setState(() {
                                  _inviteRole = role;
                                  _inviteRoleId = null;
                                });
                                setModalState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? colors.primary.withValues(alpha: 0.12)
                                      : colors.background,
                                  border: Border.all(
                                    color: selected ? colors.primary : colors.border,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _titleCase(role),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: selected ? colors.primary : colors.textSecondary,
                                    fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (customRoles.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Custom roles (defined in Roles & Permissions)',
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: customRoles.map((role) {
                          final roleId = role['id'] as String?;
                          final roleName = (role['name'] as String?) ?? '';
                          final selected =
                              _inviteRoleId != null && _inviteRoleId == roleId;
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setState(() => _inviteRoleId = roleId);
                              setModalState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: selected
                                    ? colors.primary.withValues(alpha: 0.12)
                                    : colors.background,
                                border: Border.all(
                                  color: selected ? colors.primary : colors.border,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 15,
                                    color: selected
                                        ? colors.primary
                                        : colors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    roleName,
                                    style: TextStyle(
                                      color: selected
                                          ? colors.primary
                                          : colors.textSecondary,
                                      fontWeight: selected
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isInviting ? null : _handleInvite,
                      child: _isInviting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Send Invitation'),
                    ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colors.background,
        body: const SafeArea(
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: colors.text),
                    onPressed: () => context.go('/main'),
                  ),
                  Expanded(
                    child: Text(
                      'Team',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => context.push('/main/team-roles'),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.background,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.border),
                      ),
                      child: Icon(Icons.shield_outlined, color: colors.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _showInviteModal,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchTeam,
                child: _teamMembers.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        children: [
                          const SizedBox(height: 64),
                          Icon(Icons.people_outline, size: 64, color: colors.textSecondary),
                          const SizedBox(height: 16),
                          Text(
                            'No team members yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Invite your first team member to get started',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textSecondary, fontSize: 14),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        itemCount: _teamMembers.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _memberCard(_teamMembers[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberCard(TeamMember member) {
    final colors = AppTheme.colors;
    final statusColor = _getStatusColor(member.status);
    final joinedDate = _formatJoinedDate(member.joinedAt);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: colors.primary,
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      member.name,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _titleCase(member.status),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  member.email,
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Tappable role badge → fast path to the role-change modal.
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showRoleModal(member),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _roleBadgeColor(_roleBadgeLabel(member))
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _roleBadgeColor(_roleBadgeLabel(member))
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              member.roleId != null && member.roleName != null
                                  ? Icons.shield_outlined
                                  : _getRoleIcon(member.role),
                              size: 14,
                              color: _roleBadgeColor(_roleBadgeLabel(member)),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _roleBadgeLabel(member),
                              style: TextStyle(
                                color: _roleBadgeColor(_roleBadgeLabel(member)),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.edit_outlined,
                              size: 11,
                              color: _roleBadgeColor(_roleBadgeLabel(member)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showPermissionsSheet(member),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          member.permissions.contains('*')
                              ? 'Full access'
                              : member.permissions.isEmpty
                                  ? 'Default permissions'
                                  : '${member.permissions.length} permission${member.permissions.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    if (joinedDate != null)
                      Text(
                        'Joined $joinedDate',
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              // Explicit 'Change role' affordance (the role badge is tappable
              // too — both open the same role sheet).
              _actionButton(
                icon: Icons.edit_outlined,
                color: colors.textSecondary,
                background: colors.background,
                onTap: () => _showRoleModal(member),
              ),
              const SizedBox(width: 8),
              if (member.status != 'invited')
                _actionButton(
                  icon: member.status == 'active' ? Icons.toggle_on_outlined : Icons.toggle_off_outlined,
                  color: member.status == 'active' ? AppColors.primary : colors.textSecondary,
                  background: colors.background,
                  onTap: () => _handleToggleStatus(member),
                ),
              const SizedBox(width: 8),
              _actionButton(
                icon: Icons.delete_outline,
                color: AppColors.error,
                background: AppColors.error.withValues(alpha: 0.12),
                onTap: () => _handleDelete(member),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required Color background,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}
