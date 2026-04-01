import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'chart_theme.dart';

/// Price summary section shared by stock and crypto detail pages.
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
    this.openLabel,
    this.highLabel,
    this.lowLabel,
    this.prevCloseLabel,
    this.turnoverLabel,
    this.turnoverRateLabel,
    this.amplitudeLabel,
    this.hideNullMetrics = false,
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
  final String? openLabel;
  final String? highLabel;
  final String? lowLabel;
  final String? prevCloseLabel;
  final String? turnoverLabel;
  final String? turnoverRateLabel;
  final String? amplitudeLabel;
  final bool hideNullMetrics;

  String _formatLarge(BuildContext context, double v) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1)}B';
    if (v >= 100000000) {
      return isZh
          ? '${(v / 100000000).toStringAsFixed(2)}亿'
          : '${(v / 1000000).toStringAsFixed(1)}M';
    }
    if (v >= 10000) {
      return isZh
          ? '${(v / 10000).toStringAsFixed(2)}万'
          : '${(v / 1000).toStringAsFixed(1)}K';
    }
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final isUp = change != null && change! >= 0;
    final color = change != null
        ? (isUp ? ChartTheme.up : ChartTheme.down)
        : ChartTheme.textPrimary;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final metricWidth = compact
              ? (constraints.maxWidth - 10) / 2
              : (constraints.maxWidth - 30) / 4;
          final turnoverStr = turnover != null
              ? _formatLarge(context, turnover!)
              : (marketCap != null ? _formatLarge(context, marketCap!) : null);
          final metricItems = <(String, dynamic, bool?)>[
            (openLabel ?? l10n.chartPriceOpen, open, null),
            (highLabel ?? l10n.chartPriceHigh, high, true),
            (lowLabel ?? l10n.chartPriceLow, low, false),
            (prevCloseLabel ?? l10n.chartPricePrevClose, prevClose, null),
            (turnoverLabel ?? l10n.chartPriceTotalTurnover, turnoverStr, null),
            (
              turnoverRateLabel ?? l10n.chartPriceTurnoverRate,
              turnoverRate != null ? '${turnoverRate!.toStringAsFixed(1)}%' : null,
              null,
            ),
            (
              amplitudeLabel ?? l10n.chartPriceAmplitude,
              amplitude != null ? '${amplitude!.toStringAsFixed(1)}%' : null,
              null,
            ),
          ].where((item) => !hideNullMetrics || item.$2 != null).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            currentPrice != null
                                ? ChartTheme.formatPrice(currentPrice!)
                                : '—',
                            style: TextStyle(
                              color: color,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              fontFamily: ChartTheme.fontMono,
                              fontFeatures: const [ChartTheme.tabularFigures],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (change != null || changePercent != null) ...[
                          const SizedBox(width: 10),
                          Icon(
                            change != null && change! < 0
                                ? Icons.south_east_rounded
                                : Icons.north_east_rounded,
                            color: color,
                            size: 18,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              '${change != null ? (change! >= 0 ? '+' : '') + ChartTheme.formatPrice(change!) : ''} '
                              '${changePercent != null ? '(${(changePercent! >= 0 ? '+' : '') + changePercent!.toStringAsFixed(2)}%)' : ''}',
                              style: TextStyle(
                                color: color,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                fontFamily: ChartTheme.fontMono,
                                fontFeatures: const [ChartTheme.tabularFigures],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: metricItems.map((item) {
                  return SizedBox(
                    width: metricWidth.clamp(140.0, 220.0),
                    child: _metricCard(
                      item.$1,
                      item.$2,
                      isUp: item.$3,
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _metricCard(String label, dynamic value, {bool? isUp}) {
    final str = value is double
        ? ChartTheme.formatPrice(value)
        : (value is String ? value : '—');
    final valueColor = value == null || value == '—'
        ? ChartTheme.textSecondary
        : (isUp == true
            ? ChartTheme.up
            : isUp == false
                ? ChartTheme.down
                : ChartTheme.textPrimary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ChartTheme.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ChartTheme.border.withValues(alpha: 0.9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: ChartTheme.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            str,
            style: TextStyle(
              color: valueColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: ChartTheme.fontMono,
              fontFeatures: const [ChartTheme.tabularFigures],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
