import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../trading/polygon_repository.dart';
import 'chart/chart_theme.dart';
import 'chart_viewport_controller.dart';
import 'indicators.dart';

/// K 绾胯鍙ｏ細鍩轰簬 ChartViewportController锛屾敮鎸佹嫋鍔ㄣ€佺缉鏀俱€佸姞杞芥洿澶氬巻鍙层€侀暱鎸夊崄瀛楀厜鏍?tooltip銆?
/// 涓诲浘鍙犲姞锛歁A / EMA锛涘壇鍥撅細VOL / MACD / RSI銆?
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
    /// 涓诲浘鍙犲姞锛?ma' | 'ema'锛宯ull 鏃剁敤 showMa 鏄剧ず MA
    this.overlayIndicator,
    /// 鍓浘锛?vol' | 'macd' | 'rsi'锛宯ull 鏃剁敤 showVolume 鏄剧ず鎴愪氦閲?
    this.subChartIndicator,
    this.loadMoreThreshold = 20,
    /// 鏄ㄦ敹浠凤紝鐢ㄤ簬鍙充晶娑ㄥ箙璁＄畻
    this.prevClose,
    /// 鐜颁环锛岃櫄绾跨敾鍦ㄦ浠蜂綅銆佸彸渚т负鐩稿鏄ㄦ敹娑ㄨ穼骞咃紱涓嶄紶鍒欑敤鏈€鍚庝竴鏍?K 绾挎敹鐩?
    this.currentPrice,
    /// 鏄惁鏄剧ず鏄ㄦ敹浠疯櫄绾匡紙Prev Close锛夛紝鍙湪鎸囨爣闈㈡澘鍒囨崲
    this.showPrevCloseLine = true,
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
  final double? prevClose;
  final double? currentPrice;
  final bool showPrevCloseLine;

  @override
  State<ChartViewport> createState() => _ChartViewportState();
}

class _ChartViewportState extends State<ChartViewport> {
  double _scaleStartCount = 0;
  double _scaleStartIndex = 0;
  int? _tooltipIndex;
  Offset? _tooltipPosition;
  /// 鍗佸瓧绾胯鎯呮樉绀烘椂闂达紝鐢ㄤ簬闃茶瑙︼細鏄剧ず涓嶈冻姝ゆ椂闂存椂鐐瑰嚮涓嶅叧闂?
  DateTime? _tooltipShownAt;
  static const _tooltipMinVisibleDuration = Duration(milliseconds: 500);

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
        final totalSlots = n + _kRightReservedCandleSlots;
        final i = (d.localPosition.dx / contentWidth * totalSlots).floor().clamp(0, n - 1);
        setState(() => _tooltipIndex = i);
      }
      return;
    }
    _onPanByDelta(d.delta.dx, contentWidth);
  }

  /// 鎸夋í鍚戜綅绉诲钩绉诲浘琛紙渚涘乏閿嫋鎷戒笌鍙抽敭鎷栨嫿鍏辩敤锛?
  void _onPanByDelta(double dx, double contentWidth) {
    final n = _visibleCandles.length;
    final effectiveWidth = n > 0 ? contentWidth * n / (n + _kRightReservedCandleSlots) : contentWidth;
    widget.controller.onPan(dx, effectiveWidth, widget.candles.length);
    _maybeLoadMore();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _scaleStartCount = widget.controller.visibleCount;
    _scaleStartIndex = widget.controller.visibleStartIndex;
  }

  void _maybeLoadMore() {
    if (widget.controller.visibleStartIndex < widget.loadMoreThreshold && !widget.isLoadingMore) {
      final earliestMs = (widget.candles.first.time * 1000).round();
      widget.onLoadMoreHistory(earliestMs);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, double contentWidth) {
    if (d.pointerCount < 2) return;
    if (_tooltipIndex != null) setState(() { _tooltipIndex = null; _tooltipPosition = null; });
    final focalRatio = contentWidth > 0
        ? (d.localFocalPoint.dx / contentWidth).clamp(0.0, 1.0)
        : 0.5;
    if (d.focalPointDelta.dx.abs() > 0.01) {
      _onPanByDelta(d.focalPointDelta.dx, contentWidth);
    }
    widget.controller.onZoom(
      d.scale,
      widget.candles.length,
      scaleStartCount: _scaleStartCount,
      scaleStartIndex: _scaleStartIndex,
      focalRatio: focalRatio,
    );
    _maybeLoadMore();
  }

  void _onLongPressDown(LongPressDownDetails d, double contentWidth) {
    final candles = _visibleCandles;
    if (candles.isEmpty) return;
    final n = candles.length;
    if (contentWidth <= 0) return;
    final totalSlots = n + _kRightReservedCandleSlots;
    final i = (d.localPosition.dx / contentWidth * totalSlots).floor().clamp(0, n - 1);
    setState(() {
      _tooltipIndex = i;
      _tooltipPosition = d.localPosition;
      _tooltipShownAt = DateTime.now();
    });
  }

  void _onLongPressCancel() {
    setState(() {
      _tooltipIndex = null;
      _tooltipPosition = null;
      _tooltipShownAt = null;
    });
  }

  void _dismissTooltip() {
    if (_tooltipIndex == null) return;
    // 闃茶瑙︼細鍒氬脊鍑烘椂锛堝闀挎寜鏉炬墜瑙﹀彂鐨勭偣鍑伙級涓嶇珛鍗冲叧锛岃嚦灏戜繚鐣?0.5 绉掍究浜庣湅娓?
    if (_tooltipShownAt != null &&
        DateTime.now().difference(_tooltipShownAt!) < _tooltipMinVisibleDuration) {
      return;
    }
    setState(() {
      _tooltipIndex = null;
      _tooltipPosition = null;
      _tooltipShownAt = null;
    });
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

  static const Color _ma5Color = Color(0xFFF6C343);
  static const Color _ma10Color = Color(0xFF3B82F6);
  static const Color _ma20Color = Color(0xFF8B5CF6);

  /// MA 鍥句緥锛氫笁琛?MA5/MA10/MA20 + value锛屽搴旈鑹?
  Widget _buildMaLegend(String overlay, List<double?>? ma5, List<double?>? ma10, List<double?>? ma20, int candleCount) {
    final idx = (candleCount > 0) ? candleCount - 1 : 0;
    final label = overlay == 'ema' ? 'EMA' : 'MA';
    final a = ma5 != null && idx < ma5.length ? ma5[idx] : null;
    final b = ma10 != null && idx < ma10.length ? ma10[idx] : null;
    final c = ma20 != null && idx < ma20.length ? ma20[idx] : null;
    final lines = <Widget>[];
    if (a != null) lines.add(Row(mainAxisSize: MainAxisSize.min, children: [Text('${label}5 ', style: const TextStyle(color: _ma5Color, fontSize: 11)), Text(_fmt(a), style: _labelStyle())]));
    if (b != null) lines.add(Row(mainAxisSize: MainAxisSize.min, children: [Text('${label}10 ', style: const TextStyle(color: _ma10Color, fontSize: 11)), Text(_fmt(b), style: _labelStyle())]));
    if (c != null) lines.add(Row(mainAxisSize: MainAxisSize.min, children: [Text('${label}20 ', style: const TextStyle(color: _ma20Color, fontSize: 11)), Text(_fmt(c), style: _labelStyle())]));
    if (lines.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: lines.map((w) => Padding(padding: const EdgeInsets.only(right: 12), child: w)).toList(),
    );
  }

  /// 鏄ㄦ敹浠风嚎宸︿晶鏍囩锛堢伆鑹茶櫄绾匡紝鏂囨鍦ㄧ嚎鐨勪笂鏂逛究浜庤鲸璁わ級
  Widget _buildPrevCloseLabel(double prevClose, double minY, double maxY, [double? chartHeight]) {
    final h = chartHeight ?? widget.chartHeight;
    const pad = 4.0;
    final rangeY = (maxY - minY).clamp(0.01, double.infinity);
    final chartH = h - pad * 2;
    final y = pad + chartH * (maxY - prevClose) / rangeY;
    const labelHeight = 18.0;
    const margin = 2.0;
    const gapAboveLine = 4.0;
    final top = (y - labelHeight - gapAboveLine).clamp(margin, h - labelHeight - margin);
    const lineColor = Color(0xFF9CA3AF);
    return Positioned(
      left: 4,
      top: top,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: lineColor.withValues(alpha: 0.2),
          border: Border.all(color: lineColor.withValues(alpha: 0.6), width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Prev Close',
          style: TextStyle(color: lineColor.withValues(alpha: 0.95), fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// 涓庡垎鏃跺浘涓€鑷达細娑ㄧ豢璺岀孩
  Color _refLineColor(double refPrice) {
    final prev = widget.prevClose;
    if (prev == null || prev <= 0) return ChartTheme.textSecondary;
    return refPrice >= prev ? ChartTheme.up : ChartTheme.down;
  }

  /// 鍙充晶 Y 杞村垪涓婁粎鏄剧ず娑ㄨ穼骞呮爣绛撅紙涓嶆樉绀轰环鏍硷紝宸﹁竟鎵嶆槸浠锋牸锛?
  Widget _buildRightAxisRefLabel(double refPrice, double minY, double maxY, double chartH) {
    const pad = 4.0;
    const rightLabelH = 40.0;
    const margin = 2.0;
    final rangeY = (maxY - minY).clamp(0.01, double.infinity);
    final innerH = chartH - pad * 2;
    final y = pad + innerH * (maxY - refPrice) / rangeY;
    final rightTop = (y - rightLabelH / 2).clamp(margin, chartH - rightLabelH - margin);
    final lineColor = _refLineColor(refPrice);
    final prev = widget.prevClose;
    final pct = (prev != null && prev > 0) ? ((refPrice - prev) / prev * 100) : null;
    final pctStr =
        pct != null ? "${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%" : '--';
    final boxDeco = BoxDecoration(
      color: lineColor.withValues(alpha: 0.22),
      border: Border.all(color: lineColor, width: 1),
      borderRadius: BorderRadius.circular(4),
    );
    final textStyle = TextStyle(
      color: lineColor,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    return Positioned(
      right: 0,
      top: rightTop,
      width: 72,
      height: rightLabelH,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: boxDeco,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _fmt(refPrice),
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              pctStr,
              style: textStyle.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// 铏氱嚎鍙傝€冪嚎锛氱幇浠?鏄ㄦ敹绾垮彧鍦ㄥ浘鍐呯敾绾匡紝宸﹀彸渚т环鏍?娑ㄨ穼骞呭凡绉诲埌 Y 杞村垪锛圞 绾垮浘澶栵級
  Widget _buildRefLineLabels(double refPrice, double minY, double maxY, Color lineColor, [double? chartHeight]) {
    return const SizedBox.shrink();
  }

  Widget _buildCrosshairTooltip(List<ChartCandle> candles, double contentWidth, double minY, double maxY) {
    final i = _tooltipIndex!;
    final c = candles[i];
    final n = candles.length;
    final totalSlots = n + _kRightReservedCandleSlots;
    final lineX = n > 0 ? (i + 0.5) / totalSlots * contentWidth : 0.0;
    final timeStr = _formatTimeFull(c.time);
    final change = c.close - c.open;
    final changePct = c.open != 0 ? (change / c.open * 100) : 0.0;
    final isUp = c.close >= c.open;
    final color = isUp ? ChartTheme.up : ChartTheme.down;
    final volStr = c.volume != null && c.volume! > 0 ? _formatVol(c.volume!) : '鈥?;
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
                  Text('${AppLocalizations.of(context)!.chartVol} $volStr', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context)!.chartClickToClose,
                    style: TextStyle(color: const Color(0xFF9CA3AF).withValues(alpha: 0.8), fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _formatVol(int v) {
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(1)}浜?;
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}涓?;
    return v.toString();
  }

  static String _fmt(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 100) return v.toStringAsFixed(2);
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
      return Center(
        child: Text(AppLocalizations.of(context)!.chartNoKlineData, style: TextStyle(color: Color(0xFF9CA3AF))),
      );
    }
    if (candles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
        child: SizedBox(
          width: double.infinity,
          height: 240,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0F172A), Color(0xFF111827)],
              ),
            ),
            child: Center(
              child: Text(AppLocalizations.of(context)!.chartNoKlineData, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
            ),
          ),
        ),
      );
    }

    final raw = widget.overlayIndicator ?? (widget.showMa ? 'ma' : null);
    final overlay = (raw == null || raw == 'none') ? null : raw;
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
    /// 鐜颁环绾匡細浼樺厛鐢ㄧ埗缁勪欢浼犲叆鐨?currentPrice锛堜笌搴曢儴銆屾敹銆嶄竴鑷达級锛屼繚璇佽櫄绾夸笌 14.50 / -2.30% 瀵归綈
    final refPrice = widget.currentPrice ?? (candles.isNotEmpty ? candles.last.close : null);
    if (refPrice != null && refPrice > 0) {
      if (refPrice < minY) minY = refPrice;
      if (refPrice > maxY) maxY = refPrice;
    }
    if (widget.prevClose != null && widget.prevClose! > 0) {
      final pc = widget.prevClose!;
      if (pc < minY) minY = pc;
      if (pc > maxY) maxY = pc;
    }
    var range = (maxY - minY).clamp(0.01, double.infinity);
    final verticalPad = range * 0.08;
    minY = minY - verticalPad;
    maxY = maxY + verticalPad;
    range = maxY - minY;
    // 闃叉鍗曟牴鏋佺K绾匡紙濡傛毚娑ㄦ毚璺岋級鍘嬬缉鍏朵粬K绾匡細鑻ュ崟鏍瑰崰姣旇繃澶э紝鍒欓澶栨墿灞昚杞淬€?
    final maxCandleRange = candles.fold<double>(0, (m, c) {
      final r = (c.high - c.low).clamp(0.0, double.infinity);
      return r > m ? r : m;
    });
    if (maxCandleRange > 0 && range > 0 && maxCandleRange / range > 0.38) {
      final targetRange = maxCandleRange / 0.32;
      final mid = (maxY + minY) / 2;
      minY = mid - targetRange / 2;
      maxY = mid + targetRange / 2;
    }

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
    const axisStyle = TextStyle(color: Color(0x99FFFFFF), fontSize: ChartTheme.fontSizeAxis);

    return LayoutBuilder(
      builder: (context, layoutConstraints) {
        const rightAxisWidth = 56.0;
        const horizontalPad = 4.0;
        final chartAreaWidth = (layoutConstraints.maxWidth - horizontalPad - 2 - rightAxisWidth).clamp(0.0, double.infinity);
        const timeRatio = 28 / 376;
        /// 鏃堕棿杞存渶灏忛珮搴︼紝纭繚搴曢儴鏃ユ湡鏍囩瀹屾暣鏄剧ず涓嶈瑁佸垏
        const minTimeAxisHeight = 28.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 4, 12),
          child: ClipRect(
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
              if (overlay != null) _buildMaLegend(overlay, ma5, ma10, ma20, candles.length),
              const SizedBox(height: 4),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, chartConstraints) {
                    final remaining = chartConstraints.maxHeight.clamp(120.0, double.infinity);
                    final timeH = (remaining * timeRatio).clamp(minTimeAxisHeight, 36.0);
                    final rest = remaining - timeH;
                    // 鏀惧ぇ鍓浘锛圴OL / MACD / RSI锛夊尯鍩燂紝閬垮厤鍦ㄥ皬灞忎笂杩囦簬鎷ユ尋闅剧湅娓呫€?
                    final chartH = rest * 0.84;
                    final subH = rest * 0.16;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
              SizedBox(
                width: chartConstraints.maxWidth,
                height: chartH,
                child: ClipRect(
                  child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF0F172A), Color(0xFF111827)],
                          ),
                        ),
                        child: Listener(
                      onPointerMove: (e) {
                        if ((e.buttons & 2) != 0) {
                          setState(() {
                            if (_tooltipIndex != null) {
                              _tooltipIndex = null;
                              _tooltipPosition = null;
                            }
                          });
                          _onPanByDelta(e.delta.dx, chartAreaWidth);
                        }
                      },
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
                            height: chartH,
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
                          if (widget.showPrevCloseLine &&
                              widget.prevClose != null &&
                              widget.prevClose! > 0 &&
                              widget.prevClose! >= minY &&
                              widget.prevClose! <= maxY &&
                              (refPrice == null || (refPrice - widget.prevClose!).abs() > 0.001))
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: CustomPaint(
                                painter: _ReferenceLinePainter(
                                  refPrice: widget.prevClose!,
                                  minY: minY,
                                  maxY: maxY,
                                  color: const Color(0xFF9CA3AF).withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          if (widget.showPrevCloseLine &&
                              widget.prevClose != null &&
                              widget.prevClose! > 0 &&
                              widget.prevClose! >= minY &&
                              widget.prevClose! <= maxY &&
                              (refPrice == null || (refPrice - widget.prevClose!).abs() > 0.001))
                            _buildPrevCloseLabel(widget.prevClose!, minY, maxY, chartH),
                          if (widget.showPrevCloseLine &&
                              refPrice != null &&
                              refPrice >= minY &&
                              refPrice <= maxY) ...[
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: CustomPaint(
                                painter: _ReferenceLinePainter(
                                  refPrice: refPrice,
                                  minY: minY,
                                  maxY: maxY,
                                  color: _refLineColor(refPrice),
                                ),
                              ),
                            ),
                            _buildRefLineLabels(refPrice, minY, maxY, _refLineColor(refPrice), chartH),
                          ],
                          if (_tooltipIndex != null && _tooltipPosition != null && _tooltipIndex! < candles.length)
                            _buildCrosshairTooltip(candles, chartAreaWidth, minY, maxY),
                        ],
                      ),
                    ),
                    ),
                  ),
                    ),
                    const SizedBox(width: 2),
                    SizedBox(
                      width: rightAxisWidth,
                      height: chartH,
                      child: ClipRect(
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(5, (i) {
                              final v = maxY - (maxY - minY) * i / 4;
                              return Text(
                                _fmt(v),
                                style: axisStyle.copyWith(fontSize: 9),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            }),
                          ),
                          if (widget.showPrevCloseLine &&
                              refPrice != null &&
                              refPrice >= minY &&
                              refPrice <= maxY) ...[
                            _buildRightAxisRefLabel(refPrice, minY, maxY, chartH),
                          ],
                        ],
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
                ),
            if (hasVolBars)
                SizedBox(
                  height: subH,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, volConstraints) {
                          final w = volConstraints.maxWidth.clamp(0.0, double.infinity);
                          return SizedBox(
                            height: subH,
                            child: CustomPaint(
                              size: Size(w, subH),
                              painter: _VolumeBarPainter(candles: candles),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 2),
                    SizedBox(width: rightAxisWidth),
                  ],
                ),
              ),
              if (sub == 'macd' && macdResult != null)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: SizedBox(
                    height: subH,
                    child: CustomPaint(
                      size: Size(chartAreaWidth, subH),
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
                  padding: const EdgeInsets.only(left: 2),
                  child: SizedBox(
                    height: subH,
                    child: CustomPaint(
                      size: Size(chartAreaWidth, subH),
                      painter: _RsiPainter(rsiValues: rsiList),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: SizedBox(
                  height: timeH,
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
                    );
                  },
                ),
              ),
            ],
          ),
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

/// 浣跨敤 fl_chart 缁樺埗缃戞牸涓?MA 绾匡紝CustomPaint 缁樺埗 K 绾?
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
    // 鍧囩嚎鍓?period-1 涓负 null锛屽彧缁樺埗鏈夋晥鐐癸紝閬垮厤 null 琚綋鎴?0 瀵艰嚧鍨傜洿绾?
    List<FlSpot> _maSpots(List<double?>? list) {
      if (list == null || list.length != n) return [];
      return [for (var i = 0; i < n; i++) if (list[i] != null) FlSpot(i.toDouble(), list[i]!)];
    }
    final ma5Spots = _maSpots(ma5);
    final ma10Spots = _maSpots(ma10);
    final ma20Spots = _maSpots(ma20);
    final lineBars = <LineChartBarData>[];
    if (ma5Spots.isNotEmpty) {
      lineBars.add(LineChartBarData(
        spots: ma5Spots,
        isCurved: false,
        color: const Color(0xFFF6C343), // MA5
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
    final maxX = (n - 1 + _kRightReservedCandleSlots).toDouble();
    return Stack(
      children: [
        LineChart(
          LineChartData(
            minX: 0,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            lineBarsData: lineBars,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: (maxY - minY) / 4,
              getDrawingHorizontalLine: (_) => const FlLine(
                color: ChartTheme.gridLine,
                strokeWidth: 1,
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

/// 涓诲浘妯悜铏氱嚎锛氫笌鍒嗘椂鍥?_CurrentPriceLinePainter 涓€鑷达紝鐜颁环绾夸粠宸﹀埌鍙宠疮绌匡紝杩炴帴宸︿晶浠锋牸涓庡彸渚ф定骞?
class _ReferenceLinePainter extends CustomPainter {
  _ReferenceLinePainter({
    required this.refPrice,
    required this.minY,
    required this.maxY,
    required this.color,
  });

  final double refPrice;
  final double minY;
  final double maxY;
  final Color color;

  static const _pad = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rangeY = (maxY - minY).clamp(0.01, double.infinity);
    final chartH = size.height - _pad * 2;
    // 涓?_CandlestickPainter 鍚屼竴鍧愭爣绯伙細pad + chartH - (v-minY)/range*chartH
    final y = _pad + chartH * (maxY - refPrice) / rangeY;
    if (y.isNaN || y < 0 || y > size.height) return;
    const dashLen = 4.0;
    const gapLen = 3.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    var x = 0.0;
    while (x < size.width) {
      final endX = (x + dashLen).clamp(0.0, size.width);
      if (endX > x) canvas.drawLine(Offset(x, y), Offset(endX, y), paint);
      x += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _ReferenceLinePainter old) =>
      old.refPrice != refPrice || old.minY != minY || old.maxY != maxY || old.color != color;
}

/// 鍙充晶棰勭暀鐨?K 绾跨┖浣嶆暟锛岀暀鍑虹┖闂磋娑ㄥ箙/姣斾緥鏁板瓧瀹屾暣鏄剧ず锛岄伩鍏嶈鎴柇
const int _kRightReservedCandleSlots = 4;

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
    final totalSlots = n + _kRightReservedCandleSlots;
    final slotWidth = chartW / totalSlots;
    final candleW = (slotWidth * 0.85).clamp(2.0, 20.0);
    final yMin = pad;
    final yMax = pad + chartH;
    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final isUp = c.close >= c.open;
      final color = isUp ? ChartTheme.up : ChartTheme.down;
      final x = pad + (i + 0.5) * slotWidth;
      var yHigh = pad + chartH - (c.high - minY) / rangeY * chartH;
      var yLow = pad + chartH - (c.low - minY) / rangeY * chartH;
      var yOpen = pad + chartH - (c.open - minY) / rangeY * chartH;
      var yClose = pad + chartH - (c.close - minY) / rangeY * chartH;
      // 闄愬埗鍦ㄥ浘琛ㄥ尯鍩熷唴锛岄伩鍏嶆瀬绔?K 绾垮奖绾胯秴鍑轰富鍥俱€佷镜鍏?VOL 鍖哄煙
      yHigh = yHigh.clamp(yMin, yMax);
      yLow = yLow.clamp(yMin, yMax);
      yOpen = yOpen.clamp(yMin, yMax);
      yClose = yClose.clamp(yMin, yMax);
      final bodyTop = yOpen < yClose ? yOpen : yClose;
      final bodyBottom = yOpen < yClose ? yClose : yOpen;
      final bodyH = (bodyBottom - bodyTop).clamp(1.0, double.infinity);
      const wickW = 1.2;
      final bodyW = (candleW * 0.72).clamp(3.5, 14.0);

      final isHighlight = highlightIndex != null && i == highlightIndex;
      if (isHighlight) {
        final bandW = (slotWidth * 1.2).clamp(8.0, 32.0);
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
    final totalSlots = n + _kRightReservedCandleSlots;
    final slotWidth = chartW / totalSlots;
    final barW = (slotWidth * 0.85).clamp(1.0, 12.0);
    for (var i = 0; i < n; i++) {
      final v = vols[i];
      if (v <= 0) continue;
      final isUp = candles[i].close >= candles[i].open;
      final color = isUp
          ? ChartTheme.up.withValues(alpha: 0.65)
          : ChartTheme.down.withValues(alpha: 0.65);
      final x = pad + (i + 0.5) * slotWidth - barW / 2;
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
    final totalSlots = n + _kRightReservedCandleSlots;
    final slotWidth = chartW / totalSlots;
    final barW = (slotWidth * 0.85).clamp(1.0, 8.0);

    for (var i = 0; i < n; i++) {
      final h = histogram[i];
      if (h == null) continue;
      final x = pad + (i + 0.5) * slotWidth - barW / 2;
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
      final x = pad + (i + 0.5) * slotWidth;
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
    final totalSlots = n + _kRightReservedCandleSlots;
    final slotWidth = chartW / totalSlots;

    bool first = true;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final v = rsiValues[i];
      if (v == null) continue;
      final x = pad + (i + 0.5) * slotWidth;
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

