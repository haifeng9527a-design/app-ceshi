import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../trading/polygon_repository.dart';
import 'chart_theme.dart';
import '../indicators.dart';

/// 指标 Tab 内容：主图叠加（MA/EMA）+ 副图（VOL/MACD/RSI）切换，并展示当前数值
class IndicatorsSection extends StatelessWidget {
  const IndicatorsSection({
    super.key,
    required this.overlayIndicator,
    required this.subChartIndicator,
    required this.onOverlayChanged,
    required this.onSubChartChanged,
    this.showPrevCloseLine = true,
    this.onShowPrevCloseLineChanged,
    this.candles = const [],
  });

  final String overlayIndicator;
  final String subChartIndicator;
  final ValueChanged<String> onOverlayChanged;
  final ValueChanged<String> onSubChartChanged;
  final bool showPrevCloseLine;
  final ValueChanged<bool>? onShowPrevCloseLineChanged;
  final List<ChartCandle> candles;

  static const List<({String label, String id, bool isOverlay})> items = [
    (label: '无', id: 'none', isOverlay: true),
    (label: 'MA', id: 'ma', isOverlay: true),
    (label: 'EMA', id: 'ema', isOverlay: true),
    (label: 'VOL', id: 'vol', isOverlay: false),
    (label: 'MACD', id: 'macd', isOverlay: false),
    (label: 'RSI', id: 'rsi', isOverlay: false),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      decoration: const BoxDecoration(
        color: ChartTheme.cardBackground,
        border: Border(top: BorderSide(color: ChartTheme.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSelector(context),
          if (candles.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildValuesSection(context),
          ],
        ],
      ),
    );
  }

  Widget _buildSelector(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String itemLabel(String id, String fallback) => id == 'none' ? l10n.chartIndicatorNone : fallback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.chartMainOverlay, style: TextStyle(color: ChartTheme.textTertiary, fontSize: 11)),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: items.where((e) => e.isOverlay).map((e) {
              final selected = overlayIndicator == e.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(itemLabel(e.id, e.label), style: TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => onOverlayChanged(e.id),
                  selectedColor: ChartTheme.accentGold.withValues(alpha: 0.3),
                  checkmarkColor: ChartTheme.accentGold,
                  labelStyle: TextStyle(
                    color: selected ? ChartTheme.accentGold : ChartTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Text(l10n.chartPrevCloseLine, style: TextStyle(color: ChartTheme.textTertiary, fontSize: 11)),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(l10n.chartIndicatorYes, style: TextStyle(fontSize: 12)),
                  selected: showPrevCloseLine,
                  onSelected: onShowPrevCloseLineChanged != null ? (_) => onShowPrevCloseLineChanged!(true) : null,
                  selectedColor: ChartTheme.accentGold.withValues(alpha: 0.3),
                  checkmarkColor: ChartTheme.accentGold,
                  labelStyle: TextStyle(
                    color: showPrevCloseLine ? ChartTheme.accentGold : ChartTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(l10n.chartIndicatorNo, style: TextStyle(fontSize: 12)),
                  selected: !showPrevCloseLine,
                  onSelected: onShowPrevCloseLineChanged != null ? (_) => onShowPrevCloseLineChanged!(false) : null,
                  selectedColor: ChartTheme.accentGold.withValues(alpha: 0.3),
                  checkmarkColor: ChartTheme.accentGold,
                  labelStyle: TextStyle(
                    color: !showPrevCloseLine ? ChartTheme.accentGold : ChartTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(l10n.chartSubIndicator, style: TextStyle(color: ChartTheme.textTertiary, fontSize: 11)),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: items.where((e) => !e.isOverlay).map((e) {
            final selected = subChartIndicator == e.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(itemLabel(e.id, e.label), style: TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (_) => onSubChartChanged(e.id),
                selectedColor: ChartTheme.accentGold.withValues(alpha: 0.3),
                checkmarkColor: ChartTheme.accentGold,
                labelStyle: TextStyle(
                  color: selected ? ChartTheme.accentGold : ChartTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            );
          }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildValuesSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final closes = candles.map((c) => c.close).toList();
    final volumes = candles.map((c) => c.volume ?? 0).toList();
    final lastIdx = closes.length - 1;
    if (lastIdx < 0) return const SizedBox.shrink();

    final rows = <Widget>[];

    // 主图叠加数值
    if (overlayIndicator == 'none') {
      // 无主图叠加时不显示 MA/EMA 数值
    } else {
    final label = overlayIndicator == 'ema' ? 'EMA' : 'MA';
    const ma5Color = Color(0xFFF6C343);
    const ma10Color = Color(0xFF3B82F6);
    const ma20Color = Color(0xFF8B5CF6);
    if (overlayIndicator == 'ma') {
      final ma5List = ma(closes, 5);
      final ma10List = ma(closes, 10);
      final ma20List = ma(closes, 20);
      final v5 = lastIdx < ma5List.length ? ma5List[lastIdx] : null;
      final v10 = lastIdx < ma10List.length ? ma10List[lastIdx] : null;
      final v20 = lastIdx < ma20List.length ? ma20List[lastIdx] : null;
      rows.add(_valueRow('${label}5', v5, ma5Color));
      rows.add(_valueRow('${label}10', v10, ma10Color));
      rows.add(_valueRow('${label}20', v20, ma20Color));
    } else {
      final ema5List = ema(closes, 5);
      final ema10List = ema(closes, 10);
      final ema20List = ema(closes, 20);
      final v5 = lastIdx < ema5List.length ? ema5List[lastIdx] : null;
      final v10 = lastIdx < ema10List.length ? ema10List[lastIdx] : null;
      final v20 = lastIdx < ema20List.length ? ema20List[lastIdx] : null;
      rows.add(_valueRow('${label}5', v5, ma5Color));
      rows.add(_valueRow('${label}10', v10, ma10Color));
      rows.add(_valueRow('${label}20', v20, ma20Color));
    }
    }

    // 副图数值
    if (subChartIndicator == 'vol') {
      final vol = lastIdx < volumes.length ? volumes[lastIdx] : null;
      rows.add(_valueRow(l10n.chartVol, vol != null ? vol.toDouble() : null, ChartTheme.textPrimary));
    } else if (subChartIndicator == 'macd') {
      final macdRes = macd(closes);
      final dif = lastIdx < macdRes.macdLine.length ? macdRes.macdLine[lastIdx] : null;
      final dea = lastIdx < macdRes.signalLine.length ? macdRes.signalLine[lastIdx] : null;
      final hist = lastIdx < macdRes.histogram.length ? macdRes.histogram[lastIdx] : null;
      rows.add(_valueRow('DIF', dif, const Color(0xFF3B82F6)));
      rows.add(_valueRow('DEA', dea, const Color(0xFFF6C343)));
      rows.add(_valueRow('HIST', hist, (hist ?? -1) >= 0 ? ChartTheme.up : ChartTheme.down));
    } else if (subChartIndicator == 'rsi') {
      final rsiList = rsi(closes);
      final r = lastIdx < rsiList.length ? rsiList[lastIdx] : null;
      rows.add(_valueRow('RSI', r, _rsiColor(r)));
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ChartTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ChartTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.chartCurrentValue, style: TextStyle(color: ChartTheme.textTertiary, fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: rows,
          ),
        ],
      ),
    );
  }

  Widget _valueRow(String label, double? value, Color valueColor) {
    final str = value != null ? (value.abs() >= 1000 ? value.toStringAsFixed(0) : value.toStringAsFixed(2)) : '—';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: TextStyle(color: ChartTheme.textSecondary, fontSize: 12)),
        Text(
          str,
          style: TextStyle(color: valueColor, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: ChartTheme.fontMono),
        ),
      ],
    );
  }

  Color _rsiColor(double? r) {
    if (r == null) return ChartTheme.textSecondary;
    if (r >= 70) return ChartTheme.down;
    if (r <= 30) return ChartTheme.up;
    return ChartTheme.textPrimary;
  }
}
