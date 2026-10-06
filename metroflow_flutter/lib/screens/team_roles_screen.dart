import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';

/// Safely extracts `payload['data'][key]` as a List regardless of the
/// decoded-JSON runtime type. Never throws, never relies on `as` inside
/// `&&` chains (a `bool && x as List?` precedence bug broke the release
/// build once — this helper makes that class of bug impossible).
List<dynamic> _dataList(dynamic payload, String key) {
  if (payload is Map) {
    final dynamic data = payload['data'];
    if (data is Map) {
      final dynamic raw = data[key];
      if (raw is List) return raw;
    }
  }
  return const <dynamic>[];
}

/// Role & Permission management for the business workspace.
///
/// Mirrors the web app's /team/roles page and the platform-admin RBAC:
///  - list the workspace's custom roles (with member counts + permissions)
///  - create a role and assign a permission set to it
///  - edit / delete roles (members fall back to their default role on delete)
/// Enforcement happens server-side; this UI is management-only.
class TeamRolesScreen extends StatefulWidget {
  const TeamRolesScreen({super.key});

  @override
  State<TeamRolesScreen> createState() => _TeamRolesScreenState();
}

class _Role {
  final String id;
  final String name;
  final String? description;
  final bool isSystem;
  final List<String> permissions;
  final int memberCount;

  _Role({
    required this.id,
    required this.name,
    this.description,
    required this.isSystem,
    required this.permissions,
    required this.memberCount,
  });

  factory _Role.fromJson(Map<String, dynamic> json) {
    return _Role(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: json['description'] as String?,
      // Defensive: the backend returns snake_case; older payloads may not
      // carry the flag at all (then it's simply not a system role).
      isSystem: json['is_system'] == true || json['isSystem'] == true,
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .map((p) => p.toString())
          .toList(),
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class _Permission {
  final String id;
  final String name;
  final String description;

  _Permission({
    required this.id,
    required this.name,
    required this.description,
  });

  factory _Permission.fromJson(Map<String, dynamic> json) {
    return _Permission(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
    );
  }
}

class _TeamRolesScreenState extends State<TeamRolesScreen> {
  List<_Role> _roles = [];
  List<_Permission> _catalog = [];
  Map<String, List<_Permission>> _grouped = {};
  bool _canManage = true;
  bool _isLoading = true;

  /// TRUE when the ROLES call itself failed (a REAL error, distinct from an
  /// empty list) — renders the error state with a Retry button.
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // DECOUPLED LOADING (was Future.wait = all-or-nothing): GET /roles/me
    // legitimately answers 401 "Unauthorized" for personal accounts (no
    // business workspace) and that ONE throw left the screen stuck on a
    // permanent empty state hiding the roles list. Each call now fails
    // independently; only a failure of the ROLES call itself is fatal.
    // (The 401s no longer trip the session-expiry logout either — the three
    // methods send suppressSessionLogout in their dio extra.)
    dynamic rolesRes;
    dynamic permRes;
    dynamic meRes;
    try {
      rolesRes = await ApiService().getRoles();
    } catch (e) {
      debugPrint('getRoles failed: $e');
    }
    try {
      permRes = await ApiService().getRolePermissions();
    } catch (e) {
      debugPrint('getRolePermissions failed: $e');
    }
    try {
      meRes = await ApiService().getMyTeamRole();
    } catch (e) {
      debugPrint('getMyTeamRole failed: $e');
    }

    if (!mounted) return;

    // REAL error: the roles list itself failed → error state with retry.
    if (rolesRes == null) {
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
      return;
    }

    final rolesData = rolesRes.data;
    final permData = permRes?.data;
    final meData = meRes?.data;

    final roles = _dataList(rolesData, 'roles')
        .whereType<Map>()
        .map((r) => _Role.fromJson(Map<String, dynamic>.from(r)))
        .toList();

    final catalog = _dataList(permData, 'permissions')
        .whereType<Map>()
        .map((p) => _Permission.fromJson(Map<String, dynamic>.from(p)))
        .toList();

    // '*' means the caller is owner/admin with full access. When /roles/me
    // is unavailable (personal account → 401) the previous/default
    // _canManage value is KEPT instead of downgrading the UI.
    final myPerms = _dataList(meData, 'permissions')
        .map((p) => p.toString())
        .toList();
    final wildcard = meData is Map && meData['data']?['wildcard'] == true;
    final canManage = meRes == null
        ? _canManage
        : (wildcard || myPerms.contains('manage_team'));

    setState(() {
      _roles = roles;
      _catalog = catalog;
      _grouped = _groupCatalog(catalog);
      _canManage = canManage;
      _isLoading = false;
      _loadFailed = false;
    });
  }

  /// Groups the flat permission catalog the same way the web Role Management
  /// page does (Overview / Workspace / Team / Calls & Meetings / Money / ...).
  Map<String, List<_Permission>> _groupCatalog(List<_Permission> catalog) {
    String groupFor(_Permission p) {
      if (p.id.startsWith('rtc.')) return 'Calls & Meetings';
      switch (p.id) {
        case 'view_dashboard':
        case 'view_activity':
        case 'view_ranking':
        case 'export_data':
          return 'Overview';
        case 'manage_tasks':
        case 'manage_epics':
        case 'manage_ideas':
          return 'Workspace';
        case 'manage_team':
        case 'use_meetings':
        case 'use_chat':
        case 'use_calls':
          return 'Team';
        case 'manage_finance':
          return 'Money';
        case 'manage_payment_links':
        case 'manage_invoices':
        case 'manage_store':
        case 'manage_subscriptions':
          return 'Get Paid';
        case 'manage_growth':
          return 'Growth';
        default:
          return 'Other';
      }
    }

    const order = [
      'Overview',
      'Workspace',
      'Team',
      'Calls & Meetings',
      'Money',
      'Get Paid',
      'Growth',
      'Other',
    ];

    final grouped = <String, List<_Permission>>{};
    for (final p in catalog) {
      grouped.putIfAbsent(groupFor(p), () => []).add(p);
    }
    final sorted = <String, List<_Permission>>{};
    for (final key in order) {
      if (grouped.containsKey(key)) sorted[key] = grouped[key]!;
    }
    return sorted;
  }

  String _prettyPermission(String id) {
    for (final p in _catalog) {
      if (p.id == id) return p.name;
    }
    return id.replaceAll('_', ' ').replaceAll('rtc.', '');
  }

  Future<void> _openRoleEditor({_Role? existing}) async {
    if (!_canManage) {
      Fluttertoast.showToast(
        msg: 'Only owners, admins and members with Manage Team can manage roles',
        backgroundColor: AppColors.error,
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RoleEditorSheet(
        existing: existing,
        catalog: _catalog,
        grouped: _grouped,
        onSaved: _load,
      ),
    );
  }

  Future<void> _handleDelete(_Role role) async {
    if (!_canManage) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text(
          'Delete "${role.name}"? Its ${role.memberCount} assigned member(s) will fall back to their default role.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService().deleteRole(role.id);
      Fluttertoast.showToast(msg: 'Role deleted');
      await _load();
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

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
                    onPressed: () => context.go('/main/team'),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Roles & Permissions',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Create roles and assign exactly what each role can do',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _openRoleEditor(),
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
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _loadFailed
                      ? ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          children: [
                            const SizedBox(height: 64),
                            const Icon(Icons.error_outline,
                                size: 64, color: AppColors.error),
                            const SizedBox(height: 16),
                            Text(
                              'Could not load roles',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Something went wrong while fetching your workspace roles. Check your connection and try again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: colors.textSecondary, fontSize: 14),
                            ),
                            const SizedBox(height: 24),
                            Center(
                              child: OutlinedButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ),
                          ],
                        )
                      : RefreshIndicator(
                      onRefresh: _load,
                      child: _roles.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              children: [
                                const SizedBox(height: 64),
                                Icon(Icons.shield_outlined,
                                    size: 64, color: colors.textSecondary),
                                const SizedBox(height: 16),
                                Text(
                                  'No custom roles yet',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colors.text,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Create a role and assign the exact permissions it should have',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: colors.textSecondary, fontSize: 14),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              itemCount: _roles.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) =>
                                  _roleCard(_roles[index]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleCard(_Role role) {
    final colors = AppTheme.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  role.name,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // System/default roles cannot be deleted (backend blocks it);
              // editing their permissions IS allowed.
              if (role.isSystem) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'Default',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${role.memberCount} member${role.memberCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _actionButton(
                icon: Icons.edit_outlined,
                color: colors.textSecondary,
                background: colors.background,
                onTap: () => _openRoleEditor(existing: role),
              ),
              // Delete is only offered for custom roles (system roles are
              // protected server-side too).
              if (!role.isSystem) ...[
                const SizedBox(width: 8),
                _actionButton(
                  icon: Icons.delete_outline,
                  color: AppColors.error,
                  background: AppColors.error.withValues(alpha: 0.12),
                  onTap: () => _handleDelete(role),
                ),
              ],
            ],
          ),
          if (role.description != null && role.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              role.description!,
              style: TextStyle(color: colors.textSecondary, fontSize: 13.5),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in role.permissions.take(6))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    _prettyPermission(p),
                    style: TextStyle(color: colors.textSecondary, fontSize: 11.5),
                  ),
                ),
              if (role.permissions.length > 6)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    '+${role.permissions.length - 6} more',
                    style: TextStyle(color: colors.textSecondary, fontSize: 11.5),
                  ),
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

/// Create / edit role sheet: name, description and grouped permission
/// checkboxes (identical grouping to the web Role Management page).
class _RoleEditorSheet extends StatefulWidget {
  final _Role? existing;
  final List<_Permission> catalog;
  final Map<String, List<_Permission>> grouped;
  final Future<void> Function() onSaved;

  const _RoleEditorSheet({
    this.existing,
    required this.catalog,
    required this.grouped,
    required this.onSaved,
  });

  @override
  State<_RoleEditorSheet> createState() => _RoleEditorSheetState();
}

class _RoleEditorSheetState extends State<_RoleEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late Set<String> _selected;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.existing?.description ?? '');
    _selected = Set<String>.from(widget.existing?.permissions ?? const []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      Fluttertoast.showToast(msg: 'Role name is required', backgroundColor: AppColors.error);
      return;
    }
    setState(() => _saving = true);
    try {
      final payload = {
        'name': name,
        'description': _descriptionController.text.trim(),
        'permissions': _selected.toList(),
      };
      if (_isEdit) {
        await ApiService().updateRole(widget.existing!.id, payload);
      } else {
        await ApiService().createRole(payload);
      }
      Fluttertoast.showToast(msg: _isEdit ? 'Role updated' : 'Role "$name" created');
      Navigator.of(context).pop();
      await widget.onSaved();
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isEdit ? 'Edit Role' : 'Create Role',
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
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Role name *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration:
                          const InputDecoration(hintText: 'Description (optional)'),
                    ),
                    const SizedBox(height: 16),
                    ...widget.grouped.entries.map((entry) {
                      final perms = entry.value;
                      final allSelected =
                          perms.every((p) => _selected.contains(p.id));
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                entry.key,
                                style: TextStyle(
                                  color: colors.text,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setState(() {
                                    if (allSelected) {
                                      _selected.removeAll(perms.map((p) => p.id));
                                    } else {
                                      _selected.addAll(perms.map((p) => p.id));
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  child: Text(
                                    allSelected ? 'Unselect all' : 'Select all',
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ...perms.map((p) {
                            final checked = _selected.contains(p.id);
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(() {
                                  if (checked) {
                                    _selected.remove(p.id);
                                  } else {
                                    _selected.add(p.id);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: Checkbox(
                                        value: checked,
                                        activeColor: colors.primary,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selected.add(p.id);
                                            } else {
                                              _selected.remove(p.id);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            style: TextStyle(
                                              color: colors.text,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (p.description.isNotEmpty)
                                            Text(
                                              p.description,
                                              style: TextStyle(
                                                color: colors.textSecondary,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 12),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_isEdit ? 'Save Changes' : 'Create Role'),
            ),
          ],
        ),
      ),
    );
  }
}
