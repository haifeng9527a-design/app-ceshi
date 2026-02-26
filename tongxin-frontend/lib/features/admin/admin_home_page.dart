import 'package:flutter/material.dart';

import '../../core/supabase_bootstrap.dart';
import 'admin_teacher_panel.dart';

enum AdminSection {
  dashboard,
  users,
  teachers,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('后台管理'),
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
          onGoToTeachers: () => setState(() => _section = AdminSection.teachers),
        );
      case AdminSection.users:
        return const _AdminUserPanel();
      case AdminSection.teachers:
        return const AdminTeacherPanel();
      case AdminSection.systemMessages:
        return const _PlaceholderPanel(
          title: '系统消息',
          description: '编辑系统公告、推送通知、运营消息模板。',
          hint: '建议接入 messages 与推送函数 send_push。',
        );
      case AdminSection.reports:
        return const _PlaceholderPanel(
          title: '举报与审核',
          description: '处理用户举报、内容风控、违规记录。',
        );
      case AdminSection.settings:
        return const _PlaceholderPanel(
          title: '系统设置',
          description: '运营开关、基础配置、版本策略。',
        );
    }
  }
}

/// 总览：交易员状态统计等关键指标
class _DashboardPanel extends StatefulWidget {
  const _DashboardPanel({this.onGoToTeachers});

  final VoidCallback? onGoToTeachers;

  @override
  State<_DashboardPanel> createState() => _DashboardPanelState();
}

class _DashboardPanelState extends State<_DashboardPanel> {
  static const Color _accent = Color(0xFFD4AF37);

  Future<Map<String, int>> _loadStats() async {
    try {
      final res = await SupabaseBootstrap.client.from('teacher_profiles').select('status');
      final list = res as List<dynamic>? ?? [];
      final counts = <String, int>{'pending': 0, 'approved': 0, 'rejected': 0, 'frozen': 0, 'blocked': 0};
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          final s = (e['status'] as String?) ?? 'pending';
          counts[s] = (counts[s] ?? 0) + 1;
        }
      }
      return counts;
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
          '总览',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          '关键指标与系统状态',
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
                  label: '交易员总数',
                  value: total.toString(),
                  icon: Icons.people,
                ),
                _StatCard(
                  label: '待审核',
                  value: (counts['pending'] ?? 0).toString(),
                  icon: Icons.pending_actions,
                  accent: Colors.orange,
                ),
                _StatCard(
                  label: '已通过',
                  value: (counts['approved'] ?? 0).toString(),
                  icon: Icons.check_circle_outline,
                  accent: Colors.green,
                ),
                _StatCard(
                  label: '已驳回',
                  value: (counts['rejected'] ?? 0).toString(),
                  icon: Icons.cancel_outlined,
                  accent: Colors.grey,
                ),
                _StatCard(
                  label: '已冻结',
                  value: (counts['frozen'] ?? 0).toString(),
                  icon: Icons.ac_unit,
                  accent: Colors.blue,
                ),
                _StatCard(
                  label: '已封禁',
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
          '快捷入口',
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
                avatar: const Icon(Icons.verified_outlined, color: _accent, size: 20),
                label: const Text('交易员审核'),
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
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

/// 用户管理：完整资料展示 + 限制登录/发消息/冻结/封禁/禁止加好友/加群/建群
class _AdminUserPanel extends StatefulWidget {
  const _AdminUserPanel();

  @override
  State<_AdminUserPanel> createState() => _AdminUserPanelState();
}

class _AdminUserPanelState extends State<_AdminUserPanel> {
  static const Color _accent = Color(0xFFD4AF37);

  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _loadError;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await SupabaseBootstrap.client.from('user_profiles').select(
        'user_id, display_name, avatar_url, role, email, signature, short_id, '
        'banned_until, frozen_until, restrict_login, restrict_send_message, '
        'restrict_add_friend, restrict_join_group, restrict_create_group',
      );
      final list = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _users = list;
        _loading = false;
        if (_selectedIndex != null && _selectedIndex! >= list.length) _selectedIndex = null;
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

  Future<void> _updateRestrictions(String userId, Map<String, dynamic> payload) async {
    try {
      await SupabaseBootstrap.client.from('user_profiles').update(payload).eq('user_id', userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red.shade700));
    }
  }

  Future<void> _setBannedOrFrozen(String userId, bool isBanned, int? days) async {
    final key = isBanned ? 'banned_until' : 'frozen_until';
    final DateTime? until = days == null ? null : (days <= 0 ? DateTime(2099, 1, 1) : DateTime.now().add(Duration(days: days)));
    await _updateRestrictions(userId, {key: until?.toIso8601String(), 'updated_at': DateTime.now().toIso8601String()});
  }

  @override
  Widget build(BuildContext context) {
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
                  Text('用户管理', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: _accent, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  Text('共 ${_users.length} 人', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _loadUsers, tooltip: '刷新'),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: Color(0xFFD4AF37))))
              else if (_loadError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                        const SizedBox(height: 12),
                        const Text('加载失败'),
                        const SizedBox(height: 4),
                        Text(_loadError ?? '', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 16),
                        FilledButton.icon(onPressed: _loadUsers, icon: const Icon(Icons.refresh, size: 18), label: const Text('重试')),
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
                        Icon(Icons.people_outline, size: 56, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
                        const SizedBox(height: 12),
                        Text('暂无用户数据', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                      ],
                    ),
                  ),
                )
              else
                ...List.generate(_users.length, (i) {
                  final u = _users[i];
                  final name = u['display_name']?.toString().trim() ?? '—';
                  final selected = _selectedIndex == i;
                  return ListTile(
                    selected: selected,
                    leading: u['avatar_url'] != null && u['avatar_url'].toString().trim().isNotEmpty
                        ? CircleAvatar(backgroundImage: NetworkImage(u['avatar_url'].toString()))
                        : const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(name),
                    subtitle: Text(u['email']?.toString().trim() ?? u['user_id']?.toString() ?? '—'),
                    onTap: () => setState(() => _selectedIndex = i),
                  );
                }),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 1,
          child: _selectedIndex == null || _selectedIndex! >= _users.length
              ? Center(child: Text('请从左侧选择用户', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))))
              : _UserDetailPanel(
                  user: _users[_selectedIndex!],
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
    required this.onUpdate,
    required this.onSetBannedOrFrozen,
    required this.onRefresh,
  });

  final Map<String, dynamic> user;
  final Future<void> Function(String userId, Map<String, dynamic> payload) onUpdate;
  final Future<void> Function(String userId, bool isBanned, int? days) onSetBannedOrFrozen;
  final VoidCallback onRefresh;

  static const Color _accent = Color(0xFFD4AF37);

  bool _bool(String key) => user[key] == true;

  Future<void> _toggle(BuildContext context, String key, bool value) async {
    final userId = user['user_id']?.toString();
    if (userId == null) return;
    await onUpdate(userId, {key: value, 'updated_at': DateTime.now().toIso8601String()});
  }

  @override
  Widget build(BuildContext context) {
    final userId = user['user_id']?.toString() ?? '—';
    final name = user['display_name']?.toString().trim() ?? '—';
    final email = user['email']?.toString().trim();
    final role = user['role']?.toString() ?? 'user';
    final shortId = user['short_id']?.toString();
    final signature = user['signature']?.toString().trim();
    final bannedUntil = user['banned_until'] != null ? DateTime.tryParse(user['banned_until'].toString()) : null;
    final frozenUntil = user['frozen_until'] != null ? DateTime.tryParse(user['frozen_until'].toString()) : null;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('用户资料', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _accent)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            user['avatar_url'] != null && user['avatar_url'].toString().trim().isNotEmpty
                ? CircleAvatar(radius: 40, backgroundImage: NetworkImage(user['avatar_url'].toString()))
                : const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('昵称', name),
                  _row('邮箱', email ?? '—'),
                  _row('用户 ID', userId),
                  if (shortId != null && shortId.isNotEmpty) _row('短号', shortId),
                  _row('角色', role),
                  if (signature != null && signature.isNotEmpty) _row('个性签名', signature),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('限制与封禁', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _accent)),
        const SizedBox(height: 8),
        if (bannedUntil != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Chip(
              avatar: const Icon(Icons.block, color: Colors.red, size: 18),
              label: Text('封禁至 ${bannedUntil.toIso8601String().split('T').first}'),
              backgroundColor: Colors.red.withOpacity(0.2),
            ),
          ),
        if (frozenUntil != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Chip(
              avatar: const Icon(Icons.ac_unit, color: Colors.blue, size: 18),
              label: Text('冻结至 ${frozenUntil.toIso8601String().split('T').first}'),
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
              child: const Text('封禁'),
            ),
            OutlinedButton(
              onPressed: () => _showBannedFrozenDialog(context, false),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.blue),
              child: const Text('冻结'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('权限开关（开启即禁止该用户对应行为）', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('限制登录'),
          subtitle: const Text('禁止该账号登录'),
          value: _bool('restrict_login'),
          onChanged: (v) => _toggle(context, 'restrict_login', v),
        ),
        SwitchListTile(
          title: const Text('限制发消息'),
          value: _bool('restrict_send_message'),
          onChanged: (v) => _toggle(context, 'restrict_send_message', v),
        ),
        SwitchListTile(
          title: const Text('禁止加好友'),
          value: _bool('restrict_add_friend'),
          onChanged: (v) => _toggle(context, 'restrict_add_friend', v),
        ),
        SwitchListTile(
          title: const Text('禁止加入群聊'),
          value: _bool('restrict_join_group'),
          onChanged: (v) => _toggle(context, 'restrict_join_group', v),
        ),
        SwitchListTile(
          title: const Text('禁止建群'),
          value: _bool('restrict_create_group'),
          onChanged: (v) => _toggle(context, 'restrict_create_group', v),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label, style: const TextStyle(color: Color(0xFF6C6F77), fontSize: 13))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Future<void> _showBannedFrozenDialog(BuildContext context, bool isBanned) async {
    final userId = user['user_id']?.toString();
    if (userId == null) return;
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBanned ? '封禁时长' : '冻结时长'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('7 天'), onTap: () => Navigator.pop(ctx, 7)),
            ListTile(title: const Text('30 天'), onTap: () => Navigator.pop(ctx, 30)),
            ListTile(title: const Text('90 天'), onTap: () => Navigator.pop(ctx, 90)),
            ListTile(title: const Text('永久'), onTap: () => Navigator.pop(ctx, 0)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))],
      ),
    );
    if (days != null) await onSetBannedOrFrozen(userId, isBanned, days);
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
            title: '总览',
            icon: Icons.dashboard_outlined,
            active: current == AdminSection.dashboard,
            onTap: () => onSelect(AdminSection.dashboard),
          ),
          _NavItem(
            title: '用户管理',
            icon: Icons.people_outline,
            active: current == AdminSection.users,
            onTap: () => onSelect(AdminSection.users),
          ),
          _NavItem(
            title: '交易员审核',
            icon: Icons.verified_outlined,
            active: current == AdminSection.teachers,
            onTap: () => onSelect(AdminSection.teachers),
          ),
          _NavItem(
            title: '系统消息',
            icon: Icons.notifications_outlined,
            active: current == AdminSection.systemMessages,
            onTap: () => onSelect(AdminSection.systemMessages),
          ),
          _NavItem(
            title: '举报与审核',
            icon: Icons.report_outlined,
            active: current == AdminSection.reports,
            onTap: () => onSelect(AdminSection.reports),
          ),
          _NavItem(
            title: '系统设置',
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
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6C6F77),
                ),
          ),
        ],
        const SizedBox(height: 24),
        const Text('此模块已搭好框架，下一步接入数据与操作逻辑。'),
      ],
    );
  }
}
