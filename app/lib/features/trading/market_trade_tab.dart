import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../market/market_repository.dart';

/// 行情与交易 Tab：整体行情（Polygon）→ 搜索标的 → 行情区 → 买入/卖出
class MarketTradeTab extends StatefulWidget {
  const MarketTradeTab({super.key, required this.teacherId});

  final String teacherId;

  @override
  State<MarketTradeTab> createState() => _MarketTradeTabState();
}

/// 行情展示用（仅来自 Polygon getLastTrade；涨跌幅为 null 时显示 --）
class _MarketQuote {
  const _MarketQuote({required this.symbol, required this.current, this.percentChange});
  final String symbol;
  final double current;
  final double? percentChange;
}

/// 整体行情预设标的
const _overallSymbols = ['AAPL', 'MSFT', 'GOOGL', 'AMZN', 'TSLA'];
const _overallNames = {'AAPL': '苹果', 'MSFT': '微软', 'GOOGL': '谷歌', 'AMZN': '亚马逊', 'TSLA': '特斯拉'};

class _MarketTradeTabState extends State<MarketTradeTab> {
  static const Color _accent = Color(0xFFD4AF37);
  static const Color _bg = Color(0xFF111215);
  static const Color _muted = Color(0xFF6C6F77);
  static const Color _surface = Color(0xFF1A1C21);

  final _searchController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController();
  final _market = MarketRepository();

  /// 整体行情：symbol -> quote（仅 Polygon 数据）
  Map<String, _MarketQuote?> _overallQuotes = {};
  bool _loadingOverall = false;

  String? _selectedSymbol;
  String? _selectedName;
  double? _currentPrice;
  double? _changePercent;
  int? _volume; // 实时累计成交量（WebSocket 推送累加）
  bool _loadingSearch = false;

  bool _orderTypeLimit = true;

  Timer? _refreshTimer;
  Timer? _chartRefreshTimer;
  List<ChartCandle> _candles = [];
  bool _chartKLine = false;
  DateTime? _lastUpdate;

  List<PolygonGainer> _gainers = [];
  bool _loadingGainers = false;

  PolygonRealtime? _realtime;
  StreamSubscription<PolygonTradeUpdate>? _realtimeSub;

  /// 整体行情多标的 WebSocket，有成交即更新价格与「更新时间」
  PolygonRealtimeMulti? _overallRealtime;
  StreamSubscription<PolygonTradeUpdate>? _overallRealtimeSub;

  @override
  void initState() {
    super.initState();
    _applyCachedDataThenLoad();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _loadGainers();
      if (_selectedSymbol != null && _market.polygonAvailable) _refreshSelectedQuote();
    });
  }

  /// 先展示本地缓存（秒出），再请求网络更新
  Future<void> _applyCachedDataThenLoad() async {
    if (!_market.polygonAvailable) return;
    final cachedGainers = await _market.getCachedGainers();
    if (!mounted) return;
    if (cachedGainers != null && cachedGainers.isNotEmpty) {
      setState(() {
        _gainers = cachedGainers;
        _lastUpdate = DateTime.now();
      });
    }
    _loadGainers();
  }

  void _startOverallRealtime() {
    if (!_market.polygonAvailable) return;
    _overallRealtimeSub?.cancel();
    _overallRealtime?.dispose();
    _overallRealtime = _market.openRealtimeMulti(_overallSymbols);
    if (_overallRealtime == null) return;
    _overallRealtime!.connect();
    _overallRealtimeSub = _overallRealtime!.stream.listen((update) {
      if (!mounted || update.symbol == null) return;
      final sym = update.symbol!;
      setState(() {
        final existing = _overallQuotes[sym];
        _overallQuotes = Map.from(_overallQuotes);
        _overallQuotes[sym] = _MarketQuote(
          symbol: sym,
          current: update.price,
          percentChange: existing?.percentChange,
        );
        _lastUpdate = DateTime.now();
      });
    });
  }

  Future<void> _loadGainers() async {
    if (!_market.polygonAvailable) return;
    if (_loadingGainers) return;
    setState(() => _loadingGainers = true);
    try {
      final list = await _market.getTopGainers(limit: 10);
      if (mounted) setState(() {
        _gainers = list;
        _loadingGainers = false;
        _lastUpdate = DateTime.now();
      });
    } catch (_) {
      if (mounted) setState(() {
        _loadingGainers = false;
        _lastUpdate = DateTime.now();
      });
    }
  }

  void _startRealtime(String symbol) {
    _realtimeSub?.cancel();
    _realtime?.dispose();
    _realtime = _market.openRealtime(symbol);
    if (_realtime == null) return;
    _realtime!.connect();
    _realtimeSub = _realtime!.stream.listen((update) {
      if (!mounted) return;
      setState(() {
        _currentPrice = update.price;
        _volume = (_volume ?? 0) + update.size;
      });
    });
  }

  Future<void> _refreshSelectedQuote() async {
    if (_selectedSymbol == null) return;
    final sym = _selectedSymbol!;
    final quote = await _market.getQuote(sym);
    if (quote.hasError || !mounted) return;
    if (mounted) setState(() {
      _currentPrice = quote.price;
      _changePercent = quote.changePercent;
    });
  }

  bool _chartLoading = false;

  Future<void> _loadCandles() async {
    if (_selectedSymbol == null) return;
    setState(() => _chartLoading = true);
    final sym = _selectedSymbol!;
    List<ChartCandle> list = [];
    final now = DateTime.now();
    if (_market.polygonAvailable) {
      final toMs = now.millisecondsSinceEpoch;
      if (_chartKLine) {
        final fromMs = toMs - 30 * 24 * 3600 * 1000;
        list = await _market.getAggregates(sym, multiplier: 1, timespan: 'day', fromMs: fromMs, toMs: toMs);
      } else {
        final fromMs = toMs - 6 * 3600 * 1000;
        list = await _market.getAggregates(sym, multiplier: 1, timespan: 'minute', fromMs: fromMs, toMs: toMs);
      }
    }
    if (mounted) {
      setState(() {
        _candles = list;
        _chartLoading = false;
      });
      _scheduleChartRefresh();
    }
  }

  void _scheduleChartRefresh() {
    _chartRefreshTimer?.cancel();
    if (_selectedSymbol == null) return;
    final dur = _chartKLine ? const Duration(minutes: 5) : const Duration(minutes: 1);
    _chartRefreshTimer = Timer(dur, () {
      if (mounted && _selectedSymbol != null) _loadCandles();
    });
  }

  static String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _chartRefreshTimer?.cancel();
    _overallRealtimeSub?.cancel();
    _overallRealtime?.dispose();
    _realtimeSub?.cancel();
    _realtime?.dispose();
    _searchController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _loadOverallMarket() async {
    if (!_market.polygonAvailable) return;
    final isFirstLoad = _overallQuotes.isEmpty;
    if (isFirstLoad) setState(() => _loadingOverall = true);
    try {
      final quotes = await _market.getQuotes(_overallSymbols);
      if (!mounted) return;
      final merged = <String, _MarketQuote?>{};
      for (final sym in _overallSymbols) {
        final q = quotes[sym];
        merged[sym] = (q != null && !q.hasError) ? _MarketQuote(symbol: sym, current: q.price, percentChange: q.changePercent) : null;
      }
      if (mounted) setState(() {
        _overallQuotes = merged;
        _loadingOverall = false;
        _lastUpdate = DateTime.now();
      });
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('_loadOverallMarket error: $e\n$st');
      }
      if (mounted) {
        setState(() {
          _loadingOverall = false;
          _lastUpdate = DateTime.now(); // 失败也推进更新时间，让用户看到在尝试
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('行情刷新失败: ${e.toString().replaceAll(RegExp(r'^Exception:\s*'), '')}')),
        );
      }
    }
  }

  Future<void> _onSearch() async {
    final text = _searchController.text.trim();
    if (text.isEmpty) return;
    final symbol = text.toUpperCase();
    setState(() {
      _selectedSymbol = symbol;
      _selectedName = text;
      _loadingSearch = true;
    });
    double? price;
    double? percentChange;
    final quote = await _market.getQuote(symbol);
    if (!quote.hasError) {
      price = quote.price > 0 ? quote.price : null;
      percentChange = quote.changePercent;
    }
    if (mounted) {
      setState(() {
        _loadingSearch = false;
        _currentPrice = price ?? (!_market.polygonAvailable ? 100.0 : null);
        _changePercent = percentChange;
        _volume = 0;
        if (_currentPrice != null) _priceController.text = _currentPrice!.toStringAsFixed(2);
        _candles = [];
        _chartLoading = true;
      });
      _startRealtime(symbol);
      _loadCandles();
    }
  }

  void _openOrderSheet(bool isBuy) {
    if (_selectedSymbol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先搜索并选择标的')),
      );
      return;
    }
    _priceController.text =
        (_currentPrice ?? 0).toStringAsFixed(2);
    _qtyController.text = '100';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _OrderSheet(
          symbol: _selectedSymbol!,
          symbolName: _selectedName,
          isBuy: isBuy,
          defaultPrice: _currentPrice ?? 0,
          orderTypeLimit: _orderTypeLimit,
          priceController: _priceController,
          qtyController: _qtyController,
          onOrderTypeChanged: (limit) => setState(() => _orderTypeLimit = limit),
          onSubmit: () {
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${isBuy ? "买入" : "卖出"} ${_selectedSymbol} 已提交（模拟，接口待接入）',
                ),
              ),
            );
          },
          onCancel: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadGainers,
      color: _accent,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        children: [
          _buildSearchSection(),
          const SizedBox(height: 12),
          _buildGainersStrip(),
          const SizedBox(height: 14),
          if (_selectedSymbol != null) _buildSelectedSymbolCard() else _buildPlaceholderCard(),
          const SizedBox(height: 12),
          _buildBuySellButtons(),
        ],
      ),
    );
  }

  /// 选中标的后的主卡：大号价格 + 涨跌幅/成交量 + 分时K线 + 买卖
  Widget _buildSelectedSymbolCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.35), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _selectedSymbol!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: 0.5,
                ),
              ),
              if (_selectedName != null && _selectedName != _selectedSymbol) ...[
                const SizedBox(width: 6),
                Text(
                  _selectedName!,
                  style: TextStyle(color: _muted, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _currentPrice != null ? _currentPrice!.toStringAsFixed(2) : '--',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 28,
                ),
              ),
              const SizedBox(width: 12),
              if (_changePercent != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_changePercent! >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_changePercent! >= 0 ? "+" : ""}${_changePercent!.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: _changePercent! >= 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
            ],
          ),
          if (_volume != null && _volume! > 0) ...[
            const SizedBox(height: 6),
            Text('成交量 $_volume', style: TextStyle(color: _muted, fontSize: 11)),
          ],
          const SizedBox(height: 12),
          _buildChartSection(inCard: true),
        ],
      ),
    );
  }

  /// 未选中标的时的占位卡
  Widget _buildPlaceholderCard() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _muted.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(
          children: [
            Icon(Icons.touch_app_rounded, color: _muted.withValues(alpha: 0.6), size: 40),
            const SizedBox(height: 12),
            Text(
              '选择上方涨幅榜或搜索标的',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '查看实时行情与图表',
              style: TextStyle(color: _muted.withValues(alpha: 0.8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// 涨幅榜：横向滚动条，参考交易软件「热门」区
  Widget _buildGainersStrip() {
    final hasApi = _market.polygonAvailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.trending_up, color: _accent, size: 18),
            const SizedBox(width: 6),
            Text('涨幅榜', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            if (hasApi && _loadingGainers)
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
            else if (_lastUpdate != null)
              Text('更新 ${_formatTime(_lastUpdate!)}', style: TextStyle(color: _muted, fontSize: 10)),
          ],
        ),
        if (!hasApi)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('请配置 POLYGON_API_KEY', style: TextStyle(fontSize: 11, color: _muted)),
          )
        else if (_gainers.isEmpty && !_loadingGainers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Text('暂无数据', style: TextStyle(color: _muted, fontSize: 12))),
          )
        else ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _gainers.length,
              itemBuilder: (context, i) {
                final g = _gainers[i];
                final isUp = g.todaysChangePerc >= 0;
                final isSelected = _selectedSymbol == g.ticker;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Material(
                    color: isSelected ? _accent.withValues(alpha: 0.2) : _surface,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedSymbol = g.ticker;
                          _selectedName = g.ticker;
                          _currentPrice = g.price;
                          _changePercent = g.todaysChangePerc;
                          _volume = 0;
                          _priceController.text = (g.price ?? 0).toStringAsFixed(2);
                          _candles = [];
                          _chartLoading = true;
                        });
                        _startRealtime(g.ticker);
                        _loadCandles();
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: const BoxConstraints(minWidth: 100),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              g.ticker,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: isSelected ? _accent : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  '${isUp ? "+" : ""}${g.todaysChangePerc.toStringAsFixed(2)}%',
                                  style: TextStyle(
                                    color: isUp ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (g.price != null)
                                  Text(
                                    g.price!.toStringAsFixed(2),
                                    style: TextStyle(color: _muted, fontSize: 11),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '股票代码或名称',
                hintStyle: TextStyle(color: _muted, fontSize: 12),
                prefixIcon: Icon(Icons.search_rounded, color: _muted, size: 18),
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              onSubmitted: (_) => _onSearch(),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _accent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: _loadingSearch ? null : _onSearch,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                alignment: Alignment.center,
                child: _loadingSearch
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _bg),
                      )
                    : const Text('搜索', style: TextStyle(
                        color: Color(0xFF111215),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      )),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection({bool inCard = false}) {
    final chartHeight = inCard ? 200.0 : 160.0;
    final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('分时', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: true, label: Text('K线', style: TextStyle(fontSize: 11))),
                ],
                selected: {_chartKLine},
                onSelectionChanged: (s) {
                  setState(() => _chartKLine = s.first);
                  _loadCandles();
                },
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: chartHeight,
            child: _chartLoading
                ? Center(
                    child: Text(
                      '加载中…',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  )
                : _candles.isEmpty
                    ? Center(
                        child: Text(
                          '暂无图表数据',
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      )
                    : _chartKLine
                        ? _buildCandlestickChart()
                        : _buildLineChart(),
          ),
        ],
      );
    if (inCard) return content;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: content,
    );
  }

  /// 分时：折线图（收盘价连线 + 下方填充），末端接实时价随 WebSocket 跳动，Y 轴显示价格数字
  Widget _buildLineChart() {
    if (_candles.isEmpty && _currentPrice == null) return const SizedBox.shrink();
    final closes = _candles.map((c) => c.close).toList();
    double minY = closes.isEmpty ? (_currentPrice ?? 0) : closes.reduce((a, b) => a < b ? a : b);
    double maxY = closes.isEmpty ? (_currentPrice ?? 0) : closes.reduce((a, b) => a > b ? a : b);
    if (_currentPrice != null) {
      if (_currentPrice! < minY) minY = _currentPrice!;
      if (_currentPrice! > maxY) maxY = _currentPrice!;
    }
    final range = (maxY - minY).clamp(0.01, double.infinity);
    final minYPlot = minY - range * 0.05;
    final maxYPlot = maxY + range * 0.05;

    final spots = <FlSpot>[];
    for (var i = 0; i < _candles.length; i++) {
      spots.add(FlSpot(i.toDouble(), _candles[i].close));
    }
    // 分时末端接实时价，随 WebSocket 更新而跳动
    if (_currentPrice != null) {
      final lastX = _candles.isEmpty ? 0.0 : (_candles.length - 1).toDouble();
      spots.add(FlSpot(lastX + 1, _currentPrice!));
    }
    if (spots.isEmpty) return const SizedBox.shrink();

    final lastClose = _candles.isNotEmpty ? _candles.last.close : _currentPrice;
    final firstOpen = _candles.isNotEmpty ? _candles.first.open : _currentPrice;
    final lineColor = (lastClose ?? firstOpen ?? 0) >= (firstOpen ?? lastClose ?? 0) ? Colors.green : Colors.red;

    final maxX = spots.length <= 1 ? 1.0 : (spots.length - 1).toDouble();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minYPlot,
        maxY: maxYPlot,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: lineColor,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withValues(alpha: 0.15),
            ),
          ),
        ],
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          show: true,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: range > 0 ? (range / 4).clamp(0.01, double.infinity) : 1,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    value.toStringAsFixed(2),
                    style: TextStyle(color: _muted, fontSize: 10),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
      ),
      duration: const Duration(milliseconds: 150),
    );
  }

  /// K线：蜡烛图（CustomPainter 绘制影线 + 实体）
  Widget _buildCandlestickChart() {
    if (_candles.isEmpty) return const SizedBox.shrink();
    double minY = _candles.first.low;
    double maxY = _candles.first.high;
    for (final c in _candles) {
      if (c.low < minY) minY = c.low;
      if (c.high > maxY) maxY = c.high;
    }
    final range = (maxY - minY).clamp(0.01, double.infinity);
    minY = minY - range * 0.02;
    maxY = maxY + range * 0.02;
    return CustomPaint(
      size: const Size(double.infinity, 160),
      painter: _CandlestickPainter(
        candles: _candles,
        minY: minY,
        maxY: maxY,
      ),
    );
  }

  Widget _priceChip(String label, String value, bool? isUp) {
    Color? valueColor;
    if (isUp != null) valueColor = isUp ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: _muted, fontSize: 10)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuySellButtons() {
    final enabled = _selectedSymbol != null;
    return Row(
      children: [
        Expanded(
          child: Material(
            color: enabled ? const Color(0xFF2E7D32) : _muted.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: enabled ? () => _openOrderSheet(true) : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_upward_rounded, color: enabled ? Colors.white : _muted, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '买入',
                      style: TextStyle(
                        color: enabled ? Colors.white : _muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Material(
            color: enabled ? const Color(0xFFC62828) : _muted.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: enabled ? () => _openOrderSheet(false) : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_downward_rounded, color: enabled ? Colors.white : _muted, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '卖出',
                      style: TextStyle(
                        color: enabled ? Colors.white : _muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 下单弹窗内容：价格、数量、市价/限价
class _OrderSheet extends StatefulWidget {
  const _OrderSheet({
    required this.symbol,
    this.symbolName,
    required this.isBuy,
    required this.defaultPrice,
    required this.orderTypeLimit,
    required this.priceController,
    required this.qtyController,
    required this.onOrderTypeChanged,
    required this.onSubmit,
    required this.onCancel,
  });

  final String symbol;
  final String? symbolName;
  final bool isBuy;
  final double defaultPrice;
  final bool orderTypeLimit;
  final TextEditingController priceController;
  final TextEditingController qtyController;
  final ValueChanged<bool> onOrderTypeChanged;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);
  static const Color _bg = Color(0xFF111215);

  late bool _orderTypeLimit;

  @override
  void initState() {
    super.initState();
    _orderTypeLimit = widget.orderTypeLimit;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.isBuy ? "买入" : "卖出"} ${widget.symbol}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('限价')),
                ButtonSegment(value: false, label: Text('市价')),
              ],
              selected: {_orderTypeLimit},
              onSelectionChanged: (s) => setState(() => _orderTypeLimit = s.first),
            ),
            const SizedBox(height: 16),
            if (_orderTypeLimit)
              TextField(
                controller: widget.priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '价格',
                  filled: true,
                  fillColor: _bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            if (_orderTypeLimit) const SizedBox(height: 12),
            TextField(
              controller: widget.qtyController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '数量',
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      final qtyStr = widget.qtyController.text.trim();
                      final qty = double.tryParse(qtyStr);
                      if (qty == null || qty <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入有效数量（大于 0）')),
                        );
                        return;
                      }
                      if (_orderTypeLimit) {
                        final priceStr = widget.priceController.text.trim();
                        final price = double.tryParse(priceStr);
                        if (price == null || price <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('限价单请输入有效价格（大于 0）')),
                          );
                          return;
                        }
                      }
                      widget.onSubmit();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.isBuy ? Colors.green : Colors.red,
                    ),
                    child: Text(widget.isBuy ? '确认买入' : '确认卖出'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// K 线蜡烛图绘制：影线（low-high）+ 实体（open-close）
class _CandlestickPainter extends CustomPainter {
  _CandlestickPainter({
    required this.candles,
    required this.minY,
    required this.maxY,
  });

  final List<ChartCandle> candles;
  final double minY;
  final double maxY;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    final n = candles.length;
    final pad = 4.0;
    final chartW = size.width - pad * 2;
    final chartH = size.height - pad * 2;
    final rangeY = (maxY - minY).clamp(0.01, double.infinity);
    final candleW = (chartW / n).clamp(2.0, 20.0);
    final gap = (chartW - candleW * n) / (n + 1);

    final gridPaint = Paint()
      ..color = const Color(0xFF2A2D34)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    for (var g = 0; g <= 4; g++) {
      final y = pad + chartH * g / 4;
      canvas.drawLine(Offset(pad, y), Offset(size.width - pad, y), gridPaint);
    }

    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final isUp = c.close >= c.open;
      final color = isUp ? Colors.green : Colors.red;
      final x = pad + gap + (gap + candleW) * i + candleW / 2;
      final yHigh = pad + chartH - (c.high - minY) / rangeY * chartH;
      final yLow = pad + chartH - (c.low - minY) / rangeY * chartH;
      final yOpen = pad + chartH - (c.open - minY) / rangeY * chartH;
      final yClose = pad + chartH - (c.close - minY) / rangeY * chartH;
      final bodyTop = yOpen < yClose ? yOpen : yClose;
      final bodyBottom = yOpen < yClose ? yClose : yOpen;
      final bodyH = (bodyBottom - bodyTop).clamp(1.0, double.infinity);
      final wickW = 1.0;
      final bodyW = (candleW * 0.7).clamp(3.0, 14.0);

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
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter old) {
    return old.candles != candles || old.minY != minY || old.maxY != maxY;
  }
}
