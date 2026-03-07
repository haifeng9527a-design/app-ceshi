import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../trading/polygon_repository.dart';
import 'chart_theme.dart';

/// 分时图：绿色折线 + 半透明面积填充，左侧价格、右侧百分比，底部时间轴 + 成交量柱（15-20% 高度）
/// 非 1D 时：X 轴固定为当日交易时段(9:30-16:00)，数据只画到当前时间，右侧留空，便于看出开盘多久、距收盘多久
class IntradayChart extends StatelessWidget {
  const IntradayChart({
    super.key,
    required this.candles,
    this.prevClose,
    this.currentPrice,
    required this.chartHeight,
    this.timeAxisHeight = 22,
    this.volumeHeight = 0,
    this.periodLabel = '5m',
    this.capitalFlowText,
    this.useSessionMarketHours = false,
  });

  final List<ChartCandle> candles;
  final double? prevClose;
  final double? currentPrice;
  final double chartHeight;
  final double timeAxisHeight;
  /// 若 >0 则底部绘制成交量柱
  final double volumeHeight;
  final String periodLabel;
  /// 仅美股分时启用 9:30-16:00 交易时段裁剪；加密/外汇应关闭（24x7）。
  final bool useSessionMarketHours;
  /// 主力流入等资金流向文案，如 "主力流入 -1.1亿"
  final String? capitalFlowText;

  static const double _candleWidth = 8.0;
  /// 会话模式下图表最小宽度（当可用宽度很小时保底）
  static const double _sessionChartMinWidth = 280.0;

  /// 美股常规交易时段 9:30-16:00 ET，按 EST 转为 UTC：9:30 ET = 14:30 UTC, 16:00 ET = 21:00 UTC
  static ({double startSec, double endSec})? _sessionBoundsForDay(double lastCandleTimeSec) {
    final ms = (lastCandleTimeSec * 1000).toInt();
    final utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    const estOffsetSec = 5 * 3600;
    final etMs = ms - estOffsetSec * 1000;
    final et = DateTime.fromMillisecondsSinceEpoch(etMs, isUtc: true);
    final sessionStart = DateTime.utc(et.year, et.month, et.day, 14, 30);
    final sessionEnd = DateTime.utc(et.year, et.month, et.day, 21, 0);
    final startSec = sessionStart.millisecondsSinceEpoch / 1000.0;
    final endSec = sessionEnd.millisecondsSinceEpoch / 1000.0;
    return (startSec: startSec, endSec: endSec);
  }

  String _volumeLabel(List<ChartCandle> candles) {
    final total = candles.fold<int>(0, (s, c) => s + (c.volume ?? 0));
    if (total <= 0) return 'VOL 0';
    if (total >= 10000) return 'VOL ${(total / 10000).toStringAsFixed(2)}万';
    return 'VOL $total';
  }

  String _formatTime(double timeSec) {
    final d = DateTime.fromMillisecondsSinceEpoch((timeSec * 1000).toInt());
    if (periodLabel == '1D') {
      return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    }
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// 时间轴刻度：按真实时间整点/半点取点，映射到最近 K 线索引，首格显示日期其余 HH:mm
  List<({int index, String label})> _buildTimeAxisTicks() {
    if (candles.isEmpty) return [];
    final t0 = candles.first.time;
    final t1 = candles.last.time;
    if (periodLabel == '1D') {
      final indices = <int>[0];
      final step = (candles.length - 1) / 4;
      for (var i = 1; i <= 4; i++) {
        indices.add((i * step).floor().clamp(0, candles.length - 1));
      }
      final seen = <int>{};
      return indices.where((i) => seen.add(i)).map((i) {
        final d = DateTime.fromMillisecondsSinceEpoch((candles[i].time * 1000).toInt());
        final label = i == 0 ? '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}' : _formatTime(candles[i].time);
        return (index: i, label: label);
      }).toList();
    }
    const halfHour = 30 * 60;
    final t0Round = ((t0 / halfHour).floor() * halfHour).toInt();
    final t1Sec = t1.round();
    final targets = <int>[];
    for (var t = t0Round; t <= t1Sec + halfHour; t += halfHour) {
      if (t >= t0 - 60) targets.add(t);
    }
    if (targets.isEmpty) {
      targets.add(t0.round());
      if (t1Sec != t0.round()) targets.add(t1Sec);
    }
    final n = candles.length;
    final result = <({int index, String label})>[];
    int? lastIndex;
    int? lastDay;
    for (final targetSec in targets) {
      var best = 0;
      var bestDiff = (candles[0].time - targetSec).abs();
      for (var i = 1; i < n; i++) {
        final d = (candles[i].time - targetSec).abs();
        if (d < bestDiff) {
          bestDiff = d;
          best = i;
        }
      }
      if (lastIndex != null && best == lastIndex) continue;
      lastIndex = best;
      final d = DateTime.fromMillisecondsSinceEpoch((candles[best].time * 1000).toInt());
      final day = d.day;
      final label = result.isEmpty
          ? '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}'
          : (lastDay != null && day != lastDay ? '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}\n${_formatTime(candles[best].time)}' : _formatTime(candles[best].time));
      lastDay = day;
      result.add((index: best, label: label));
    }
    if (result.isEmpty) {
      result.add((index: 0, label: _formatTime(t0)));
      if (n > 1) result.add((index: n - 1, label: _formatTime(t1)));
    }
    // 最多保留 7 个刻度，避免重叠
    const maxTicks = 7;
    if (result.length > maxTicks) {
      final step = (result.length - 1) / (maxTicks - 1);
      final kept = <({int index, String label})>[];
      final seen = <int>{};
      for (var i = 0; i < maxTicks; i++) {
        final idx = (i * step).round().clamp(0, result.length - 1);
        if (seen.add(idx)) kept.add(result[idx]);
      }
      if (kept.isEmpty) return result;
      return kept;
    }
    return result;
  }

  /// UTC 日历日唯一标识（同一天相同）
  static int _utcDayKey(double timeSec) =>
      (timeSec * 1000).toInt() ~/ (24 * 3600 * 1000);

  /// 多日分时：按“日”分段的边界索引（每个新交易日第一个 K 的索引）及对应日期标签，用于画分隔虚线和时间轴
  static List<({int index, String label})> _multiDayBoundaryTicks(List<ChartCandle> plotCandles) {
    if (plotCandles.isEmpty) return [];
    final ticks = <({int index, String label})>[];
    int? prevKey;
    for (var i = 0; i < plotCandles.length; i++) {
      final key = _utcDayKey(plotCandles[i].time);
      if (prevKey == null || key != prevKey) {
        prevKey = key;
        final d = DateTime.fromMillisecondsSinceEpoch((plotCandles[i].time * 1000).toInt(), isUtc: true);
        ticks.add((index: i, label: '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}'));
      }
    }
    return ticks;
  }

  /// 多日分时：需要画虚线的日边界索引（不含首日 0，避免左侧重复线）
  static List<int> _multiDayBoundaryIndices(List<ChartCandle> plotCandles) {
    if (plotCandles.length < 2) return [];
    final indices = <int>[];
    int? prevKey;
    for (var i = 0; i < plotCandles.length; i++) {
      final key = _utcDayKey(plotCandles[i].time);
      if (prevKey != null && key != prevKey) indices.add(i);
      prevKey = key;
    }
    return indices;
  }

  /// 多日分时：每日的 [startIndex, endIndex]（用于按天平均分配宽度）
  static List<({int start, int end})> _multiDayDayRanges(List<ChartCandle> plotCandles) {
    if (plotCandles.isEmpty) return [];
    final ranges = <({int start, int end})>[];
    int start = 0;
    int? prevKey;
    for (var i = 0; i < plotCandles.length; i++) {
      final key = _utcDayKey(plotCandles[i].time);
      if (prevKey != null && key != prevKey) {
        ranges.add((start: start, end: i - 1));
        start = i;
      }
      prevKey = key;
    }
    ranges.add((start: start, end: plotCandles.length - 1));
    return ranges;
  }

  /// 固定时间轴刻度（与第二张参考图一致）：MM/dd、09:30、10:30、11:30、13:00、14:00、15:00、16:00，位于成交量图底部同一水平、居中
  List<({double xFraction, String label})> _buildSessionTimeAxisTicks(double sessionStartSec, double sessionEndSec, double dataEndX) {
    const estOffset = Duration(hours: 5);
    final startUtc = DateTime.fromMillisecondsSinceEpoch((sessionStartSec * 1000).toInt(), isUtc: true);
    final et = startUtc.subtract(estOffset);
    final dateLabel = '${et.month.toString().padLeft(2, '0')}/${et.day.toString().padLeft(2, '0')}';
    const timeLabels = ['09:30', '10:30', '11:30', '13:00', '14:00', '15:00', '16:00'];
    return [
      (xFraction: 0.0, label: dateLabel),
      ...timeLabels.asMap().entries.map((e) => (xFraction: (e.key + 1) / 7, label: e.value)),
    ];
  }

  /// 紧凑模式时间轴：按实际数据时间范围，首尾各一个刻度 + 中间均匀分布
  List<({double xFraction, String label})> _buildCompactSessionTimeAxisTicks(double dataStartSec, double dataEndSec) {
    final d0 = DateTime.fromMillisecondsSinceEpoch((dataStartSec * 1000).toInt());
    final d1 = DateTime.fromMillisecondsSinceEpoch((dataEndSec * 1000).toInt());
    if (d0.day != d1.day) {
      return [
        (xFraction: 0.0, label: '${d0.month.toString().padLeft(2, '0')}/${d0.day.toString().padLeft(2, '0')} ${d0.hour.toString().padLeft(2, '0')}:${d0.minute.toString().padLeft(2, '0')}'),
        (xFraction: 0.5, label: '${d1.month.toString().padLeft(2, '0')}/${d1.day.toString().padLeft(2, '0')}'),
        (xFraction: 1.0, label: '${d1.hour.toString().padLeft(2, '0')}:${d1.minute.toString().padLeft(2, '0')}'),
      ];
    }
    String fmt(double sec) {
      final d = DateTime.fromMillisecondsSinceEpoch((sec * 1000).round());
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return [
      (xFraction: 0.0, label: '${d0.month.toString().padLeft(2, '0')}/${d0.day.toString().padLeft(2, '0')} ${d0.hour.toString().padLeft(2, '0')}:${d0.minute.toString().padLeft(2, '0')}'),
      (xFraction: 0.25, label: fmt(dataStartSec + (dataEndSec - dataStartSec) * 0.25)),
      (xFraction: 0.5, label: fmt(dataStartSec + (dataEndSec - dataStartSec) * 0.5)),
      (xFraction: 0.75, label: fmt(dataStartSec + (dataEndSec - dataStartSec) * 0.75)),
      (xFraction: 1.0, label: '${d1.hour.toString().padLeft(2, '0')}:${d1.minute.toString().padLeft(2, '0')}'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context)!.chartNoIntradayData, style: TextStyle(color: ChartTheme.textSecondary)));
    }
    final axisStyle = TextStyle(color: ChartTheme.textSecondary, fontSize: ChartTheme.fontSizeAxis, fontFamily: ChartTheme.fontMono);
    final basePrice = prevClose ?? candles.first.open;

    // 1m/5m/15m/30m 按“当日交易时段”展示（9:30-16:00），右侧预留空白；2d/3d/4d 为多日连续分时
    bool useSessionMode =
        useSessionMarketHours && ['1m', '5m', '15m', '30m'].contains(periodLabel);
    double sessionStartSec = 0, sessionEndSec = 0, sessionLen = 0, dataEndX = 1.0;
    List<ChartCandle> plotCandles = candles;
    if (useSessionMode && candles.isNotEmpty) {
      final bounds = _sessionBoundsForDay(candles.last.time);
      if (bounds != null) {
        sessionStartSec = bounds.startSec;
        sessionEndSec = bounds.endSec;
        sessionLen = (sessionEndSec - sessionStartSec).clamp(1.0, double.infinity);
        plotCandles = candles.where((c) => c.time >= sessionStartSec && c.time <= sessionEndSec).toList();
        if (plotCandles.isEmpty) plotCandles = candles;
      } else {
        useSessionMode = false;
      }
    }

    final closes = plotCandles.map((c) => c.close).toList();
    double minY = closes.reduce((a, b) => a < b ? a : b);
    double maxY = closes.reduce((a, b) => a > b ? a : b);
    if (currentPrice != null) {
      if (currentPrice! < minY) minY = currentPrice!;
      if (currentPrice! > maxY) maxY = currentPrice!;
    }
    // 异常值处理：若极值（如 API 错误数据、0 等）导致 Y 轴范围过大，会压缩正常波动呈「垂直暴跌」状
    // 用 2%/98% 分位数限制范围，并过滤绘制用的价格，避免异常点拉出垂直线
    List<double> plotCloses = closes;
    double yFloor = minY;
    double yCeil = maxY;
    if (closes.length >= 10 && basePrice > 0) {
      final sorted = List<double>.from(closes)..sort();
      final p2 = sorted[(closes.length * 0.02).floor().clamp(0, closes.length - 1)];
      final p98 = sorted[(closes.length * 0.98).floor().clamp(0, closes.length - 1)];
      final midRange = (p98 - p2).clamp(0.001 * basePrice, double.infinity);
      yFloor = p2 - midRange * 0.2;
      yCeil = p98 + midRange * 0.2;
      // 限制 Y 轴范围
      if (minY < yFloor) minY = yFloor;
      if (maxY > yCeil) maxY = yCeil;
      // 过滤绘制：异常点用前一点替代，避免折线出现垂直暴跌
      plotCloses = <double>[];
      for (var i = 0; i < closes.length; i++) {
        final v = closes[i];
        final prev = i > 0 ? plotCloses[i - 1] : v;
        plotCloses.add((v < yFloor || v > yCeil) ? prev : v);
      }
    }
    final range = (maxY - minY).clamp(0.01, double.infinity);
    final minYPlot = minY - range * 0.05;
    final maxYPlot = maxY + range * 0.05;

    final dayRanges = (!useSessionMode && plotCandles.length > 1)
        ? _multiDayDayRanges(plotCandles)
        : <({int start, int end})>[];
    final useEqualDayWidth = dayRanges.length > 1;
    final dayCount = dayRanges.length;

    final spots = <FlSpot>[];
    List<double>? spotXFractionsComputed;
    double maxXComputed = 0;

    if (useSessionMode && sessionLen > 0 && plotCandles.isNotEmpty) {
      // 按会话时间(9:30-16:00)映射 X，数据只占 0～dataEndX，右侧预留空白（与主流看盘软件一致）
      final lastTime = plotCandles.last.time;
      dataEndX = ((lastTime - sessionStartSec) / sessionLen).clamp(0.0, 1.0);
      for (var i = 0; i < plotCandles.length; i++) {
        final c = plotCandles[i];
        final x = ((c.time - sessionStartSec) / sessionLen).clamp(0.0, 1.0);
        spots.add(FlSpot(x, plotCloses[i]));
      }
      if (currentPrice != null) {
        final cp = currentPrice!;
        final lastPlot = plotCloses.isNotEmpty ? plotCloses.last : cp;
        final sanePrice = (plotCloses.length >= 10 && basePrice > 0)
            ? (cp < yFloor || cp > yCeil ? lastPlot : cp)
            : cp;
        spots.add(FlSpot(dataEndX.clamp(0.0, 1.0), sanePrice));
      }
      maxXComputed = 1.0;
      spotXFractionsComputed = plotCandles.map((c) => ((c.time - sessionStartSec) / sessionLen).clamp(0.0, 1.0)).toList();
    } else if (useEqualDayWidth) {
      for (var i = 0; i < plotCandles.length; i++) {
        var d = 0;
        for (; d < dayRanges.length; d++) {
          if (i >= dayRanges[d].start && i <= dayRanges[d].end) break;
        }
        if (d >= dayRanges.length) d = dayRanges.length - 1;
        final start = dayRanges[d].start;
        final end = dayRanges[d].end;
        final count = (end - start + 1).clamp(1, 0x7fffffff);
        final localJ = (i - start).toDouble();
        final x = (d + localJ / count) / dayCount;
        spots.add(FlSpot(x, plotCloses[i]));
      }
      if (currentPrice != null) {
        final cp = currentPrice!;
        final lastPlot = plotCloses.isNotEmpty ? plotCloses.last : cp;
        final sanePrice = (plotCloses.length >= 10 && basePrice > 0)
            ? (cp < yFloor || cp > yCeil ? lastPlot : cp)
            : cp;
        spots.add(FlSpot(1.0, sanePrice));
      }
      maxXComputed = 1.0;
      spotXFractionsComputed = <double>[];
      for (var i = 0; i < plotCandles.length; i++) {
        var d = 0;
        for (; d < dayRanges.length; d++) {
          if (i >= dayRanges[d].start && i <= dayRanges[d].end) break;
        }
        if (d >= dayRanges.length) d = dayRanges.length - 1;
        final start = dayRanges[d].start;
        final end = dayRanges[d].end;
        final count = (end - start + 1).clamp(1, 0x7fffffff);
        final localJ = (i - start).toDouble();
        spotXFractionsComputed.add((d + localJ / count) / dayCount);
      }
    } else {
      for (var i = 0; i < plotCandles.length; i++) {
        spots.add(FlSpot(i.toDouble(), plotCloses[i]));
      }
      if (currentPrice != null) {
        final cp = currentPrice!;
        final lastPlot = plotCloses.isNotEmpty ? plotCloses.last : cp;
        final sanePrice = (plotCloses.length >= 10 && basePrice > 0)
            ? (cp < yFloor || cp > yCeil ? lastPlot : cp)
            : cp;
        spots.add(FlSpot(
            plotCandles.isEmpty ? 0.0 : (plotCandles.length - 1).toDouble() + 1,
            sanePrice));
      }
      maxXComputed = (spots.length <= 1 ? 1.0 : (plotCandles.length - 1).toDouble());
    }
    if (spots.isEmpty) return const SizedBox.shrink();

    final List<double>? spotXFractions = (useSessionMode && sessionLen > 0 && plotCandles.isNotEmpty) || useEqualDayWidth
        ? spotXFractionsComputed
        : null;

    final lastClose = plotCandles.isNotEmpty ? plotCandles.last.close : currentPrice;
    final firstOpen = plotCandles.isNotEmpty ? plotCandles.first.open : currentPrice;
    final maxX = useSessionMode ? 1.0 : maxXComputed;

    // 均价线（橙色）：VWAP 或简单均线
    final avgSpots = <FlSpot>[];
    if (plotCandles.isNotEmpty) {
      var sumV = 0.0;
      var sumVw = 0.0;
      for (var i = 0; i < plotCandles.length; i++) {
        final c = plotCandles[i];
        final v = (c.volume ?? 0).toDouble();
        sumV += v;
        sumVw += c.close * v;
        final avg = sumV > 0 ? sumVw / sumV : (sumVw / (i + 1));
        double x;
        if (useSessionMode && plotCandles.isNotEmpty && sessionLen > 0) {
          x = ((c.time - sessionStartSec) / sessionLen).clamp(0.0, 1.0);
        } else if (useEqualDayWidth) {
          var d = 0;
          for (; d < dayRanges.length; d++) {
            if (i >= dayRanges[d].start && i <= dayRanges[d].end) break;
          }
          if (d >= dayRanges.length) d = dayRanges.length - 1;
          final start = dayRanges[d].start;
          final end = dayRanges[d].end;
          final count = (end - start + 1).clamp(1, 0x7fffffff);
          x = (d + (i - start) / count) / dayCount;
        } else {
          x = i.toDouble();
        }
        avgSpots.add(FlSpot(x, avg));
      }
    }

    final totalBottom = timeAxisHeight + (volumeHeight > 0 ? volumeHeight : 0);
    const tickCount = 5;
    final yTicks = List.generate(tickCount, (i) => maxYPlot - (maxYPlot - minYPlot) * i / (tickCount - 1));
    int? highlightTickIndex;
    if (currentPrice != null && basePrice > 0) {
      var best = 0;
      var bestDiff = (yTicks[0] - currentPrice!).abs();
      for (var i = 1; i < tickCount; i++) {
        final d = (yTicks[i] - currentPrice!).abs();
        if (d < bestDiff) {
          bestDiff = d;
          best = i;
        }
      }
      highlightTickIndex = best;
    }

    final multiDayTicks = (!useSessionMode && plotCandles.length > 1)
        ? _multiDayBoundaryTicks(plotCandles)
        : <({int index, String label})>[];
    final dayBoundaryIndices = (!useSessionMode && plotCandles.length > 1 && !useEqualDayWidth)
        ? _multiDayBoundaryIndices(plotCandles)
        : <int>[];
    // 按天平均分配时：分隔线在 x = 1/N, 2/N, ...；时间轴刻度在 0, 1/N, 2/N, ...
    final dayBoundaryXFractions = useEqualDayWidth && dayCount > 1
        ? List.generate(dayCount - 1, (i) => (i + 1) / dayCount)
        : <double>[];
    final multiDayTickFractions = useEqualDayWidth && multiDayTicks.length == dayCount
        ? List.generate(dayCount, (d) => (xFraction: d / dayCount, label: multiDayTicks[d].label))
        : <({double xFraction, String label})>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        // 铺满屏：与 1 天一致，2天/3天/4天 也用可用宽度铺满，不再按根数算窄条
        const rightAxisWidth = 38.0;
        final availableWidth = (constraints.maxWidth - 4 - 2 - rightAxisWidth).clamp(_sessionChartMinWidth, double.infinity);
        final contentWidth = availableWidth;
        // 限制总高度不超过可用空间，避免 BOTTOM OVERFLOWED
        const volumeOverhead = 4.0;
        final maxTotalH = (constraints.maxHeight - 60).clamp(100.0, double.infinity);
        final totalNeeded = chartHeight + totalBottom;
        final scale = totalNeeded > 0 && maxTotalH < totalNeeded ? maxTotalH / totalNeeded : 1.0;
        final effectiveChartH = (chartHeight * scale).clamp(80.0, double.infinity);
        final effectiveTimeH = (timeAxisHeight * scale).clamp(18.0, double.infinity);
        final effectiveVolH = volumeHeight > 0 ? (volumeHeight * scale).clamp(24.0, double.infinity) : 0.0;
        final effectiveTotalBottom = effectiveTimeH + effectiveVolH + (effectiveVolH > 0 ? volumeOverhead : 0);

        return _buildChartContent(
          useSessionMode: useSessionMode,
          sessionStartSec: sessionStartSec,
          sessionEndSec: sessionEndSec,
          sessionLen: sessionLen,
          dataEndX: dataEndX,
          plotCandles: plotCandles,
          spotXFractions: spotXFractions,
          spots: spots,
          avgSpots: avgSpots,
          lineColor: (lastClose ?? firstOpen ?? 0) >= (firstOpen ?? lastClose ?? 0) ? ChartTheme.up : ChartTheme.down,
          maxX: maxX,
          contentWidth: contentWidth,
          minYPlot: minYPlot,
          maxYPlot: maxYPlot,
          yTicks: yTicks,
          highlightTickIndex: highlightTickIndex,
          basePrice: basePrice,
          axisStyle: axisStyle,
          chartHeight: effectiveChartH,
          timeAxisHeight: effectiveTimeH,
          volumeHeight: effectiveVolH,
          totalBottom: effectiveTotalBottom,
          rightAxisWidth: rightAxisWidth,
          multiDayTicks: multiDayTicks,
          dayBoundaryIndices: dayBoundaryIndices,
          dayBoundaryXFractions: dayBoundaryXFractions,
          multiDayTickFractions: multiDayTickFractions,
        );
      },
    );
  }

  Widget _buildChartContent({
    required bool useSessionMode,
    required double sessionStartSec,
    required double sessionEndSec,
    required double sessionLen,
    required double dataEndX,
    required List<ChartCandle> plotCandles,
    required List<double>? spotXFractions,
    required List<FlSpot> spots,
    required List<FlSpot> avgSpots,
    required Color lineColor,
    required double maxX,
    required double contentWidth,
    required double minYPlot,
    required double maxYPlot,
    required List<double> yTicks,
    required int? highlightTickIndex,
    required double basePrice,
    required TextStyle axisStyle,
    required double chartHeight,
    required double timeAxisHeight,
    required double volumeHeight,
    required double totalBottom,
    double rightAxisWidth = 56.0,
    List<({int index, String label})> multiDayTicks = const [],
    List<int> dayBoundaryIndices = const [],
    List<double> dayBoundaryXFractions = const [],
    List<({double xFraction, String label})> multiDayTickFractions = const [],
  }) {
    const tickCount = 5;
    const labelHeight = 20.0;
    final rangeY = (maxYPlot - minYPlot).clamp(0.001, double.infinity);
    double yToTop(double value) => ((maxYPlot - value) / rangeY * chartHeight).clamp(0.0, chartHeight);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: SizedBox(
                width: contentWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (dayBoundaryXFractions.isNotEmpty || dayBoundaryIndices.isNotEmpty)
                      Positioned(
                        left: 0,
                        top: 0,
                        width: contentWidth,
                        height: chartHeight + totalBottom,
                        child: CustomPaint(
                          painter: _DaySeparatorLinePainter(
                            boundaryIndices: dayBoundaryIndices,
                            maxIndex: (plotCandles.length - 1).clamp(1, 0x7fffffff),
                            boundaryXFractions: dayBoundaryXFractions,
                            contentWidth: contentWidth,
                            totalHeight: chartHeight + totalBottom,
                          ),
                        ),
                      ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: chartHeight,
                          width: contentWidth,
                          child: Stack(
                            children: [
                              LineChart(
                            LineChartData(
                              minX: 0,
                              maxX: useSessionMode ? 1.0 : maxX,
                              minY: minYPlot,
                              maxY: maxYPlot,
                              lineBarsData: [
                                LineChartBarData(
                                  spots: spots,
                                  isCurved: false,
                                  color: lineColor,
                                  barWidth: 2.2,
                                  dotData: FlDotData(
                                    show: true,
                                    checkToShowDot: (FlSpot spot, LineChartBarData barData) {
                                      if (barData.spots.isEmpty) return false;
                                      return spot == barData.spots.last;
                                    },
                                    getDotPainter: (FlSpot spot, double percent, LineChartBarData barData, int index) =>
                                        FlDotCirclePainter(
                                          color: lineColor,
                                          radius: 4,
                                          strokeWidth: 1.5,
                                          strokeColor: ChartTheme.background,
                                        ),
                                  ),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    gradient: LinearGradient(
                                      colors: lineColor == ChartTheme.down
                                          ? [
                                              ChartTheme.down.withValues(alpha: 0.35),
                                              ChartTheme.down.withValues(alpha: 0.05),
                                            ]
                                          : [
                                              ChartTheme.up.withValues(alpha: 0.25),
                                              ChartTheme.up.withValues(alpha: 0.04),
                                            ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                ),
                                if (avgSpots.length > 1)
                                  LineChartBarData(
                                    spots: avgSpots,
                                    isCurved: false,
                                    color: ChartTheme.avgLine,
                                    barWidth: 1.8,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(show: false),
                                  ),
                              ],
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: (maxYPlot - minYPlot) / 4,
                                getDrawingHorizontalLine: (_) => const FlLine(color: ChartTheme.gridLine, strokeWidth: 1),
                              ),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                            ),
                            duration: const Duration(milliseconds: 150),
                          ),
                          if (currentPrice != null && currentPrice! >= minYPlot && currentPrice! <= maxYPlot)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _CurrentPriceLinePainter(
                                  value: currentPrice!,
                                  minY: minYPlot,
                                  maxY: maxYPlot,
                                  color: lineColor,
                                ),
                              ),
                            ),
                          if (useSessionMode && dataEndX > 0 && dataEndX <= 1)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _CurrentTimeLinePainter(
                                  dataEndX: dataEndX,
                                  color: ChartTheme.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (volumeHeight > 0 && plotCandles.any((c) => (c.volume ?? 0) > 0)) ...[
                      Container(height: 1, width: contentWidth, color: ChartTheme.chartDivider),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                        child: Text(
                          _volumeLabel(plotCandles),
                          style: axisStyle.copyWith(fontSize: 11, color: ChartTheme.textTertiary),
                        ),
                      ),
                      SizedBox(
                        height: volumeHeight - 14,
                        width: contentWidth,
                        child: CustomPaint(
                          size: Size(contentWidth, volumeHeight - 14),
                          painter: _VolumeBarPainter(
                            candles: plotCandles,
                            spotXFractions: spotXFractions,
                            sessionStartSec: useSessionMode ? sessionStartSec : null,
                            sessionEndSec: useSessionMode ? sessionEndSec : null,
                            dataEndX: useSessionMode ? dataEndX : null,
                          ),
                        ),
                      ),
                      if (capitalFlowText != null && capitalFlowText!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
                          child: Text(
                            capitalFlowText!,
                            style: axisStyle.copyWith(fontSize: 9, color: ChartTheme.down),
                          ),
                        ),
                    ],
                    SizedBox(
                      height: timeAxisHeight,
                      width: contentWidth,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (useSessionMode && sessionLen > 0 && plotCandles.isNotEmpty) {
                            // 固定会话刻度：MM/dd、09:30、10:30、11:30、13:00、14:00、15:00、16:00，右侧预留空白
                            final ticks = _buildSessionTimeAxisTicks(sessionStartSec, sessionEndSec, dataEndX);
                            if (ticks.isEmpty) return const SizedBox.shrink();
                            const labelW = 56.0;
                            return Stack(
                              clipBehavior: Clip.none,
                              children: ticks.map((t) {
                                final x = (t.xFraction * contentWidth).clamp(0.0, contentWidth - 1);
                                if (t.xFraction <= 0.001) {
                                  return Positioned(left: 0, top: 0, bottom: 0, width: labelW,
                                      child: Align(alignment: Alignment.centerLeft, child: Text(t.label, style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                                }
                                if (t.xFraction >= 0.999) {
                                  return Positioned(right: 0, top: 0, bottom: 0, width: labelW,
                                      child: Align(alignment: Alignment.centerRight, child: Text(t.label, style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                                }
                                return Positioned(left: (x - labelW / 2).clamp(0.0, contentWidth - labelW), top: 0, bottom: 0, width: labelW,
                                    child: Align(alignment: Alignment.center, child: Text(t.label, style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                              }).toList(),
                            );
                          }
                          if (multiDayTickFractions.isNotEmpty) {
                            const labelW = 44.0;
                            return Stack(
                              clipBehavior: Clip.none,
                              children: multiDayTickFractions.map((t) {
                                final x = (t.xFraction * contentWidth).clamp(0.0, contentWidth);
                                if (t.xFraction <= 0.001) {
                                  return Positioned(left: 0, top: 0, bottom: 0, width: labelW,
                                      child: Align(alignment: Alignment.centerLeft, child: Text(t.label, style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                                }
                                if (t.xFraction >= 0.999) {
                                  return Positioned(right: 0, top: 0, bottom: 0, width: labelW,
                                      child: Align(alignment: Alignment.centerRight, child: Text(t.label, style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                                }
                                return Positioned(left: (x - labelW / 2).clamp(0.0, contentWidth - labelW), top: 0, bottom: 0, width: labelW,
                                    child: Align(alignment: Alignment.center, child: Text(t.label, style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                              }).toList(),
                            );
                          }
                          if (multiDayTicks.isNotEmpty) {
                            const labelW = 44.0;
                            final maxIdx = (plotCandles.length - 1).clamp(1, 0x7fffffff);
                            return Stack(
                              clipBehavior: Clip.none,
                              children: multiDayTicks.map((t) {
                                final x = maxIdx > 0 ? (t.index / maxIdx) * contentWidth : 0.0;
                                if (t.index == 0) {
                                  return Positioned(left: 0, top: 0, bottom: 0, width: labelW,
                                      child: Align(alignment: Alignment.centerLeft, child: Text(t.label, style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                                }
                                if (t.index >= plotCandles.length - 1) {
                                  return Positioned(right: 0, top: 0, bottom: 0, width: labelW,
                                      child: Align(alignment: Alignment.centerRight, child: Text(t.label, style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                                }
                                return Positioned(left: (x - labelW / 2).clamp(0.0, contentWidth - labelW), top: 0, bottom: 0, width: labelW,
                                    child: Align(alignment: Alignment.center, child: Text(t.label, style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                              }).toList(),
                            );
                          }
                          final ticks = _buildTimeAxisTicks();
                          if (ticks.isEmpty) return const SizedBox.shrink();
                          final maxIdx = (plotCandles.length - 1).clamp(1, 0x7fffffff);
                          const labelW = 44.0;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: ticks.map((t) {
                              final x = maxIdx > 0 ? (t.index / maxIdx) * contentWidth : 0.0;
                              if (t.index == 0) {
                                return Positioned(left: 0, top: 0, bottom: 0, width: labelW,
                                    child: Align(alignment: Alignment.centerLeft, child: Text(t.label.replaceAll('\n', ' '), style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                              }
                              if (t.index >= plotCandles.length - 1) {
                                return Positioned(right: 0, top: 0, bottom: 0, width: labelW,
                                    child: Align(alignment: Alignment.centerRight, child: Text(t.label.replaceAll('\n', ' '), style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                              }
                              return Positioned(left: (x - labelW / 2).clamp(0.0, contentWidth - labelW), top: 0, bottom: 0, width: labelW,
                                  child: Align(alignment: Alignment.center, child: Text(t.label.replaceAll('\n', ' '), style: axisStyle, maxLines: 1, overflow: TextOverflow.ellipsis)));
                            }).toList(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                ],
              ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          SizedBox(
            width: rightAxisWidth,
            height: chartHeight + totalBottom,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < tickCount; i++) ...[
                  Positioned(
                    right: 0,
                    top: (yToTop(yTicks[i]) - labelHeight / 2).clamp(0.0, chartHeight - labelHeight),
                    width: rightAxisWidth,
                    height: labelHeight,
                    child: Container(
                      padding: const EdgeInsets.only(left: 2, right: 0),
                      alignment: Alignment.centerRight,
                      child: Text(
                        basePrice > 0 ? '${(yTicks[i] - basePrice) / basePrice * 100 >= 0 ? '+' : ''}${((yTicks[i] - basePrice) / basePrice * 100).toStringAsFixed(1)}%' : '—',
                        style: axisStyle.copyWith(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                if (currentPrice != null && currentPrice! >= minYPlot && currentPrice! <= maxYPlot && basePrice > 0)
                  Positioned(
                    right: 0,
                    top: (yToTop(currentPrice!) - labelHeight / 2).clamp(0.0, chartHeight - labelHeight),
                    width: rightAxisWidth,
                    height: labelHeight,
                    child: Container(
                      padding: const EdgeInsets.only(left: 2, right: 0),
                      decoration: BoxDecoration(
                        color: lineColor.withValues(alpha: 0.22),
                        border: Border.all(color: lineColor, width: 1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${(currentPrice! - basePrice) / basePrice * 100 >= 0 ? '+' : ''}${((currentPrice! - basePrice) / basePrice * 100).toStringAsFixed(1)}%',
                        style: axisStyle.copyWith(
                          fontWeight: FontWeight.w700,
                          color: lineColor,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentPriceLinePainter extends CustomPainter {
  _CurrentPriceLinePainter({
    required this.value,
    required this.minY,
    required this.maxY,
    required this.color,
  });
  final double value;
  final double minY;
  final double maxY;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final range = maxY - minY;
    if (range <= 0) return;
    final t = (value - minY) / range;
    final y = size.height * (1 - t);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const dashLen = 5.0;
    const gapLen = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset((x + dashLen).clamp(0, size.width), y), paint);
      x += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _CurrentPriceLinePainter old) =>
      old.value != value || old.minY != minY || old.maxY != maxY;
}

class _CurrentTimeLinePainter extends CustomPainter {
  _CurrentTimeLinePainter({required this.dataEndX, required this.color});
  final double dataEndX;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = (size.width * dataEndX.clamp(0.0, 1.0));
    if (x <= 0 || x >= size.width) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashLen = 4.0;
    const gapLen = 3.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(x, y), Offset(x, (y + dashLen).clamp(0, size.height)), paint);
      y += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _CurrentTimeLinePainter old) =>
      old.dataEndX != dataEndX || old.color != color;
}

/// 多日分时：在每日边界画垂直虚线，贯通主图、成交量、时间轴
class _DaySeparatorLinePainter extends CustomPainter {
  _DaySeparatorLinePainter({
    required this.boundaryIndices,
    required this.maxIndex,
    this.boundaryXFractions = const [],
    required this.contentWidth,
    required this.totalHeight,
  });
  final List<int> boundaryIndices;
  final int maxIndex;
  /// 按天平均分配时使用：分隔线在 0..1 的比例位置
  final List<double> boundaryXFractions;
  final double contentWidth;
  final double totalHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ChartTheme.textSecondary.withValues(alpha: 0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const dashLength = 4.0;
    const gapLength = 3.0;
    void drawLineAt(double x) {
      if (x <= 0 || x >= contentWidth) return;
      double y = 0;
      while (y < totalHeight) {
        final endY = (y + dashLength).clamp(0.0, totalHeight);
        canvas.drawLine(Offset(x, y), Offset(x, endY), paint);
        y = endY + gapLength;
      }
    }
    if (boundaryXFractions.isNotEmpty) {
      for (final f in boundaryXFractions) {
        drawLineAt(f * contentWidth);
      }
    } else if (maxIndex > 0 && boundaryIndices.isNotEmpty) {
      for (final i in boundaryIndices) {
        drawLineAt((i / maxIndex) * contentWidth);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DaySeparatorLinePainter old) =>
      old.boundaryIndices != boundaryIndices ||
      old.maxIndex != maxIndex ||
      old.boundaryXFractions != boundaryXFractions ||
      old.contentWidth != contentWidth ||
      old.totalHeight != totalHeight;
}

class _VolumeBarPainter extends CustomPainter {
  _VolumeBarPainter({
    required this.candles,
    this.spotXFractions,
    this.sessionStartSec,
    this.sessionEndSec,
    this.dataEndX,
  });
  final List<ChartCandle> candles;
  /// 与主图 spots 完全一致的 X 比例(0..1)，保证成交量与价格图上下对齐
  final List<double>? spotXFractions;
  final double? sessionStartSec;
  final double? sessionEndSec;
  final double? dataEndX;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final vols = candles.map((c) => (c.volume ?? 0).toDouble()).toList();
    final maxV = vols.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return;
    final n = candles.length;
    final chartH = size.height;
    final useSpotX = spotXFractions != null && spotXFractions!.length == n;
    final dataWidth = (dataEndX != null && dataEndX! > 0)
        ? (size.width * dataEndX!).clamp(1.0, size.width)
        : size.width;

    // 会话模式且有 dataEndX 时：量柱按索引均匀铺满 0～dataEndX，与主图“有数据”宽度一致，避免全挤在左侧
    final useDataRange = dataEndX != null && dataEndX! > 0 && dataEndX! <= 1;
    for (var i = 0; i < n; i++) {
      final v = vols[i];
      if (v <= 0) continue;
      final isUp = candles[i].close >= candles[i].open;
      final color = (isUp ? ChartTheme.volumeUp : ChartTheme.down).withValues(alpha: 0.75);
      final centerX = useDataRange
          ? (n > 1 ? (i / (n - 1)) * dataEndX! * size.width : dataEndX! * size.width * 0.5)
          : (useSpotX
              ? (spotXFractions![i].clamp(0.0, 1.0) * size.width)
              : (n > 1 ? (i / (n - 1)) : 0.5) * size.width);
      final barW = (useDataRange ? (dataWidth / n * 0.88) : (size.width / n * 0.88)).clamp(2.5, 14.0);
      final left = (centerX - barW / 2).clamp(0.0, size.width - barW);
      final h = (v / maxV * chartH).clamp(2.0, chartH);
      final y = chartH - h;
      canvas.drawRect(
        Rect.fromLTWH(left, y, barW, h),
        Paint()..color = color..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VolumeBarPainter old) =>
      old.candles != candles ||
      old.spotXFractions != spotXFractions ||
      old.sessionStartSec != sessionStartSec ||
      old.sessionEndSec != sessionEndSec ||
      old.dataEndX != dataEndX;
}
