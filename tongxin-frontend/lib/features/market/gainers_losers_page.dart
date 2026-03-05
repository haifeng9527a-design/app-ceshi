import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../trading/realtime_quote_service.dart';
import 'market_colors.dart';
import 'market_repository.dart';
import 'stock_chart_page.dart';

/// 涨跌榜：Gainers / Losers 两个 Tab，表格展示代码/名称/涨跌幅/最新价/涨跌额/今开/昨收/最高/最低/成交量，底部三大指数
class GainersLosersPage extends StatefulWidget {
  const GainersLosersPage({super.key});

  @override
  State<GainersLosersPage> createState() => _GainersLosersPageState();
}

class _GainersLosersPageState extends State<GainersLosersPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final _market = MarketRepository();
  final _realtime = RealtimeQuoteService();
  StreamSubscription<List<PolygonGainer>>? _gainersSub;
  StreamSubscription<List<PolygonGainer>>? _losersSub;

  List<PolygonGainer> _gainers = [];
  List<PolygonGainer> _losers = [];
  Map<String, MarketQuote> _indexQuotes = {};
  bool _loadingGainers = true;
  bool _loadingLosers = true;
  String? _errorGainers;
  String? _errorLosers;
  /// 排序列：code/name/pct/price/change/open/prev/high/low/vol；默认涨跌幅
  String _sortColumn = 'pct';
  bool _sortAscending = false;
  static const _latestRefreshInterval = Duration(seconds: 15);
  Timer? _latestRefreshTimer;
  bool _refreshingLatest = false;

  static const _bg = Color(0xFF0B0C0E);
  static const _surface = Color(0xFF111215);
  static const _accent = Color(0xFFD4AF37);
  static const _muted = Color(0xFF9CA3AF);
  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _indexSymbols = ['DJI', 'IXIC', 'SPX'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _gainersSub = _realtime.gainersStream.listen((list) {
      if (mounted) setState(() => _gainers = list);
    });
    _losersSub = _realtime.losersStream.listen((list) {
      if (mounted) setState(() => _losers = list);
    });
    _loadGainers();
    _loadLosers();
    _loadIndices();
    _startLatestRefreshTimer();
  }

  Future<void> _loadIndices() async {
    try {
      final q = await _market.getQuotes(_indexSymbols);
      if (mounted) setState(() => _indexQuotes = q);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _latestRefreshTimer?.cancel();
    _gainersSub?.cancel();
    _losersSub?.cancel();
    _realtime.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLatestData();
    }
  }

  void _startLatestRefreshTimer() {
    _latestRefreshTimer?.cancel();
    _latestRefreshTimer = Timer.periodic(_latestRefreshInterval, (_) {
      _refreshLatestData();
    });
  }

  Future<void> _refreshLatestData() async {
    if (!mounted || _refreshingLatest) return;
    _refreshingLatest = true;
    try {
      await Future.wait([
        _loadIndices(),
        _loadGainers(),
        _loadLosers(),
      ]);
    } finally {
      _refreshingLatest = false;
    }
  }

  Future<void> _loadGainers() async {
    setState(() {
      _loadingGainers = true;
      _errorGainers = null;
    });
    try {
      final list = await _market.getTopGainers(limit: 50);
      if (!mounted) return;
      setState(() {
        _gainers = list;
        _loadingGainers = false;
      });
      _realtime.setGainersLosers(gainers: list, losers: _losers);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorGainers = e.toString();
        _loadingGainers = false;
      });
    }
  }

  Future<void> _loadLosers() async {
    setState(() {
      _loadingLosers = true;
      _errorLosers = null;
    });
    try {
      final list = await _market.getTopLosers(limit: 50);
      if (!mounted) return;
      setState(() {
        _losers = list;
        _loadingLosers = false;
      });
      _realtime.setGainersLosers(gainers: _gainers, losers: list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorLosers = e.toString();
        _loadingLosers = false;
      });
    }
  }

  List<PolygonGainer> _sortedList(List<PolygonGainer> list) {
    if (list.isEmpty) return list;
    final sorted = List<PolygonGainer>.from(list);
    final asc = _sortAscending ? 1 : -1;
    sorted.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
        case 'code':
        case 'name':
          cmp = a.ticker.compareTo(b.ticker);
          break;
        case 'pct':
          cmp = (a.todaysChangePerc - b.todaysChangePerc).sign.toInt();
          break;
        case 'price':
          final pa = (a.price != null && a.price! > 0) ? a.price! : (a.prevClose != null ? a.prevClose! + a.todaysChange : 0.0);
          final pb = (b.price != null && b.price! > 0) ? b.price! : (b.prevClose != null ? b.prevClose! + b.todaysChange : 0.0);
          cmp = (pa - pb).sign.toInt();
          break;
        case 'change':
          cmp = (a.todaysChange - b.todaysChange).sign.toInt();
          break;
        case 'open':
          cmp = ((a.dayOpen ?? 0) - (b.dayOpen ?? 0)).sign.toInt();
          break;
        case 'prev':
          cmp = ((a.prevClose ?? 0) - (b.prevClose ?? 0)).sign.toInt();
          break;
        case 'high':
          cmp = ((a.dayHigh ?? 0) - (b.dayHigh ?? 0)).sign.toInt();
          break;
        case 'low':
          cmp = ((a.dayLow ?? 0) - (b.dayLow ?? 0)).sign.toInt();
          break;
        case 'vol':
          cmp = ((a.dayVolume ?? 0) - (b.dayVolume ?? 0)).sign.toInt();
          break;
        default:
          cmp = (a.todaysChangePerc - b.todaysChangePerc).sign.toInt();
      }
      return cmp * asc;
    });
    return sorted;
  }

  void _onSortTap(String col) {
    setState(() {
      if (_sortColumn == col) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = col;
        _sortAscending = col == 'code' || col == 'name' || col == 'vol';
      }
    });
  }

  void _openChart(PolygonGainer g, {required List<PolygonGainer> list}) {
    final symbols = list.map((e) => e.ticker).toList();
    final idx = list.indexWhere((e) => e.ticker == g.ticker);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StockChartPage(
          symbol: g.ticker,
          initialSnapshot: g,
          symbolList: symbols,
          symbolIndex: idx >= 0 ? idx : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.marketGainersLosersTitle,
          style: TextStyle(
            color: Color(0xFFE8D5A3),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFE8D5A3)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _accent,
          unselectedLabelColor: _muted,
          indicatorColor: _accent,
          tabs: const [
            Tab(text: 'Gainers'),
            Tab(text: 'Losers'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTable(
                  list: _gainers,
                  loading: _loadingGainers,
                  error: _errorGainers,
                  isGainers: true,
                  onRefresh: _loadGainers,
                ),
                _buildTable(
                  list: _losers,
                  loading: _loadingLosers,
                  error: _errorLosers,
                  isGainers: false,
                  onRefresh: _loadLosers,
                ),
              ],
            ),
          ),
          _buildIndicesBar(),
        ],
      ),
    );
  }

  static String _formatPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 100) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  static String _formatVolume(int? v) {
    if (v == null || v <= 0) return '—';
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(2)}亿';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(2)}万';
    return v.toString();
  }

  Widget _buildIndicesBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: const Color(0xFF1F1F23), width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text(AppLocalizations.of(context)!.marketThreeIndicesLabel, style: const TextStyle(color: Color(0xFF6B6B70), fontSize: 12)),
            ...List.generate(3, (i) {
              final sym = _indexSymbols[i];
              final l10n = AppLocalizations.of(context)!;
              final name = switch (i) {
                0 => l10n.marketIndexDow,
                1 => l10n.marketIndexNasdaq,
                _ => l10n.marketIndexSp500,
              };
              final q = _indexQuotes[sym];
              final hasError = q?.hasError ?? true;
              final isUp = (q?.changePercent ?? 0) >= 0;
              final color = MarketColors.forUp(isUp);
              return Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$name ', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                    Text(
                      hasError ? '—' : (q != null && q.price > 0 ? _formatPrice(q.price) : '—'),
                      style: TextStyle(color: hasError ? _muted : Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (!hasError && q != null && q.price > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${q.change >= 0 ? '+' : ''}${q.change.toStringAsFixed(2)} ${q.changePercent >= 0 ? '+' : ''}${q.changePercent.toStringAsFixed(2)}%',
                        style: TextStyle(color: color, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTable({
    required List<PolygonGainer> list,
    required bool loading,
    required String? error,
    required bool isGainers,
    required Future<void> Function() onRefresh,
  }) {
    if (loading && list.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
    }
    if (error != null && list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Color(0xFF6B6B70)),
              const SizedBox(height: 16),
              Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 20),
                label: Text(AppLocalizations.of(context)!.commonRetry),
                style: TextButton.styleFrom(foregroundColor: _accent),
              ),
            ],
          ),
        ),
      );
    }
    if (list.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context)!.marketNoData, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)));
    }

    const colCode = 64.0;
    const colName = 72.0;
    const colPct = 68.0;
    const colPrice = 68.0;
    const colChange = 60.0;
    const colOpen = 60.0;
    const colPrev = 60.0;
    const colHigh = 60.0;
    const colLow = 60.0;
    const colVol = 72.0;
    const styleLabel = TextStyle(color: Color(0xFF6B6B70), fontSize: 11, fontWeight: FontWeight.w600);

    Widget sortHeader(String label, String col, double w) {
      final isActive = _sortColumn == col;
      return SizedBox(
        width: w,
        child: GestureDetector(
          onTap: () => _onSortTap(col),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: styleLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (isActive) Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(_sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 16, color: _accent),
              ),
            ],
          ),
        ),
      );
    }
    final headerRow = Row(
      children: [
        sortHeader(AppLocalizations.of(context)!.marketCode, 'code', colCode),
        sortHeader(AppLocalizations.of(context)!.marketNameLabel, 'name', colName),
        sortHeader(AppLocalizations.of(context)!.tradingChangePct, 'pct', colPct),
        sortHeader(AppLocalizations.of(context)!.marketLatestPrice, 'price', colPrice),
        sortHeader(AppLocalizations.of(context)!.marketChange, 'change', colChange),
        sortHeader(AppLocalizations.of(context)!.marketOpen, 'open', colOpen),
        sortHeader(AppLocalizations.of(context)!.marketPrevClose, 'prev', colPrev),
        sortHeader(AppLocalizations.of(context)!.marketHigh, 'high', colHigh),
        sortHeader(AppLocalizations.of(context)!.marketLow, 'low', colLow),
        sortHeader(AppLocalizations.of(context)!.marketVolume, 'vol', colVol),
      ],
    );

    final sortedList = _sortedList(list);
    final isPc = MediaQuery.sizeOf(context).width >= 1100;
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: _accent,
      child: ListView(
        padding: isPc ? const EdgeInsets.symmetric(vertical: 12) : const EdgeInsets.fromLTRB(16, 12, 16, 12),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1C21),
                    border: Border(bottom: BorderSide(color: const Color(0xFF1F1F23), width: 0.6)),
                  ),
                  child: headerRow,
                ),
                ...sortedList.map((g) {
                  final color = MarketColors.forChangePercent(g.todaysChangePerc);
                  final effectivePrice = (g.price != null && g.price! > 0)
                      ? g.price!
                      : (g.prevClose != null ? g.prevClose! + g.todaysChange : null);
                  return Material(
                    color: _surface,
                    child: InkWell(
                      onTap: () => _openChart(g, list: sortedList),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFF1F1F23), width: 0.6)),
                        ),
                        child: Row(
                          children: [
                            SizedBox(width: colCode, child: Text(g.ticker, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colName, child: Text(g.ticker, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colPct, child: Text('${g.todaysChangePerc >= 0 ? '+' : ''}${g.todaysChangePerc.toStringAsFixed(2)}%', style: TextStyle(color: color, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colPrice, child: Text(effectivePrice != null && effectivePrice > 0 ? _formatPrice(effectivePrice) : '—', style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colChange, child: Text('${g.todaysChange >= 0 ? '+' : ''}${g.todaysChange.toStringAsFixed(2)}', style: TextStyle(color: color, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colOpen, child: Text(g.dayOpen != null && g.dayOpen! > 0 ? _formatPrice(g.dayOpen!) : '—', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colPrev, child: Text(g.prevClose != null && g.prevClose! > 0 ? _formatPrice(g.prevClose!) : '—', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colHigh, child: Text(g.dayHigh != null && g.dayHigh! > 0 ? _formatPrice(g.dayHigh!) : '—', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colLow, child: Text(g.dayLow != null && g.dayLow! > 0 ? _formatPrice(g.dayLow!) : '—', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colVol, child: Text(_formatVolume(g.dayVolume), style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
