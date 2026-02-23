import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../trading/polygon_repository.dart';
import 'chart_viewport_controller.dart';
import 'indicators.dart';

/// K 线视口：基于 ChartViewportController，支持拖动、缩放、加载更多历史、长按十字光标 tooltip。
/// 主图叠加：MA / EMA；副图：VOL / MACD / RSI。
class ChartViewport extends StatefulWidget {
  const ChartViewport({
    super.key,
    required this.controller,
    required this.candles,
    required this.onLoadMoreHistory,
    this.isLoadingMore = false,
    this.chartHeight = 220,
    this.volumeHeight = 48,
    this.timeAxisHeight = 24,
    this.showVolume = true,
    this.showMa = true,
    /// 主图叠加：'ma' | 'ema'，null 时用 showMa 显示 MA
    this.overlayIndicator,
    /// 副图：'vol' | 'macd' | 'rsi'，null 时用 showVolume 显示成交量
    this.subChartIndicator,
    this.loadMoreThreshold = 20,
  });

  final ChartViewportController controller;
  final List<ChartCandle> candles;
  final Future<void> Function(int earliestTimestampMs) onLoadMoreHistory;
  final bool isLoadingMore;
  final double chartHeight;
  final double volumeHeight;
  final double timeAxisHeight;
  final bool showVolume;
  final bool showMa;
  final String? overlayIndicator;
  final String? subChartIndicator;
  final int loadMoreThreshold;

  @override
  State<ChartViewport> createState() => _ChartViewportState();
}

class _ChartViewportState extends State<ChartViewport> {
  double _scaleStartCount = 0;
  int? _tooltipIndex;
  Offset? _tooltipPosition;

  List<ChartCandle> get _visibleCandles {
    final (s, e) = widget.controller.visibleRange(widget.candles.length);
    if (s >= e) return [];
    return widget.candles.sublist(s, e);
  }

  void _onPan(DragUpdateDetails d, double contentWidth) {
    if (_tooltipIndex != null) {
      final candles = _visibleCandles;
      if (candles.isNotEmpty && contentWidth > 0) {
        final n = candles.length;
        final i = (d.localPosition.dx / contentWidth * n).floor().clamp(0, n - 1);
        setState(() => _tooltipIndex = i);
      }
      return;
    }
    widget.controller.onPan(d.delta.dx, contentWidth, widget.candles.length);
    _maybeLoadMore();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _scaleStartCount = widget.controller.visibleCount;
  }

  void _maybeLoadMore() {
    if (widget.controller.visibleStartIndex < widget.loadMoreThreshold && !widget.isLoadingMore) {
      final earliestMs = (widget.candles.first.time * 1000).round();
      widget.onLoadMoreHistory(earliestMs);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, double contentWidth) {
    if (_tooltipIndex != null) setState(() { _tooltipIndex = null; _tooltipPosition = null; });
    widget.controller.onZoom(d.scale, widget.candles.length, scaleStartCount: _scaleStartCount);
    _maybeLoadMore();
  }

  void _onLongPressDown(LongPressDownDetails d, double contentWidth) {
    final candles = _visibleCandles;
    if (candles.isEmpty) return;
    final n = candles.length;
    if (contentWidth <= 0) return;
    final i = (d.localPosition.dx / contentWidth * n).floor().clamp(0, n - 1);
    setState(() {
      _tooltipIndex = i;
      _tooltipPosition = d.localPosition;
    });
  }

  void _onLongPressCancel() {
    setState(() {
      _tooltipIndex = null;
      _tooltipPosition = null;
    });
  }

  void _dismissTooltip() {
    if (_tooltipIndex != null) setState(() { _tooltipIndex = null; _tooltipPosition = null; });
  }

  Widget _buildTopIndicatorBar({
    required int index,
    required String? overlay,
    List<double?>? ma5,
    List<double?>? ma10,
    List<double?>? ma20,
    List<double?>? macdLine,
    List<double?>? signalLine,
    List<double?>? histogram,
    List<double?>? rsiList,
  }) {
    const style = TextStyle(color: Color(0xFF9CA3AF), fontSize: 10);
    final parts = <Widget>[];
    if (overlay != null && ma5 != null && index < ma5.length) {
      final a = ma5[index];
      final b = ma10 != null && index < ma10.length ? ma10[index] : null;
      final c = ma20 != null && index < ma20.length ? ma20[index] : null;
      final label = overlay == 'ema' ? 'EMA' : 'MA';
      final t = <String>[];
      if (a != null) t.add('${label}5:${_fmt(a)}');
      if (b != null) t.add('${label}10:${_fmt(b)}');
      if (c != null) t.add('${label}20:${_fmt(c)}');
      if (t.isNotEmpty) parts.add(Text(t.join('  '), style: style));
    }
    if (macdLine != null && signalLine != null && histogram != null && index < macdLine.length) {
      final dif = macdLine[index];
      final dea = signalLine[index];
      final hist = histogram[index];
      final t = <String>[];
      if (dif != null) t.add('DIF:${_fmt(dif)}');
      if (dea != null) t.add('DEA:${_fmt(dea)}');
      if (hist != null) t.add('HIST:${_fmt(hist)}');
      if (t.isNotEmpty) parts.add(Padding(padding: const EdgeInsets.only(left: 12), child: Text(t.join('  '), style: style)));
    }
    if (rsiList != null && index < rsiList.length) {
      final r = rsiList[index];
      if (r != null) parts.add(Padding(padding: const EdgeInsets.only(left: 12), child: Text('RSI:${r.toStringAsFixed(1)}', style: style)));
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: parts,
      ),
    );
  }

  Widget _buildCrosshairTooltip(List<ChartCandle> candles, double contentWidth, double minY, double maxY) {
    final i = _tooltipIndex!;
    final c = candles[i];
    final n = candles.length;
    final lineX = n > 0 ? (i + 0.5) / n * contentWidth : 0.0;
    final timeStr = _formatTimeFull(c.time);
    final change = c.close - c.open;
    final changePct = c.open != 0 ? (change / c.open * 100) : 0.0;
    final isUp = c.close >= c.open;
    final color = isUp ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final volStr = c.volume != null && c.volume! > 0 ? _formatVol(c.volume!) : '—';
    return Stack(
      children: [
        Positioned(
          left: lineX.clamp(0.0, contentWidth) - 0.5,
          top: 0,
          bottom: 0,
          child: Container(width: 1, color: const Color(0xFFD4AF37).withValues(alpha: 0.8)),
        ),
        Positioned(
          left: (lineX + 8).clamp(8.0, contentWidth - 4),
          top: 8,
          child: Material(
            color: const Color(0xFF1A1C21),
            borderRadius: BorderRadius.circular(6),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(timeStr, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                  const SizedBox(height: 4),
                  Text('O ${_fmt(c.open)}  H ${_fmt(c.high)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  Text('L ${_fmt(c.low)}  C ${_fmt(c.close)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  Text(
                    '${change >= 0 ? '+' : ''}${_fmt(change)} (${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%)',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text('量 $volStr', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _formatVol(int v) {
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(1)}亿';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}万';
    return v.toString();
  }

  static String _fmt(double v) {
    if (v >= 1000) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  static String _formatTimeFull(double timeSec) {
    final d = DateTime.fromMillisecondsSinceEpoch((timeSec * 1000).round());
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final (vStart, vEnd) = widget.controller.visibleRange(widget.candles.length);
    final candles = _visibleCandles;
    if (widget.candles.isEmpty) {
      return const Center(
        child: Text('No chart data', style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    if (candles.isEmpty) return const SizedBox.shrink();

    final overlay = widget.overlayIndicator ?? (widget.showMa ? 'ma' : null);
    final sub = widget.subChartIndicator ?? (widget.showVolume ? 'vol' : null);
    final hasSubChart = sub != null;

    final fullCloses = widget.candles.map((c) => c.close).toList();

    List<double?>? ma5, ma10, ma20;
    if (overlay == 'ma') {
      final a = ma(fullCloses, 5);
      final b = ma(fullCloses, 10);
      final c = ma(fullCloses, 20);
      ma5 = a.sublist(vStart, vEnd);
      ma10 = b.sublist(vStart, vEnd);
      ma20 = c.sublist(vStart, vEnd);
    } else if (overlay == 'ema') {
      final a = ema(fullCloses, 5);
      final b = ema(fullCloses, 10);
      final c = ema(fullCloses, 20);
      ma5 = a.sublist(vStart, vEnd);
      ma10 = b.sublist(vStart, vEnd);
      ma20 = c.sublist(vStart, vEnd);
    }

    double minY = candles.first.low;
    double maxY = candles.first.high;
    for (final c in candles) {
      if (c.low < minY) minY = c.low;
      if (c.high > maxY) maxY = c.high;
    }
    for (var i = 0; i < candles.length; i++) {
      for (final v in [ma5?[i], ma10?[i], ma20?[i]]) {
        if (v != null) {
          if (v < minY) minY = v;
          if (v > maxY) maxY = v;
        }
      }
    }
    final range = (maxY - minY).clamp(0.01, double.infinity);
    minY = minY - range * 0.02;
    maxY = maxY + range * 0.02;

    MacdResult? macdResult;
    List<double?>? rsiList;
    if (sub == 'macd') {
      macdResult = macd(fullCloses);
    } else if (sub == 'rsi') {
      final r = rsi(fullCloses);
      rsiList = r.sublist(vStart, vEnd);
    }
    if (_tooltipIndex != null && (macdResult == null || rsiList == null)) {
      if (macdResult == null) macdResult = macd(fullCloses);
      if (rsiList == null) rsiList = rsi(fullCloses).sublist(vStart, vEnd);
    }
    final macdLine = macdResult?.macdLine.sublist(vStart, vEnd);
    final signalLine = macdResult?.signalLine.sublist(vStart, vEnd);
    final histogram = macdResult?.histogram.sublist(vStart, vEnd);

    final hasVolBars = sub == 'vol' && candles.any((c) => (c.volume ?? 0) > 0);
    const axisStyle = TextStyle(color: Color(0xFF6B6B70), fontSize: 10);
    final subHeight = widget.volumeHeight;

    return LayoutBuilder(
      builder: (context, layoutConstraints) {
        final chartAreaWidth = (layoutConstraints.maxWidth - 48 - 4 - 4 - 44).clamp(0.0, double.infinity);
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_tooltipIndex != null && _tooltipIndex! < candles.length)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _buildTopIndicatorBar(
                    index: _tooltipIndex!,
                    overlay: overlay,
                    ma5: ma5,
                    ma10: ma10,
                    ma20: ma20,
                    macdLine: macdLine,
                    signalLine: signalLine,
                    histogram: histogram,
                    rsiList: rsiList,
                  ),
                ),
              if (overlay != null) Text(overlay == 'ema' ? 'EMA5/10/20' : 'MA5/10/20', style: _labelStyle()),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 48,
                    height: widget.chartHeight + (hasSubChart ? subHeight : 0) + widget.timeAxisHeight,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(5, (i) {
                        final v = maxY - (maxY - minY) * i / 4;
                        return Text(v.toStringAsFixed(2), style: axisStyle);
                      }),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: _dismissTooltip,
                      onHorizontalDragUpdate: (d) => _onPan(d, chartAreaWidth),
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: (d) => _onScaleUpdate(d, chartAreaWidth),
                      onLongPressDown: (d) => _onLongPressDown(d, chartAreaWidth),
                      onLongPressCancel: _onLongPressCancel,
                      onLongPressEnd: (_) => _onLongPressCancel(),
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          SizedBox(
                            height: widget.chartHeight,
                            child: _FlChartCandleLayer(
                              candles: candles,
                              minY: minY,
                              maxY: maxY,
                              ma5: ma5,
                              ma10: ma10,
                              ma20: ma20,
                              highlightIndex: _tooltipIndex,
                            ),
                          ),
                          if (_tooltipIndex != null && _tooltipPosition != null && _tooltipIndex! < candles.length)
                            _buildCrosshairTooltip(candles, chartAreaWidth, minY, maxY),
                          if (widget.isLoadingMore)
                            Positioned(
                              left: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFD4AF37),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Loading history...',
                                      style: TextStyle(
                                        color: const Color(0xFF9CA3AF).withValues(alpha: 0.95),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 44,
                    height: widget.chartHeight + (hasSubChart ? subHeight : 0) + widget.timeAxisHeight,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(5, (i) {
                        final v = maxY - (maxY - minY) * i / 4;
                        return Text(
                          '${(v >= 0 ? '+' : '')}${v.toStringAsFixed(2)}',
                          style: axisStyle,
                        );
                      }),
                    ),
                  ),
                ],
              ),
              if (hasVolBars)
                Padding(
                  padding: const EdgeInsets.only(left: 52),
                  child: SizedBox(
                    height: subHeight,
                    child: CustomPaint(
                      size: Size(chartAreaWidth, subHeight),
                      painter: _VolumeBarPainter(candles: candles),
                    ),
                  ),
                ),
              if (sub == 'macd' && macdResult != null)
                Padding(
                  padding: const EdgeInsets.only(left: 52),
                  child: SizedBox(
                    height: subHeight,
                    child: CustomPaint(
                      size: Size(chartAreaWidth, subHeight),
                      painter: _MacdPainter(
                        macdLine: macdResult.macdLine.sublist(vStart, vEnd),
                        signalLine: macdResult.signalLine.sublist(vStart, vEnd),
                        histogram: macdResult.histogram.sublist(vStart, vEnd),
                      ),
                    ),
                  ),
                ),
              if (sub == 'rsi' && rsiList != null)
                Padding(
                  padding: const EdgeInsets.only(left: 52),
                  child: SizedBox(
                    height: subHeight,
                    child: CustomPaint(
                      size: Size(chartAreaWidth, subHeight),
                      painter: _RsiPainter(rsiValues: rsiList),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: SizedBox(
                  height: widget.timeAxisHeight,
                  width: chartAreaWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(5, (i) {
                      final idx = i == 0 ? 0 : (i * (candles.length - 1) / 4).floor().clamp(0, candles.length - 1);
                      if (idx >= candles.length) return const SizedBox.shrink();
                      return Text(_formatTime(candles[idx].time), style: axisStyle);
                    }),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatTime(double timeSec) {
    final d = DateTime.fromMillisecondsSinceEpoch((timeSec * 1000).round());
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  TextStyle _labelStyle() {
    return const TextStyle(
      color: Color(0xFF9CA3AF),
      fontSize: 12,
    );
  }
}

/// 使用 fl_chart 绘制网格与 MA 线，CustomPaint 绘制 K 线
class _FlChartCandleLayer extends StatelessWidget {
  const _FlChartCandleLayer({
    required this.candles,
    required this.minY,
    required this.maxY,
    this.ma5,
    this.ma10,
    this.ma20,
    this.highlightIndex,
  });

  final List<ChartCandle> candles;
  final double minY;
  final double maxY;
  final List<double?>? ma5;
  final List<double?>? ma10;
  final List<double?>? ma20;
  final int? highlightIndex;

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) return const SizedBox.shrink();
    final n = candles.length;
    final ma5Spots = ma5 == null || ma5!.length != n
        ? <FlSpot>[]
        : List.generate(n, (i) => FlSpot(i.toDouble(), ma5![i] ?? 0));
    final ma10Spots = ma10 == null || ma10!.length != n
        ? <FlSpot>[]
        : List.generate(n, (i) => FlSpot(i.toDouble(), ma10![i] ?? 0));
    final ma20Spots = ma20 == null || ma20!.length != n
        ? <FlSpot>[]
        : List.generate(n, (i) => FlSpot(i.toDouble(), ma20![i] ?? 0));
    final lineBars = <LineChartBarData>[];
    if (ma5Spots.isNotEmpty) {
      lineBars.add(LineChartBarData(
        spots: ma5Spots,
        isCurved: false,
        color: const Color(0xFFF59E0B),
        barWidth: 1.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    if (ma10Spots.isNotEmpty) {
      lineBars.add(LineChartBarData(
        spots: ma10Spots,
        isCurved: false,
        color: const Color(0xFF3B82F6),
        barWidth: 1.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    if (ma20Spots.isNotEmpty) {
      lineBars.add(LineChartBarData(
        spots: ma20Spots,
        isCurved: false,
        color: const Color(0xFF8B5CF6),
        barWidth: 1.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    if (lineBars.isEmpty) {
      lineBars.add(LineChartBarData(
        spots: [FlSpot(0, minY), FlSpot((n - 1).toDouble(), maxY)],
        isCurved: false,
        color: Colors.transparent,
        barWidth: 0,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }
    return Stack(
      children: [
        LineChart(
          LineChartData(
            minX: 0,
            maxX: (n - 1).toDouble(),
            minY: minY,
            maxY: maxY,
            lineBarsData: lineBars,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: const Color(0xFF2A2D34),
                strokeWidth: 0.8,
              ),
            ),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
          ),
          duration: Duration.zero,
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _CandlestickPainter(
              candles: candles,
              minY: minY,
              maxY: maxY,
              highlightIndex: highlightIndex,
            ),
          ),
        ),
      ],
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  _CandlestickPainter({
    required this.candles,
    required this.minY,
    required this.maxY,
    this.highlightIndex,
  });

  final List<ChartCandle> candles;
  final double minY;
  final double maxY;
  final int? highlightIndex;

  static const Color _highlightFill = Color(0x18D4AF37);
  static const Color _highlightStroke = Color(0xFFD4AF37);

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final n = candles.length;
    const pad = 4.0;
    final chartW = size.width - pad * 2;
    final chartH = size.height - pad * 2;
    final rangeY = (maxY - minY).clamp(0.01, double.infinity);
    final candleW = (chartW / n).clamp(2.0, 20.0);
    final gap = (chartW - candleW * n) / (n + 1);
    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final isUp = c.close >= c.open;
      final color = isUp ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
      final x = pad + gap + (gap + candleW) * i + candleW / 2;
      final yHigh = pad + chartH - (c.high - minY) / rangeY * chartH;
      final yLow = pad + chartH - (c.low - minY) / rangeY * chartH;
      final yOpen = pad + chartH - (c.open - minY) / rangeY * chartH;
      final yClose = pad + chartH - (c.close - minY) / rangeY * chartH;
      final bodyTop = yOpen < yClose ? yOpen : yClose;
      final bodyBottom = yOpen < yClose ? yClose : yOpen;
      final bodyH = (bodyBottom - bodyTop).clamp(1.0, double.infinity);
      const wickW = 1.0;
      final bodyW = (candleW * 0.7).clamp(3.0, 14.0);

      final isHighlight = highlightIndex != null && i == highlightIndex;
      if (isHighlight) {
        final bandW = (candleW + gap).clamp(8.0, 32.0);
        canvas.drawRect(
          Rect.fromCenter(center: Offset(x, pad + chartH / 2), width: bandW, height: chartH),
          Paint()..color = _highlightFill..style = PaintingStyle.fill,
        );
      }

      final paint = Paint()
        ..color = color
        ..strokeWidth = wickW
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(x, yHigh), Offset(x, yLow), paint);
      paint.style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, (bodyTop + bodyBottom) / 2),
          width: bodyW,
          height: bodyH,
        ),
        paint,
      );

      if (isHighlight) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(x, (bodyTop + bodyBottom) / 2),
            width: bodyW,
            height: bodyH,
          ),
          Paint()
            ..color = _highlightStroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter old) {
    return old.candles != candles || old.minY != minY || old.maxY != maxY || old.highlightIndex != highlightIndex;
  }
}

class _VolumeBarPainter extends CustomPainter {
  _VolumeBarPainter({required this.candles});
  final List<ChartCandle> candles;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final vols = candles.map((c) => (c.volume ?? 0).toDouble()).toList();
    final maxV = vols.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return;
    final n = candles.length;
    const pad = 4.0;
    final chartW = size.width - pad * 2;
    final chartH = size.height - pad * 2;
    final barW = (chartW / n).clamp(1.0, 12.0);
    final gap = (chartW - barW * n) / (n + 1);
    for (var i = 0; i < n; i++) {
      final v = vols[i];
      if (v <= 0) continue;
      final isUp = candles[i].close >= candles[i].open;
      final color = isUp
          ? const Color(0xFF22C55E).withValues(alpha: 0.7)
          : const Color(0xFFEF4444).withValues(alpha: 0.7);
      final x = pad + gap + (gap + barW) * i;
      final h = (v / maxV * chartH).clamp(2.0, chartH);
      final y = pad + chartH - h;
      canvas.drawRect(
        Rect.fromLTWH(x, y, barW, h),
        Paint()..color = color..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VolumeBarPainter old) => old.candles != candles;
}

class _MacdPainter extends CustomPainter {
  _MacdPainter({
    required this.macdLine,
    required this.signalLine,
    required this.histogram,
  });
  final List<double?> macdLine;
  final List<double?> signalLine;
  final List<double?> histogram;

  @override
  void paint(Canvas canvas, Size size) {
    if (macdLine.isEmpty) return;
    final n = macdLine.length;
    double minV = double.infinity;
    double maxV = -double.infinity;
    for (var i = 0; i < n; i++) {
      for (final v in [macdLine[i], signalLine[i], histogram[i]]) {
        if (v != null) {
          if (v < minV) minV = v;
          if (v > maxV) maxV = v;
        }
      }
    }
    if (minV > maxV) return;
    final range = (maxV - minV).clamp(0.01, double.infinity);
    const pad = 4.0;
    final chartW = size.width - pad * 2;
    final chartH = size.height - pad * 2;
    final barW = (chartW / n).clamp(1.0, 8.0);
    final gap = (chartW - barW * n) / (n + 1);

    for (var i = 0; i < n; i++) {
      final h = histogram[i];
      if (h == null) continue;
      final x = pad + gap + (gap + barW) * i;
      final zeroY = pad + chartH - (0 - minV) / range * chartH;
      final y = pad + chartH - (h - minV) / range * chartH;
      final top = h >= 0 ? y : zeroY;
      final bottom = h >= 0 ? zeroY : y;
      final color = h >= 0 ? const Color(0xFF22C55E).withValues(alpha: 0.8) : const Color(0xFFEF4444).withValues(alpha: 0.8);
      canvas.drawRect(
        Rect.fromLTWH(x, top, barW, (bottom - top).clamp(1.0, chartH)),
        Paint()..color = color..style = PaintingStyle.fill,
      );
    }

    bool firstMacd = true;
    bool firstSignal = true;
    final pathMacd = Path();
    final pathSignal = Path();
    for (var i = 0; i < n; i++) {
      final m = macdLine[i];
      final s = signalLine[i];
      final x = pad + gap + (gap + barW) * i + barW / 2;
      if (m != null) {
        final y = pad + chartH - (m - minV) / range * chartH;
        if (firstMacd) { pathMacd.moveTo(x, y); firstMacd = false; } else pathMacd.lineTo(x, y);
      }
      if (s != null) {
        final y = pad + chartH - (s - minV) / range * chartH;
        if (firstSignal) { pathSignal.moveTo(x, y); firstSignal = false; } else pathSignal.lineTo(x, y);
      }
    }
    canvas.drawPath(pathMacd, Paint()..color = const Color(0xFFD4AF37)..style = PaintingStyle.stroke..strokeWidth = 1.2);
    canvas.drawPath(pathSignal, Paint()..color = const Color(0xFF3B82F6)..style = PaintingStyle.stroke..strokeWidth = 1.0);
  }

  @override
  bool shouldRepaint(covariant _MacdPainter old) =>
      old.macdLine != macdLine || old.signalLine != signalLine || old.histogram != histogram;
}

class _RsiPainter extends CustomPainter {
  _RsiPainter({required this.rsiValues});
  final List<double?> rsiValues;

  @override
  void paint(Canvas canvas, Size size) {
    if (rsiValues.isEmpty) return;
    const rsiMin = 0.0;
    const rsiMax = 100.0;
    const pad = 4.0;
    final chartW = size.width - pad * 2;
    final chartH = size.height - pad * 2;
    final n = rsiValues.length;
    final barW = (chartW / n).clamp(2.0, 12.0);
    final gap = (chartW - barW * n) / (n + 1);

    bool first = true;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final v = rsiValues[i];
      if (v == null) continue;
      final x = pad + gap + (gap + barW) * i + barW / 2;
      final y = pad + chartH - (v - rsiMin) / (rsiMax - rsiMin) * chartH;
      if (first) { path.moveTo(x, y); first = false; } else path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = const Color(0xFFD4AF37)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    final line30Y = pad + chartH - (30 - rsiMin) / (rsiMax - rsiMin) * chartH;
    final line70Y = pad + chartH - (70 - rsiMin) / (rsiMax - rsiMin) * chartH;
    canvas.drawLine(Offset(pad, line30Y), Offset(size.width - pad, line30Y), Paint()..color = const Color(0xFF6B6B70).withValues(alpha: 0.6)..strokeWidth = 0.8);
    canvas.drawLine(Offset(pad, line70Y), Offset(size.width - pad, line70Y), Paint()..color = const Color(0xFF6B6B70).withValues(alpha: 0.6)..strokeWidth = 0.8);
  }

  @override
  bool shouldRepaint(covariant _RsiPainter old) => old.rsiValues != rsiValues;
}
