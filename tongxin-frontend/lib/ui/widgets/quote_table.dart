import 'package:flutter/material.dart';

import '../tv_theme.dart';
import '../../features/trading/polygon_repository.dart';
import '../../features/market/market_colors.dart';

/// TradingView 风格数据表：表头 40、行 44~48、hover/selected、数字右对齐、正负色
class TvQuoteTable extends StatefulWidget {
  const TvQuoteTable({
    super.key,
    required this.rows,
    this.selectedSymbol,
    required this.onSelectSymbol,
  });

  final List<PolygonGainer> rows;
  final String? selectedSymbol;
  final ValueChanged<String> onSelectSymbol;

  @override
  State<TvQuoteTable> createState() => _TvQuoteTableState();
}

class _TvQuoteTableState extends State<TvQuoteTable> {
  int _hoveredIndex = -1;

  static String _formatPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  static String _formatTurnover(double v) {
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(2)}亿';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(2)}万';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(),
        ...widget.rows.asMap().entries.map((e) => _buildRow(e.key, e.value)),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: TvTheme.tableHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: TvTheme.innerPadding),
      decoration: BoxDecoration(
        color: TvTheme.tableHeaderBg,
        border: Border(bottom: BorderSide(color: TvTheme.border, width: 1)),
      ),
      child: Row(
        children: [
          _headerCell('代码', flex: 1, align: TextAlign.left),
          _headerCell('最新价', width: 88),
          _headerCell('涨跌额', width: 80),
          _headerCell('涨跌幅', width: 76),
          _headerCell('成交额', width: 84),
        ],
      ),
    );
  }

  Widget _headerCell(String label, {double? width, int flex = 0, TextAlign align = TextAlign.right}) {
    final child = Text(label, style: TvTheme.meta, textAlign: align);
    if (width != null) {
      return SizedBox(width: width, child: child);
    }
    return Expanded(flex: flex == 0 ? 1 : flex, child: child);
  }

  Widget _buildRow(int index, PolygonGainer g) {
    final isHovered = index == _hoveredIndex;
    final isSelected = g.ticker == widget.selectedSymbol;
    final color = MarketColors.forChangePercent(g.todaysChangePerc);
    final effectivePrice = (g.price != null && g.price! > 0)
        ? g.price!
        : (g.prevClose != null && g.todaysChange != null ? g.prevClose! + g.todaysChange! : null);
    final turnover = (effectivePrice != null && g.dayVolume != null && g.dayVolume! > 0)
        ? effectivePrice * g.dayVolume!
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = -1),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: isSelected
            ? TvTheme.rowSelectedBg
            : (isHovered ? TvTheme.rowHoverBg : Colors.transparent),
        child: InkWell(
          onTap: () => widget.onSelectSymbol(g.ticker),
          child: Container(
            height: TvTheme.rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: TvTheme.innerPadding),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: TvTheme.borderSubtle, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Text(
                    g.ticker,
                    style: TvTheme.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    effectivePrice != null && effectivePrice > 0
                        ? _formatPrice(effectivePrice)
                        : '—',
                    style: TvTheme.bodySecondary.copyWith(
                      fontFamily: TvTheme.fontMono,
                      color: effectivePrice != null && effectivePrice > 0
                          ? TvTheme.textPrimary
                          : TvTheme.textTertiary,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    g.todaysChange != null
                        ? '${g.todaysChange! >= 0 ? '+' : ''}${g.todaysChange!.toStringAsFixed(2)}'
                        : '—',
                    style: TvTheme.bodySecondary.copyWith(
                      color: g.todaysChange != null ? color : TvTheme.textTertiary,
                      fontFamily: TvTheme.fontMono,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 76,
                  child: Text(
                    g.todaysChangePerc != null
                        ? '${g.todaysChangePerc >= 0 ? '+' : ''}${g.todaysChangePerc.toStringAsFixed(2)}%'
                        : '—',
                    style: TvTheme.bodySecondary.copyWith(
                      color: g.todaysChangePerc != null ? color : TvTheme.textTertiary,
                      fontFamily: TvTheme.fontMono,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 84,
                  child: Text(
                    turnover != null && turnover > 0 ? _formatTurnover(turnover) : '—',
                    style: TvTheme.metaTertiary.copyWith(fontFamily: TvTheme.fontMono),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
