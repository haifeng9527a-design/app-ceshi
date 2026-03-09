import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/admin_api_client.dart';

class AdminTradingPanel extends StatefulWidget {
  const AdminTradingPanel({super.key});

  @override
  State<AdminTradingPanel> createState() => _AdminTradingPanelState();
}

class _AdminTradingPanelState extends State<AdminTradingPanel> {
  final _api = AdminApiClient.instance;
  final _defaultTradingCashController = TextEditingController();
  final _defaultLeverageController = TextEditingController();
  final _maxLeverageController = TextEditingController();
  final _maintenanceMarginRateController = TextEditingController();
  final _forcedLiqRatioController = TextEditingController();
  final _adjustAmountController = TextEditingController(text: '1000');
  final _adjustNoteController = TextEditingController();
  final _teacherSearchController = TextEditingController();

  bool _loadingTeachers = false;
  bool _loading = false;
  bool _savingTradingConfig = false;
  String? _error;
  String? _selectedTeacherId;
  String _teacherQuery = '';
  String _accountType = 'spot';
  String _defaultProductType = 'spot';
  String _defaultMarginMode = 'cross';
  bool _allowShort = true;
  String _adjustAccountType = 'spot';
  bool _adjustIncrease = true;
  String? _selectedRemarkPreset;
  List<Map<String, dynamic>> _teacherOptions = const [];

  Map<String, dynamic>? _overview;
  List<Map<String, dynamic>> _positions = const [];
  List<Map<String, dynamic>> _closedPositions = const [];
  List<Map<String, dynamic>> _ledger = const [];
  final Set<String> _closingPositionIds = <String>{};
  static const int _pageSize = 20;
  int _positionsPage = 1;
  int _closedPage = 1;
  int _ledgerPage = 1;
  bool _positionsHasNext = false;
  bool _closedHasNext = false;
  bool _ledgerHasNext = false;

  @override
  void initState() {
    super.initState();
    _loadTradingConfig();
    _loadTeachers();
  }

  @override
  void dispose() {
    _defaultTradingCashController.dispose();
    _defaultLeverageController.dispose();
    _maxLeverageController.dispose();
    _maintenanceMarginRateController.dispose();
    _forcedLiqRatioController.dispose();
    _adjustAmountController.dispose();
    _adjustNoteController.dispose();
    _teacherSearchController.dispose();
    super.dispose();
  }

  String get _teacherId => (_selectedTeacherId ?? '').trim();

  Future<void> _loadTeachers() async {
    setState(() {
      _loadingTeachers = true;
      _error = null;
    });
    try {
      final resp = await _api.get('api/admin/teachers/profiles');
      if (resp.statusCode != 200) {
        throw StateError('交易员列表加载失败(${resp.statusCode})：${resp.body}');
      }
      final rows = jsonDecode(resp.body) as List<dynamic>;
      final usersResp = await _api.get('api/admin/users/detailed');
      Map<String, Map<String, dynamic>> usersById = const {};
      if (usersResp.statusCode == 200) {
        final userRows = jsonDecode(usersResp.body) as List<dynamic>;
        usersById = {
          for (final raw in userRows)
            (raw as Map)['user_id']?.toString() ?? '':
                Map<String, dynamic>.from(raw),
        };
      }
      final list = rows
          .map((e) {
            final row = Map<String, dynamic>.from(e as Map);
            final uid = row['user_id']?.toString() ?? '';
            final user = usersById[uid] ?? const <String, dynamic>{};
            return {
              ...row,
              'display_name': row['display_name'] ?? user['display_name'],
              'email': user['email'],
              'avatar_url': row['avatar_url'] ?? user['avatar_url'],
              'short_id': user['short_id'],
            };
          })
          .where(
            (row) => (row['user_id']?.toString().trim().isNotEmpty ?? false),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _teacherOptions = list;
        final selectedStillExists = list.any(
          (item) => item['user_id']?.toString() == _selectedTeacherId,
        );
        if (!selectedStillExists) {
          _selectedTeacherId = list.isNotEmpty
              ? list.first['user_id']?.toString()
              : null;
        }
      });
      if ((_selectedTeacherId ?? '').isNotEmpty) {
        await _loadData();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingTeachers = false);
    }
  }

  Future<void> _loadTradingConfig() async {
    try {
      final resp = await _api.get('/api/admin/trading/config');
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return;
      }
      final body = jsonDecode(resp.body);
      if (body is! Map<String, dynamic>) {
        return;
      }
      if (!mounted) return;
      setState(() {
        final cash = (body['default_initial_cash_usd'] as num?)?.toDouble();
        final defaultLeverage = (body['default_leverage'] as num?)?.toInt();
        final maxLeverage = (body['max_leverage'] as num?)?.toInt();
        final maintenanceRate = (body['maintenance_margin_rate'] as num?)
            ?.toDouble();
        final forcedLiq = (body['forced_liquidation_ratio'] as num?)
            ?.toDouble();
        if (cash != null && cash > 0) {
          _defaultTradingCashController.text = cash.toStringAsFixed(0);
        }
        if (defaultLeverage != null && defaultLeverage > 0) {
          _defaultLeverageController.text = '$defaultLeverage';
        }
        if (maxLeverage != null && maxLeverage > 0) {
          _maxLeverageController.text = '$maxLeverage';
        }
        if (maintenanceRate != null && maintenanceRate > 0) {
          _maintenanceMarginRateController.text = (maintenanceRate * 100)
              .toStringAsFixed(2);
        }
        if (forcedLiq != null && forcedLiq > 0) {
          _forcedLiqRatioController.text = forcedLiq.toStringAsFixed(2);
        }
        final productType = body['default_product_type']?.toString();
        final marginMode = body['default_margin_mode']?.toString();
        if (productType != null && productType.isNotEmpty) {
          _defaultProductType = productType;
        }
        if (marginMode != null && marginMode.isNotEmpty) {
          _defaultMarginMode = marginMode;
        }
        _allowShort =
            body['allow_short'] == true ||
            '${body['allow_short']}'.toLowerCase() == 'true';
      });
    } catch (_) {}
  }

  Future<void> _saveTradingConfig() async {
    if (_savingTradingConfig) return;
    final cash = double.tryParse(_defaultTradingCashController.text.trim());
    final defaultLeverage = int.tryParse(
      _defaultLeverageController.text.trim(),
    );
    final maxLeverage = int.tryParse(_maxLeverageController.text.trim());
    final maintenancePercent = double.tryParse(
      _maintenanceMarginRateController.text.trim(),
    );
    final forcedLiq = double.tryParse(_forcedLiqRatioController.text.trim());
    if (cash == null || cash <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('初始资金必须大于 0')));
      return;
    }
    if (defaultLeverage == null || defaultLeverage <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('默认杠杆必须大于 0')));
      return;
    }
    if (maxLeverage == null || maxLeverage < defaultLeverage) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('最大杠杆不能小于默认杠杆')));
      return;
    }
    if (maintenancePercent == null ||
        maintenancePercent <= 0 ||
        maintenancePercent >= 100) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('维持保证金率请输入 0-100 之间数字')));
      return;
    }
    if (forcedLiq == null || forcedLiq <= 0 || forcedLiq > 5) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('强制平仓风险比例请输入 0-5 之间数字')));
      return;
    }
    setState(() => _savingTradingConfig = true);
    try {
      final resp = await _api.patch(
        '/api/admin/trading/config',
        body: {
          'default_initial_cash_usd': cash,
          'default_product_type': _defaultProductType,
          'default_margin_mode': _defaultMarginMode,
          'default_leverage': defaultLeverage,
          'max_leverage': maxLeverage,
          'allow_short': _allowShort,
          'maintenance_margin_rate': maintenancePercent / 100,
          'forced_liquidation_ratio': forcedLiq,
        },
      );
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('交易参数已保存')));
      } else {
        throw StateError('${resp.statusCode} ${resp.body}');
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
      if (mounted) setState(() => _savingTradingConfig = false);
    }
  }

  String _teacherLabel(Map<String, dynamic> item) {
    final displayName = item['display_name']?.toString().trim();
    final email = item['email']?.toString().trim();
    final shortId = item['short_id']?.toString().trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    if (email != null && email.isNotEmpty) {
      return email;
    }
    if (shortId != null && shortId.isNotEmpty) {
      return shortId;
    }
    return '未命名交易员';
  }

  bool _teacherMatchesQuery(Map<String, dynamic> item) {
    final q = _teacherQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final texts = <String>[
      item['display_name']?.toString() ?? '',
      item['email']?.toString() ?? '',
      item['short_id']?.toString() ?? '',
      item['user_id']?.toString() ?? '',
    ];
    return texts.any((t) => t.toLowerCase().contains(q));
  }

  List<Map<String, dynamic>> get _filteredTeacherOptions {
    return _teacherOptions.where(_teacherMatchesQuery).toList(growable: false);
  }

  void _resetPaging() {
    _positionsPage = 1;
    _closedPage = 1;
    _ledgerPage = 1;
    _positionsHasNext = false;
    _closedHasNext = false;
    _ledgerHasNext = false;
  }

  Future<void> _loadData() async {
    final teacherId = _teacherId;
    if (teacherId.isEmpty) {
      setState(() => _error = '请先选择交易员');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overviewResp = await _api.get(
        'api/admin/trading/users/$teacherId/overview?account_type=$_accountType',
      );
      final positionsResp = await _api.get(
        'api/admin/trading/users/$teacherId/positions?account_type=$_accountType&page_size=$_pageSize&page=$_positionsPage',
      );
      final closedResp = await _api.get(
        'api/admin/trading/users/$teacherId/positions?account_type=$_accountType&include_history=true&page_size=$_pageSize&page=$_closedPage',
      );
      final ledgerResp = await _api.get(
        'api/admin/trading/users/$teacherId/ledger?account_type=$_accountType&page_size=$_pageSize&page=$_ledgerPage',
      );

      if (overviewResp.statusCode != 200) {
        throw StateError(
          '总览加载失败(${overviewResp.statusCode})：${overviewResp.body}',
        );
      }
      if (positionsResp.statusCode != 200) {
        throw StateError(
          '持仓加载失败(${positionsResp.statusCode})：${positionsResp.body}',
        );
      }
      if (ledgerResp.statusCode != 200) {
        throw StateError('流水加载失败(${ledgerResp.statusCode})：${ledgerResp.body}');
      }
      if (closedResp.statusCode != 200) {
        throw StateError(
          '平仓记录加载失败(${closedResp.statusCode})：${closedResp.body}',
        );
      }

      final overviewJson = jsonDecode(overviewResp.body);
      final positionsJson = jsonDecode(positionsResp.body) as List<dynamic>;
      final closedJson = jsonDecode(closedResp.body) as List<dynamic>;
      final ledgerJson = jsonDecode(ledgerResp.body) as List<dynamic>;

      if (!mounted) return;
      setState(() {
        _overview = overviewJson is Map<String, dynamic>
            ? overviewJson
            : Map<String, dynamic>.from(overviewJson as Map);
        _positions = positionsJson
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
        _closedPositions = closedJson
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
        _ledger = ledgerJson
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);
        _positionsHasNext = _positions.length >= _pageSize;
        _closedHasNext = _closedPositions.length >= _pageSize;
        _ledgerHasNext = _ledger.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _closePosition(Map<String, dynamic> position) async {
    final teacherId = _teacherId;
    final positionId = position['id']?.toString() ?? '';
    if (teacherId.isEmpty || positionId.isEmpty) return;
    final symbol = position['asset']?.toString() ?? '-';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认平仓'),
        content: Text('确定对 $symbol 执行后台强制平仓吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认平仓'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (mounted) {
      setState(() => _closingPositionIds.add(positionId));
    }
    try {
      final resp = await _api.post(
        'api/admin/trading/users/$teacherId/positions/$positionId/close',
      );
      if (resp.statusCode != 200) {
        throw StateError('平仓失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$symbol 平仓成功')));
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('平仓失败：$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _closingPositionIds.remove(positionId));
      }
    }
  }

  Future<void> _adjustBalance() async {
    final teacherId = _teacherId;
    if (teacherId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择交易员')));
      return;
    }
    final amountRaw = double.tryParse(
      _adjustAmountController.text.replaceAll(',', '').trim(),
    );
    if (amountRaw == null || amountRaw <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('金额必须大于 0')));
      return;
    }
    final amount = _adjustIncrease ? amountRaw : -amountRaw;
    try {
      final resp = await _api.post(
        'api/admin/trading/users/$teacherId/adjust-balance',
        body: {
          'account_type': _adjustAccountType,
          'amount': amount,
          'note': _adjustNoteController.text.trim(),
        },
      );
      if (resp.statusCode != 200) {
        throw StateError('调账失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已${amount > 0 ? '上分' : '下分'} ${amount.abs().toStringAsFixed(2)}',
          ),
        ),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('调账失败：$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  String _fmt(dynamic value) {
    if (value == null) return '-';
    if (value is num) {
      final v = value.toDouble();
      if (v == v.roundToDouble()) return v.toStringAsFixed(0);
      return v.toStringAsFixed(2);
    }
    return value.toString();
  }

  String _fmtTime(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '-';
    final normalized = raw.replaceFirst('T', ' ').replaceFirst('Z', '');
    final trimmed = normalized.split('.').first;
    if (trimmed.length >= 16) {
      return trimmed.substring(0, 16);
    }
    return trimmed;
  }

  String _formatFinancialAmount(double value) {
    final negative = value < 0;
    final abs = value.abs();
    final fixed = abs.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i += 1) {
      final idxFromRight = intPart.length - i;
      buf.write(intPart[i]);
      if (idxFromRight > 1 && idxFromRight % 3 == 1) {
        buf.write(',');
      }
    }
    return '${negative ? '-' : ''}${buf.toString()}.$decPart';
  }

  String _toChineseAmount(double value) {
    final digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
    final units = ['', '十', '百', '千'];
    final bigUnits = ['', '万', '亿', '万亿'];
    int n = value.abs().floor();
    if (n == 0) return '零';
    var groupIndex = 0;
    final parts = <String>[];
    while (n > 0) {
      final group = n % 10000;
      if (group > 0) {
        var groupText = '';
        var num = group;
        var zeroFlag = false;
        for (var i = 0; i < 4; i += 1) {
          final d = num % 10;
          if (d == 0) {
            if (groupText.isNotEmpty) zeroFlag = true;
          } else {
            final prefix = (zeroFlag ? '零' : '') + digits[d] + units[i];
            groupText = prefix + groupText;
            zeroFlag = false;
          }
          num ~/= 10;
        }
        parts.insert(0, groupText + bigUnits[groupIndex]);
      }
      n ~/= 10000;
      groupIndex += 1;
    }
    var result = parts.join('');
    result = result.replaceAll('一十', '十');
    return value < 0 ? '负$result' : result;
  }

  double get _adjustAmountValue {
    final raw = _adjustAmountController.text.replaceAll(',', '').trim();
    return double.tryParse(raw) ?? 0;
  }

  String get _adjustAmountPreviewFinancial =>
      _formatFinancialAmount(_adjustAmountValue);

  String get _adjustAmountPreviewChinese =>
      _toChineseAmount(_adjustAmountValue);

  List<String> get _remarkPresets {
    if (_adjustIncrease) {
      return const ['USDT充值', '网页充值', '管理员补发', '活动赠金', '纠错上分'];
    }
    return const ['用户提现', '互相转账', '手续费扣减', '风控扣减', '纠错下分'];
  }

  void _onAmountChanged(String rawInput) {
    final cleaned = rawInput.replaceAll(',', '').trim();
    if (cleaned.isEmpty) {
      setState(() {});
      return;
    }
    final parsed = double.tryParse(cleaned);
    if (parsed == null) {
      setState(() {});
      return;
    }
    final hasDot = cleaned.contains('.');
    final text = hasDot
        ? _formatFinancialAmount(parsed)
        : _formatFinancialAmount(parsed).split('.').first;
    if (_adjustAmountController.text != text) {
      _adjustAmountController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    setState(() {});
  }

  double _num(dynamic value, [double fallback = 0]) {
    if (value is num) return value.toDouble();
    final parsed = double.tryParse('${value ?? ''}');
    return parsed ?? fallback;
  }

  Color _pnlColor(double value) {
    if (value > 0) return const Color(0xFF35C46A);
    if (value < 0) return const Color(0xFFFF5D5D);
    return Colors.white70;
  }

  Widget _sectionCard(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
        color: const Color(0xFF0B111B),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFFD4AF37),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildSummaryTable(Map<String, dynamic> account) {
    final rows = <({String key, String label, dynamic value})>[
      (key: 'account_type', label: '账户类型', value: account['account_type']),
      (key: 'currency', label: '币种', value: account['currency']),
      (key: 'cash_balance', label: '余额', value: account['cash_balance']),
      (key: 'cash_available', label: '可用', value: account['cash_available']),
      (key: 'cash_frozen', label: '冻结', value: account['cash_frozen']),
      (key: 'equity', label: '权益', value: account['equity']),
      (key: 'used_margin', label: '已用保证金', value: account['used_margin']),
      (
        key: 'maintenance_margin',
        label: '维持保证金',
        value: account['maintenance_margin'],
      ),
      (key: 'realized_pnl', label: '已实现盈亏', value: account['realized_pnl']),
      (key: 'unrealized_pnl', label: '未实现盈亏', value: account['unrealized_pnl']),
    ];
    return Table(
      columnWidths: const {0: FlexColumnWidth(1.6), 1: FlexColumnWidth(2.4)},
      border: TableBorder.all(color: Colors.white24),
      children: rows
          .map(
            (e) => TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    e.label,
                    style: const TextStyle(
                      color: Color(0xFF9AA0A6),
                      fontSize: 12,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    _fmt(e.value),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          e.key == 'realized_pnl' || e.key == 'unrealized_pnl'
                          ? _pnlColor(_num(e.value))
                          : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  Widget _buildKpiCards(Map<String, dynamic> account) {
    final kpis = <({String label, double value, bool pnl})>[
      (label: '权益', value: _num(account['equity']), pnl: false),
      (label: '可用资金', value: _num(account['cash_available']), pnl: false),
      (label: '已实现盈亏', value: _num(account['realized_pnl']), pnl: true),
      (label: '未实现盈亏', value: _num(account['unrealized_pnl']), pnl: true),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: kpis.map((k) {
        final color = k.pnl ? _pnlColor(k.value) : const Color(0xFFD4AF37);
        return Container(
          width: 220,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: const Color(0xFF101A2A),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                k.label,
                style: const TextStyle(fontSize: 12, color: Color(0xFF9AA0A6)),
              ),
              const SizedBox(height: 8),
              Text(
                _fmt(k.value),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<double> _balanceSeries() {
    final values = <double>[];
    for (final row in _ledger.reversed) {
      final v = _num(row['balance_after'], double.nan);
      if (!v.isNaN && v.isFinite) values.add(v);
    }
    if (values.length > 24) {
      return values.sublist(values.length - 24);
    }
    return values;
  }

  Widget _buildMiniCharts() {
    final balance = _balanceSeries();
    final pnlRows = _closedPositions.take(8).map((e) {
      return (symbol: _fmt(e['asset']), pnl: _num(e['pnl_amount']));
    }).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 1050;
        final leftCard = _sectionCard(
          '资产趋势',
          SizedBox(
            height: 170,
            child: balance.length < 2
                ? const Center(child: Text('数据不足，暂无趋势图'))
                : CustomPaint(
                    painter: _LineChartPainter(balance),
                    child: Container(),
                  ),
          ),
        );
        final rightCard = _sectionCard(
          '平仓盈亏分布',
          pnlRows.isEmpty
              ? const SizedBox(
                  height: 170,
                  child: Center(child: Text('暂无平仓数据')),
                )
              : Column(
                  children: pnlRows.map((row) {
                    final widthFactor = math.min(
                      1.0,
                      (row.pnl.abs() / 10000).clamp(0.08, 1.0),
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 70,
                            child: Text(
                              row.symbol,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: widthFactor,
                                child: Container(
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _pnlColor(row.pnl),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 92,
                            child: Text(
                              _fmt(row.pnl),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: _pnlColor(row.pnl),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        );
        if (narrow) {
          return Column(
            children: [leftCard, const SizedBox(height: 12), rightCard],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: leftCard),
            const SizedBox(width: 12),
            Expanded(child: rightCard),
          ],
        );
      },
    );
  }

  Widget _buildPager({
    required int page,
    required bool hasNext,
    required VoidCallback onPrev,
    required VoidCallback onNext,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: page > 1 ? onPrev : null,
          icon: const Icon(Icons.chevron_left, size: 18),
          label: const Text('上一页'),
        ),
        const SizedBox(width: 10),
        Text('第 $page 页', style: const TextStyle(color: Colors.white70)),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: hasNext ? onNext : null,
          icon: const Icon(Icons.chevron_right, size: 18),
          label: const Text('下一页'),
        ),
      ],
    );
  }

  Widget _buildPositionsTable() {
    if (_positions.isEmpty) return const Text('暂无持仓数据');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF13233A)),
        dataRowMinHeight: 44,
        columnSpacing: 28,
        headingTextStyle: const TextStyle(fontWeight: FontWeight.w700),
        columns: const [
          DataColumn(label: Text('标的')),
          DataColumn(label: Text('方向')),
          DataColumn(label: Text('数量')),
          DataColumn(label: Text('成本价')),
          DataColumn(label: Text('现价')),
          DataColumn(label: Text('浮盈亏')),
          DataColumn(label: Text('操作')),
          DataColumn(label: Text('下单时间')),
        ],
        rows: _positions
            .take(_pageSize)
            .map(
              (p) => DataRow(
                cells: [
                  DataCell(Text(_fmt(p['asset']))),
                  DataCell(Text(_fmt(p['position_side']))),
                  DataCell(Text(_fmt(p['buy_shares']))),
                  DataCell(Text(_fmt(p['cost_price']))),
                  DataCell(Text(_fmt(p['current_price']))),
                  DataCell(
                    Text(
                      _fmt(p['floating_pnl']),
                      style: TextStyle(
                        color: _pnlColor(_num(p['floating_pnl'])),
                      ),
                    ),
                  ),
                  DataCell(
                    OutlinedButton(
                      onPressed:
                          _closingPositionIds.contains(p['id']?.toString())
                          ? null
                          : () => _closePosition(p),
                      child: Text(
                        _closingPositionIds.contains(p['id']?.toString())
                            ? '平仓中...'
                            : '平仓',
                      ),
                    ),
                  ),
                  DataCell(Text(_fmtTime(p['buy_time'] ?? p['created_at']))),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildClosedPositionsTable() {
    if (_closedPositions.isEmpty) return const Text('暂无平仓记录');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF13233A)),
        dataRowMinHeight: 44,
        columnSpacing: 26,
        headingTextStyle: const TextStyle(fontWeight: FontWeight.w700),
        columns: const [
          DataColumn(label: Text('标的')),
          DataColumn(label: Text('动作')),
          DataColumn(label: Text('方向')),
          DataColumn(label: Text('开仓时间')),
          DataColumn(label: Text('平仓时间')),
          DataColumn(label: Text('开仓价')),
          DataColumn(label: Text('平仓价')),
          DataColumn(label: Text('数量')),
          DataColumn(label: Text('盈亏')),
        ],
        rows: _closedPositions
            .take(_pageSize)
            .map(
              (p) => DataRow(
                cells: [
                  DataCell(Text(_fmt(p['asset']))),
                  DataCell(Text(_fmt(p['position_action']))),
                  DataCell(Text(_fmt(p['position_side']))),
                  DataCell(Text(_fmtTime(p['buy_time']))),
                  DataCell(Text(_fmtTime(p['sell_time']))),
                  DataCell(Text(_fmt(p['buy_price'] ?? p['cost_price']))),
                  DataCell(Text(_fmt(p['sell_price']))),
                  DataCell(Text(_fmt(p['buy_shares']))),
                  DataCell(
                    Text(
                      _fmt(p['pnl_amount']),
                      style: TextStyle(color: _pnlColor(_num(p['pnl_amount']))),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildLedgerTable() {
    if (_ledger.isEmpty) return const Text('暂无资金流水数据');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF13233A)),
        dataRowMinHeight: 44,
        columnSpacing: 26,
        headingTextStyle: const TextStyle(fontWeight: FontWeight.w700),
        columns: const [
          DataColumn(label: Text('时间')),
          DataColumn(label: Text('类型')),
          DataColumn(label: Text('金额')),
          DataColumn(label: Text('余额后')),
          DataColumn(label: Text('备注')),
        ],
        rows: _ledger
            .take(_pageSize)
            .map(
              (l) => DataRow(
                cells: [
                  DataCell(Text(_fmtTime(l['created_at']))),
                  DataCell(Text(_fmt(l['entry_type']))),
                  DataCell(
                    Text(
                      _fmt(l['amount']),
                      style: TextStyle(color: _pnlColor(_num(l['amount']))),
                    ),
                  ),
                  DataCell(Text(_fmt(l['balance_after']))),
                  DataCell(
                    SizedBox(
                      width: 280,
                      child: Text(
                        _fmt(l['note']),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = _overview?['account'] is Map
        ? Map<String, dynamic>.from(_overview!['account'] as Map)
        : const <String, dynamic>{};
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          '交易管理',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFFD4AF37),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '统一按表格查看交易员资金、持仓、流水，并支持直接调账。',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          '交易参数设置',
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 230,
                child: TextField(
                  controller: _defaultTradingCashController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '默认初始资金(USD)',
                    hintText: '1000000',
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _defaultProductType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '默认产品',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'spot', child: Text('现货 spot')),
                    DropdownMenuItem(
                      value: 'perpetual',
                      child: Text('永续 perpetual'),
                    ),
                    DropdownMenuItem(value: 'future', child: Text('期货 future')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _defaultProductType = v);
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _defaultMarginMode,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '默认保证金模式',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cross', child: Text('全仓 cross')),
                    DropdownMenuItem(
                      value: 'isolated',
                      child: Text('逐仓 isolated'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _defaultMarginMode = v);
                  },
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _defaultLeverageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '默认杠杆',
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _maxLeverageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '最大杠杆',
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: _maintenanceMarginRateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '维持保证金率(%)',
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: TextField(
                  controller: _forcedLiqRatioController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '强平风险比例',
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: SwitchListTile(
                  value: _allowShort,
                  onChanged: (v) => setState(() => _allowShort = v),
                  title: const Text('允许做空'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
              FilledButton(
                onPressed: _savingTradingConfig ? null : _saveTradingConfig,
                child: _savingTradingConfig
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存参数'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          '筛选条件',
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 420,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedTeacherId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '交易员',
                  ),
                  selectedItemBuilder: (context) {
                    return _filteredTeacherOptions.map((item) {
                      final hasAvatar =
                          item['avatar_url']?.toString().trim().isNotEmpty ??
                          false;
                      return Row(
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundImage: hasAvatar
                                ? NetworkImage(item['avatar_url'].toString())
                                : null,
                            child: hasAvatar
                                ? null
                                : const Icon(Icons.person, size: 12),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _teacherLabel(item),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                  items: _filteredTeacherOptions
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item['user_id']?.toString(),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundImage:
                                    (item['avatar_url']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ??
                                        false)
                                    ? NetworkImage(
                                        item['avatar_url'].toString(),
                                      )
                                    : null,
                                child:
                                    (item['avatar_url']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ??
                                        false)
                                    ? null
                                    : const Icon(Icons.person, size: 14),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 300,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _teacherLabel(item),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      item['email']?.toString() ??
                                          item['short_id']?.toString() ??
                                          '',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF9AA0A6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _loadingTeachers
                      ? null
                      : (v) async {
                          if (v == null || v.isEmpty) return;
                          setState(() {
                            _selectedTeacherId = v;
                            _resetPaging();
                          });
                          await _loadData();
                        },
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _teacherSearchController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '搜索邮箱/ID',
                    hintText: 'email / short_id / user_id',
                  ),
                  onChanged: (v) => setState(() => _teacherQuery = v.trim()),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _accountType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '账户',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'spot', child: Text('现货 spot')),
                    DropdownMenuItem(
                      value: 'contract',
                      child: Text('合约 contract'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _accountType = v;
                        _resetPaging();
                      });
                    }
                  },
                ),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _loadData,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('查询'),
              ),
              OutlinedButton.icon(
                onPressed: _loadingTeachers ? null : _loadTeachers,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(_loadingTeachers ? '加载中' : '刷新交易员'),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: Colors.red.shade300)),
        ],
        const SizedBox(height: 20),
        _buildKpiCards(account),
        const SizedBox(height: 20),
        _buildMiniCharts(),
        const SizedBox(height: 20),
        _sectionCard('资金总览', _buildSummaryTable(account)),
        const SizedBox(height: 20),
        _sectionCard(
          '上分/下分',
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _adjustAccountType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '调账账户',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'spot', child: Text('现货')),
                    DropdownMenuItem(value: 'contract', child: Text('合约')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _adjustAccountType = v);
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<bool>(
                  initialValue: _adjustIncrease,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '操作',
                  ),
                  items: const [
                    DropdownMenuItem(value: true, child: Text('上分')),
                    DropdownMenuItem(value: false, child: Text('下分')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _adjustIncrease = v;
                        _selectedRemarkPreset = null;
                      });
                    }
                  },
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _adjustAmountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '金额',
                  ),
                  onChanged: _onAmountChanged,
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _adjustNoteController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '备注',
                  ),
                ),
              ),
              FilledButton(
                onPressed: _adjustBalance,
                child: const Text('确认调账'),
              ),
              SizedBox(
                width: 620,
                child: Text(
                  '金额预览：$_adjustAmountPreviewFinancial（$_adjustAmountPreviewChinese）',
                  style: const TextStyle(
                    color: Color(0xFFD4AF37),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 900,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _remarkPresets.map((preset) {
                    final selected = _selectedRemarkPreset == preset;
                    return ChoiceChip(
                      label: Text(preset),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _selectedRemarkPreset = preset;
                          _adjustNoteController.text = preset;
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionCard('当前持仓（分页）', _buildPositionsTable()),
        const SizedBox(height: 10),
        _buildPager(
          page: _positionsPage,
          hasNext: _positionsHasNext,
          onPrev: () async {
            if (_positionsPage <= 1) return;
            setState(() => _positionsPage -= 1);
            await _loadData();
          },
          onNext: () async {
            if (!_positionsHasNext) return;
            setState(() => _positionsPage += 1);
            await _loadData();
          },
        ),
        const SizedBox(height: 20),
        _sectionCard('平仓记录（分页）', _buildClosedPositionsTable()),
        const SizedBox(height: 10),
        _buildPager(
          page: _closedPage,
          hasNext: _closedHasNext,
          onPrev: () async {
            if (_closedPage <= 1) return;
            setState(() => _closedPage -= 1);
            await _loadData();
          },
          onNext: () async {
            if (!_closedHasNext) return;
            setState(() => _closedPage += 1);
            await _loadData();
          },
        ),
        const SizedBox(height: 20),
        _sectionCard('资金流水（分页）', _buildLedgerTable()),
        const SizedBox(height: 10),
        _buildPager(
          page: _ledgerPage,
          hasNext: _ledgerHasNext,
          onPrev: () async {
            if (_ledgerPage <= 1) return;
            setState(() => _ledgerPage -= 1);
            await _loadData();
          },
          onNext: () async {
            if (!_ledgerHasNext) return;
            setState(() => _ledgerPage += 1);
            await _loadData();
          },
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV).abs() < 0.0001 ? 1.0 : (maxV - minV);

    final gridPaint = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i += 1) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    for (var i = 0; i < values.length; i += 1) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - ((values[i] - minV) / span) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    final areaPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final areaPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x66D4AF37), Color(0x00D4AF37)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(areaPath, areaPaint);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    if (oldDelegate.values.length != values.length) return true;
    for (var i = 0; i < values.length; i += 1) {
      if (oldDelegate.values[i] != values[i]) return true;
    }
    return false;
  }
}
