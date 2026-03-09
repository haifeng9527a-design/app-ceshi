import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';

import '../l10n/admin_strings.dart';
import '../repo/customer_service_repository.dart';

class AdminSettingsPanel extends StatefulWidget {
  const AdminSettingsPanel({super.key});

  @override
  State<AdminSettingsPanel> createState() => _AdminSettingsPanelState();
}

enum _CsSettingsTab { system, staff, assignment, broadcast }

class _AdminSettingsPanelState extends State<AdminSettingsPanel> {
  final _csRepo = CustomerServiceRepository();
  final _avatarController = TextEditingController();
  final _welcomeController = TextEditingController();
  final _broadcastController = TextEditingController();
  final _picker = ImagePicker();

  String? _systemCsUserId;
  bool _broadcasting = false;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _csStaff = [];
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String _userSearch = '';
  _CsSettingsTab _tab = _CsSettingsTab.system;
  Map<String, int> _assignmentStats = const {};

  static const Color _accent = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _avatarController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _avatarController.dispose();
    _welcomeController.dispose();
    _broadcastController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final csId = await _csRepo.getSystemCustomerServiceUserId();
      final avatarUrl = await _csRepo.getCustomerServiceAvatarUrl();
      final welcomeMsg = await _csRepo.getCustomerServiceWelcomeMessage();
      final users = await _csRepo.listUsersBasic();
      final staff = await _csRepo.listCustomerServiceStaffBasic();
      final assignmentStats = await _csRepo.getAssignmentStats();
      if (!mounted) return;
      setState(() {
        _systemCsUserId = csId;
        _avatarController.text = avatarUrl ?? '';
        _welcomeController.text = welcomeMsg ?? '';
        _users = users;
        _csStaff = staff;
        _assignmentStats = assignmentStats;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('AdminSettingsPanel _load: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveSystemCs(String? userId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _csRepo.setSystemCustomerServiceUserId(userId ?? '');
      await _csRepo.setCustomerServiceAvatarUrl(
        _avatarController.text.trim().isEmpty
            ? null
            : _avatarController.text.trim(),
      );
      await _csRepo.setCustomerServiceWelcomeMessage(
        _welcomeController.text.trim().isEmpty
            ? null
            : _welcomeController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminSaved)));
      setState(() {
        _systemCsUserId = userId;
        _saving = false;
      });
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AdminStrings.adminSaveFailed(e.toString())),
          backgroundColor: Colors.red.shade700,
        ),
      );
      setState(() => _saving = false);
    }
  }

  Future<void> _setUserAsSystemCs(String userId) async {
    await _saveSystemCs(userId);
  }

  Future<void> _addCsStaff(String userId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _csRepo.setUserRole(userId, 'customer_service');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminSaved)));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AdminStrings.adminSaveFailed(e.toString())),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadAvatar() async {
    if (_uploadingAvatar) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext)
          ? ext
          : 'jpg';
      final contentType = safeExt == 'png'
          ? 'image/png'
          : safeExt == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
      final url = await _csRepo.uploadCustomerServiceAvatar(
        contentBase64: base64Encode(bytes),
        contentType: contentType,
        fileName: picked.name,
      );
      await _csRepo.setCustomerServiceAvatarUrl(url);
      if (!mounted) return;
      setState(() {
        _avatarController.text = url;
        _uploadingAvatar = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminSaved)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AdminStrings.adminSaveFailed(e.toString())),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _doBroadcast() async {
    final msg = _broadcastController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminCsBroadcastEmpty)),
      );
      return;
    }
    setState(() => _broadcasting = true);
    try {
      final res = await _csRepo.broadcastMessage(msg);
      if (!mounted) return;
      final ok = res['ok'] == true;
      final count = res['count'] as int? ?? 0;
      final err = res['error']?.toString();
      if (ok) {
        _broadcastController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AdminStrings.adminCsBroadcastSuccess('$count')),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err ?? ''),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _broadcasting = false);
    }
  }

  Future<void> _removeCsStaff(String userId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _csRepo.setUserRole(userId, 'user');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminSaved)));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AdminStrings.adminSaveFailed(e.toString())),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _userLabel(Map<String, dynamic> u) {
    final name = u['display_name']?.toString().trim();
    final email = u['email']?.toString().trim();
    final shortId = u['short_id']?.toString();
    if (name != null && name.isNotEmpty) return name;
    if (email != null && email.isNotEmpty) return email;
    return shortId ?? u['user_id']?.toString() ?? '—';
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final q = _userSearch.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users
        .where((u) {
          final name = _userLabel(u).toLowerCase();
          final email = (u['email']?.toString() ?? '').toLowerCase();
          final sid = (u['short_id']?.toString() ?? '').toLowerCase();
          return name.contains(q) || email.contains(q) || sid.contains(q);
        })
        .toList(growable: false);
  }

  Widget _buildTabs() {
    IconData iconOf(_CsSettingsTab t) {
      switch (t) {
        case _CsSettingsTab.system:
          return Icons.verified_user_outlined;
        case _CsSettingsTab.staff:
          return Icons.support_agent_outlined;
        case _CsSettingsTab.assignment:
          return Icons.account_tree_outlined;
        case _CsSettingsTab.broadcast:
          return Icons.campaign_outlined;
      }
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _CsSettingsTab.values.map((tab) {
        final selected = _tab == tab;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _tab = tab),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? _accent.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? _accent.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  iconOf(tab),
                  size: 16,
                  color: selected
                      ? _accent
                      : Colors.white.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Text(
                  _tabLabel(tab),
                  style: TextStyle(
                    color: selected
                        ? _accent
                        : Colors.white.withValues(alpha: 0.9),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _tabLabel(_CsSettingsTab tab) {
    switch (tab) {
      case _CsSettingsTab.system:
        return '系统客服账号';
      case _CsSettingsTab.staff:
        return '客服人员';
      case _CsSettingsTab.assignment:
        return '分配规则';
      case _CsSettingsTab.broadcast:
        return '群发中心';
    }
  }

  Widget _buildSystemSection() {
    final current = _users.firstWhere(
      (u) => u['user_id'] == _systemCsUserId,
      orElse: () => {
        'user_id': _systemCsUserId,
        'display_name': _systemCsUserId,
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _accent.withValues(alpha: 0.2),
                child: const Icon(
                  Icons.support_agent,
                  color: _accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AdminStrings.adminCsSystemAccount,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _systemCsUserId != null && _systemCsUserId!.isNotEmpty
                          ? _userLabel(current)
                          : AdminStrings.adminCsNotConfigured,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AdminStrings.adminCsSystemAccountHint,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77)),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            hintText: '搜索用户（昵称/邮箱/短ID）',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _userSearch = v),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _filteredUsers.take(30).map((u) {
            final uid = u['user_id']?.toString() ?? '';
            final isCurrent = uid == _systemCsUserId;
            return FilterChip(
              label: Text(_userLabel(u)),
              selected: isCurrent,
              onSelected: isCurrent ? null : (_) => _setUserAsSystemCs(uid),
              selectedColor: _accent.withValues(alpha: 0.3),
              checkmarkColor: _accent,
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _avatarController,
                decoration: InputDecoration(
                  labelText: AdminStrings.adminCsAvatarUrl,
                  hintText: 'https://... 或点击上传',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _uploadingAvatar ? null : _uploadAvatar,
              icon: _uploadingAvatar
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.upload_file, size: 20),
              label: Text(AdminStrings.adminCsUploadAvatar),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _welcomeController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminCsWelcomeMessage,
            hintText: AdminStrings.adminCsWelcomeMessageHint,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : () => _saveSystemCs(_systemCsUserId),
          child: _saving
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

  Widget _buildStaffSection() {
    final candidateUsers = _filteredUsers
        .where((u) => !_csStaff.any((s) => s['user_id'] == u['user_id']))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _statBadge('客服人数', '${_csStaff.length}'),
            const SizedBox(width: 10),
            _statBadge('可添加用户', '${candidateUsers.length}'),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          AdminStrings.adminCsStaffHint,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77)),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            color: Colors.white.withValues(alpha: 0.02),
          ),
          child: Column(
            children: _csStaff.map((u) {
              final uid = u['user_id']?.toString() ?? '';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: _accent.withValues(alpha: 0.2),
                  child: Text(
                    _userLabel(u).isNotEmpty
                        ? _userLabel(u)[0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: _accent),
                  ),
                ),
                title: Text(_userLabel(u)),
                subtitle: Text(uid),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.red,
                  ),
                  onPressed: _saving ? null : () => _removeCsStaff(uid),
                  tooltip: AdminStrings.adminRemoveCsStaff,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        const Text('添加客服人员'),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            hintText: '搜索用户（昵称/邮箱/短ID）',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _userSearch = v),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: candidateUsers.take(30).map((u) {
            final uid = u['user_id']?.toString() ?? '';
            return ActionChip(
              label: Text(_userLabel(u)),
              onPressed: _saving ? null : () => _addCsStaff(uid),
              avatar: const Icon(Icons.add, size: 18, color: Color(0xFFD4AF37)),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAssignmentSection() {
    final staffMap = {
      for (final s in _csStaff) s['user_id']?.toString() ?? '': _userLabel(s),
    };
    final entries = _assignmentStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _statBadge('参与分配客服', '${entries.length}'),
            const SizedBox(width: 10),
            _statBadge(
              '累计分配用户',
              '${entries.fold<int>(0, (sum, e) => sum + e.value)}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '当前规则：优先已有绑定；否则按在线客服池哈希分配；无人在线时回退系统客服。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          Text(
            '暂无分配数据',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77)),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('客服')),
                DataColumn(label: Text('用户ID')),
                DataColumn(label: Text('分配人数')),
              ],
              rows: entries
                  .map(
                    (e) => DataRow(
                      cells: [
                        DataCell(Text(staffMap[e.key] ?? e.key)),
                        DataCell(
                          Text(
                            e.key,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${e.value} 人',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildBroadcastSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: _accent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '该消息会发送给已绑定系统客服会话的用户，请避免在高峰期频繁群发。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          AdminStrings.adminCsBroadcastHint,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77)),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _broadcastController,
                decoration: const InputDecoration(
                  hintText: '输入群发内容...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _broadcasting ? null : _doBroadcast,
              icon: _broadcasting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.send, size: 20),
              label: Text(AdminStrings.adminCsBroadcastSend),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCurrentTabBody() {
    switch (_tab) {
      case _CsSettingsTab.system:
        return _buildSystemSection();
      case _CsSettingsTab.staff:
        return _buildStaffSection();
      case _CsSettingsTab.assignment:
        return _buildAssignmentSection();
      case _CsSettingsTab.broadcast:
        return _buildBroadcastSection();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          AdminStrings.adminSettings,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: _accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AdminStrings.adminSettingsDesc,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '交易参数已迁移到「交易管理」页进行统一设置。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: AdminStrings.adminCsConfig,
          subtitle: '系统客服账号、客服人员、分配规则与群发管理',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _statBadge(
                    '系统客服',
                    (_systemCsUserId?.isNotEmpty ?? false) ? '已配置' : '未配置',
                  ),
                  const SizedBox(width: 10),
                  _statBadge('客服人员', '${_csStaff.length} 人'),
                  const SizedBox(width: 10),
                  _statBadge(
                    '总分配',
                    '${_assignmentStats.values.fold<int>(0, (s, v) => s + v)} 人',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTabs(),
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
              else
                _buildCurrentTabBody(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.02),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _statBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12),
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: _accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
