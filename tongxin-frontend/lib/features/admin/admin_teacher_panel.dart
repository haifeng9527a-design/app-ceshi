import 'package:flutter/material.dart';

import '../../core/supabase_bootstrap.dart';
import '../teachers/teacher_models.dart';

class AdminTeacherPanel extends StatefulWidget {
  const AdminTeacherPanel({super.key});

  @override
  State<AdminTeacherPanel> createState() => _AdminTeacherPanelState();
}

class _AdminTeacherPanelState extends State<AdminTeacherPanel> {
  String? _selectedTeacherId;
  TeacherProfile? _selectedProfile;
  /// 筛选：all | pending | approved | rejected | frozen | blocked
  String _statusFilter = 'all';

  List<TeacherProfile> _rawItems = [];
  bool _loading = true;
  /// 仅存错误文案，避免在 Web 上把 FirebaseException 等对象放入 State 导致 TypeError
  String? _loadError;

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
      final res = await SupabaseBootstrap.client.from('teacher_profiles').select();
      final list = (res as List<dynamic>)
          .map((e) => TeacherProfile.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _rawItems = list;
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
    await SupabaseBootstrap.client.from('teacher_profiles').upsert(payload);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('资料已保存')),
    );
    _loadTeachers();
  }

  static const List<String> _statusOrder = ['pending', 'rejected', 'approved', 'frozen', 'blocked'];
  static const Map<String, String> _statusLabel = {
    'pending': '待审核',
    'approved': '已通过',
    'rejected': '已驳回',
    'frozen': '已冻结',
    'blocked': '已封禁',
  };

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
      await SupabaseBootstrap.client
          .from('teacher_profiles')
          .update(payload)
          .eq('user_id', teacherId);
      if (!mounted) return;
      final label = _statusLabel[status] ?? status;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('状态已更新为：$label')),
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
          content: Text('更新失败: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      debugPrint('_updateStatus error: $e\n$st');
    }
  }

  Future<void> _notifyApplicantStatus(String userId, String status) async {
    if (userId.isEmpty) return;
    String title = '交易员申请结果';
    String body;
    switch (status) {
      case 'rejected':
        body = '您的交易员申请已被驳回，可修改后重新提交。';
        break;
      case 'approved':
        body = '恭喜，您的交易员申请已通过，可以发布策略与交易记录。';
        break;
      case 'blocked':
        body = '您的交易员账号已被封禁，如有疑问请联系客服。';
        break;
      case 'frozen':
        body = '您的交易员账号已被冻结，冻结期内无法发布内容。';
        break;
      default:
        return;
    }
    try {
      await SupabaseBootstrap.client.functions.invoke('send_push', body: {
        'receiverId': userId,
        'title': title,
        'body': body,
        'messageType': 'trader_application',
      });
    } catch (_) {
      // 推送失败不阻塞状态更新，仅忽略
    }
  }

  Future<void> _confirmStatus(String status, String actionName, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text('$actionName确认'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: const Text('取消'),
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
        title: const Text('冻结时长'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('请选择冻结时长：'),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => navigator.pop(7),
                child: const Text('7 天'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => navigator.pop(30),
                child: const Text('30 天'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => navigator.pop(90),
                child: const Text('90 天'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text('取消'),
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
    final confirmed = await _simpleDialog(
      title: '新增策略',
      children: [
        TextField(
          controller: titleController,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        TextField(
          controller: summaryController,
          decoration: const InputDecoration(labelText: '摘要'),
        ),
        TextField(
          controller: contentController,
          decoration: const InputDecoration(labelText: '内容'),
          maxLines: 3,
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    await SupabaseBootstrap.client.from('trade_strategies').insert({
      'teacher_id': teacherId,
      'title': titleController.text.trim(),
      'summary': summaryController.text.trim(),
      'content': contentController.text.trim(),
      'status': 'published',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
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
    final confirmed = await _simpleDialog(
      title: '新增交易记录',
      children: [
        TextField(
          controller: assetController,
          decoration: const InputDecoration(labelText: '品种'),
        ),
        TextField(
          controller: buyTimeController,
          decoration: const InputDecoration(labelText: '买入时间(YYYY-MM-DD)'),
        ),
        TextField(
          controller: buySharesController,
          decoration: const InputDecoration(labelText: '买入数量'),
        ),
        TextField(
          controller: buyPriceController,
          decoration: const InputDecoration(labelText: '买入价'),
        ),
        TextField(
          controller: sellTimeController,
          decoration: const InputDecoration(labelText: '卖出时间(YYYY-MM-DD)'),
        ),
        TextField(
          controller: sellSharesController,
          decoration: const InputDecoration(labelText: '卖出数量'),
        ),
        TextField(
          controller: sellPriceController,
          decoration: const InputDecoration(labelText: '卖出价'),
        ),
        TextField(
          controller: pnlRatioController,
          decoration: const InputDecoration(labelText: '收益率%'),
        ),
        TextField(
          controller: pnlAmountController,
          decoration: const InputDecoration(labelText: '盈亏金额'),
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    await SupabaseBootstrap.client.from('trade_records').insert({
      'teacher_id': teacherId,
      'asset': assetController.text.trim(),
      'buy_time': _toTime(buyTimeController.text),
      'buy_shares': _toNum(buySharesController.text),
      'buy_price': _toNum(buyPriceController.text),
      'sell_time': _toTime(sellTimeController.text),
      'sell_shares': _toNum(sellSharesController.text),
      'sell_price': _toNum(sellPriceController.text),
      'pnl_ratio': _toNum(pnlRatioController.text),
      'pnl_amount': _toNum(pnlAmountController.text),
      'created_at': DateTime.now().toIso8601String(),
    });
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
    final children = <Widget>[
      TextField(
        controller: assetController,
        decoration: const InputDecoration(labelText: '品种'),
      ),
      TextField(
        controller: buyTimeController,
        decoration: const InputDecoration(labelText: '买入时间(YYYY-MM-DD)'),
      ),
      TextField(
        controller: buySharesController,
        decoration: const InputDecoration(labelText: '买入数量'),
      ),
      TextField(
        controller: buyPriceController,
        decoration: const InputDecoration(labelText: '买入价'),
      ),
      TextField(
        controller: costPriceController,
        decoration: const InputDecoration(labelText: '成本价'),
      ),
      TextField(
        controller: currentPriceController,
        decoration: const InputDecoration(labelText: '现价'),
      ),
      TextField(
        controller: floatingPnlController,
        decoration: const InputDecoration(labelText: '浮动盈亏'),
      ),
      TextField(
        controller: pnlRatioController,
        decoration: const InputDecoration(labelText: '收益率%'),
      ),
      TextField(
        controller: pnlAmountController,
        decoration: const InputDecoration(labelText: '盈亏金额'),
      ),
    ];
    if (isHistory) {
      children.addAll([
        TextField(
          controller: sellTimeController,
          decoration: const InputDecoration(labelText: '卖出时间(YYYY-MM-DD)'),
        ),
        TextField(
          controller: sellPriceController,
          decoration: const InputDecoration(labelText: '卖出价格'),
        ),
      ]);
    }
    final confirmed = await _simpleDialog(
      title: isHistory ? '新增历史持仓' : '新增当前持仓',
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
    await SupabaseBootstrap.client.from('teacher_positions').insert(payload);
  }

  Future<void> _addComment() async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return;
    }
    final userController = TextEditingController();
    final contentController = TextEditingController();
    final timeController = TextEditingController();
    final confirmed = await _simpleDialog(
      title: '新增评论',
      children: [
        TextField(
          controller: userController,
          decoration: const InputDecoration(labelText: '用户昵称'),
        ),
        TextField(
          controller: contentController,
          decoration: const InputDecoration(labelText: '内容'),
        ),
        TextField(
          controller: timeController,
          decoration: const InputDecoration(labelText: '时间(YYYY-MM-DD)'),
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    await SupabaseBootstrap.client.from('teacher_comments').insert({
      'teacher_id': teacherId,
      'user_name': userController.text.trim(),
      'content': contentController.text.trim(),
      'comment_time': _toTime(timeController.text),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _addArticle() async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return;
    }
    final titleController = TextEditingController();
    final summaryController = TextEditingController();
    final timeController = TextEditingController();
    final confirmed = await _simpleDialog(
      title: '新增文章',
      children: [
        TextField(
          controller: titleController,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        TextField(
          controller: summaryController,
          decoration: const InputDecoration(labelText: '摘要'),
        ),
        TextField(
          controller: timeController,
          decoration: const InputDecoration(labelText: '时间(YYYY-MM-DD)'),
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    await SupabaseBootstrap.client.from('teacher_articles').insert({
      'teacher_id': teacherId,
      'title': titleController.text.trim(),
      'summary': summaryController.text.trim(),
      'article_time': _toTime(timeController.text),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _addSchedule() async {
    final teacherId = _selectedTeacherId;
    if (teacherId == null || teacherId.isEmpty) {
      return;
    }
    final titleController = TextEditingController();
    final timeController = TextEditingController();
    final locationController = TextEditingController();
    final confirmed = await _simpleDialog(
      title: '新增日程',
      children: [
        TextField(
          controller: titleController,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        TextField(
          controller: timeController,
          decoration: const InputDecoration(labelText: '时间(YYYY-MM-DD HH:MM)'),
        ),
        TextField(
          controller: locationController,
          decoration: const InputDecoration(labelText: '地点'),
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    await SupabaseBootstrap.client.from('teacher_schedules').insert({
      'teacher_id': teacherId,
      'title': titleController.text.trim(),
      'schedule_time': _toTime(timeController.text),
      'location': locationController.text.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final rawItems = _rawItems;
    final filtered = _statusFilter == 'all'
        ? rawItems
        : rawItems.where((e) => (e.status ?? 'pending') == _statusFilter).toList();
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
                          '全部交易员',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: const Color(0xFFD4AF37),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '共 ${_rawItems.length} 人',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _loading ? null : _loadTeachers,
                          tooltip: '刷新列表',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Text(
                      '按状态筛选',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: DropdownButtonFormField<String>(
                      value: _statusFilter,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('全部')),
                        DropdownMenuItem(value: 'pending', child: Text('待审核（刚刚申请）')),
                        DropdownMenuItem(value: 'approved', child: Text('已通过')),
                        DropdownMenuItem(value: 'rejected', child: Text('已驳回')),
                        DropdownMenuItem(value: 'frozen', child: Text('已冻结')),
                        DropdownMenuItem(value: 'blocked', child: Text('已封禁')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _statusFilter = v);
                      },
                    ),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                        : _loadError != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                                      const SizedBox(height: 12),
                                      Text(
                                        '加载失败',
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
                                        label: const Text('重试'),
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
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            _statusFilter == 'all' ? '暂无交易员数据' : '暂无符合条件的数据',
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _statusFilter == 'all'
                                                ? '请确认 teacher_profiles 表已有数据'
                                                : '可尝试切换「全部」查看',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    itemCount: items.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      final name = item.displayName?.trim().isNotEmpty == true
                                          ? item.displayName!
                                          : (item.realName?.trim().isNotEmpty == true
                                              ? item.realName!
                                              : '交易员');
                                      final status = item.status ?? 'pending';
                                      return ListTile(
                                        tileColor: _selectedTeacherId == item.userId
                                            ? const Color(0xFF1A1C20)
                                            : null,
                                        title: Text(name),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: _StatusChip(status: status),
                                        ),
                                        onTap: () => _loadProfile(item),
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
                  ? const Center(child: Text('请选择交易员'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildCurrentStatusBar(context, _selectedProfile!.status ?? 'pending'),
                        if (_selectedProfile!.status == 'frozen' &&
                            _selectedProfile!.frozenUntil != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade900.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '冻结至：${_formatDate(_selectedProfile!.frozenUntil!)}',
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
                            border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '操作（根据当前状态）',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
                        _buildSectionTitle('基础信息'),
                        _textField(_displayNameController, '展示名'),
                        _textField(_realNameController, '真实姓名'),
                        _textField(_titleController, '职位/称号'),
                        _textField(_orgController, '机构'),
                        _textField(_bioController, '个人简介', maxLines: 3),
                        _textField(_tagsController, '标签(逗号分隔)'),
                        const SizedBox(height: 16),
                        _buildSectionTitle('审核资料（证件与资质）'),
                        _readOnlyRow('执照/注册编号', _selectedProfile!.licenseNo),
                        _readOnlyRow('资质/证书', _selectedProfile!.certifications),
                        _readOnlyRow('主要市场', _selectedProfile!.markets),
                        _readOnlyRow('交易风格', _selectedProfile!.style),
                        _readOnlyRow('合作券商/交易平台', _selectedProfile!.broker),
                        _readOnlyRow('国家/地区', _selectedProfile!.country),
                        _readOnlyRow('城市', _selectedProfile!.city),
                        _readOnlyRow('从业年限', _selectedProfile!.yearsExperience?.toString()),
                        if (_selectedProfile!.trackRecord != null &&
                            _selectedProfile!.trackRecord!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('业绩说明',
                                    style: Theme.of(context).textTheme.labelLarge),
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
                        Text('证件与资质照片',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _photoCard(
                              context,
                              '证件照',
                              _selectedProfile!.idPhotoUrl,
                            ),
                            _photoCard(
                              context,
                              '资质证明',
                              _selectedProfile!.licensePhotoUrl,
                            ),
                            _photoCard(
                              context,
                              '资质照片',
                              _selectedProfile!.certificationPhotoUrl,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildSectionTitle('战绩与盈亏'),
                        _textField(_winsController, '胜场'),
                        _textField(_lossesController, '败场'),
                        _textField(_ratingController, '评分'),
                        _textField(_todayStrategyController, '今日策略',
                            maxLines: 3),
                        _textField(_pnlCurrentController, '本周总盈亏'),
                        _textField(_pnlMonthController, '年度盈亏'),
                        _textField(_pnlYearController, '总盈亏'),
                        _textField(_pnlTotalController, '累计盈亏'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _saveProfile,
                          child: const Text('保存资料'),
                        ),
                        const SizedBox(height: 20),
                        _buildSectionTitle('内容管理'),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton(
                              onPressed: _addStrategy,
                              child: const Text('新增策略'),
                            ),
                            OutlinedButton(
                              onPressed: _addTradeRecord,
                              child: const Text('新增交易记录'),
                            ),
                            OutlinedButton(
                              onPressed: () => _addPosition(isHistory: false),
                              child: const Text('新增当前持仓'),
                            ),
                            OutlinedButton(
                              onPressed: () => _addPosition(isHistory: true),
                              child: const Text('新增历史持仓'),
                            ),
                            OutlinedButton(
                              onPressed: _addComment,
                              child: const Text('新增评论'),
                            ),
                            OutlinedButton(
                              onPressed: _addArticle,
                              child: const Text('新增文章'),
                            ),
                            OutlinedButton(
                              onPressed: _addSchedule,
                              child: const Text('新增日程'),
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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFD4AF37),
                ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: url != null && url.trim().isNotEmpty
                ? () {
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(label, style: Theme.of(context).textTheme.titleSmall),
                              ),
                              SizedBox(
                                height: 360,
                                child: InteractiveViewer(
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) =>
                                        const Padding(
                                          padding: EdgeInsets.all(24),
                                          child: Text('加载失败'),
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
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image_outlined)),
                      ),
                    )
                  : const Center(
                      child: Text('未上传', style: TextStyle(fontSize: 12)),
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
    final raw = _selectedProfile!.status ?? 'pending';
    final status = raw.toString().trim().toLowerCase();
    if (status == 'pending') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '审核操作（刚刚申请）',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFD4AF37),
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () => _updateStatus('approved'),
                child: const Text('审核通过'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => _confirmStatus('rejected', '驳回', '确定驳回该申请？'),
                child: const Text('驳回'),
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
            '处置',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFD4AF37),
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _freezeWithDuration,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue.shade300,
                  side: BorderSide(color: Colors.blue.shade300),
                ),
                icon: const Icon(Icons.ac_unit, size: 18),
                label: const Text('冻结'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _confirmStatus('blocked', '封禁', '确定封禁该交易员？封禁后其主页将不在公域展示。'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade300,
                  side: BorderSide(color: Colors.red.shade300),
                ),
                icon: const Icon(Icons.block, size: 18),
                label: const Text('封禁'),
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
            '审核操作',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFD4AF37),
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () => _updateStatus('approved'),
                child: const Text('审核通过'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => _updateStatus('pending'),
                child: const Text('改为待审核'),
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
            '处置',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFD4AF37),
                ),
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
              label: const Text('解除冻结'),
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
            '处置',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFD4AF37),
                ),
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
              label: const Text('解除封禁'),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '未知状态: $raw，请检查数据库 status 字段是否为 pending/approved/rejected/frozen/blocked',
        style: TextStyle(color: Colors.orange.shade300, fontSize: 12),
      ),
    );
  }

  Widget _buildCurrentStatusBar(BuildContext context, String status) {
    final label = _statusLabel[status] ?? status;
    Color bgColor;
    if (status == 'pending') bgColor = Colors.orange.shade900;
    else if (status == 'approved') bgColor = Colors.green.shade900;
    else if (status == 'rejected') bgColor = Colors.grey.shade800;
    else if (status == 'frozen') bgColor = Colors.blue.shade900;
    else if (status == 'blocked') bgColor = Colors.red.shade900;
    else bgColor = Colors.grey.shade800;
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
            '当前状态：',
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
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _textField(TextEditingController controller, String label,
      {int maxLines = 1}) {
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
          content: SingleChildScrollView(
            child: Column(children: children),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
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

  static const Map<String, String> _label = {
    'pending': '待审核',
    'approved': '已通过',
    'rejected': '已驳回',
    'frozen': '已冻结',
    'blocked': '已封禁',
  };

  @override
  Widget build(BuildContext context) {
    final label = _label[status] ?? status;
    Color color;
    if (status == 'pending') color = Colors.orange;
    else if (status == 'approved') color = Colors.green;
    else if (status == 'rejected') color = Colors.grey;
    else if (status == 'frozen') color = Colors.blue;
    else if (status == 'blocked') color = Colors.red;
    else color = Colors.grey;
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
