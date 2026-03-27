import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../teachers/teacher_models.dart';
import '../teachers/teacher_repository.dart';
import 'trading_models.dart';

/// 交易记录页：上传/查看自己的股票交易记录，含实时行情占位（后续接 API）
/// 可单独作为页面使用，也可嵌入交易员中心（showAppBar: false）
/// 传入 teacherId 时从 Supabase 加载/保存持仓与历史记录
class TradingPage extends StatefulWidget {
  const TradingPage({super.key, this.showAppBar = true, this.teacherId});

  /// 为 false 时嵌入交易员中心 Tab，不显示自己的 AppBar
  final bool showAppBar;
  /// 交易员中心内传入当前用户 id，从 Supabase 读写持仓与交易记录
  final String? teacherId;

  @override
  State<TradingPage> createState() => _TradingPageState();
}

class _TradingPageState extends State<TradingPage> {
  static const Color _accent = Color(0xFFD4AF37);
  static const Color _bg = Color(0xFF111215);
  static const Color _muted = Color(0xFF6C6F77);

  final _repository = TeacherRepository();

  /// 仅当 teacherId 为空时使用（本地内存）
  final List<LocalTradeRecord> _records = [];

  @override
  Widget build(BuildContext context) {
    final bool useSupabase = widget.teacherId != null && widget.teacherId!.trim().isNotEmpty;
    final body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildRealtimeSection(),
          const SizedBox(height: 24),
          if (useSupabase) _buildPositionsSection(),
          if (useSupabase) const SizedBox(height: 24),
          useSupabase ? _buildMyRecordsSectionFromSupabase() : _buildMyRecordsSection(),
        ],
      );
    return Scaffold(
      backgroundColor: _bg,
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(AppLocalizations.of(context)!.tradingRecords),
              backgroundColor: _bg,
              foregroundColor: Colors.white,
              elevation: 0,
            )
          : null,
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddRecord(useSupabase: useSupabase),
        backgroundColor: _accent,
        foregroundColor: _bg,
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 持仓区块（仅 teacherId 时有）
  Widget _buildPositionsSection() {
    final teacherId = widget.teacherId!;
    return StreamBuilder<List<TeacherPosition>>(
      stream: _repository.watchPositions(teacherId),
      builder: (context, snapshot) {
        final positions = snapshot.data ?? const <TeacherPosition>[];
        if (positions.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_outline, color: _accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.tradingCurrentPositions,
                  style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...positions.map((p) => _PositionCard(position: p)),
          ],
        );
      },
    );
  }

  Widget _buildMyRecordsSectionFromSupabase() {
    final teacherId = widget.teacherId!;
    return StreamBuilder<List<TradeRecord>>(
      stream: _repository.watchTradeRecords(teacherId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <TradeRecord>[];
        final records = items.map((r) => LocalTradeRecord.fromTradeRecord(
          r.id,
          r.symbol,
          r.symbol,
          r.buyTime,
          r.buyPrice,
          r.buyShares,
          r.sellTime,
          r.sellPrice,
          r.sellShares,
        )).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt, color: _accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.tradingMyRecords,
                  style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (records.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32),
                alignment: Alignment.center,
                child: Text(
                  AppLocalizations.of(context)!.tradingNoRecordsAdd,
                  style: TextStyle(color: _muted, fontSize: 14),
                ),
              )
            else
              ...records.map((r) => _RecordCard(
                    record: r,
                    onDelete: null,
                  )),
          ],
        );
      },
    );
  }

  /// 实时行情占位：搜索、当前价、买入/卖出（后续接数据源 API）
  Widget _buildRealtimeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C21),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart, color: _accent, size: 20),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.tradingRealtimeQuote,
                style: TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Text(
                '（接口待接入）',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.tradingSymbolHint,
              hintStyle: const TextStyle(color: _muted),
              prefixIcon: const Icon(Icons.search, color: _muted, size: 20),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _muted.withValues(alpha: 0.3)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _priceChip(AppLocalizations.of(context)!.tradingCurrentPrice, '--', null),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _priceChip(AppLocalizations.of(context)!.tradingChangePct, '--', null),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppLocalizations.of(context)!.tradingBuyApiPending)),
                    );
                  },
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  label: Text(AppLocalizations.of(context)!.tradingBuy),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: const BorderSide(color: Colors.green),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppLocalizations.of(context)!.tradingSellApiPending)),
                    );
                  },
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  label: Text(AppLocalizations.of(context)!.tradingSell),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceChip(String label, String value, bool? isUp) {
    Color? valueColor;
    if (isUp != null) valueColor = isUp ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyRecordsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.list_alt, color: _accent, size: 20),
            const SizedBox(width: 8),
            Text(
              '我的交易记录',
              style: TextStyle(
                color: _accent,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_records.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Text(
              '暂无记录，点击右下角 + 添加',
              style: TextStyle(color: _muted, fontSize: 14),
            ),
          )
        else
          ..._records.map((r) => _RecordCard(
                record: r,
                onDelete: () => _deleteRecord(r.id),
              )),
      ],
    );
  }

  void _openAddRecord({bool useSupabase = false}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddRecordSheet(
        onSave: (record) async {
          if (useSupabase && widget.teacherId != null) {
            try {
              await _repository.addTradeRecordDetail(
                teacherId: widget.teacherId!,
                symbol: record.symbol,
                stockName: record.stockName,
                buyTime: record.buyTime,
                buyPrice: record.buyPrice,
                buyQty: record.buyQty,
                sellTime: record.sellTime,
                sellPrice: record.sellPrice,
                sellQty: record.sellQty,
              );
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.tradingRecordAdded)),
              );
            } catch (e) {
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${AppLocalizations.of(context)!.teachersSaveFailed}：$e')),
              );
            }
          } else {
            setState(() => _records.insert(0, record));
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)!.tradingRecordAdded)),
            );
          }
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  void _deleteRecord(String id) {
    setState(() => _records.removeWhere((r) => r.id == id));
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    this.onDelete,
  });

  final LocalTradeRecord record;
  final VoidCallback? onDelete;

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);

  @override
  Widget build(BuildContext context) {
    final pnl = record.pnlAmount;
    final pnlColor = pnl >= 0 ? Colors.green : Colors.red;
    final dateFmt = DateFormat('MM/dd HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1A1C21),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _accent, width: 0.4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  record.symbol,
                  style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (record.stockName.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      record.stockName,
                      style: const TextStyle(color: _muted, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: _muted),
                    onPressed: () {
                      showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1C21),
                          title: Text(AppLocalizations.of(context)!.tradingDeleteRecord),
                          content: Text(AppLocalizations.of(context)!.tradingConfirmDeleteRecord),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(c).pop(false),
                              child: Text(AppLocalizations.of(context)!.commonCancel),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(c).pop(true),
                              child: Text(AppLocalizations.of(context)!.tradingDelete),
                            ),
                          ],
                        ),
                      ).then((ok) {
                        if (ok == true) onDelete!();
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _labelValue(AppLocalizations.of(context)!.tradingBuyTime, dateFmt.format(record.buyTime)),
                const SizedBox(width: 16),
                _labelValue(AppLocalizations.of(context)!.tradingBuyPrice, '${record.buyPrice}'),
                const SizedBox(width: 16),
                _labelValue(AppLocalizations.of(context)!.tradingQty, '${record.buyQty}'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _labelValue(AppLocalizations.of(context)!.tradingSellTime, dateFmt.format(record.sellTime)),
                const SizedBox(width: 16),
                _labelValue(AppLocalizations.of(context)!.tradingSellPrice, '${record.sellPrice}'),
                const SizedBox(width: 16),
                _labelValue(AppLocalizations.of(context)!.tradingQty, '${record.sellQty}'),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${AppLocalizations.of(context)!.tradingPnl} ${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)} (${record.pnlRatioPercent.toStringAsFixed(2)}%)',
                style: TextStyle(
                  color: pnlColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _labelValue(String label, String value) => _labelValueStatic(label, value);
}

Widget _labelValueStatic(String label, String value) {
  return RichText(
    text: TextSpan(
      style: const TextStyle(fontSize: 13),
      children: [
        TextSpan(text: '$label ', style: const TextStyle(color: Color(0xFF6C6F77))),
        TextSpan(text: value, style: const TextStyle(color: Colors.white)),
      ],
    ),
  );
}

Widget _labelValue(String label, String value) => _labelValueStatic(label, value);

class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.position});

  final TeacherPosition position;

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);

  static Widget _positionLine(String value, {required String prefix}) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          TextSpan(text: '$prefix ', style: const TextStyle(color: _muted)),
          TextSpan(text: value, style: const TextStyle(color: Colors.white)),
        ],
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  static Widget _positionInline(List<(String, String)> pairs) {
    if (pairs.isEmpty) return const SizedBox.shrink();
    final spans = <InlineSpan>[];
    for (var i = 0; i < pairs.length; i++) {
      if (i > 0) spans.add(TextSpan(text: '  ', style: TextStyle(color: _muted, fontSize: 12)));
      spans.add(TextSpan(text: '${pairs[i].$1} ', style: const TextStyle(color: _muted, fontSize: 12)));
      spans.add(TextSpan(text: pairs[i].$2, style: const TextStyle(color: Colors.white, fontSize: 12)));
    }
    return Text.rich(TextSpan(style: const TextStyle(fontSize: 12), children: spans), maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Widget _buildCard({
    required String amountText,
    required Color pnlColor,
    String? ratioText,
    required List<Widget> detailRows,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1A1C21),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _accent, width: 0.4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    position.asset,
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      amountText,
                      style: TextStyle(
                        color: pnlColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (ratioText != null)
                      Text(
                        ratioText,
                        style: TextStyle(color: pnlColor, fontSize: 11),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...detailRows.map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: w,
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm');
    final isHistory = position.isHistory;

    if (isHistory) {
      final amount = position.realizedPnlAmount ?? 0;
      final ratio = position.realizedPnlRatioPercent;
      final pnlColor = amount >= 0 ? Colors.green : Colors.red;
      final rows = <Widget>[
        if (position.buyTime != null)
          _positionLine(dateFmt.format(position.buyTime!), prefix: AppLocalizations.of(context)!.tradingBuy),
        _positionInline([
          (AppLocalizations.of(context)!.tradingCost, '${position.costPrice ?? position.buyPrice ?? '--'}'),
          if (position.buyShares != null) (AppLocalizations.of(context)!.tradingQty, '${position.buyShares}'),
        ]),
        if (position.sellTime != null || position.sellPrice != null)
          _positionInline([
            if (position.sellTime != null) (AppLocalizations.of(context)!.tradingSell, dateFmt.format(position.sellTime!)),
            if (position.sellPrice != null) (AppLocalizations.of(context)!.tradingSellPrice, position.sellPrice!.toStringAsFixed(2)),
          ]),
      ];
      return _buildCard(
        amountText: '${amount >= 0 ? '+' : ''}${amount.toStringAsFixed(2)}',
        pnlColor: pnlColor,
        ratioText: ratio != null ? '${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(2)}%' : null,
        detailRows: rows,
      );
    }

    final pnl = position.floatingPnl ?? 0;
    final ratio = position.pnlRatio;
    final pnlColor = pnl >= 0 ? Colors.green : Colors.red;
    final rows = <Widget>[
      if (position.buyTime != null)
        _positionLine(dateFmt.format(position.buyTime!), prefix: AppLocalizations.of(context)!.tradingBuy),
      _positionInline([
        (AppLocalizations.of(context)!.tradingCost, '${position.costPrice ?? position.buyPrice ?? '--'}'),
        (AppLocalizations.of(context)!.tradingCurrentPriceLabel, '${position.currentPrice ?? '--'}'),
        if (position.buyShares != null) (AppLocalizations.of(context)!.tradingQty, '${position.buyShares}'),
      ]),
    ];
    return _buildCard(
      amountText: '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
      pnlColor: pnlColor,
      ratioText: ratio != null ? '${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(2)}%' : null,
      detailRows: rows,
    );
  }
}

class _AddRecordSheet extends StatefulWidget {
  const _AddRecordSheet({
    required this.onSave,
    required this.onCancel,
  });

  final void Function(LocalTradeRecord record) onSave;
  final VoidCallback onCancel;

  @override
  State<_AddRecordSheet> createState() => _AddRecordSheetState();
}

class _AddRecordSheetState extends State<_AddRecordSheet> {
  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);

  final _symbolController = TextEditingController();
  final _stockNameController = TextEditingController();
  final _buyPriceController = TextEditingController();
  final _buyQtyController = TextEditingController();
  final _sellPriceController = TextEditingController();
  final _sellQtyController = TextEditingController();

  DateTime _buyTime = DateTime.now();
  DateTime _sellTime = DateTime.now();

  @override
  void dispose() {
    _symbolController.dispose();
    _stockNameController.dispose();
    _buyPriceController.dispose();
    _buyQtyController.dispose();
    _sellPriceController.dispose();
    _sellQtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _muted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.tradingAddRecord,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                          ),
                    ),
                    TextButton(
                      onPressed: widget.onCancel,
                      child: Text(AppLocalizations.of(context)!.commonCancel),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _field(AppLocalizations.of(context)!.tradingStockCode, _symbolController, hint: AppLocalizations.of(context)!.tradingHintStockCode),
                    const SizedBox(height: 12),
                    _field(AppLocalizations.of(context)!.tradingStockName, _stockNameController,
                        hint: AppLocalizations.of(context)!.tradingHintStockName),
                    const SizedBox(height: 12),
                    _dateTimeTile(AppLocalizations.of(context)!.tradingBuyTime, _buyTime, (t) => setState(() => _buyTime = t)),
                    const SizedBox(height: 12),
                    _field(AppLocalizations.of(context)!.tradingBuyPrice, _buyPriceController,
                        hint: AppLocalizations.of(context)!.tradingHintYuan, keyboardType: TextInputType.numberWithOptions(decimal: true)),
                    const SizedBox(height: 12),
                    _field(AppLocalizations.of(context)!.tradingBuyQty, _buyQtyController,
                        hint: AppLocalizations.of(context)!.tradingHintShares,
                        keyboardType: TextInputType.numberWithOptions(decimal: true)),
                    const SizedBox(height: 12),
                    _dateTimeTile(AppLocalizations.of(context)!.tradingSellTime, _sellTime, (t) => setState(() => _sellTime = t)),
                    const SizedBox(height: 12),
                    _field(AppLocalizations.of(context)!.tradingSellPrice, _sellPriceController,
                        hint: AppLocalizations.of(context)!.tradingHintYuan,
                        keyboardType: TextInputType.numberWithOptions(decimal: true)),
                    const SizedBox(height: 12),
                    _field(AppLocalizations.of(context)!.tradingSellQty, _sellQtyController,
                        hint: AppLocalizations.of(context)!.tradingHintShares,
                        keyboardType: TextInputType.numberWithOptions(decimal: true)),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: const Color(0xFF111215),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(AppLocalizations.of(context)!.commonSave),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _muted),
        hintStyle: const TextStyle(color: _muted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _muted.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent),
        ),
      ),
      style: const TextStyle(color: Colors.white),
    );
  }

  Widget _dateTimeTile(String label, DateTime value, ValueChanged<DateTime> onPick) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date == null || !mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        if (time == null || !mounted) return;
        onPick(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _muted),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _muted.withValues(alpha: 0.5)),
          ),
        ),
        child: Text(
          fmt.format(value),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  void _submit() {
    final symbol = _symbolController.text.trim();
    if (symbol.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.tradingFillSymbol)),
      );
      return;
    }
    final buyPrice = double.tryParse(_buyPriceController.text.trim()) ?? 0;
    final buyQty = double.tryParse(_buyQtyController.text.trim()) ?? 0;
    final sellPrice = double.tryParse(_sellPriceController.text.trim()) ?? 0;
    final sellQty = double.tryParse(_sellQtyController.text.trim()) ?? 0;
    if (buyPrice <= 0 || buyQty <= 0 || sellPrice <= 0 || sellQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.tradingFillPriceQty)),
      );
      return;
    }

    final record = LocalTradeRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      symbol: symbol,
      stockName: _stockNameController.text.trim(),
      buyTime: _buyTime,
      buyPrice: buyPrice,
      buyQty: buyQty,
      sellTime: _sellTime,
      sellPrice: sellPrice,
      sellQty: sellQty,
    );
    widget.onSave(record);
  }
}
