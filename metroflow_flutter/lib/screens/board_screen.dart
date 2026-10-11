import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/task.dart';
import '../utils/app_toast.dart';

// ============================================================================
// BOARD SCREEN — clean rebuild (web parity).
//
// This file intentionally mirrors client/pages/Board.tsx on the web:
//   DATA     : GET /board -> [{id, business_id, name, color, is_default,
//              sort_order, created_at, updated_at, tasks: Task[]}]
//              Tasks come DOWN-LOADED IN THE COLUMNS — rendered directly,
//              exactly like the web (no /tasks re-fetch, no local re-bucketing).
//   MOVE     : optimistic local move + PUT /tasks/:id {status: <column NAME>}
//              then refetch (web refetches after a status change).
//   COLUMNS  : POST /task-statuses (create), PUT /task-statuses/:id (edit),
//              DELETE /task-statuses/:id (delete non-default only) — same as web.
//   PARANOID PARSING: every nested object goes through _asMap(), every task
//              parse is individually try/catch'ed — one malformed row can
//              never blank the board again.
// ============================================================================

/// Converts ANY decoded map (Map<String,dynamic>, Map<dynamic,dynamic>,
/// _InternalLinkedHashMap…) into a clean Map<String, dynamic>. Decoded JSON
/// keys are always String; values may need recursion, which call sites do.
Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

/// Parses a task row defensively. Returns null (and logs) on malformed rows
/// instead of throwing through the whole board render.
Task? _parseTask(Object? raw) {
  try {
    return Task.fromJson(_asMap(raw));
  } catch (e) {
    debugPrint('[Board] skipped malformed task: $e');
    return null;
  }
}

String formatDate(String dateString) {
  try {
    final date = DateTime.parse(dateString).toLocal();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  } catch (e) {
    return dateString;
  }
}

class _BoardColumn {
  final String id;
  final String name;
  final String color;
  final bool isDefault;
  final int sortOrder;
  final List<Task> tasks;
  _BoardColumn({
    required this.id,
    required this.name,
    required this.color,
    required this.isDefault,
    required this.sortOrder,
    required this.tasks,
  });

  static _BoardColumn fromJson(Map<String, dynamic> json) {
    final rawTasks = json['tasks'];
    final tasks = <Task>[];
    if (rawTasks is List) {
      for (final t in rawTasks) {
        final parsed = _parseTask(t);
        if (parsed != null) tasks.add(parsed);
      }
    }
    return _BoardColumn(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      color: (json['color'] ?? '#6B7280').toString(),
      isDefault: json['is_default'] == true,
      sortOrder: (json['sort_order'] is num) ? (json['sort_order'] as num).toInt() : 0,
      tasks: tasks,
    );
  }
}

Color _hexToColor(String hex, [Color fallback = const Color(0xFF6B7280)]) {
  try {
    var h = hex.replaceFirst('#', '').trim();
    if (h.length == 6) h = 'ff$h';
    if (h.length == 8) return Color(int.parse(h, radix: 16));
    return fallback;
  } catch (_) {
    return fallback;
  }
}

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  List<_BoardColumn> _columns = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  bool _showOverview = false;
  int _activeColumn = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _fetchBoard();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // DATA — one call, web parity: GET /board
  // --------------------------------------------------------------------------
  Future<void> _fetchBoard() async {
    if (!_loading) setState(() => _refreshing = true);
    try {
      final res = await ApiService().getBoard();
      final body = _asMap(res.data);
      if (body['success'] != true) {
        throw Exception((body['error'] ?? body['message'] ?? 'Failed to fetch board').toString());
      }
      final list = body['data'];
      final cols = <_BoardColumn>[];
      if (list is List) {
        for (final raw in list) {
          final c = _asMap(raw);
          if ((c['id'] ?? '').toString().isEmpty) continue;
          cols.add(_BoardColumn.fromJson(c));
        }
      }
      cols.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      if (!mounted) return;
      setState(() {
        _columns = cols;
        _error = null;
        if (_activeColumn >= cols.length) _activeColumn = 0;
      });
    } catch (e) {
      debugPrint('[Board] fetch failed: $e');
      if (mounted) {
        setState(() => _error = ApiService.extractErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  // --------------------------------------------------------------------------
  // MOVE — web: PUT /tasks/:id {status} then fetchBoardData()
  // The backend now resolves a status that matches a column id/name to the
  // canonical column NAME, so sending the name (this screen) and the web's
  // id both land in the same column.
  // --------------------------------------------------------------------------
  Future<void> _moveTask(Task task, _BoardColumn target) async {
    if (task.status.toLowerCase() == target.name.toLowerCase()) return;

    // 1. Optimistic local move (instant feedback — web does the same).
    setState(() {
      _columns = [
        for (final c in _columns)
          _BoardColumn(
            id: c.id,
            name: c.name,
            color: c.color,
            isDefault: c.isDefault,
            sortOrder: c.sortOrder,
            tasks: c.id == target.id
                ? [task, ...c.tasks.where((t) => t.id != task.id)]
                : c.tasks.where((t) => t.id != task.id).toList(),
          ),
      ];
    });

    try {
      await ApiService().updateTask(task.id, {'status': target.name});
      AppToast.show('Task moved to ${target.name}', type: AppToastType.success);
    } catch (e) {
      AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
    } finally {
      await _fetchBoard(); // web refreshes after a status change — same here
    }
  }

  // --------------------------------------------------------------------------
  // COLUMN CRUD — web parity: /task-statuses
  // --------------------------------------------------------------------------
  Future<void> _createColumn() async {
    final result = await _columnDialog(title: 'Create New Status Column');
    if (result == null) return;
    try {
      final res = await ApiService().createTaskStatus({
        'name': result.$1,
        'color': result.$2,
        'sort_order': _columns.length,
      });
      final body = _asMap(res.data);
      if (body['success'] == true) {
        AppToast.show('Column created', type: AppToastType.success);
        await _fetchBoard();
      } else {
        throw Exception((body['error'] ?? 'Failed to create column').toString());
      }
    } catch (e) {
      AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
    }
  }

  Future<void> _editColumn(_BoardColumn column) async {
    final result = await _columnDialog(
      title: 'Edit Column',
      initialName: column.name,
      initialColor: _hexToColor(column.color),
    );
    if (result == null) return;
    try {
      final res = await ApiService().updateTaskStatus(column.id, {
        'name': result.$1,
        'color': result.$2,
      });
      final body = _asMap(res.data);
      if (body['success'] == true) {
        AppToast.show('Column updated', type: AppToastType.success);
        await _fetchBoard();
      } else {
        throw Exception((body['error'] ?? 'Failed to update column').toString());
      }
    } catch (e) {
      AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
    }
  }

  Future<void> _deleteColumn(_BoardColumn column) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete column?'),
        content: Text(
          'This will delete the "${column.name}" column.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await ApiService().deleteTaskStatus(column.id);
      final body = _asMap(res.data);
      if (body['success'] == true) {
        AppToast.show('Column deleted', type: AppToastType.success);
        await _fetchBoard();
      } else {
        throw Exception((body['error'] ?? 'Failed to delete column').toString());
      }
    } catch (e) {
      AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
      await _fetchBoard();
    }
  }

  Future<(String, String)?> _columnDialog({
    required String title,
    String initialName = '',
    Color initialColor = const Color(0xFF6B7280),
  }) async {
    final nameController = TextEditingController(text: initialName);
    Color selected = initialColor;
    final colors = AppTheme.colors;
    return showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: initialName.isEmpty,
                  decoration: const InputDecoration(
                    labelText: 'Status Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Select Color:'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: BlockPicker(
                    pickerColor: selected,
                    onColorChanged: (c) => setDialogState(() => selected = c),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  AppToast.show('Please enter a status name', type: AppToastType.error);
                  return;
                }
                final hex =
                    '#${selected.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
                Navigator.pop(ctx, (name, hex));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // HELPERS
  // --------------------------------------------------------------------------
  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main/tasks');
    }
  }

  void _openTask(Task task) => context.push('/main/task-detail', extra: task);

  void _moveSheet(Task task) {
    final colors = AppTheme.colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                'Move "${task.title}" to…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
            ),
            ...List.generate(_columns.length, (i) {
              final column = _columns[i];
              final accent = _hexToColor(column.color);
              final isCurrent = column.name.toLowerCase() == task.status.toLowerCase();
              return ListTile(
                leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                title: Text(column.name, style: const TextStyle(fontSize: 14)),
                trailing: isCurrent
                    ? const Icon(Icons.check_rounded, size: 18, color: Colors.green)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _moveTask(task, column);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  int get _totalTasks => _columns.fold(0, (n, c) => n + c.tasks.length);
  int get _overdueCount =>
      _columns.fold(0, (n, c) => n + c.tasks.where((t) => t.isOverdue).length);

  // --------------------------------------------------------------------------
  // BUILD
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (_loading) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: colors.primary),
              const SizedBox(height: 16),
              Text('Loading board…', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _IconBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: _goBack),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Board',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: colors.text,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 2),
                        Text(
                          _totalTasks == 0
                              ? 'No tasks yet — add one to get started'
                              : '$_totalTasks task${_totalTasks == 1 ? '' : 's'}'
                                  '${_overdueCount > 0 ? ' · $_overdueCount overdue' : ''}',
                          style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _IconBtn(icon: Icons.refresh_rounded, onTap: _fetchBoard),
                ],
              ),
            ),

            // action row (web parity: Overview · Add Column · Add Task)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  _ActionBtn(
                    label: _showOverview ? 'Show Board' : 'Overview',
                    icon: Icons.donut_small_rounded,
                    onTap: () => setState(() => _showOverview = !_showOverview),
                  ),
                  const SizedBox(width: 8),
                  _ActionBtn(label: 'Column', icon: Icons.add_rounded, onTap: _createColumn),
                  const SizedBox(width: 8),
                  _ActionBtn(
                    label: 'Add Task',
                    icon: Icons.add_rounded,
                    filled: true,
                    onTap: () async {
                      await context.push('/main/create-task');
                      if (mounted) await _fetchBoard();
                    },
                  ),
                ],
              ),
            ),

            Expanded(
              child: _error != null
                  ? RefreshIndicator(
                      onRefresh: _fetchBoard,
                      color: colors.primary,
                      backgroundColor: colors.surface,
                      child: ListView(
                        children: [
                          const SizedBox(height: 64),
                          Icon(Icons.cloud_off_rounded, size: 44, color: colors.textSecondary),
                          const SizedBox(height: 12),
                          Text("Couldn't load the board",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.text)),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, height: 1.4, color: colors.textSecondary),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: OutlinedButton.icon(
                              onPressed: _fetchBoard,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Retry'),
                              style: OutlinedButton.styleFrom(foregroundColor: colors.primary),
                            ),
                          ),
                        ],
                      ),
                    )
                  : _columns.isEmpty
                      ? _EmptyBoard(onAddColumn: _createColumn)
                      : _showOverview
                          ? _Overview(
                              columns: _columns,
                              totalTasks: _totalTasks,
                              overdueCount: _overdueCount,
                              onPick: (i) {
                                setState(() {
                                  _showOverview = false;
                                  _activeColumn = i.clamp(0, _columns.length - 1);
                                });
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) _pageController.jumpToPage(_activeColumn);
                                });
                              },
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchBoard,
                              color: colors.primary,
                              backgroundColor: colors.surface,
                              child: Column(
                                children: [
                                  _ChipRow(
                                    columns: _columns,
                                    active: _activeColumn,
                                    onPick: (i) {
                                      _pageController.animateToPage(
                                        i,
                                        duration: const Duration(milliseconds: 260),
                                        curve: Curves.easeOut,
                                      );
                                      setState(() => _activeColumn = i);
                                    },
                                  ),
                                  Expanded(
                                    child: PageView.builder(
                                      controller: _pageController,
                                      itemCount: _columns.length,
                                      onPageChanged: (i) => setState(() => _activeColumn = i),
                                      itemBuilder: (context, i) =>
                                          _ColumnPage(
                                            column: _columns[i.clamp(0, _columns.length - 1)],
                                            columns: _columns,
                                            onMove: _moveTask,
                                            onOpenTask: _openTask,
                                            onMoveSheet: _moveSheet,
                                            onEditColumn: _editColumn,
                                            onDeleteColumn: _deleteColumn,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// COLUMN PAGE — header card + DragTarget well + task cards
// ============================================================================
class _ColumnPage extends StatelessWidget {
  final _BoardColumn column;
  final List<_BoardColumn> columns;
  final Future<void> Function(Task, _BoardColumn) onMove;
  final void Function(Task) onOpenTask;
  final void Function(Task) onMoveSheet;
  final void Function(_BoardColumn) onEditColumn;
  final void Function(_BoardColumn) onDeleteColumn;

  const _ColumnPage({
    required this.column,
    required this.columns,
    required this.onMove,
    required this.onOpenTask,
    required this.onMoveSheet,
    required this.onEditColumn,
    required this.onDeleteColumn,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final accent = _hexToColor(column.color);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header card (web: dot + name + count + edit + delete-if-not-default)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    column.name,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${column.tasks.length}',
                    style: TextStyle(color: accent, fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => onEditColumn(column),
                  child: Icon(Icons.edit_outlined, size: 16, color: colors.textSecondary),
                ),
                if (!column.isDefault) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => onDeleteColumn(column),
                    child: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: DragTarget<Task>(
              onWillAcceptWithDetails: (details) =>
                  details.data.status.toLowerCase() != column.name.toLowerCase(),
              onAcceptWithDetails: (details) => onMove(details.data, column),
              builder: (context, candidateData, _) {
                final targeting = candidateData.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: targeting ? accent.withValues(alpha: 0.08) : colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: targeting ? accent : colors.border,
                      width: targeting ? 1.6 : 1,
                    ),
                  ),
                  child: column.tasks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.outbound_rounded,
                                  color: colors.textSecondary.withValues(alpha: 0.7), size: 30),
                              const SizedBox(height: 8),
                              Text(
                                targeting ? 'Drop here' : 'No tasks',
                                style: TextStyle(
                                  color: targeting ? accent : colors.textSecondary,
                                  fontSize: 12.5,
                                  fontWeight: targeting ? FontWeight.w700 : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: column.tasks.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final task = column.tasks[i];
                            return _TaskCard(
                              task: task,
                              accent: accent,
                              onTap: () => onOpenTask(task),
                              onMove: () => onMoveSheet(task),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TASK CARD — web parity: accent stripe, title, description, due chip,
// epic chip. Long-press = move sheet (single-column view can't drag across
// pages); drag within the page targets the column well.
// ============================================================================
class _TaskCard extends StatelessWidget {
  final Task task;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onMove;

  const _TaskCard({required this.task, required this.accent, required this.onTap, required this.onMove});

  String? _dueLabel() {
    final raw = task.dueDate?.isNotEmpty == true ? task.dueDate : task.endDate;
    if (raw == null || raw.isEmpty) return null;
    try {
      final d = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(d.year, d.month, d.day);
      final diff = day.difference(today).inDays;
      if (diff < 0) return 'Overdue · ${formatDate(raw)}';
      if (diff == 0) return 'Due today';
      if (diff == 1) return 'Due tomorrow';
      return 'Due ${formatDate(raw)}';
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final due = _dueLabel();
    final overdue = task.isOverdue;

    return Draggable<Task>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 260),
          child: _card(context, colors, dragging: true),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: _card(context, colors)),
      child: _card(context, colors),
    );
  }

  Widget _card(BuildContext context, dynamic colors, {bool dragging = false}) {
    final due = _dueLabel();
    final overdue = task.isOverdue;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onMove,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
          boxShadow: dragging
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (task.description?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          task.description!,
                          style: TextStyle(fontSize: 11.5, height: 1.35, color: colors.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (due != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: overdue
                                    ? Colors.red.withValues(alpha: 0.12)
                                    : colors.surfaceVariant,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: overdue ? Colors.red.withValues(alpha: 0.4) : colors.border,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    overdue ? Icons.warning_amber_rounded : Icons.calendar_today_rounded,
                                    size: 10,
                                    color: overdue ? Colors.red : colors.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    due,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: overdue ? Colors.red : colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (task.epic?.isNotEmpty == true) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
                                ),
                                child: Text(
                                  task.epic!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: colors.primary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (task.assignedTo?.isNotEmpty == true)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_rounded, size: 11, color: colors.textSecondary),
                                const SizedBox(width: 3),
                                Text(
                                  '${task.assignedTo!.length}',
                                  style: TextStyle(fontSize: 10.5, color: colors.textSecondary),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CHIP ROW (web mobile parity — tap chip to page to that column)
// ============================================================================
class _ChipRow extends StatelessWidget {
  final List<_BoardColumn> columns;
  final int active;
  final void Function(int) onPick;

  const _ChipRow({required this.columns, required this.active, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: columns.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final column = columns[i];
          final isActive = i == active.clamp(0, columns.length - 1);
          final accent = _hexToColor(column.color);
          return GestureDetector(
            onTap: () => onPick(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isActive ? accent : colors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: isActive ? accent : colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? Colors.white : accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    column.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isActive ? Colors.white : colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white24 : colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${column.tasks.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isActive ? Colors.white : colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// OVERVIEW (web "Status Overview" parity)
// ============================================================================
class _Overview extends StatelessWidget {
  final List<_BoardColumn> columns;
  final int totalTasks;
  final int overdueCount;
  final void Function(int) onPick;

  const _Overview({
    required this.columns,
    required this.totalTasks,
    required this.overdueCount,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: CustomPaint(
                  painter: _DonutPainter(columns),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$totalTasks total tasks',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colors.text)),
                    const SizedBox(height: 4),
                    Text(
                      overdueCount > 0 ? '$overdueCount overdue — needs attention' : 'Nothing overdue',
                      style: TextStyle(
                        fontSize: 12,
                        color: overdueCount > 0 ? Colors.red : colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${columns.length} columns',
                        style: TextStyle(fontSize: 11.5, color: colors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...List.generate(columns.length, (i) {
          final c = columns[i];
          final accent = _hexToColor(c.color);
          final pct = totalTasks == 0 ? 0.0 : c.tasks.length / totalTasks;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onPick(i),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(c.name,
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: colors.text)),
                        ),
                        Text('${c.tasks.length}',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: accent)),
                        const SizedBox(width: 6),
                        Icon(Icons.chevron_right_rounded, size: 18, color: colors.textSecondary),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 5,
                        backgroundColor: colors.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<_BoardColumn> columns;
  _DonutPainter(this.columns);

  @override
  void paint(Canvas canvas, Size size) {
    final total = columns.fold(0, (n, c) => n + c.tasks.length);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    if (total == 0) {
      canvas.drawCircle(rect.center, size.width / 2 - 6, Paint()..color = const Color(0x226B7280));
      return;
    }
    double start = -math.pi / 2;
    for (final c in columns) {
      if (c.tasks.isEmpty) continue;
      final sweep = (c.tasks.length / total) * 2 * math.pi;
      canvas.drawArc(
        rect.deflate(6),
        start,
        sweep,
        true,
        Paint()..color = _hexToColor(c.color),
      );
      start += sweep;
    }
    canvas.drawCircle(
      rect.center,
      size.width / 2 - 14,
      Paint()..color = AppTheme.colors.surface,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => oldDelegate.columns != columns;
}

// ============================================================================
// SMALL WIDGETS
// ============================================================================
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 19, color: colors.text),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.icon, this.filled = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Material(
      color: filled ? colors.primary : colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: filled ? Colors.white : colors.text),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: filled ? Colors.white : colors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  final VoidCallback onAddColumn;
  const _EmptyBoard({required this.onAddColumn});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.view_kanban_outlined, size: 56, color: colors.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Text('No columns yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colors.text)),
          const SizedBox(height: 6),
          Text(
            'Create your first status column to start\norganising tasks on the board.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.5, color: colors.textSecondary),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: onAddColumn,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create Column'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
