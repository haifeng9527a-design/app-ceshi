import 'package:flutter/material.dart';
import 'dart:convert';

import '../core/admin_api_client.dart';
import '../l10n/admin_strings.dart';
import '../models/teacher_profile.dart';

class AdminTeacherPanel extends StatefulWidget {
  const AdminTeacherPanel({super.key});

  @override
  State<AdminTeacherPanel> createState() => _AdminTeacherPanelState();
}

class _AdminTeacherPanelState extends State<AdminTeacherPanel> {
  final _api = AdminApiClient.instance;
  String? _selectedTeacherId;
  TeacherProfile? _selectedProfile;

  /// 筛选：all | pending | approved | rejected | frozen | blocked
  String _statusFilter = 'all';

  List<TeacherProfile> _rawItems = [];
  bool _loading = true;

  /// 仅存错误文案，避免在 Web 上把 FirebaseException 等对象放入 State 导致 TypeError
  String? _loadError;
  bool _batchSelectMode = false;
  final Set<String> _selectedBatchTeacherIds = <String>{};

  final _displayNameController = TextEditingController();
  final _realNameController = TextEditingController();
  final _titleController = TextEditingController();
  final _orgController = TextEditingController();
  final _bioController = TextEditingController();
  final _tagsController = TextEditingController();
  final _winsController = TextEditingController();
  final _lossesController = TextEditingController();
  final _ratingController = TextEditingController();
  final _todayStrategyController = TextEditingController();
  final _pnlCurrentController = TextEditingController();
  final _pnlMonthController = TextEditingController();
  final _pnlYearController = TextEditingController();
  final _pnlTotalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  /// 使用普通 select 拉取列表，避免 stream/realtime 因 RLS 或权限导致加载失败
  Future<void> _loadTeachers() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final resp = await _api.get('api/admin/teachers/profiles');
      if (resp.statusCode != 200) {
        throw StateError('加载交易员失败(${resp.statusCode})：${resp.body}');
      }
      final rows = jsonDecode(resp.body) as List<dynamic>;
      final list = rows
          .map(
            (e) => TeacherProfile.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _rawItems = list;
        _selectedBatchTeacherIds.removeWhere(
          (id) => !list.any((e) => e.userId == id),
        );
        _loading = false;
      });
      if (list.isNotEmpty && _selectedTeacherId == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _selectedTeacherId != null) return;
          _loadProfile(list.first);
        });
      }
    } catch (e, st) {
      debugPrint('AdminTeacherPanel _loadTeachers: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _realNameController.dispose();
    _titleController.dispose();
    _orgController.dispose();
    _bioController.dispose();
    _tagsController.dispose();
    _winsController.dispose();
    _lossesController.dispose();
    _ratingController.dispose();
    _todayStrategyController.dispose();
    _pnlCurrentController.dispose();
    _pnlMonthController.dispose();
    _pnlYearController.dispose();
    _pnlTotalController.dispose();
    super.dispose();
  }

  void _loadProfile(TeacherProfile profile) {
    _selectedTeacherId = profile.userId;
    _selectedProfile = profile;
    _displayNameController.text = profile.displayName ?? '';
    _realNameController.text = profile.realName ?? '';
    _titleController.text = profile.title ?? '';
    _orgController.text = profile.organization ?? '';
    _bioController.text = profile.bio ?? '';
    _tagsController.text = (profile.tags ?? const <String>[]).join(',');
    _winsController.text = (profile.wins ?? 0).toString();
    _lossesController.text = (profile.losses ?? 0).toString();
    _ratingController.text = (profile.rating ?? 0).toString();
    _todayStrategyController.text = profile.todayStrategy ?? '';
    _pnlCurrentController.text = (profile.pnlCurrent ?? 0).toString();
    _pnlMonthController.text = (profile.pnlMonth ?? 0).toString();
    _pnlYearController.text = (profile.pnlYear ?? 0).toString();
    _pnlTotalController.text = (profile.pnlTotal ?? 0).toString();
    setState(() {});
  }

  Future<void> _saveProfile() async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return;
    }
    final tags = _tagsController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final payload = {
      'user_id': teacherId,
      'display_name': _displayNameController.text.trim(),
      'real_name': _realNameController.text.trim(),
      'title': _titleController.text.trim(),
      'organization': _orgController.text.trim(),
      'bio': _bioController.text.trim(),
      'tags': tags.isEmpty ? null : tags,
      'wins': _toInt(_winsController.text),
      'losses': _toInt(_lossesController.text),
      'rating': _toInt(_ratingController.text),
      'today_strategy': _todayStrategyController.text.trim(),
      'pnl_current': _toNum(_pnlCurrentController.text),
      'pnl_month': _toNum(_pnlMonthController.text),
      'pnl_year': _toNum(_pnlYearController.text),
      'pnl_total': _toNum(_pnlTotalController.text),
      'updated_at': DateTime.now().toIso8601String(),
    };
    try {
      final resp = await _api.put(
        'api/admin/teachers/$teacherId/profile',
        body: payload,
      );
      if (resp.statusCode != 200) {
        throw StateError('保存失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminProfileSaved)));
      _loadTeachers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AdminStrings.adminSaveFailed}: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  static const List<String> _statusOrder = [
    'pending',
    'rejected',
    'approved',
    'frozen',
    'blocked',
  ];

  String _getStatusLabel(BuildContext context, String status) {
    // AdminStrings used directly
    switch (status) {
      case 'pending':
        return AdminStrings.adminPending;
      case 'approved':
        return AdminStrings.adminApproved;
      case 'rejected':
        return AdminStrings.adminRejected;
      case 'frozen':
        return AdminStrings.adminFrozen;
      case 'blocked':
        return AdminStrings.adminBlocked;
      default:
        return status;
    }
  }

  List<TeacherProfile> _sortByStatus(List<TeacherProfile> list) {
    final copy = List<TeacherProfile>.from(list);
    copy.sort((a, b) {
      final sa = _statusOrder.indexOf(a.status ?? 'pending');
      final sb = _statusOrder.indexOf(b.status ?? 'pending');
      if (sa != sb) return sa.compareTo(sb);
      final na = a.realName ?? a.displayName ?? '';
      final nb = b.realName ?? b.displayName ?? '';
      return na.compareTo(nb);
    });
    return copy;
  }

  List<TeacherProfile> _approvedTeachers(List<TeacherProfile> items) {
    return items
        .where((e) => (e.status ?? '').toLowerCase() == 'approved')
        .toList(growable: false);
  }

  List<TeacherProfile> _selectedApprovedTeachers(List<TeacherProfile> items) {
    return items
        .where(
          (e) =>
              _selectedBatchTeacherIds.contains(e.userId) &&
              (e.status ?? '').toLowerCase() == 'approved',
        )
        .toList(growable: false);
  }

  Future<void> _updateStatus(String status, {DateTime? frozenUntil}) async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return;
    }
    try {
      final payload = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };
      // 仅在有冻结截止时间时写入 frozen_until，避免数据库尚未有此列时报错
      if (status == 'frozen' && frozenUntil != null) {
        payload['frozen_until'] = frozenUntil.toIso8601String();
      }
      final resp = await _api.patch(
        'api/admin/teachers/$teacherId/status',
        body: payload,
      );
      if (resp.statusCode != 200) {
        throw StateError('状态更新失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      final label = _getStatusLabel(context, status);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AdminStrings.adminStatusUpdated(label))),
      );
      if (_selectedProfile != null) {
        _loadProfile(_selectedProfile!);
      }
      // 向申请人推送系统消息，便于用户在手机端收到提示
      await _notifyApplicantStatus(teacherId, status);
      _loadTeachers();
    } catch (e, st) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AdminStrings.adminUpdateFailed}: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      debugPrint('_updateStatus error: $e\n$st');
    }
  }

  Future<({double amount, bool clearHistory})?> _showResetAccountDialog({
    required String title,
    required String subtitle,
  }) async {
    final controller = TextEditingController(text: '1000000');
    bool clearHistory = true;
    final result = await showDialog<({double amount, bool clearHistory})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '1000000',
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: clearHistory,
                onChanged: (v) =>
                    setDialogState(() => clearHistory = v ?? true),
                title: const Text('清空历史数据（订单/成交/流水）'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AdminStrings.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(controller.text.trim());
                if (v == null || v <= 0) return;
                Navigator.of(ctx).pop((amount: v, clearHistory: clearHistory));
              },
              child: const Text('确认重置'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Future<void> _resetTradingAccountCash() async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) return;
    final options = await _showResetAccountDialog(
      title: '重置模拟盘资金',
      subtitle: '请输入新的初始资金 (USD)',
    );
    if (options == null) return;
    try {
      final resp = await _api.post(
        'api/admin/trading/accounts/$teacherId/reset',
        body: {
          'initial_cash_usd': options.amount,
          'clear_history': options.clearHistory,
        },
      );
      if (resp.statusCode != 200) {
        throw StateError('重置失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已重置模拟盘资金为 ${options.amount.toStringAsFixed(2)} USD'
            '${options.clearHistory ? '（已清空历史）' : '（保留历史）'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('重置失败: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<({String accountType, double amount, String note})?>
  _showAdjustBalanceDialog() async {
    String accountType = 'spot';
    bool isIncrease = true;
    final amountController = TextEditingController(text: '1000');
    final noteController = TextEditingController();
    final result =
        await showDialog<({String accountType, double amount, String note})>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: const Text('账户上分/下分'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: accountType,
                    decoration: const InputDecoration(
                      labelText: '账户类型',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'spot',
                        child: Text('现货账户 (USDT)'),
                      ),
                      DropdownMenuItem(
                        value: 'contract',
                        child: Text('合约账户 (USD)'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => accountType = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<bool>(
                    initialValue: isIncrease,
                    decoration: const InputDecoration(
                      labelText: '操作类型',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('上分（加资金）')),
                      DropdownMenuItem(value: false, child: Text('下分（减资金）')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => isIncrease = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '金额',
                      hintText: '1000',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '备注（可选）',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(AdminStrings.commonCancel),
                ),
                FilledButton(
                  onPressed: () {
                    final amountRaw = double.tryParse(
                      amountController.text.trim(),
                    );
                    if (amountRaw == null || amountRaw <= 0) return;
                    final amount = isIncrease ? amountRaw : -amountRaw;
                    Navigator.of(ctx).pop((
                      accountType: accountType,
                      amount: amount,
                      note: noteController.text.trim(),
                    ));
                  },
                  child: const Text('确认'),
                ),
              ],
            ),
          ),
        );
    return result;
  }

  Future<void> _adjustTradingBalance() async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) return;
    final options = await _showAdjustBalanceDialog();
    if (options == null) return;
    try {
      final resp = await _api.post(
        'api/admin/trading/users/$teacherId/adjust-balance',
        body: {
          'account_type': options.accountType,
          'amount': options.amount,
          'note': options.note,
        },
      );
      if (resp.statusCode != 200) {
        throw StateError('调账失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已${options.amount >= 0 ? '上分' : '下分'} ${options.amount.abs().toStringAsFixed(2)} '
            '${options.accountType == 'spot' ? 'USDT' : 'USD'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('调账失败: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _batchResetTradingAccountCash(
    List<TeacherProfile> targets,
  ) async {
    if (targets.isEmpty) return;
    final options = await _showResetAccountDialog(
      title: '批量重置模拟盘资金',
      subtitle: '将对当前筛选中的 ${targets.length} 名交易员执行重置',
    );
    if (options == null) return;
    try {
      int ok = 0;
      for (final t in targets) {
        final resp = await _api.post(
          'api/admin/trading/accounts/${t.userId}/reset',
          body: {
            'initial_cash_usd': options.amount,
            'clear_history': options.clearHistory,
          },
        );
        if (resp.statusCode == 200) ok += 1;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量重置完成：成功 $ok / ${targets.length}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('批量重置失败: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _notifyApplicantStatus(String userId, String status) async {
    if (userId.isEmpty) return;
    // AdminStrings used directly
    String title = AdminStrings.adminNotifyTraderResult;
    String body;
    switch (status) {
      case 'rejected':
        body = AdminStrings.adminNotifyRejected;
        break;
      case 'approved':
        body = AdminStrings.adminNotifyApproved;
        break;
      case 'blocked':
        body = AdminStrings.adminNotifyBlocked;
        break;
      case 'frozen':
        body = AdminStrings.adminNotifyFrozen;
        break;
      default:
        return;
    }
    try {
      await _api.post(
        'api/admin/notifications/send-push',
        body: {
          'receiverId': userId,
          'title': title,
          'body': body,
          'messageType': 'trader_application',
        },
      );
    } catch (_) {
      // 推送失败不阻塞状态更新，仅忽略
    }
  }

  Future<void> _confirmStatus(
    String status,
    String actionName,
    String message,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(actionName),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: Text(AdminStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            child: Text(actionName),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _updateStatus(status);
    }
  }

  Future<void> _freezeWithDuration() async {
    final navigator = Navigator.of(context);
    final days = await showDialog<int>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(AdminStrings.adminFreezeDuration),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AdminStrings.adminSelectFreezeDuration),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => navigator.pop(7),
                child: Text(AdminStrings.adminDays7),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => navigator.pop(30),
                child: Text(AdminStrings.adminDays30),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => navigator.pop(90),
                child: Text(AdminStrings.adminDays90),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: Text(AdminStrings.commonCancel),
          ),
        ],
      ),
    );
    if (days != null && days > 0) {
      final until = DateTime.now().add(Duration(days: days));
      await _updateStatus('frozen', frozenUntil: until);
    }
  }

  Future<void> _addStrategy() async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return;
    }
    final titleController = TextEditingController();
    final summaryController = TextEditingController();
    final contentController = TextEditingController();
    // AdminStrings used directly
    final confirmed = await _simpleDialog(
      title: AdminStrings.adminAddStrategy,
      children: [
        TextField(
          controller: titleController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelTitle,
          ),
        ),
        TextField(
          controller: summaryController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelSummary,
          ),
        ),
        TextField(
          controller: contentController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelContent,
          ),
          maxLines: 3,
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    try {
      final resp = await _api.post(
        'api/admin/teachers/$teacherId/strategies',
        body: {
          'title': titleController.text.trim(),
          'summary': summaryController.text.trim(),
          'content': contentController.text.trim(),
          'status': 'published',
        },
      );
      if (resp.statusCode != 200) {
        throw StateError('新增策略失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminSaved)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AdminStrings.adminSaveFailed}: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _addTradeRecord() async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return;
    }
    final assetController = TextEditingController();
    final buyTimeController = TextEditingController();
    final buySharesController = TextEditingController();
    final buyPriceController = TextEditingController();
    final sellTimeController = TextEditingController();
    final sellSharesController = TextEditingController();
    final sellPriceController = TextEditingController();
    final pnlRatioController = TextEditingController();
    final pnlAmountController = TextEditingController();
    // AdminStrings used directly
    final confirmed = await _simpleDialog(
      title: AdminStrings.adminAddTradeRecord,
      children: [
        TextField(
          controller: assetController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelAsset,
          ),
        ),
        TextField(
          controller: buyTimeController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelBuyTime,
          ),
        ),
        TextField(
          controller: buySharesController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelBuyShares,
          ),
        ),
        TextField(
          controller: buyPriceController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelBuyPrice,
          ),
        ),
        TextField(
          controller: sellTimeController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelSellTime,
          ),
        ),
        TextField(
          controller: sellSharesController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelSellShares,
          ),
        ),
        TextField(
          controller: sellPriceController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelSellPrice,
          ),
        ),
        TextField(
          controller: pnlRatioController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelPnlRatio,
          ),
        ),
        TextField(
          controller: pnlAmountController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelPnlAmount,
          ),
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    try {
      final resp = await _api.post(
        'api/admin/teachers/$teacherId/trade-records',
        body: {
          'asset': assetController.text.trim(),
          'buy_time': _toTime(buyTimeController.text),
          'buy_shares': _toNum(buySharesController.text),
          'buy_price': _toNum(buyPriceController.text),
          'sell_time': _toTime(sellTimeController.text),
          'sell_shares': _toNum(sellSharesController.text),
          'sell_price': _toNum(sellPriceController.text),
          'pnl_ratio': _toNum(pnlRatioController.text),
          'pnl_amount': _toNum(pnlAmountController.text),
        },
      );
      if (resp.statusCode != 200) {
        throw StateError('新增交易记录失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminSaved)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AdminStrings.adminSaveFailed}: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _addPosition({required bool isHistory}) async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return;
    }
    final assetController = TextEditingController();
    final buyTimeController = TextEditingController();
    final buySharesController = TextEditingController();
    final buyPriceController = TextEditingController();
    final costPriceController = TextEditingController();
    final currentPriceController = TextEditingController();
    final floatingPnlController = TextEditingController();
    final pnlRatioController = TextEditingController();
    final pnlAmountController = TextEditingController();
    final sellTimeController = TextEditingController();
    final sellPriceController = TextEditingController();
    // AdminStrings used directly
    final children = <Widget>[
      TextField(
        controller: assetController,
        decoration: InputDecoration(
          labelText: AdminStrings.adminFormLabelAsset,
        ),
      ),
      TextField(
        controller: buyTimeController,
        decoration: InputDecoration(
          labelText: AdminStrings.adminFormLabelBuyTime,
        ),
      ),
      TextField(
        controller: buySharesController,
        decoration: InputDecoration(
          labelText: AdminStrings.adminFormLabelBuyShares,
        ),
      ),
      TextField(
        controller: buyPriceController,
        decoration: InputDecoration(
          labelText: AdminStrings.adminFormLabelBuyPrice,
        ),
      ),
      TextField(
        controller: costPriceController,
        decoration: InputDecoration(
          labelText: AdminStrings.adminFormLabelCostPrice,
        ),
      ),
      TextField(
        controller: currentPriceController,
        decoration: InputDecoration(
          labelText: AdminStrings.adminFormLabelCurrentPrice,
        ),
      ),
      TextField(
        controller: floatingPnlController,
        decoration: InputDecoration(
          labelText: AdminStrings.adminFormLabelFloatingPnl,
        ),
      ),
      TextField(
        controller: pnlRatioController,
        decoration: InputDecoration(
          labelText: AdminStrings.adminFormLabelPnlRatio,
        ),
      ),
      TextField(
        controller: pnlAmountController,
        decoration: InputDecoration(
          labelText: AdminStrings.adminFormLabelPnlAmount,
        ),
      ),
    ];
    if (isHistory) {
      children.addAll([
        TextField(
          controller: sellTimeController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelSellTimeHistory,
          ),
        ),
        TextField(
          controller: sellPriceController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelSellPriceHistory,
          ),
        ),
      ]);
    }
    final confirmed = await _simpleDialog(
      title: isHistory
          ? AdminStrings.adminAddHistoryPosition
          : AdminStrings.adminAddCurrentPosition,
      children: children,
    );
    if (confirmed != true) {
      return;
    }
    final payload = <String, dynamic>{
      'teacher_id': teacherId,
      'asset': assetController.text.trim(),
      'buy_time': _toTime(buyTimeController.text),
      'buy_shares': _toNum(buySharesController.text),
      'buy_price': _toNum(buyPriceController.text),
      'cost_price': _toNum(costPriceController.text),
      'current_price': _toNum(currentPriceController.text),
      'floating_pnl': _toNum(floatingPnlController.text),
      'pnl_ratio': _toNum(pnlRatioController.text),
      'pnl_amount': _toNum(pnlAmountController.text),
      'is_history': isHistory,
      'created_at': DateTime.now().toIso8601String(),
    };
    if (isHistory) {
      payload['sell_time'] = _toTime(sellTimeController.text);
      payload['sell_price'] = _toNum(sellPriceController.text);
    }
    try {
      final resp = await _api.post(
        'api/admin/teachers/$teacherId/positions',
        body: payload,
      );
      if (resp.statusCode != 200) {
        throw StateError('新增持仓失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminSaved)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AdminStrings.adminSaveFailed}: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _addComment() async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return;
    }
    final userController = TextEditingController();
    final contentController = TextEditingController();
    final timeController = TextEditingController();
    // AdminStrings used directly
    final confirmed = await _simpleDialog(
      title: AdminStrings.adminAddComment,
      children: [
        TextField(
          controller: userController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelUserName,
          ),
        ),
        TextField(
          controller: contentController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelContent,
          ),
        ),
        TextField(
          controller: timeController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelTime,
          ),
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    try {
      final resp = await _api.post(
        'api/admin/teachers/$teacherId/comments',
        body: {
          'user_name': userController.text.trim(),
          'content': contentController.text.trim(),
          'comment_time': _toTime(timeController.text),
        },
      );
      if (resp.statusCode != 200) {
        throw StateError('新增评论失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminSaved)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AdminStrings.adminSaveFailed}: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _addArticle() async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return;
    }
    final titleController = TextEditingController();
    final summaryController = TextEditingController();
    final timeController = TextEditingController();
    // AdminStrings used directly
    final confirmed = await _simpleDialog(
      title: AdminStrings.adminAddArticle,
      children: [
        TextField(
          controller: titleController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelTitle,
          ),
        ),
        TextField(
          controller: summaryController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelSummary,
          ),
        ),
        TextField(
          controller: timeController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelTime,
          ),
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    try {
      final resp = await _api.post(
        'api/admin/teachers/$teacherId/articles',
        body: {
          'title': titleController.text.trim(),
          'summary': summaryController.text.trim(),
          'article_time': _toTime(timeController.text),
        },
      );
      if (resp.statusCode != 200) {
        throw StateError('新增文章失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminSaved)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AdminStrings.adminSaveFailed}: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _addSchedule() async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return;
    }
    final titleController = TextEditingController();
    final timeController = TextEditingController();
    final locationController = TextEditingController();
    // AdminStrings used directly
    final confirmed = await _simpleDialog(
      title: AdminStrings.adminAddSchedule,
      children: [
        TextField(
          controller: titleController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelTitle,
          ),
        ),
        TextField(
          controller: timeController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelTimeSchedule,
          ),
        ),
        TextField(
          controller: locationController,
          decoration: InputDecoration(
            labelText: AdminStrings.adminFormLabelLocation,
          ),
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    try {
      final resp = await _api.post(
        'api/admin/teachers/$teacherId/schedules',
        body: {
          'title': titleController.text.trim(),
          'schedule_time': _toTime(timeController.text),
          'location': locationController.text.trim(),
        },
      );
      if (resp.statusCode != 200) {
        throw StateError('新增日程失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AdminStrings.adminSaved)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AdminStrings.adminSaveFailed}: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // AdminStrings used directly
    final rawItems = _rawItems;
    final filtered = _statusFilter == 'all'
        ? rawItems
        : rawItems
              .where((e) => (e.status ?? 'pending') == _statusFilter)
              .toList();
    final items = _sortByStatus(filtered);
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Row(
                  children: [
                    Text(
                      AdminStrings.adminAllTeachers,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFD4AF37),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AdminStrings.adminTeachersCount(_rawItems.length),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    if (_batchSelectMode) ...[
                      const SizedBox(width: 8),
                      Text(
                        '已勾选 ${_selectedBatchTeacherIds.length}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFD4AF37),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        _batchSelectMode
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                      ),
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() {
                                _batchSelectMode = !_batchSelectMode;
                                if (!_batchSelectMode) {
                                  _selectedBatchTeacherIds.clear();
                                }
                              });
                            },
                      tooltip: _batchSelectMode ? '退出勾选模式' : '进入勾选模式',
                    ),
                    IconButton(
                      icon: const Icon(Icons.currency_exchange),
                      onPressed: _loading
                          ? null
                          : () async {
                              final allApproved = _approvedTeachers(items);
                              final selectedApproved =
                                  _selectedApprovedTeachers(items);
                              if (allApproved.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('当前筛选下没有已通过的交易员可批量重置'),
                                  ),
                                );
                                return;
                              }
                              List<TeacherProfile> targets = allApproved;
                              if (selectedApproved.isNotEmpty) {
                                final scope =
                                    await showDialog<String>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('选择批量重置范围'),
                                        content: const Text('请选择对哪些交易员执行批量重置'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(
                                              ctx,
                                            ).pop('selected'),
                                            child: Text(
                                              '仅勾选项（${selectedApproved.length}）',
                                            ),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop('all'),
                                            child: Text(
                                              '当前筛选全部（${allApproved.length}）',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ) ??
                                    'all';
                                targets = scope == 'selected'
                                    ? selectedApproved
                                    : allApproved;
                              }
                              _batchResetTradingAccountCash(targets);
                            },
                      tooltip: '批量重置资金',
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loading ? null : _loadTeachers,
                      tooltip: AdminStrings.adminRefreshList,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Text(
                  AdminStrings.adminFilterByStatus,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text(AdminStrings.adminAll),
                    ),
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text(AdminStrings.adminPendingJustApplied),
                    ),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text(AdminStrings.adminApproved),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text(AdminStrings.adminRejected),
                    ),
                    DropdownMenuItem(
                      value: 'frozen',
                      child: Text(AdminStrings.adminFrozen),
                    ),
                    DropdownMenuItem(
                      value: 'blocked',
                      child: Text(AdminStrings.adminBlocked),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _statusFilter = v);
                  },
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFD4AF37),
                        ),
                      )
                    : _loadError != null
                    ? Center(
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
                                AdminStrings.adminLoadFailed,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
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
                                onPressed: _loadTeachers,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: Text(AdminStrings.commonRetry),
                              ),
                            ],
                          ),
                        ),
                      )
                    : items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
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
                                _statusFilter == 'all'
                                    ? AdminStrings.adminNoTeachersData
                                    : AdminStrings.adminNoMatchingData,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.7),
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _statusFilter == 'all'
                                    ? AdminStrings.adminConfirmTableData
                                    : AdminStrings.adminTrySwitchAll,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.5),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final name =
                              item.displayName?.trim().isNotEmpty == true
                              ? item.displayName!
                              : (item.realName?.trim().isNotEmpty == true
                                    ? item.realName!
                                    : AdminStrings.adminTeacherDefault);
                          final status = item.status ?? 'pending';
                          final checked = _selectedBatchTeacherIds.contains(
                            item.userId,
                          );
                          return ListTile(
                            tileColor: _selectedTeacherId == item.userId
                                ? const Color(0xFF1A1C20)
                                : null,
                            leading: _batchSelectMode
                                ? Checkbox(
                                    value: checked,
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _selectedBatchTeacherIds.add(
                                            item.userId,
                                          );
                                        } else {
                                          _selectedBatchTeacherIds.remove(
                                            item.userId,
                                          );
                                        }
                                      });
                                    },
                                  )
                                : null,
                            title: Text(name),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: _StatusChip(status: status),
                            ),
                            onTap: () {
                              if (_batchSelectMode) {
                                setState(() {
                                  if (checked) {
                                    _selectedBatchTeacherIds.remove(
                                      item.userId,
                                    );
                                  } else {
                                    _selectedBatchTeacherIds.add(item.userId);
                                  }
                                });
                              } else {
                                _loadProfile(item);
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedProfile == null
              ? Center(child: Text(AdminStrings.adminSelectTeacher))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildCurrentStatusBar(
                      context,
                      _selectedProfile!.status ?? 'pending',
                    ),
                    if (_selectedProfile!.status == 'frozen' &&
                        _selectedProfile!.frozenUntil != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade900.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          AdminStrings.adminFrozenUntilLabel(
                            _formatDate(_selectedProfile!.frozenUntil!),
                          ),
                          style: TextStyle(color: Colors.blue.shade200),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFD4AF37).withOpacity(0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AdminStrings.adminActionsByStatus,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: const Color(0xFFD4AF37),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 10),
                          _buildActionButtons(context),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSectionTitle(AdminStrings.adminBasicInfo),
                    _textField(
                      _displayNameController,
                      AdminStrings.adminDisplayName,
                    ),
                    _textField(_realNameController, AdminStrings.adminRealName),
                    _textField(
                      _titleController,
                      AdminStrings.adminTitlePosition,
                    ),
                    _textField(_orgController, AdminStrings.adminOrg),
                    _textField(
                      _bioController,
                      AdminStrings.adminBio,
                      maxLines: 3,
                    ),
                    _textField(_tagsController, AdminStrings.adminTags),
                    const SizedBox(height: 16),
                    _buildSectionTitle(AdminStrings.adminReviewCredentials),
                    _readOnlyRow(
                      AdminStrings.adminLicenseNo,
                      _selectedProfile!.licenseNo,
                    ),
                    _readOnlyRow(
                      AdminStrings.adminCertifications,
                      _selectedProfile!.certifications,
                    ),
                    _readOnlyRow(
                      AdminStrings.adminMarkets,
                      _selectedProfile!.markets,
                    ),
                    _readOnlyRow(
                      AdminStrings.adminStyle,
                      _selectedProfile!.style,
                    ),
                    _readOnlyRow(
                      AdminStrings.adminBroker,
                      _selectedProfile!.broker,
                    ),
                    _readOnlyRow(
                      AdminStrings.adminCountry,
                      _selectedProfile!.country,
                    ),
                    _readOnlyRow(
                      AdminStrings.adminCity,
                      _selectedProfile!.city,
                    ),
                    _readOnlyRow(
                      AdminStrings.adminYearsExperience,
                      _selectedProfile!.yearsExperience?.toString(),
                    ),
                    if (_selectedProfile!.trackRecord != null &&
                        _selectedProfile!.trackRecord!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AdminStrings.adminPerformanceLabel,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedProfile!.trackRecord!,
                              style: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      AdminStrings.adminIdPhotoLabel,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _photoCard(
                          context,
                          AdminStrings.adminIdPhoto,
                          _selectedProfile!.idPhotoUrl,
                        ),
                        _photoCard(
                          context,
                          AdminStrings.adminLicensePhoto,
                          _selectedProfile!.licensePhotoUrl,
                        ),
                        _photoCard(
                          context,
                          AdminStrings.adminCertificationPhoto,
                          _selectedProfile!.certificationPhotoUrl,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildSectionTitle(AdminStrings.adminPerformanceSection),
                    _textField(_winsController, AdminStrings.adminWins),
                    _textField(_lossesController, AdminStrings.adminLosses),
                    _textField(_ratingController, AdminStrings.adminRating),
                    _textField(
                      _todayStrategyController,
                      AdminStrings.adminTodayStrategy,
                      maxLines: 3,
                    ),
                    _textField(
                      _pnlCurrentController,
                      AdminStrings.adminPnlCurrent,
                    ),
                    _textField(_pnlMonthController, AdminStrings.adminPnlMonth),
                    _textField(_pnlYearController, AdminStrings.adminPnlYear),
                    _textField(_pnlTotalController, AdminStrings.adminPnlTotal),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _saveProfile,
                      child: Text(AdminStrings.adminSaveProfile),
                    ),
                    const SizedBox(height: 20),
                    _buildSectionTitle(AdminStrings.adminContentManagement),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: _addStrategy,
                          child: Text(AdminStrings.adminAddStrategy),
                        ),
                        OutlinedButton(
                          onPressed: _addTradeRecord,
                          child: Text(AdminStrings.adminAddTradeRecord),
                        ),
                        OutlinedButton(
                          onPressed: () => _addPosition(isHistory: false),
                          child: Text(AdminStrings.adminAddCurrentPosition),
                        ),
                        OutlinedButton(
                          onPressed: () => _addPosition(isHistory: true),
                          child: Text(AdminStrings.adminAddHistoryPosition),
                        ),
                        OutlinedButton(
                          onPressed: _addComment,
                          child: Text(AdminStrings.adminAddComment),
                        ),
                        OutlinedButton(
                          onPressed: _addArticle,
                          child: Text(AdminStrings.adminAddArticle),
                        ),
                        OutlinedButton(
                          onPressed: _addSchedule,
                          child: Text(AdminStrings.adminAddSchedule),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _readOnlyRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.trim().isNotEmpty == true ? value! : '—',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoCard(BuildContext context, String label, String? url) {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C21),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: const Color(0xFFD4AF37)),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: url != null && url.trim().isNotEmpty
                ? () {
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 520,
                            maxHeight: 420,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  label,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              SizedBox(
                                height: 360,
                                child: InteractiveViewer(
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(AdminStrings.adminLoadFailed),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                : null,
            child: Container(
              height: 100,
              width: 120,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0C0E),
                borderRadius: BorderRadius.circular(6),
              ),
              child: url != null && url.trim().isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        AdminStrings.adminNotUploaded,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildActionButtons(BuildContext context) {
    // AdminStrings used directly
    final raw = _selectedProfile!.status ?? 'pending';
    final status = raw.toString().trim().toLowerCase();
    if (status == 'pending') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AdminStrings.adminReviewActions,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: const Color(0xFFD4AF37)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () => _updateStatus('approved'),
                child: Text(AdminStrings.adminApprove),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => _confirmStatus(
                  'rejected',
                  AdminStrings.adminReject,
                  AdminStrings.adminConfirmReject,
                ),
                child: Text(AdminStrings.adminReject),
              ),
            ],
          ),
        ],
      );
    }
    if (status == 'approved') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AdminStrings.adminDispose,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: const Color(0xFFD4AF37)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _freezeWithDuration,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue.shade300,
                  side: BorderSide(color: Colors.blue.shade300),
                ),
                icon: const Icon(Icons.ac_unit, size: 18),
                label: Text(AdminStrings.adminFreeze),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _confirmStatus(
                  'blocked',
                  AdminStrings.adminBan,
                  AdminStrings.adminConfirmBlock,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade300,
                  side: BorderSide(color: Colors.red.shade300),
                ),
                icon: const Icon(Icons.block, size: 18),
                label: Text(AdminStrings.adminBan),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _resetTradingAccountCash,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F5A4A),
                ),
                icon: const Icon(Icons.account_balance_wallet, size: 18),
                label: const Text('重置模拟盘资金'),
              ),
              OutlinedButton.icon(
                onPressed: _adjustTradingBalance,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD4AF37),
                  side: const BorderSide(color: Color(0xFFD4AF37)),
                ),
                icon: const Icon(Icons.currency_exchange, size: 18),
                label: const Text('账户上分/下分'),
              ),
            ],
          ),
        ],
      );
    }
    if (status == 'rejected') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AdminStrings.adminReviewActionsShort,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: const Color(0xFFD4AF37)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () => _updateStatus('approved'),
                child: Text(AdminStrings.adminApprove),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => _updateStatus('pending'),
                child: Text(AdminStrings.adminRevertToPending),
              ),
            ],
          ),
        ],
      );
    }
    if (status == 'frozen') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AdminStrings.adminDispose,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: const Color(0xFFD4AF37)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: () => _updateStatus('approved'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade800,
                foregroundColor: Colors.green.shade100,
              ),
              icon: const Icon(Icons.lock_open, size: 20),
              label: Text(AdminStrings.adminUnfreeze),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _resetTradingAccountCash,
              icon: const Icon(Icons.account_balance_wallet, size: 18),
              label: const Text('重置模拟盘资金'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _adjustTradingBalance,
              icon: const Icon(Icons.currency_exchange, size: 18),
              label: const Text('账户上分/下分'),
            ),
          ),
        ],
      );
    }
    if (status == 'blocked') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AdminStrings.adminDispose,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: const Color(0xFFD4AF37)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: () => _updateStatus('approved'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade800,
                foregroundColor: Colors.green.shade100,
              ),
              icon: const Icon(Icons.block, size: 20),
              label: Text(AdminStrings.adminUnblock),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _resetTradingAccountCash,
              icon: const Icon(Icons.account_balance_wallet, size: 18),
              label: const Text('重置模拟盘资金'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _adjustTradingBalance,
              icon: const Icon(Icons.currency_exchange, size: 18),
              label: const Text('账户上分/下分'),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        AdminStrings.adminUnknownStatus(raw),
        style: TextStyle(color: Colors.orange.shade300, fontSize: 12),
      ),
    );
  }

  Widget _buildCurrentStatusBar(BuildContext context, String status) {
    final label = _getStatusLabel(context, status);
    Color bgColor;
    if (status == 'pending')
      bgColor = Colors.orange.shade900;
    else if (status == 'approved')
      bgColor = Colors.green.shade900;
    else if (status == 'rejected')
      bgColor = Colors.grey.shade800;
    else if (status == 'frozen')
      bgColor = Colors.blue.shade900;
    else if (status == 'blocked')
      bgColor = Colors.red.shade900;
    else
      bgColor = Colors.grey.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bgColor.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Text(
            AdminStrings.adminCurrentStatus,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: const Color(0xFFD4AF37),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Future<bool?> _simpleDialog({
    required String title,
    required List<Widget> children,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Column(children: children)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AdminStrings.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(AdminStrings.commonSave),
            ),
          ],
        );
      },
    );
  }

  int _toInt(String input) {
    return int.tryParse(input.trim()) ?? 0;
  }

  num _toNum(String input) {
    return num.tryParse(input.trim()) ?? 0;
  }

  String? _toTime(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(trimmed);
    return parsed?.toIso8601String();
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    // AdminStrings used directly
    String label;
    switch (status) {
      case 'pending':
        label = AdminStrings.adminPending;
        break;
      case 'approved':
        label = AdminStrings.adminApproved;
        break;
      case 'rejected':
        label = AdminStrings.adminRejected;
        break;
      case 'frozen':
        label = AdminStrings.adminFrozen;
        break;
      case 'blocked':
        label = AdminStrings.adminBlocked;
        break;
      default:
        label = status;
    }
    Color color;
    if (status == 'pending')
      color = Colors.orange;
    else if (status == 'approved')
      color = Colors.green;
    else if (status == 'rejected')
      color = Colors.grey;
    else if (status == 'frozen')
      color = Colors.blue;
    else if (status == 'blocked')
      color = Colors.red;
    else
      color = Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: color.withOpacity(0.95)),
      ),
    );
  }
}
