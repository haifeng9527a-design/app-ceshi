import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../teachers/teacher_models.dart';
import 'trading_api_client.dart';
import 'trading_models.dart';
import 'trading_ui.dart';

/// 成交与持仓 Tab：成交记录列表 + 当前持仓（可点持仓快捷卖出）
/// 成交记录先 mock，持仓来自 Supabase
class FillsAndPositionsTab extends StatefulWidget {
  const FillsAndPositionsTab({super.key, required this.teacherId});

  final String teacherId;

  @override
  State<FillsAndPositionsTab> createState() => _FillsAndPositionsTabState();
}

class _FillsAndPositionsTabState extends State<FillsAndPositionsTab> {
  final _api = TradingApiClient.instance;

  List<OrderFill> _fills = const [];
  List<TeacherPosition> _positions = const [];
  TradingAccountSummary? _summary;
  bool _loading = true;
  String? _error;
  final Set<String> _sellingPositionIds = <String>{};

  static const Color _surface = Color(0xFF1A1C21);

  @override
  void initState() {
    super.initState();
    _loadData(showLoading: true);
    _pollRefresh();
  }

  void _pollRefresh() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) break;
      await _loadData();
    }
  }

  Future<void> _loadData({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final fills = await _api.getFills(limit: 120);
      final positions = await _api.getPositions();
      final summary = await _api.getSummary();
      if (!mounted) return;
      setState(() {
        _fills = fills;
        _positions = positions;
        _summary = summary;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _quickSellPosition(TeacherPosition p) async {
    final qty = p.buyShares ?? 0;
    if (qty <= 0) return;
    if (_sellingPositionIds.contains(p.id)) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tradesConfirmMarketSellTitle),
        content: Text(
          l10n.tradesConfirmMarketSellContent(
            p.asset,
            qty.toStringAsFixed(0),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sellingPositionIds.add(p.id));
    try {
      await _api.placeOrder(
        symbol: p.asset,
        side: OrderSide.sell,
        type: OrderType.market,
        quantity: qty,
      );
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tradesSellSubmitted(p.asset))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sellingPositionIds.remove(p.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final timeFmt = DateFormat('MM-dd HH:mm');

    return TradingPageScaffold(
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TradingSectionHeader(
            title: l10n.tradesCurrentPositions,
            icon: Icons.pie_chart_outline,
          ),
          const SizedBox(height: 10),
          TradingSummaryStrip(summary: _summary),
          const SizedBox(height: 12),
          if (_loading)
            const TradingStateBlock.loading()
          else if (_error != null)
            TradingStateBlock.error(message: _error!)
          else if (_positions.isEmpty)
            TradingStateBlock.empty(
              message: l10n.tradesNoPosition,
            )
          else
            ..._positions.map(
              (p) => _PositionCard(
                position: p,
                selling: _sellingPositionIds.contains(p.id),
                onQuickSell: () => _quickSellPosition(p),
              ),
            ),
          const SizedBox(height: 20),
          TradingSectionHeader(
            title: l10n.tradesFillsRecord,
            icon: Icons.receipt_long,
          ),
          const SizedBox(height: 10),
          if (_fills.isEmpty)
            TradingStateBlock.empty(
              message: l10n.tradesNoFills,
            )
          else
            ..._fills.map((f) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: _surface,
                child: ListTile(
                  title: Text(
                    '${f.symbol} ${f.symbolName ?? ""}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${f.price.toStringAsFixed(2)} × ${f.quantity.toStringAsFixed(0)}  ${timeFmt.format(f.filledAt)}',
                    style: const TextStyle(color: TradingUi.textMuted, fontSize: 12),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: f.isBuy
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      f.isBuy ? l10n.tradingBuy : l10n.tradingSell,
                      style: TextStyle(
                        color: f.isBuy ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              )),
        ]),
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.position,
    required this.selling,
    required this.onQuickSell,
  });

  final TeacherPosition position;
  final bool selling;
  final VoidCallback onQuickSell;

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);
  static const Color _surface = Color(0xFF171E2B);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final qty = position.buyShares ?? 0;
    final cost = position.costPrice ?? position.buyPrice ?? 0;
    final current = position.currentPrice ?? 0;
    final buyMarketValue = qty > 0 && cost > 0 ? qty * cost : 0;
    final currentMarketValue = qty > 0 && current > 0 ? qty * current : 0;
    final totalPnl = position.pnlAmount ?? position.floatingPnl ?? 0.0;
    final dayFloatingPnl = position.floatingPnl ?? 0.0;
    final pnlColor = totalPnl >= 0 ? Colors.green : Colors.red;
    final dayPnlColor = dayFloatingPnl >= 0 ? Colors.green : Colors.red;
    final dateFmt = DateFormat('MM-dd HH:mm');
    final buyTimeText =
        position.buyTime == null ? '--' : dateFmt.format(position.buyTime!);
    final ratioText = (position.pnlRatio != null || position.realizedPnlRatioPercent != null)
        ? '${(position.pnlRatio ?? position.realizedPnlRatioPercent)! >= 0 ? "+" : ""}${(position.pnlRatio ?? position.realizedPnlRatioPercent)!.toStringAsFixed(2)}%'
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _accent.withValues(alpha: 0.45), width: 0.7),
      ),
      child: InkWell(
        onTap: onQuickSell,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    position.asset,
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Text(
                      '${l10n.tradesPositionShares} ${qty <= 0 ? "--" : qty.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    totalPnl >= 0
                        ? '+${totalPnl.toStringAsFixed(2)}'
                        : totalPnl.toStringAsFixed(2),
                    style: TextStyle(
                      color: pnlColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  if (ratioText != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: pnlColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        ratioText,
                        style: TextStyle(
                          color: pnlColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: selling ? null : onQuickSell,
                    style: FilledButton.styleFrom(
                      foregroundColor: _accent,
                      backgroundColor: _accent.withValues(alpha: 0.15),
                      minimumSize: const Size(66, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: selling
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            l10n.tradingSell,
                            style: const TextStyle(fontSize: 12),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, c) {
                  final w = (c.maxWidth - 16) / 3;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metricCell(l10n.tradingBuyTime, buyTimeText, width: w),
                      _metricCell(
                        l10n.tradesPositionBuyMarketValue,
                        buyMarketValue <= 0 ? '--' : buyMarketValue.toStringAsFixed(2),
                        width: w,
                      ),
                      _metricCell(
                        l10n.tradesPositionCurrentMarketValue,
                        currentMarketValue <= 0 ? '--' : currentMarketValue.toStringAsFixed(2),
                        width: w,
                      ),
                      _metricCell(l10n.tradingBuyPrice, cost > 0 ? cost.toStringAsFixed(2) : '--', width: w),
                      _metricCell(l10n.tradingCurrentPriceLabel, current > 0 ? current.toStringAsFixed(2) : '--', width: w),
                      _metricCell(
                        l10n.tradesPositionTodayFloatingPnl,
                        '${dayFloatingPnl >= 0 ? "+" : ""}${dayFloatingPnl.toStringAsFixed(2)}',
                        valueColor: dayPnlColor,
                        width: w,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricCell(String k, String v, {Color? valueColor, required double width}) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            v,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
