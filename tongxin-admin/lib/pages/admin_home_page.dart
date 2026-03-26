import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/admin_api_client.dart';
import '../l10n/admin_strings.dart';
import 'admin_activities_panel.dart';
import 'admin_login_page.dart';
import 'admin_reports_panel.dart';
import 'admin_settings_panel.dart';
import 'admin_teacher_panel.dart';
import 'admin_trading_panel.dart';

enum AdminSection {
  dashboard,
  users,
  teachers,
  admins,
  appConfig,
  activities,
  trading,
  systemMessages,
  reports,
  settings,
}

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  AdminSection _section = AdminSection.teachers;

  void _logout() {
    AdminApiClient.instance.clearSessionToken();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminLoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AdminStrings.adminTitle),
        actions: [
          TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('退出'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          _SideNav(
            current: _section,
            onSelect: (section) => setState(() => _section = section),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildSection()),
        ],
      ),
    );
  }

  Widget _buildSection() {
    switch (_section) {
      case AdminSection.dashboard:
        return _DashboardPanel(
          onGoToTeachers: () =>
              setState(() => _section = AdminSection.teachers),
        );
      case AdminSection.users:
        return const _AdminUserPanel();
      case AdminSection.admins:
        return const _AdminAccountsPanel();
      case AdminSection.appConfig:
        return const _AppConfigPanel();
      case AdminSection.activities:
        return const AdminActivitiesPanel();
      case AdminSection.trading:
        return const AdminTradingPanel();
      case AdminSection.teachers:
        return const AdminTeacherPanel();
      case AdminSection.systemMessages:
        return _PlaceholderPanel(
          title: AdminStrings.adminSystemMessages,
          description: AdminStrings.adminSystemMessagesDesc,
          hint: AdminStrings.adminSystemMessagesHint,
        );
      case AdminSection.reports:
        return const AdminReportsPanel();
      case AdminSection.settings:
        return const AdminSettingsPanel();
    }
  }
}

class _DashboardPanel extends StatefulWidget {
  const _DashboardPanel({this.onGoToTeachers});

  final VoidCallback? onGoToTeachers;

  @override
  State<_DashboardPanel> createState() => _DashboardPanelState();
}

class _DashboardPanelState extends State<_DashboardPanel> {
  static const Color _accent = Color(0xFFD4AF37);
  final _api = AdminApiClient.instance;

  Future<Map<String, int>> _loadStats() async {
    try {
      final resp = await _api.get('api/admin/teachers/stats');
      if (resp.statusCode != 200) return {};
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return {
        'pending': (json['pending'] as num?)?.toInt() ?? 0,
        'approved': (json['approved'] as num?)?.toInt() ?? 0,
        'rejected': (json['rejected'] as num?)?.toInt() ?? 0,
        'frozen': (json['frozen'] as num?)?.toInt() ?? 0,
        'blocked': (json['blocked'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          AdminStrings.adminOverview,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: _accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AdminStrings.adminKeyMetrics,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 24),
        FutureBuilder<Map<String, int>>(
          future: _loadStats(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: _accent),
                ),
              );
            }
            final counts = snapshot.data ?? {};
            final total = counts.values.fold<int>(0, (a, b) => a + b);
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _StatCard(
                  label: AdminStrings.adminTeachersTotal,
                  value: total.toString(),
                  icon: Icons.people,
                ),
                _StatCard(
                  label: AdminStrings.adminPending,
                  value: (counts['pending'] ?? 0).toString(),
                  icon: Icons.pending_actions,
                  accent: Colors.orange,
                ),
                _StatCard(
                  label: AdminStrings.adminApproved,
                  value: (counts['approved'] ?? 0).toString(),
                  icon: Icons.check_circle_outline,
                  accent: Colors.green,
                ),
                _StatCard(
                  label: AdminStrings.adminRejected,
                  value: (counts['rejected'] ?? 0).toString(),
                  icon: Icons.cancel_outlined,
                  accent: Colors.grey,
                ),
                _StatCard(
                  label: AdminStrings.adminFrozen,
                  value: (counts['frozen'] ?? 0).toString(),
                  icon: Icons.ac_unit,
                  accent: Colors.blue,
                ),
                _StatCard(
                  label: AdminStrings.adminBlocked,
                  value: (counts['blocked'] ?? 0).toString(),
                  icon: Icons.block,
                  accent: Colors.red,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 32),
        Text(
          AdminStrings.pcQuickEntry,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (widget.onGoToTeachers != null)
              ActionChip(
                avatar: const Icon(
                  Icons.verified_outlined,
                  color: _accent,
                  size: 20,
                ),
                label: Text(AdminStrings.adminTeacherReview),
                onPressed: widget.onGoToTeachers,
              ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  static const Color _accent = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final color = accent ?? _accent;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminUserPanel extends StatefulWidget {
  const _AdminUserPanel();

  @override
  State<_AdminUserPanel> createState() => _AdminUserPanelState();
}

class _AdminUserPanelState extends State<_AdminUserPanel> {
  static const Color _accent = Color(0xFFD4AF37);
  final _api = AdminApiClient.instance;

  List<Map<String, dynamic>> _users = [];
  final Map<String, String> _userNameById = {};
  final Map<String, int> _reportCountByUser = {};
  final Map<String, List<Map<String, dynamic>>> _reportHistoryByUser = {};
  final Map<String, List<Map<String, dynamic>>> _reportSubmittedHistoryByUser =
      {};
  bool _loading = true;
  String? _loadError;
  String? _selectedUserId;
  String _roleFilter = 'all';
  String _statusFilter = 'all';
  String _keyword = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final usersResp = await _api.get('api/admin/users/detailed');
      if (usersResp.statusCode != 200) {
        throw StateError('加载用户失败(${usersResp.statusCode})：${usersResp.body}');
      }
      final usersJson = jsonDecode(usersResp.body) as List<dynamic>;
      final list = usersJson
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final userNameById = <String, String>{};
      for (final u in list) {
        final uid = u['user_id']?.toString();
        if (uid == null || uid.isEmpty) continue;
        final display = u['display_name']?.toString().trim();
        final email = u['email']?.toString().trim();
        final shortId = u['short_id']?.toString().trim();
        userNameById[uid] = (display != null && display.isNotEmpty)
            ? display
            : ((email != null && email.isNotEmpty)
                  ? email
                  : (shortId != null && shortId.isNotEmpty ? shortId : uid));
      }
      final userIds = list
          .map((e) => e['user_id']?.toString())
          .whereType<String>()
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      final userIdSet = userIds.toSet();
      final reportCountByUser = <String, int>{};
      final reportHistoryByUser = <String, List<Map<String, dynamic>>>{};
      final reportSubmittedHistoryByUser =
          <String, List<Map<String, dynamic>>>{};
      if (userIds.isNotEmpty) {
        final reportsResp = await _api.get('api/reports');
        if (reportsResp.statusCode != 200) {
          throw StateError(
            '加载举报失败(${reportsResp.statusCode})：${reportsResp.body}',
          );
        }
        final reportsRes = jsonDecode(reportsResp.body) as List<dynamic>;
        for (final raw in reportsRes) {
          final row = Map<String, dynamic>.from(raw as Map);
          final rid = row['reported_user_id']?.toString();
          final sid = row['reporter_id']?.toString();
          if (rid != null && rid.isNotEmpty && userIdSet.contains(rid)) {
            reportCountByUser[rid] = (reportCountByUser[rid] ?? 0) + 1;
            final listByUser = reportHistoryByUser.putIfAbsent(
              rid,
              () => <Map<String, dynamic>>[],
            );
            if (listByUser.length < 10) listByUser.add(row);
          }
          if (sid != null && sid.isNotEmpty && userIdSet.contains(sid)) {
            final submitted = reportSubmittedHistoryByUser.putIfAbsent(
              sid,
              () => <Map<String, dynamic>>[],
            );
            if (submitted.length < 10) submitted.add(row);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _users = list;
        _userNameById
          ..clear()
          ..addAll(userNameById);
        _reportCountByUser
          ..clear()
          ..addAll(reportCountByUser);
        _reportHistoryByUser
          ..clear()
          ..addAll(reportHistoryByUser);
        _reportSubmittedHistoryByUser
          ..clear()
          ..addAll(reportSubmittedHistoryByUser);
        _loading = false;
        final hasSelected =
            _selectedUserId != null &&
            list.any((u) => u['user_id']?.toString() == _selectedUserId);
        if (!hasSelected) _selectedUserId = null;
      });
    } catch (e, st) {
      debugPrint('_AdminUserPanel _loadUsers: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _updateRestrictions(
    String userId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final resp = await _api.patch(
        'api/admin/users/$userId/restrictions',
        body: payload,
      );
      if (resp.statusCode != 200) {
        throw StateError('更新限制失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminSaved)));
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AdminStrings.adminSaveFailed(e.toString())),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _setBannedOrFrozen(
    String userId,
    bool isBanned,
    int? days,
  ) async {
    final key = isBanned ? 'banned_until' : 'frozen_until';
    final DateTime? until = days == null
        ? null
        : (days <= 0
              ? DateTime(2099, 1, 1)
              : DateTime.now().add(Duration(days: days)));
    await _updateRestrictions(userId, {
      key: until?.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  String _roleLabel(Map<String, dynamic> user) {
    final role =
        (user['effective_role'] ?? user['role'])
            ?.toString()
            .trim()
            .toLowerCase() ??
        'user';
    final teacherStatus = user['teacher_status']
        ?.toString()
        .trim()
        .toLowerCase();
    if (role.contains('customer_service')) return '客服';
    if (role.contains('teacher')) return '交易员';
    if (teacherStatus != null &&
        teacherStatus.isNotEmpty &&
        teacherStatus != 'rejected') {
      return '交易员';
    }
    return '普通会员';
  }

  bool _isRestricted(Map<String, dynamic> user) {
    final bannedUntil = user['banned_until'] != null
        ? DateTime.tryParse(user['banned_until'].toString())
        : null;
    final frozenUntil = user['frozen_until'] != null
        ? DateTime.tryParse(user['frozen_until'].toString())
        : null;
    final now = DateTime.now();
    final hardRestricted =
        (bannedUntil != null && bannedUntil.isAfter(now)) ||
        (frozenUntil != null && frozenUntil.isAfter(now));
    if (hardRestricted) return true;
    return user['restrict_login'] == true ||
        user['restrict_send_message'] == true ||
        user['restrict_add_friend'] == true ||
        user['restrict_join_group'] == true ||
        user['restrict_create_group'] == true;
  }

  String _statusLabel(Map<String, dynamic> user) =>
      _isRestricted(user) ? '受限' : '正常';

  List<Map<String, dynamic>> get _filteredUsers {
    return _users
        .where((u) {
          if (_roleFilter != 'all' && _roleLabel(u) != _roleFilter)
            return false;
          if (_statusFilter != 'all' && _statusLabel(u) != _statusFilter)
            return false;
          if (_keyword.isNotEmpty) {
            final k = _keyword.toLowerCase();
            final text = <String>[
              u['display_name']?.toString() ?? '',
              u['email']?.toString() ?? '',
              u['short_id']?.toString() ?? '',
              u['user_id']?.toString() ?? '',
            ].join(' ').toLowerCase();
            if (!text.contains(k)) return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _filteredUsers;
    final selectedUser = _selectedUserId == null
        ? null
        : filteredUsers
              .where((u) => u['user_id']?.toString() == _selectedUserId)
              .cast<Map<String, dynamic>?>()
              .firstWhere((u) => u != null, orElse: () => null);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 1,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Text(
                    AdminStrings.adminUserManagement,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: _accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '共 ${_users.length} 人 · 当前 ${filteredUsers.length} 人',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loading ? null : _loadUsers,
                    tooltip: AdminStrings.adminRefresh,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('角色'),
                  ...<String>['all', '普通会员', '客服', '交易员'].map(
                    (r) => ChoiceChip(
                      label: Text(r == 'all' ? '全部' : r),
                      selected: _roleFilter == r,
                      onSelected: (_) {
                        setState(() => _roleFilter = r);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text('状态'),
                  ...<String>['all', '正常', '受限'].map(
                    (s) => ChoiceChip(
                      label: Text(s == 'all' ? '全部' : s),
                      selected: _statusFilter == s,
                      onSelected: (_) {
                        setState(() => _statusFilter = s);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '搜索昵称 / 邮箱 / 用户ID',
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _keyword = v.trim()),
                    ),
                  ),
                  if (_roleFilter != 'all' ||
                      _statusFilter != 'all' ||
                      _keyword.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _roleFilter = 'all';
                        _statusFilter = 'all';
                        _keyword = '';
                        _searchController.clear();
                      }),
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('清空筛选'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                  ),
                )
              else if (_loadError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(AdminStrings.chartQuoteLoadFailed),
                        const SizedBox(height: 4),
                        Text(
                          _loadError ?? '',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadUsers,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(AdminStrings.commonRetry),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_users.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 56,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '没有匹配当前筛选条件的用户',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                              ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...List.generate(filteredUsers.length, (i) {
                  final u = filteredUsers[i];
                  final name = u['display_name']?.toString().trim() ?? '—';
                  final uid = u['user_id']?.toString() ?? '';
                  final reportCount = _reportCountByUser[uid] ?? 0;
                  final role = _roleLabel(u);
                  final status = _statusLabel(u);
                  final selected = _selectedUserId == uid;
                  return ListTile(
                    selected: selected,
                    leading:
                        u['avatar_url'] != null &&
                            u['avatar_url'].toString().trim().isNotEmpty
                        ? CircleAvatar(
                            backgroundImage: NetworkImage(
                              u['avatar_url'].toString(),
                            ),
                          )
                        : const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(name),
                    subtitle: Text(
                      '${u['email']?.toString().trim() ?? u['user_id']?.toString() ?? '—'}'
                      '  ·  $role  ·  $status'
                      '${reportCount > 0 ? '  ·  被投诉 $reportCount 次' : ''}',
                    ),
                    onTap: () => setState(() => _selectedUserId = uid),
                  );
                }),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 1,
          child: selectedUser == null
              ? Center(
                  child: Text(
                    AdminStrings.adminSelectUser,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                )
              : _UserDetailPanel(
                  user: selectedUser,
                  userNameById: _userNameById,
                  reportCount:
                      _reportCountByUser[selectedUser['user_id']?.toString() ??
                          ''] ??
                      0,
                  reportHistory:
                      _reportHistoryByUser[selectedUser['user_id']
                              ?.toString() ??
                          ''] ??
                      const [],
                  submittedReportHistory:
                      _reportSubmittedHistoryByUser[selectedUser['user_id']
                              ?.toString() ??
                          ''] ??
                      const [],
                  onUpdate: _updateRestrictions,
                  onSetBannedOrFrozen: _setBannedOrFrozen,
                  onRefresh: _loadUsers,
                ),
        ),
      ],
    );
  }
}

class _UserDetailPanel extends StatelessWidget {
  const _UserDetailPanel({
    required this.user,
    required this.userNameById,
    required this.reportCount,
    required this.reportHistory,
    required this.submittedReportHistory,
    required this.onUpdate,
    required this.onSetBannedOrFrozen,
    required this.onRefresh,
  });

  final Map<String, dynamic> user;
  final Map<String, String> userNameById;
  final int reportCount;
  final List<Map<String, dynamic>> reportHistory;
  final List<Map<String, dynamic>> submittedReportHistory;
  final Future<void> Function(String userId, Map<String, dynamic> payload)
  onUpdate;
  final Future<void> Function(String userId, bool isBanned, int? days)
  onSetBannedOrFrozen;
  final VoidCallback onRefresh;

  static const Color _accent = Color(0xFFD4AF37);

  bool _bool(String key) => user[key] == true;

  Future<void> _toggle(BuildContext context, String key, bool value) async {
    final userId = user['user_id']?.toString();
    if (userId == null) return;
    await onUpdate(userId, {
      key: value,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = user['user_id']?.toString() ?? '—';
    final name = user['display_name']?.toString().trim() ?? '—';
    final email = user['email']?.toString().trim();
    final role = user['role']?.toString() ?? 'user';
    final shortId = user['short_id']?.toString();
    final signature = user['signature']?.toString().trim();
    final bannedUntil = user['banned_until'] != null
        ? DateTime.tryParse(user['banned_until'].toString())
        : null;
    final frozenUntil = user['frozen_until'] != null
        ? DateTime.tryParse(user['frozen_until'].toString())
        : null;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          AdminStrings.adminUserProfile,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: _accent),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            user['avatar_url'] != null &&
                    user['avatar_url'].toString().trim().isNotEmpty
                ? CircleAvatar(
                    radius: 40,
                    backgroundImage: NetworkImage(
                      user['avatar_url'].toString(),
                    ),
                  )
                : const CircleAvatar(
                    radius: 40,
                    child: Icon(Icons.person, size: 40),
                  ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(AdminStrings.adminNickname, name),
                  _row(AdminStrings.authEmail, email ?? '—'),
                  _row(AdminStrings.adminUserId, userId),
                  if (shortId != null && shortId.isNotEmpty)
                    _row(AdminStrings.adminShortId, shortId),
                  _row(AdminStrings.adminRole, role),
                  if (signature != null && signature.isNotEmpty)
                    _row(AdminStrings.adminSignature, signature),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          AdminStrings.adminRestrictAndBan,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: _accent),
        ),
        const SizedBox(height: 8),
        if (bannedUntil != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Chip(
              avatar: const Icon(Icons.block, color: Colors.red, size: 18),
              label: Text(
                AdminStrings.adminBanUntil(
                  bannedUntil.toIso8601String().split('T').first,
                ),
              ),
              backgroundColor: Colors.red.withOpacity(0.2),
            ),
          ),
        if (frozenUntil != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Chip(
              avatar: const Icon(Icons.ac_unit, color: Colors.blue, size: 18),
              label: Text(
                AdminStrings.adminFrozenUntil(
                  frozenUntil.toIso8601String().split('T').first,
                ),
              ),
              backgroundColor: Colors.blue.withOpacity(0.2),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _showBannedFrozenDialog(context, true),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              child: Text(AdminStrings.adminBan),
            ),
            OutlinedButton(
              onPressed: () => _showBannedFrozenDialog(context, false),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.blue),
              child: Text(AdminStrings.adminFreeze),
            ),
            OutlinedButton(
              onPressed: () => onSetBannedOrFrozen(userId, true, null),
              child: const Text('解除封禁'),
            ),
            OutlinedButton(
              onPressed: () => onSetBannedOrFrozen(userId, false, null),
              child: const Text('解除冻结'),
            ),
            OutlinedButton(
              onPressed: () async {
                await onUpdate(userId, {
                  'banned_until': null,
                  'frozen_until': null,
                  'restrict_login': false,
                  'restrict_send_message': false,
                  'restrict_add_friend': false,
                  'restrict_join_group': false,
                  'restrict_create_group': false,
                  'updated_at': DateTime.now().toIso8601String(),
                });
              },
              child: const Text('解除全部限制'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          AdminStrings.adminRestrictHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: Text(AdminStrings.adminRestrictLogin),
          subtitle: Text(AdminStrings.adminRestrictLoginSub),
          value: _bool('restrict_login'),
          onChanged: (v) => _toggle(context, 'restrict_login', v),
        ),
        SwitchListTile(
          title: Text(AdminStrings.adminRestrictSendMessage),
          value: _bool('restrict_send_message'),
          onChanged: (v) => _toggle(context, 'restrict_send_message', v),
        ),
        SwitchListTile(
          title: Text(AdminStrings.adminRestrictAddFriend),
          value: _bool('restrict_add_friend'),
          onChanged: (v) => _toggle(context, 'restrict_add_friend', v),
        ),
        SwitchListTile(
          title: Text(AdminStrings.adminRestrictJoinGroup),
          value: _bool('restrict_join_group'),
          onChanged: (v) => _toggle(context, 'restrict_join_group', v),
        ),
        SwitchListTile(
          title: Text(AdminStrings.adminRestrictCreateGroup),
          value: _bool('restrict_create_group'),
          onChanged: (v) => _toggle(context, 'restrict_create_group', v),
        ),
        const SizedBox(height: 24),
        Text(
          '投诉画像',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: _accent),
        ),
        const SizedBox(height: 8),
        _row('被投诉次数', '$reportCount'),
        if (reportHistory.isEmpty)
          Text(
            '暂无投诉记录',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          )
        else
          ...reportHistory.map((r) {
            final reason = r['reason']?.toString() ?? '—';
            final status = r['status']?.toString() ?? '—';
            final reporterId = r['reporter_id']?.toString() ?? '—';
            final reporter = userNameById[reporterId] ?? reporterId;
            final content = r['content']?.toString().trim();
            final createdAt = r['created_at']?.toString() ?? '';
            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('举报人：$reporter  ·  原因：$reason  ·  状态：$status'),
                  if (createdAt.isNotEmpty)
                    Text(
                      createdAt,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (content != null && content.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SelectableText(content),
                  ],
                ],
              ),
            );
          }),
        const SizedBox(height: 16),
        Text(
          '发起投诉历史',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: _accent),
        ),
        const SizedBox(height: 8),
        _row('发起投诉次数', '${submittedReportHistory.length}'),
        if (submittedReportHistory.isEmpty)
          Text(
            '暂无发起投诉记录',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          )
        else
          ...submittedReportHistory.map((r) {
            final reason = r['reason']?.toString() ?? '—';
            final status = r['status']?.toString() ?? '—';
            final targetId = r['reported_user_id']?.toString() ?? '—';
            final target = userNameById[targetId] ?? targetId;
            final content = r['content']?.toString().trim();
            final createdAt = r['created_at']?.toString() ?? '';
            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('投诉对象：$target  ·  原因：$reason  ·  状态：$status'),
                  if (createdAt.isNotEmpty)
                    Text(
                      createdAt,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (content != null && content.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SelectableText(content),
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF6C6F77), fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Future<void> _showBannedFrozenDialog(
    BuildContext context,
    bool isBanned,
  ) async {
    final userId = user['user_id']?.toString();
    if (userId == null) return;
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isBanned
              ? AdminStrings.adminBanDuration
              : AdminStrings.adminFrozenDuration,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(AdminStrings.adminDays7),
              onTap: () => Navigator.pop(ctx, 7),
            ),
            ListTile(
              title: Text(AdminStrings.adminDays30),
              onTap: () => Navigator.pop(ctx, 30),
            ),
            ListTile(
              title: Text(AdminStrings.adminDays90),
              onTap: () => Navigator.pop(ctx, 90),
            ),
            ListTile(
              title: Text(AdminStrings.adminPermanent),
              onTap: () => Navigator.pop(ctx, 0),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AdminStrings.commonCancel),
          ),
        ],
      ),
    );
    if (days != null) await onSetBannedOrFrozen(userId, isBanned, days);
  }
}

class _AdminAccountsPanel extends StatefulWidget {
  const _AdminAccountsPanel();

  @override
  State<_AdminAccountsPanel> createState() => _AdminAccountsPanelState();
}

class _AdminAccountsPanelState extends State<_AdminAccountsPanel> {
  static const Color _accent = Color(0xFFD4AF37);
  final _api = AdminApiClient.instance;

  List<Map<String, dynamic>> _admins = [];
  bool _loading = true;
  String? _loadError;
  final _addUsernameController = TextEditingController();
  final _addPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addUsernameController.dispose();
    _addPasswordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final resp = await _api.get('api/admin/accounts');
      if (!mounted) return;
      if (resp.statusCode != 200) {
        throw StateError('加载失败(${resp.statusCode})：${resp.body}');
      }
      final list = (jsonDecode(resp.body) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _admins = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  void _showAddAdminDialog() {
    _addUsernameController.clear();
    _addPasswordController.clear();
    showDialog<void>(
      context: context,
      builder: (ctx) => _AddAdminDialog(
        usernameController: _addUsernameController,
        passwordController: _addPasswordController,
        onAdd: (username, password) =>
            _addAdminFromDialog(ctx, username, password),
      ),
    );
  }

  Future<void> _addAdminFromDialog(
    BuildContext dialogContext,
    String username,
    String password,
  ) async {
    try {
      final resp = await _api.post(
        'api/admin/accounts',
        body: {'username': username, 'password': password},
      );
      if (!mounted) return;
      if (resp.statusCode == 201 || resp.statusCode == 200) {
        if (mounted) Navigator.of(dialogContext).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已添加管理员')));
        _load();
      } else {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        final err = body is Map ? body['error']?.toString() : resp.body;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err ?? '添加失败'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('添加失败：$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _unlock(String id) async {
    try {
      final resp = await _api.patch(
        'api/admin/accounts/$id',
        body: {'unlock': true},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已解锁')));
        _load();
      } else {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        final err = body is Map ? body['error']?.toString() : resp.body;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err ?? '解锁失败'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('解锁失败：$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _setPermanentLock(String id, bool locked) async {
    try {
      final resp = await _api.patch(
        'api/admin/accounts/$id',
        body: {'locked': locked},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(locked ? '已锁定' : '已解锁')));
        _load();
      } else {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        final err = body is Map ? body['error']?.toString() : resp.body;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err ?? '操作失败'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('操作失败：$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _changePassword(String id) async {
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('修改密码'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: '新密码（至少 6 位）'),
            onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AdminStrings.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(AdminStrings.commonSave),
            ),
          ],
        );
      },
    );
    if (password == null || password.length < 6) return;
    try {
      final resp = await _api.patch(
        'api/admin/accounts/$id',
        body: {'password': password},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码已修改')));
      } else {
        final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;
        final err = body is Map ? body['error']?.toString() : resp.body;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err ?? '修改失败'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('修改失败：$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _deleteAdmin(String id, String username) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除管理员'),
        content: Text('确定删除管理员「$username」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AdminStrings.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final resp = await _api.delete('api/admin/accounts/$id');
      if (!mounted) return;
      if (resp.statusCode == 204 || resp.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已删除')));
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败：${resp.body}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败：$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text(
              '管理员账号',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '共 ${_admins.length} 个',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
              tooltip: AdminStrings.adminRefresh,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 20),
              label: const Text('添加管理员'),
              onPressed: _showAddAdminDialog,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: _accent),
            ),
          )
        else if (_loadError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(AdminStrings.commonRetry),
                  ),
                ],
              ),
            ),
          )
        else if (_admins.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 56,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '暂无管理员，请点击「添加管理员」',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...List<Widget>.from(
            _admins.map((a) {
              final id = a['id']?.toString() ?? '';
              final username = a['username']?.toString() ?? '—';
              final failed = (a['failed_attempts'] as num?)?.toInt() ?? 0;
              final lockedUntil = a['locked_until'] != null
                  ? DateTime.tryParse(a['locked_until'].toString())
                  : null;
              final permanentlyLocked = a['permanently_locked'] == true;
              final isTempLocked =
                  lockedUntil != null && lockedUntil.isAfter(DateTime.now());
              final createdAt = a['created_at']?.toString();
              final statusParts = <String>[];
              if (permanentlyLocked) statusParts.add('已锁定');
              if (isTempLocked) statusParts.add('密码错误锁定');
              if (failed > 0 && !isTempLocked) statusParts.add('错误 $failed 次');
              if (createdAt != null)
                statusParts.add('创建于 ${createdAt.split('T').first}');
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _accent.withOpacity(0.3),
                    child: Icon(
                      Icons.person,
                      color: permanentlyLocked ? Colors.grey : _accent,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(username),
                      if (permanentlyLocked) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.lock,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(statusParts.join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isTempLocked)
                        TextButton.icon(
                          icon: const Icon(Icons.lock_open, size: 18),
                          label: const Text('解锁'),
                          onPressed: () => _unlock(id),
                        ),
                      TextButton.icon(
                        icon: Icon(
                          permanentlyLocked ? Icons.lock_open : Icons.lock,
                          size: 18,
                        ),
                        label: Text(permanentlyLocked ? '解锁' : '锁定'),
                        onPressed: () =>
                            _setPermanentLock(id, !permanentlyLocked),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.lock_reset, size: 18),
                        label: const Text('改密'),
                        onPressed: () => _changePassword(id),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _deleteAdmin(id, username),
                        tooltip: '删除',
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}

class _AppConfigPanel extends StatefulWidget {
  const _AppConfigPanel();

  @override
  State<_AppConfigPanel> createState() => _AppConfigPanelState();
}

class _AppConfigPanelState extends State<_AppConfigPanel> {
  static const Color _accent = Color(0xFFD4AF37);
  final _api = AdminApiClient.instance;

  List<Map<String, dynamic>> _configs = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final resp = await _api.get('api/admin/config');
      if (!mounted) return;
      if (resp.statusCode != 200) {
        throw StateError('加载失败(${resp.statusCode})：${resp.body}');
      }
      final list = (jsonDecode(resp.body) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _configs = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  void _showAddDialog() {
    final keyCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增配置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: 'Key'),
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueCtrl,
                decoration: const InputDecoration(labelText: 'Value'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarkCtrl,
                decoration: const InputDecoration(labelText: '备注（参数说明）'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AdminStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () async {
              final key = keyCtrl.text.trim();
              final value = valueCtrl.text;
              if (key.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Key 不能为空')));
                return;
              }
              try {
                final resp = await _api.post(
                  'api/admin/config',
                  body: {
                    'key': key,
                    'value': value,
                    'remark': remarkCtrl.text.trim().isEmpty
                        ? null
                        : remarkCtrl.text.trim(),
                  },
                );
                if (!mounted) return;
                if (resp.statusCode == 200 || resp.statusCode == 201) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已保存')));
                  _load();
                } else {
                  final body = resp.body.isNotEmpty
                      ? jsonDecode(resp.body)
                      : null;
                  final err = body is Map
                      ? body['error']?.toString()
                      : resp.body;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(err ?? '保存失败'),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('保存失败：$e'),
                    backgroundColor: Colors.red.shade700,
                  ),
                );
              }
            },
            child: Text(AdminStrings.commonSave),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item) {
    final key = item['key']?.toString() ?? '';
    final valueCtrl = TextEditingController(
      text: item['value']?.toString() ?? '',
    );
    final remarkCtrl = TextEditingController(
      text: item['remark']?.toString() ?? '',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑 $key'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: valueCtrl,
                decoration: const InputDecoration(labelText: 'Value'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarkCtrl,
                decoration: const InputDecoration(labelText: '备注（参数说明）'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AdminStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final resp = await _api.patch(
                  'api/admin/config/${Uri.encodeComponent(key)}',
                  body: {
                    'value': valueCtrl.text,
                    'remark': remarkCtrl.text.trim().isEmpty
                        ? null
                        : remarkCtrl.text.trim(),
                  },
                );
                if (!mounted) return;
                if (resp.statusCode == 200) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已保存')));
                  _load();
                } else {
                  final body = resp.body.isNotEmpty
                      ? jsonDecode(resp.body)
                      : null;
                  final err = body is Map
                      ? body['error']?.toString()
                      : resp.body;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(err ?? '保存失败'),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('保存失败：$e'),
                    backgroundColor: Colors.red.shade700,
                  ),
                );
              }
            },
            child: Text(AdminStrings.commonSave),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text(
              '应用配置',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '共 ${_configs.length} 项',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
              tooltip: AdminStrings.adminRefresh,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 20),
              label: const Text('新增配置'),
              onPressed: _showAddDialog,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Key-Value 配置，用于客服、交易模拟盘等系统参数',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 24),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: _accent),
            ),
          )
        else if (_loadError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(AdminStrings.commonRetry),
                  ),
                ],
              ),
            ),
          )
        else if (_configs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_outlined,
                    size: 56,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '暂无配置，请点击「新增配置」',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...List<Widget>.from(
            _configs.map((c) {
              final key = c['key']?.toString() ?? '—';
              final value = c['value']?.toString() ?? '';
              final remark = c['remark']?.toString() ?? '';
              final updatedAt = c['updated_at']?.toString();
              final displayValue = value.length > 80
                  ? '${value.substring(0, 80)}...'
                  : value;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(Icons.key, color: _accent),
                  title: Text(
                    key,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (remark.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            remark,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: _accent.withOpacity(0.9)),
                          ),
                        ),
                      SelectableText(
                        displayValue,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (updatedAt != null)
                        Text(
                          updatedAt.split('T').first,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.5),
                              ),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _showEditDialog(c),
                    tooltip: '编辑',
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}

class _AddAdminDialog extends StatefulWidget {
  const _AddAdminDialog({
    required this.usernameController,
    required this.passwordController,
    required this.onAdd,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final Future<void> Function(String username, String password) onAdd;

  @override
  State<_AddAdminDialog> createState() => _AddAdminDialogState();
}

class _AddAdminDialogState extends State<_AddAdminDialog> {
  bool _adding = false;

  Future<void> _submit() async {
    final username = widget.usernameController.text.trim();
    final password = widget.passwordController.text;
    if (username.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('账号不能为空，密码至少 6 位')));
      return;
    }
    setState(() => _adding = true);
    await widget.onAdd(username, password);
    if (mounted) setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加管理员'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.usernameController,
            decoration: const InputDecoration(labelText: '账号'),
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码（至少 6 位）'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _adding ? null : () => Navigator.pop(context),
          child: Text(AdminStrings.commonCancel),
        ),
        FilledButton(
          onPressed: _adding ? null : _submit,
          child: _adding
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(AdminStrings.commonSave),
        ),
      ],
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.current, required this.onSelect});

  final AdminSection current;
  final ValueChanged<AdminSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _NavItem(
            title: AdminStrings.adminOverview,
            icon: Icons.dashboard_outlined,
            active: current == AdminSection.dashboard,
            onTap: () => onSelect(AdminSection.dashboard),
          ),
          _NavItem(
            title: AdminStrings.adminUserManagement,
            icon: Icons.people_outline,
            active: current == AdminSection.users,
            onTap: () => onSelect(AdminSection.users),
          ),
          _NavItem(
            title: AdminStrings.adminTeacherReview,
            icon: Icons.verified_outlined,
            active: current == AdminSection.teachers,
            onTap: () => onSelect(AdminSection.teachers),
          ),
          _NavItem(
            title: '交易管理',
            icon: Icons.candlestick_chart,
            active: current == AdminSection.trading,
            onTap: () => onSelect(AdminSection.trading),
          ),
          _NavItem(
            title: '管理员账号',
            icon: Icons.admin_panel_settings_outlined,
            active: current == AdminSection.admins,
            onTap: () => onSelect(AdminSection.admins),
          ),
          _NavItem(
            title: '应用配置',
            icon: Icons.tune_outlined,
            active: current == AdminSection.appConfig,
            onTap: () => onSelect(AdminSection.appConfig),
          ),
          _NavItem(
            title: '活动管理',
            icon: Icons.campaign_outlined,
            active: current == AdminSection.activities,
            onTap: () => onSelect(AdminSection.activities),
          ),
          _NavItem(
            title: AdminStrings.adminSystemMessages,
            icon: Icons.notifications_outlined,
            active: current == AdminSection.systemMessages,
            onTap: () => onSelect(AdminSection.systemMessages),
          ),
          _NavItem(
            title: AdminStrings.adminReports,
            icon: Icons.report_outlined,
            active: current == AdminSection.reports,
            onTap: () => onSelect(AdminSection.reports),
          ),
          _NavItem(
            title: AdminStrings.adminSettings,
            icon: Icons.settings_outlined,
            active: current == AdminSection.settings,
            onTap: () => onSelect(AdminSection.settings),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.title,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      selected: active,
      onTap: onTap,
    );
  }
}

class _PlaceholderPanel extends StatelessWidget {
  const _PlaceholderPanel({
    required this.title,
    required this.description,
    this.hint,
  });

  final String title;
  final String description;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(description, style: Theme.of(context).textTheme.bodyMedium),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77)),
          ),
        ],
        const SizedBox(height: 24),
        Text(AdminStrings.adminPlaceholderHint),
      ],
    );
  }
}
