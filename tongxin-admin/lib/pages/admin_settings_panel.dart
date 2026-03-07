import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';

import '../core/admin_api_client.dart';
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
  final _defaultTradingCashController = TextEditingController();
  final _defaultLeverageController = TextEditingController();
  final _maxLeverageController = TextEditingController();
  final _maintenanceMarginRateController = TextEditingController();
  final _picker = ImagePicker();

  String? _systemCsUserId;
  bool _broadcasting = false;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _csStaff = [];
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _savingTradingCash = false;
  bool _uploadingAvatar = false;
  String _defaultProductType = 'spot';
  String _defaultMarginMode = 'cross';
  bool _allowShort = true;
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
    _defaultTradingCashController.dispose();
    _defaultLeverageController.dispose();
    _maxLeverageController.dispose();
    _maintenanceMarginRateController.dispose();
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
      double? tradingDefaultCash;
      int? defaultLeverage;
      int? maxLeverage;
      double? maintenanceMarginRate;
      String? defaultProductType;
      String? defaultMarginMode;
      bool? allowShort;
      try {
        final config = await _loadTradingConfig();
        tradingDefaultCash = config.$1;
        defaultLeverage = config.$2;
        maxLeverage = config.$3;
        maintenanceMarginRate = config.$4;
        defaultProductType = config.$5;
        defaultMarginMode = config.$6;
        allowShort = config.$7;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _systemCsUserId = csId;
        _avatarController.text = avatarUrl ?? '';
        _welcomeController.text = welcomeMsg ?? '';
        if (tradingDefaultCash != null) {
          _defaultTradingCashController.text =
              tradingDefaultCash.toStringAsFixed(0);
        }
        if (defaultLeverage != null) {
          _defaultLeverageController.text = '$defaultLeverage';
        }
        if (maxLeverage != null) {
          _maxLeverageController.text = '$maxLeverage';
        }
        if (maintenanceMarginRate != null) {
          _maintenanceMarginRateController.text =
              (maintenanceMarginRate * 100).toStringAsFixed(2);
        }
        if (defaultProductType != null && defaultProductType.isNotEmpty) {
          _defaultProductType = defaultProductType;
        }
        if (defaultMarginMode != null && defaultMarginMode.isNotEmpty) {
          _defaultMarginMode = defaultMarginMode;
        }
        if (allowShort != null) {
          _allowShort = allowShort;
        }
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

  Future<(double?, int?, int?, double?, String?, String?, bool?)> _loadTradingConfig() async {
    final client = AdminApiClient.instance;
    if (!client.isAvailable) return (null, null, null, null, null, null, null);
    final resp = await client.get('/api/admin/trading/config');
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return (null, null, null, null, null, null, null);
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      return (null, null, null, null, null, null, null);
    }
    final raw = body['default_initial_cash_usd'];
    final cash = raw is num ? raw.toDouble() : double.tryParse('$raw');
    final defaultLeverage = body['default_leverage'] is num
        ? (body['default_leverage'] as num).toInt()
        : int.tryParse('${body['default_leverage']}');
    final maxLeverage = body['max_leverage'] is num
        ? (body['max_leverage'] as num).toInt()
        : int.tryParse('${body['max_leverage']}');
    final maintenanceMarginRate = body['maintenance_margin_rate'] is num
        ? (body['maintenance_margin_rate'] as num).toDouble()
        : double.tryParse('${body['maintenance_margin_rate']}');
    final defaultProductType = body['default_product_type']?.toString();
    final defaultMarginMode = body['default_margin_mode']?.toString();
    final allowShort = body['allow_short'] == true ||
        '${body['allow_short']}'.toLowerCase() == 'true';
    return (
      cash != null && cash > 0 ? cash : null,
      defaultLeverage,
      maxLeverage,
      maintenanceMarginRate,
      defaultProductType,
      defaultMarginMode,
      allowShort,
    );
  }

  Future<void> _saveTradingDefaultCash() async {
    if (_savingTradingCash) return;
    final text = _defaultTradingCashController.text.trim();
    final n = double.tryParse(text);
    final defaultLeverage = int.tryParse(_defaultLeverageController.text.trim());
    final maxLeverage = int.tryParse(_maxLeverageController.text.trim());
    final maintenanceMarginRatePercent =
        double.tryParse(_maintenanceMarginRateController.text.trim());
    if (n == null || n <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('初始资金必须是大于 0 的数字')),
      );
      return;
    }
    if (defaultLeverage == null || defaultLeverage <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('默认杠杆必须是大于 0 的整数')),
      );
      return;
    }
    if (maxLeverage == null || maxLeverage < defaultLeverage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最大杠杆不能小于默认杠杆')),
      );
      return;
    }
    if (maintenanceMarginRatePercent == null ||
        maintenanceMarginRatePercent <= 0 ||
        maintenanceMarginRatePercent >= 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('维持保证金率请输入 0 到 100 之间的数字')),
      );
      return;
    }
    setState(() => _savingTradingCash = true);
    try {
      final resp = await AdminApiClient.instance.patch(
        '/api/admin/trading/config',
        body: {
          'default_initial_cash_usd': n,
          'default_product_type': _defaultProductType,
          'default_margin_mode': _defaultMarginMode,
          'default_leverage': defaultLeverage,
          'max_leverage': maxLeverage,
          'allow_short': _allowShort,
          'maintenance_margin_rate': maintenanceMarginRatePercent / 100,
        },
      );
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('模拟盘默认初始资金已保存')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败：${resp.statusCode} ${resp.body}'),
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
    } finally {
      if (mounted) setState(() => _savingTradingCash = false);
    }
  }

  Future<void> _saveSystemCs(String? userId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _csRepo.setSystemCustomerServiceUserId(userId ?? '');
      await _csRepo.setCustomerServiceAvatarUrl(
        _avatarController.text.trim().isEmpty ? null : _avatarController.text.trim(),
      );
      await _csRepo.setCustomerServiceWelcomeMessage(
        _welcomeController.text.trim().isEmpty ? null : _welcomeController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminSaved)),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminSaved)),
      );
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
      final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminSaved)),
      );
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
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminSaved)),
      );
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
    return _users.where((u) {
      final name = _userLabel(u).toLowerCase();
      final email = (u['email']?.toString() ?? '').toLowerCase();
      final sid = (u['short_id']?.toString() ?? '').toLowerCase();
      return name.contains(q) || email.contains(q) || sid.contains(q);
    }).toList(growable: false);
  }

  Widget _buildTabs() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _CsSettingsTab.values.map((tab) {
        final selected = _tab == tab;
        return ChoiceChip(
          label: Text(_tabLabel(tab)),
          selected: selected,
          onSelected: (_) => setState(() => _tab = tab),
          selectedColor: _accent.withValues(alpha: 0.25),
          labelStyle: TextStyle(
            color: selected ? _accent : Colors.white.withValues(alpha: 0.9),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
      orElse: () => {'user_id': _systemCsUserId, 'display_name': _systemCsUserId},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRow(AdminStrings.adminCsSystemAccount, _systemCsUserId != null && _systemCsUserId!.isNotEmpty ? _userLabel(current) : AdminStrings.adminCsNotConfigured),
        const SizedBox(height: 8),
        Text(AdminStrings.adminCsSystemAccountHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77))),
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
        const SizedBox(height: 20),
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
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
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
          child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : Text(AdminStrings.commonSave),
        ),
      ],
    );
  }

  Widget _buildStaffSection() {
    final candidateUsers = _filteredUsers.where((u) => !_csStaff.any((s) => s['user_id'] == u['user_id'])).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AdminStrings.adminCsStaffHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77))),
        const SizedBox(height: 10),
        ..._csStaff.map((u) {
          final uid = u['user_id']?.toString() ?? '';
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: _accent.withValues(alpha: 0.2),
              child: Text(_userLabel(u).isNotEmpty ? _userLabel(u)[0].toUpperCase() : '?', style: const TextStyle(color: _accent)),
            ),
            title: Text(_userLabel(u)),
            subtitle: Text(uid),
            trailing: IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              onPressed: _saving ? null : () => _removeCsStaff(uid),
              tooltip: AdminStrings.adminRemoveCsStaff,
            ),
          );
        }),
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
    final entries = _assignmentStats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('当前规则：优先已有绑定；否则按在线客服池哈希分配；无人在线时回退系统客服。', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          Text('暂无分配数据', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77)))
        else
          ...entries.map((e) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.support_agent_outlined, color: _accent),
                title: Text(staffMap[e.key] ?? e.key),
                subtitle: Text(e.key),
                trailing: Text('${e.value} 人', style: const TextStyle(fontWeight: FontWeight.w700)),
              )),
      ],
    );
  }

  Widget _buildBroadcastSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AdminStrings.adminCsBroadcastHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF6C6F77))),
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
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
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
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
        ),
        const SizedBox(height: 24),
        Text(
          '交易模拟盘配置',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _accent),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                controller: _defaultTradingCashController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '交易员默认初始资金 (USD)',
                  hintText: '1000000',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _defaultProductType,
                decoration: const InputDecoration(
                  labelText: '默认产品类型',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'spot', child: Text('现货 spot')),
                  DropdownMenuItem(value: 'perpetual', child: Text('永续 perpetual')),
                  DropdownMenuItem(value: 'future', child: Text('期货 future')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _defaultProductType = value);
                  }
                },
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _defaultMarginMode,
                decoration: const InputDecoration(
                  labelText: '默认保证金模式',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'cross', child: Text('全仓 cross')),
                  DropdownMenuItem(value: 'isolated', child: Text('逐仓 isolated')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _defaultMarginMode = value);
                  }
                },
              ),
            ),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _defaultLeverageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '默认杠杆',
                  hintText: '5',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _maxLeverageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '最大杠杆',
                  hintText: '50',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _maintenanceMarginRateController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '维持保证金率 (%)',
                  hintText: '0.50',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: SwitchListTile(
                value: _allowShort,
                onChanged: (value) => setState(() => _allowShort = value),
                title: const Text('允许做空'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
              ),
            ),
            FilledButton(
              onPressed: _savingTradingCash ? null : _saveTradingDefaultCash,
              child: _savingTradingCash
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          AdminStrings.adminCsConfig,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _accent),
        ),
        const SizedBox(height: 8),
        _buildTabs(),
        const SizedBox(height: 12),
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
                  Text(_loadError!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: Text(AdminStrings.commonRetry)),
                ],
              ),
            ),
          )
        else ...[_buildCurrentTabBody()],
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Color(0xFF6C6F77), fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
