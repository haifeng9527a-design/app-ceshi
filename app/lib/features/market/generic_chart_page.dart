import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'chart_viewport.dart';
import 'chart_viewport_controller.dart';
import 'market_colors.dart';
import 'market_repository.dart';

/// 指数/外汇/加密货币详情：行情 + 分时/K 线（Twelve Data）
class GenericChartPage extends StatefulWidget {
  const GenericChartPage({
    super.key,
    required this.symbol,
    required this.name,
  });

  final String symbol;
  final String name;

  @override
  State<GenericChartPage> createState() => _GenericChartPageState();
}

class _GenericChartPageState extends State<GenericChartPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _market = MarketRepository();

  MarketQuote? _quote;
  List<ChartCandle> _intraday = [];
  List<ChartCandle> _daily = [];
  late final ChartViewportController _dailyController;
  bool _dailyLoadingMore = false;
  int? _lastLoadedEarliestTs;
  String _overlayIndicator = 'ma';
  String _subChartIndicator = 'vol';
  bool _loading = true;
  String? _error;
  bool _statsExpanded = false;

  static const double _tabBarHeight = 46.0;
  static const double _chartScreenRatio = 0.70;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
    _dailyController = ChartViewportController(initialVisibleCount: 80, minVisibleCount: 30, maxVisibleCount: 200);
    _loadCachedThenRefresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedThenRefresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  Future<void> _load() async {
    if (!_market.twelveDataAvailable) {
      if (mounted) setState(() {
        _loading = false;
        _error = _quote == null ? 'TWELVE_DATA_API_KEY 未配置' : null;
      });
      return;
    }
    final sym = widget.symbol.trim();
    final q = await _market.getQuote(sym);
    final intra = await _market.getCandles(sym, '1min');
    final day = await _market.getCandles(sym, '1day');
    if (!mounted) return;
    setState(() {
      _quote = q;
      _intraday = intra;
      _daily = day;
      _lastLoadedEarliestTs = null;
      _dailyController.initFromCandlesLength(day.length);
      _loading = false;
    });
  }

  Future<void> _loadDailyOlder(int earliestTimestampMs) async {
    if (_dailyLoadingMore) return;
    if (_lastLoadedEarliestTs != null && earliestTimestampMs >= _lastLoadedEarliestTs!) return;
    setState(() => _dailyLoadingMore = true);
    try {
      final beforeLen = _daily.length;
      final earliestTsBefore = beforeLen > 0 ? (_daily.first.time * 1000).round() : null;
      final list = await _market.getCandlesOlderThan(
        widget.symbol,
        '1day',
        olderThanMs: earliestTimestampMs,
        limit: 300,
      );
      if (!mounted) return;
      if (list.isNotEmpty) {
        final merged = MarketRepository.mergeAndDedupeCandles(list, _daily);
        final afterLen = merged.length;
        final newCandlesLen = afterLen - beforeLen;
        final earliestTsAfter = afterLen > 0 ? (merged.first.time * 1000).round() : null;
        if (kDebugMode) {
          debugPrint('[Daily loadMore] beforeLen=$beforeLen afterLen=$afterLen earliestTsBefore=$earliestTsBefore earliestTsAfter=$earliestTsAfter newCandlesLen=$newCandlesLen');
        }
        setState(() {
          _daily = merged;
          _dailyController.addStartOffset(newCandlesLen);
          _lastLoadedEarliestTs = earliestTimestampMs;
        });
      }
    } finally {
      if (mounted) setState(() => _dailyLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final chartBlockHeight = screenHeight * _chartScreenRatio;
    final chartContentHeight = (chartBlockHeight - _tabBarHeight).clamp(120.0, double.infinity);
    final chartHeight = chartContentHeight * (220 / 298);
    final volumeHeight = chartContentHeight * (56 / 298);
    final timeAxisHeight = chartContentHeight * (22 / 298);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0C0E),
        foregroundColor: const Color(0xFFD4AF37),
        elevation: 0,
        title: _buildTradingViewHeader(),
      ),
      body: Column(
        children: [
          SizedBox(
            height: chartBlockHeight,
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFFD4AF37),
                  unselectedLabelColor: const Color(0xFF9CA3AF),
                  indicatorColor: const Color(0xFFD4AF37),
                  tabAlignment: TabAlignment.center,
                  tabs: const [
                    Tab(text: '分时'),
                    Tab(text: 'K线'),
                  ],
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                      : _error != null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!, style: const TextStyle(color: Color(0xFF9CA3AF))),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _load,
                                    child: const Text('重试'),
                                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFD4AF37)),
                                  ),
                                ],
                              ),
                            )
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                _intraday.isEmpty
                                    ? const Center(child: Text('暂无分时数据', style: TextStyle(color: Color(0xFF9CA3AF))))
                                    : _buildLineChart(_intraday),
                                _daily.isEmpty
                                    ? const Center(child: Text('暂无K线数据', style: TextStyle(color: Color(0xFF9CA3AF))))
                                    : Stack(
                                        children: [
                                          ChartViewport(
                                            controller: _dailyController,
                                            candles: _daily,
                                            onLoadMoreHistory: _loadDailyOlder,
                                            isLoadingMore: _dailyLoadingMore,
                                            chartHeight: chartHeight,
                                            volumeHeight: volumeHeight,
                                            timeAxisHeight: timeAxisHeight,
                                            overlayIndicator: _overlayIndicator,
                                            subChartIndicator: _subChartIndicator,
                                          ),
                                          ListenableBuilder(
                                            listenable: _dailyController,
                                            builder: (_, __) {
                                              final atRealtime = _dailyController.isAtRealtime(_daily.length);
                                              if (atRealtime) return const SizedBox.shrink();
                                              return Positioned(
                                                right: 12,
                                                bottom: 12,
                                                child: Material(
                                                  color: const Color(0xFF1A1C21),
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: InkWell(
                                                    onTap: () => _dailyController.goToRealtime(_daily.length),
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: const Padding(
                                                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                      child: Text(
                                                        'Go to realtime',
                                                        style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.w600),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                              ],
                            ),
                ),
              ],
            ),
          ),
          if (_tabController.index == 1) _buildIndicatorSelector(),
          Expanded(child: _buildStatsExpansion()),
        ],
      ),
    );
  }

  /// 顶部仅：symbol + name、price + change + changePercent
  Widget _buildTradingViewHeader() {
    final q = _quote;
    if (q == null || q.hasError) {
      return Text(
        widget.symbol,
        style: const TextStyle(color: Color(0xFFE8D5A3), fontSize: 16, fontWeight: FontWeight.w700),
      );
    }
    final pctStr = (q.changePercent >= 0 ? '+' : '') + q.changePercent.toStringAsFixed(2) + '%';
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.symbol,
                style: const TextStyle(color: Color(0xFFE8D5A3), fontSize: 16, fontWeight: FontWeight.w700),
              ),
              if (widget.name.isNotEmpty)
                Text(
                  widget.name,
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              q.price > 0 ? _formatPrice(q.price) : '—',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              pctStr,
              style: TextStyle(
                color: MarketColors.forChangePercent(q.changePercent),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsExpansion() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _statsExpanded = !_statsExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text(
                    'Stats',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _statsExpanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF9CA3AF),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_statsExpanded) _buildStatsContent(),
        ],
      ),
    );
  }

  Widget _buildStatsContent() {
    final q = _quote;
    if (q == null || q.hasError) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text(
          q?.errorReason ?? '—',
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('开', q.open),
          _statItem('高', q.high),
          _statItem('低', q.low),
          _statItem('收', q.price),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('量', style: TextStyle(color: Color(0xFF6B6B70), fontSize: 10)),
              const SizedBox(height: 2),
              Text(
                q.volume != null && q.volume! > 0 ? _formatVol(q.volume!) : '—',
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, double? value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF6B6B70), fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value != null && value > 0 ? _formatPrice(value) : '—',
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildIndicatorSelector() {
    const items = [
      ['MA', 'ma', true],
      ['EMA', 'ema', true],
      ['VOL', 'vol', false],
      ['MACD', 'macd', false],
      ['RSI', 'rsi', false],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: items.map((e) {
            final label = e[0] as String;
            final id = e[1] as String;
            final isOverlay = e[2] as bool;
            final selected = isOverlay ? _overlayIndicator == id : _subChartIndicator == id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    if (isOverlay) _overlayIndicator = id;
                    else _subChartIndicator = id;
                  });
                },
                selectedColor: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                checkmarkColor: const Color(0xFFD4AF37),
                labelStyle: TextStyle(
                  color: selected ? const Color(0xFFD4AF37) : const Color(0xFF9CA3AF),
                  fontSize: 12,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _formatPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  String _formatVol(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toString();
  }

  Widget _buildLineChart(List<ChartCandle> candles) {
    if (candles.isEmpty) return const Center(child: Text('暂无数据', style: TextStyle(color: Color(0xFF9CA3AF))));
    final closes = candles.map((c) => c.close).toList();
    double minY = closes.reduce((a, b) => a < b ? a : b);
    double maxY = closes.reduce((a, b) => a > b ? a : b);
    final last = _quote?.price;
    if (last != null) {
      if (last < minY) minY = last;
      if (last > maxY) maxY = last;
    }
    final range = (maxY - minY).clamp(0.01, double.infinity);
    final minYPlot = minY - range * 0.05;
    final maxYPlot = maxY + range * 0.05;
    final spots = <FlSpot>[];
    for (var i = 0; i < candles.length; i++) {
      spots.add(FlSpot(i.toDouble(), candles[i].close));
    }
    if (last != null) {
      spots.add(FlSpot(candles.length.toDouble(), last));
    }
    if (spots.isEmpty) return const SizedBox.shrink();
    final lineColor = (candles.last.close >= candles.first.open)
        ? MarketColors.up
        : MarketColors.down;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: minYPlot,
          maxY: maxYPlot,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: lineColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: lineColor.withOpacity(0.15)),
            ),
          ],
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            show: true,
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: (range / 4).clamp(0.01, double.infinity),
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(value.toStringAsFixed(2), style: const TextStyle(color: Color(0xFF6B6B70), fontSize: 10)),
                ),
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
        ),
        duration: const Duration(milliseconds: 150),
      ),
    );
  }

  Widget _buildCandlestickChart(List<ChartCandle> candles) {
    if (candles.isEmpty) return const Center(child: Text('暂无数据', style: TextStyle(color: Color(0xFF9CA3AF))));
    double minY = candles.first.low;
    double maxY = candles.first.high;
    for (final c in candles) {
      if (c.low < minY) minY = c.low;
      if (c.high > maxY) maxY = c.high;
    }
    final range = (maxY - minY).clamp(0.01, double.infinity);
    minY -= range * 0.02;
    maxY += range * 0.02;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CustomPaint(
        size: Size.infinite,
        painter: _CandlestickPainter(candles: candles, minY: minY, maxY: maxY),
      ),
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  _CandlestickPainter({required this.candles, required this.minY, required this.maxY});
  final List<ChartCandle> candles;
  final double minY;
  final double maxY;

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
    final gridPaint = Paint()..color = const Color(0xFF2A2D34)..strokeWidth = 0.8..style = PaintingStyle.stroke;
    for (var g = 0; g <= 4; g++) {
      final y = pad + chartH * g / 4;
      canvas.drawLine(Offset(pad, y), Offset(size.width - pad, y), gridPaint);
    }
    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final isUp = c.close >= c.open;
      final color = MarketColors.forUp(isUp);
      final x = pad + gap + (gap + candleW) * i + candleW / 2;
      final yHigh = pad + chartH - (c.high - minY) / rangeY * chartH;
      final yLow = pad + chartH - (c.low - minY) / rangeY * chartH;
      final yOpen = pad + chartH - (c.open - minY) / rangeY * chartH;
      final yClose = pad + chartH - (c.close - minY) / rangeY * chartH;
      final bodyTop = yOpen < yClose ? yOpen : yClose;
      final bodyBottom = yOpen < yClose ? yClose : yOpen;
      final bodyH = (bodyBottom - bodyTop).clamp(1.0, double.infinity);
      final bodyW = (candleW * 0.7).clamp(3.0, 14.0);
      final paint = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(x, yHigh), Offset(x, yLow), paint);
      paint.style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, (bodyTop + bodyBottom) / 2), width: bodyW, height: bodyH),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter old) =>
      old.candles != candles || old.minY != minY || old.maxY != maxY;
}
