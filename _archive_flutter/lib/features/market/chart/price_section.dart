import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'chart_theme.dart';

class PriceSection extends StatelessWidget {
  const PriceSection({
    super.key,
    required this.currentPrice,
    this.change,
    this.changePercent,
    this.prevClose,
    this.open,
    this.high,
    this.low,
    this.turnover,
    this.marketCap,
    this.turnoverRate,
    this.amplitude,
  });

  final double? currentPrice;
  final double? change;
  final double? changePercent;
  final double? prevClose;
  final double? open;
  final double? high;
  final double? low;
  final double? turnover;
  final double? marketCap;
  final double? turnoverRate;
  final double? amplitude;

  String _formatLarge(BuildContext context, double v) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(2)}B';
    if (v >= 100000000) {
      return isZh ? '${(v / 100000000).toStringAsFixed(2)}亿' : '${(v / 1000000).toStringAsFixed(1)}M';
    }
    if (v >= 10000) {
      return isZh ? '${(v / 10000).toStringAsFixed(2)}万' : '${(v / 1000).toStringAsFixed(1)}K';
    }
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isUp = change == null || change! >= 0;
    final tone = isUp ? ChartTheme.up : ChartTheme.down;
    final statCards = [
      _MetricData(l10n.chartPriceOpen, _formatPrice(open), tone: null),
      _MetricData(l10n.chartPriceHigh, _formatPrice(high), tone: ChartTheme.up),
      _MetricData(l10n.chartPriceLow, _formatPrice(low), tone: ChartTheme.down),
      _MetricData(l10n.chartPricePrevClose, _formatPrice(prevClose), tone: null),
      _MetricData(
        l10n.chartPriceTotalTurnover,
        turnover != null
            ? _formatLarge(context, turnover!)
            : (marketCap != null ? _formatLarge(context, marketCap!) : '—'),
        tone: null,
      ),
      _MetricData(
        l10n.chartPriceTurnoverRate,
        turnoverRate != null ? '${turnoverRate!.toStringAsFixed(2)}%' : '—',
        tone: null,
      ),
      _MetricData(
        l10n.chartPriceAmplitude,
        amplitude != null ? '${amplitude!.toStringAsFixed(2)}%' : '—',
        tone: null,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: ChartTheme.cardBackground,
          borderRadius: BorderRadius.circular(ChartTheme.radiusCard),
          border: Border.all(color: ChartTheme.border),
          boxShadow: ChartTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last Price',
                        style: TextStyle(
                          color: ChartTheme.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currentPrice != null
                            ? ChartTheme.formatPrice(currentPrice!)
                            : '—',
                        style: TextStyle(
                          color: tone,
                          fontSize: 40,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          fontFamily: ChartTheme.fontMono,
                          fontFeatures: const [ChartTheme.tabularFigures],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: tone.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          '${_signedValue(change)}  ${_signedPercent(changePercent)}',
                          style: TextStyle(
                            color: tone,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFamily: ChartTheme.fontMono,
                            fontFeatures: const [ChartTheme.tabularFigures],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: ChartTheme.surface2,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Key Range',
                          style: TextStyle(
                            color: ChartTheme.textTertiary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _sideMetric(
                          label: l10n.chartPriceHigh,
                          value: _formatPrice(high),
                          color: ChartTheme.up,
                        ),
                        const SizedBox(height: 10),
                        _sideMetric(
                          label: l10n.chartPriceLow,
                          value: _formatPrice(low),
                          color: ChartTheme.down,
                        ),
                        const SizedBox(height: 10),
                        _sideMetric(
                          label: l10n.chartPricePrevClose,
                          value: _formatPrice(prevClose),
                          color: ChartTheme.textPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width > 1100 ? 7 : width > 760 ? 4 : 2;
                final itemWidth =
                    ((width - (columns - 1) * 10) / columns).clamp(130.0, 240.0);
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: statCards
                      .map(
                        (item) => SizedBox(
                          width: itemWidth,
                          child: _metricCard(item),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: ChartTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: ChartTheme.fontMono,
            fontFeatures: const [ChartTheme.tabularFigures],
          ),
        ),
      ],
    );
  }

  Widget _metricCard(_MetricData item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ChartTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: const TextStyle(
              color: ChartTheme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: item.tone ?? ChartTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: const [ChartTheme.tabularFigures],
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(double? value) =>
      value != null && value > 0 ? ChartTheme.formatPrice(value) : '—';

  String _signedValue(double? value) {
    if (value == null) return '—';
    return '${value >= 0 ? '+' : ''}${ChartTheme.formatPrice(value)}';
  }

  String _signedPercent(double? value) {
    if (value == null) return '—';
    return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%';
  }
}

class _MetricData {
  const _MetricData(this.label, this.value, {this.tone});

  final String label;
  final String value;
  final Color? tone;
}
