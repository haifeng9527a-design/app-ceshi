import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// 指标区（仅 K 线模式）：MA/EMA + VOL/MACD/RSI 切换，卡片样式
class IndicatorsPanel extends StatelessWidget {
  const IndicatorsPanel({
    super.key,
    required this.overlayIndicator,
    required this.subChartIndicator,
    required this.onOverlayChanged,
    required this.onSubChartChanged,
  });

  final String overlayIndicator;
  final String subChartIndicator;
  final ValueChanged<String> onOverlayChanged;
  final ValueChanged<String> onSubChartChanged;

  static const List<({String label, String id, bool isOverlay})> items = [
    (label: 'MA', id: 'ma', isOverlay: true),
    (label: 'EMA', id: 'ema', isOverlay: true),
    (label: 'VOL', id: 'vol', isOverlay: false),
    (label: 'MACD', id: 'macd', isOverlay: false),
    (label: 'RSI', id: 'rsi', isOverlay: false),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: ChartTheme.cardBackground,
        borderRadius: BorderRadius.circular(ChartTheme.radiusCard),
        border: Border.all(color: ChartTheme.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: items.map((e) {
            final selected = e.isOverlay
                ? overlayIndicator == e.id
                : subChartIndicator == e.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(e.label),
                selected: selected,
                onSelected: (_) {
                  if (e.isOverlay) {
                    onOverlayChanged(e.id);
                  } else {
                    onSubChartChanged(e.id);
                  }
                },
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
    );
  }
}
