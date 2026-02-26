import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../teachers/teacher_models.dart';
import '../teachers/teacher_repository.dart';
import 'trading_models.dart';

/// 成交与持仓 Tab：成交记录列表 + 当前持仓（可点持仓快捷卖出）
/// 成交记录先 mock，持仓来自 Supabase
class FillsAndPositionsTab extends StatelessWidget {
  const FillsAndPositionsTab({super.key, required this.teacherId});

  final String teacherId;

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);
  static const Color _surface = Color(0xFF1A1C21);

  static List<OrderFill> _mockFills() {
    final now = DateTime.now();
    return [
      OrderFill(
        id: 'f1',
        orderId: 'ord-1',
        symbol: 'AAPL',
        symbolName: '苹果',
        side: OrderSide.buy,
        price: 178.50,
        quantity: 100,
        filledAt: now.subtract(const Duration(hours: 2)),
      ),
      OrderFill(
        id: 'f2',
        orderId: 'ord-2',
        symbol: 'TSLA',
        symbolName: '特斯拉',
        side: OrderSide.sell,
        price: 245.00,
        quantity: 20,
        filledAt: now.subtract(const Duration(minutes: 30)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final repo = TeacherRepository();
    final fills = _mockFills();
    final timeFmt = DateFormat('MM-dd HH:mm');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('成交记录'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '（模拟数据）',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
        ),
        if (fills.isEmpty)
          _emptyHint('暂无成交记录')
        else
          ...fills.map((f) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: _surface,
                child: ListTile(
                  title: Text(
                    '${f.symbol} ${f.symbolName ?? ""}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${f.price.toStringAsFixed(2)} × ${f.quantity.toStringAsFixed(0)}  ${timeFmt.format(f.filledAt)}',
                    style: TextStyle(color: _muted, fontSize: 12),
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
                      f.isBuy ? '买入' : '卖出',
                      style: TextStyle(
                        color: f.isBuy ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              )),
        const SizedBox(height: 24),
        _sectionTitle('当前持仓'),
        const SizedBox(height: 12),
        StreamBuilder<List<TeacherPosition>>(
          stream: repo.watchPositions(teacherId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.error_outline, size: 40, color: _muted),
                      const SizedBox(height: 8),
                      Text(
                        '加载持仓失败',
                        style: TextStyle(color: _muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final positions = snapshot.data ?? const <TeacherPosition>[];
            if (positions.isEmpty) return _emptyHint('暂无持仓');
            return Column(
              children: positions.map((p) => _PositionCard(position: p)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Icon(
          text == '成交记录' ? Icons.receipt_long : Icons.pie_chart_outline,
          color: _accent,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: _accent,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(text, style: TextStyle(color: _muted, fontSize: 14)),
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.position});

  final TeacherPosition position;

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);
  static const Color _surface = Color(0xFF1A1C21);

  @override
  Widget build(BuildContext context) {
    final pnl = position.floatingPnl ?? position.realizedPnlAmount ?? 0.0;
    final pnlColor = pnl >= 0 ? Colors.green : Colors.red;
    final amountText = position.buyShares?.toStringAsFixed(0) ?? '--';
    final ratioText = (position.pnlRatio != null || position.realizedPnlRatioPercent != null)
        ? '${(position.pnlRatio ?? position.realizedPnlRatioPercent)! >= 0 ? "+" : ""}${(position.pnlRatio ?? position.realizedPnlRatioPercent)!.toStringAsFixed(2)}%'
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _accent, width: 0.4),
      ),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('快捷卖出 ${position.asset}（待接入）')),
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      position.asset,
                      style: const TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '持仓 $amountText  盈亏 ${pnl >= 0 ? "+" : ""}${pnl.toStringAsFixed(2)}',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                    if (ratioText != null)
                      Text(
                        ratioText,
                        style: TextStyle(color: pnlColor, fontSize: 11),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    pnl >= 0 ? '+${pnl.toStringAsFixed(2)}' : pnl.toStringAsFixed(2),
                    style: TextStyle(color: pnlColor, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('卖出 ${position.asset}（待接入）')),
                      );
                    },
                    child: const Text('卖出'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
