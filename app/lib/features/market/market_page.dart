import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/pc_dashboard_theme.dart';
import '../trading/market_snapshot_repository.dart';
import '../trading/mock_market_data.dart';
import '../trading/trading_cache.dart';
import 'gainers_losers_page.dart';
import 'generic_chart_page.dart';
import 'market_colors.dart';
import 'market_repository.dart';
import 'quote_row.dart';
import 'search_page.dart';
import 'stock_chart_page.dart';
import 'watchlist_page.dart';
import 'watchlist_repository.dart';

/// 行情页：市场头部、首页/美股/外汇/加密货币、地图概览、环球指数带迷你图、资讯（仅美股与加密货币）
class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  static const _tabs = ['首页', '美股', '外汇', '加密货币'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isPc => MediaQuery.sizeOf(context).width >= 1100;

  @override
  Widget build(BuildContext context) {
    if (_isPc) return _buildPcPage(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0E),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            SizedBox(
              height: 46,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: const Color(0xFFD4AF37),
                unselectedLabelColor: const Color(0xFF9CA3AF),
                indicatorColor: const Color(0xFFD4AF37),
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                tabs: _tabs.map((e) => Tab(text: e)).toList(),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _HomeTab(),
                  _UsStocksTab(),
                  _ForexTab(),
                  _CryptoTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// PC 端：无重复顶栏（Shell 已有「行情」+ 搜索），仅 Tab + 内容，统一 PcDashboardTheme
  Widget _buildPcPage(BuildContext context) {
    return ColoredBox(
      color: PcDashboardTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPcTabBar(context),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _HomeTab(),
                _UsStocksTab(),
                _ForexTab(),
                _CryptoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// PC 端 Tab 栏：安静克制的分段式标签 + 右侧自选入口
  Widget _buildPcTabBar(BuildContext context) {
    return ListenableBuilder(
      listenable: _tabController,
      builder: (context, _) {
        final idx = _tabController.index;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: PcDashboardTheme.surface,
            border: Border(bottom: BorderSide(color: PcDashboardTheme.border, width: 1)),
          ),
          child: Row(
            children: [
              ...List.generate(_tabs.length, (i) {
                final selected = i == idx;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _tabController.animateTo(i),
                      borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected ? PcDashboardTheme.accentSubtle : null,
                          borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
                        ),
                        child: Text(
                          _tabs[i],
                          style: (selected ? PcDashboardTheme.titleSmall : PcDashboardTheme.bodyMedium).copyWith(
                            color: selected ? PcDashboardTheme.accent : PcDashboardTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WatchlistPage()),
                  );
                },
                icon: Icon(Icons.star_border_rounded, size: 18, color: PcDashboardTheme.textSecondary),
                label: Text('自选', style: PcDashboardTheme.bodyMedium.copyWith(color: PcDashboardTheme.accent)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
      child: Row(
        children: [
          Icon(Icons.public_rounded, color: const Color(0xFFD4AF37), size: 26),
          const SizedBox(width: 8),
          Text(
            '市场',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFFE8D5A3),
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            color: const Color(0xFF9CA3AF),
            onPressed: () {},
            tooltip: 'AI',
          ),
          IconButton(
            icon: const Icon(Icons.star_border),
            color: const Color(0xFF9CA3AF),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WatchlistPage(),
                ),
              );
            },
            tooltip: '自选',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            color: const Color(0xFF9CA3AF),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SearchPage(),
                ),
              );
            },
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.mail_outline),
                color: const Color(0xFF9CA3AF),
                onPressed: () {},
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: MarketColors.down,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- 首页：Market Dashboard（列表为主，国际习惯）---------

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  final _market = MarketRepository();
  final _watchlist = WatchlistRepository.instance;
  static final _cache = TradingCache.instance;
  final _snapshotRepo = MarketSnapshotRepository();
  static const _cacheMaxAge = Duration(days: 7);

  /// Major Indexes: (label, symbol) 4~6 个
  static const _indexList = [
    ('Dow', 'DJI'),
    ('S&P 500', 'SPX'),
    ('Nasdaq', 'IXIC'),
    ('VIX', 'VIX'),
    ('Russell 2000', 'RUT'),
  ];

  Map<String, MarketQuote> _indexQuotes = {};
  List<PolygonGainer> _gainers = [];
  List<PolygonGainer> _losers = [];
  List<String> _watchlistSymbols = [];
  Map<String, MarketQuote> _watchlistQuotes = {};
  List<PolygonGainer> _trendingStocks = [];
  Map<String, MarketQuote> _trendingCryptoQuotes = {};
  int _trendingSegment = 0; // 0 Stocks, 1 Crypto
  bool _loading = true;
  /// PC 涨跌榜：true = 领涨，false = 领跌
  bool _showGainers = true;
  /// PC 市场热度面板：true = 涨幅榜，false = 跌幅榜
  bool _showMarketHeatGainers = true;

  static const _cryptoSymbols = ['BTC', 'ETH', 'SOL', 'XRP', 'DOGE', 'ADA', 'AVAX', 'DOT', 'MATIC', 'LINK'];
  static const _loadTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _loadCachedThenRefresh();
  }

  /// 先读本地/缓存并展示，再后台拉接口；有缓存或超时后也会结束 loading，避免一直转圈
  Future<void> _loadCachedThenRefresh() async {
    setState(() => _loading = true);
    await _loadFromCache();
    if (mounted) setState(() => _loading = false);
    _load();
  }

  /// 从本地缓存快速加载：指数（TradingCache + Supabase 快照）、涨跌榜缓存
  Future<void> _loadFromCache() async {
    final indexQuotes = <String, MarketQuote>{};
    final indicesList = await _cache.getList('market_overview_indices', maxAge: _cacheMaxAge);
    if (indicesList != null && indicesList.isNotEmpty) {
      for (final m in indicesList) {
        if (m is Map<String, dynamic>) {
          final q = MarketQuote.fromSnapshotMap(m);
          if (q != null) indexQuotes[q.symbol] = q;
        }
      }
    }
    if (indexQuotes.length < _indexList.length) {
      final fromDb = await _snapshotRepo.getQuotes('indices');
      for (final m in fromDb) {
        final q = MarketQuote.fromSnapshotMap(m);
        if (q != null && !indexQuotes.containsKey(q.symbol)) indexQuotes[q.symbol] = q;
      }
    }
    List<PolygonGainer> gainers = [];
    List<PolygonGainer> losers = [];
    final cachedG = await _market.getCachedGainersOnly(maxAge: const Duration(hours: 48));
    if (cachedG != null && cachedG.isNotEmpty) gainers = cachedG.take(5).toList();
    final cachedL = await _market.getCachedLosersOnly(maxAge: const Duration(hours: 48));
    if (cachedL != null && cachedL.isNotEmpty) losers = cachedL.take(5).toList();

    final list = await _watchlist.getWatchlist();
    final take6 = list.take(6).toList();

    if (!mounted) return;
    setState(() {
      _indexQuotes = indexQuotes;
      _gainers = gainers;
      _losers = losers;
      _watchlistSymbols = take6;
      if (indexQuotes.isEmpty) _applyMockIndices();
      if (gainers.isEmpty && losers.isEmpty) _applyMockGainersLosers();
    });
  }

  void _applyMockIndices() {
    final mock = <String, MarketQuote>{};
    for (final m in MockMarketData.indicesQuotes) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null) mock[q.symbol] = q;
    }
    for (final e in _indexList) {
      final sym = e.$2;
      final existing = _indexQuotes[sym];
      if (existing == null || existing.hasError) {
        if (mock.containsKey(sym)) _indexQuotes[sym] = mock[sym]!;
      }
    }
  }

  void _applyMockGainersLosers() {
    if (_gainers.isNotEmpty || _losers.isNotEmpty) return;
    _gainers = MockMarketData.mockGainers;
    _losers = MockMarketData.mockLosers;
  }

  Future<void> _load() async {
    final indexSymbols = _indexList.map((e) => e.$2).toList();
    Map<String, MarketQuote> indexQuotes = {};
    List<PolygonGainer> gainers = [];
    List<PolygonGainer> losers = [];

    try {
      final result = await Future.any([
        Future.wait([
          _market.getQuotes(indexSymbols),
          _safeGetGainers(5),
          _safeGetLosers(5),
        ]),
        Future.delayed(_loadTimeout, () => throw TimeoutException('首页行情请求超时')),
      ]);
      indexQuotes = result[0] as Map<String, MarketQuote>;
      gainers = result[1] as List<PolygonGainer>;
      losers = result[2] as List<PolygonGainer>;
    } on TimeoutException catch (_) {
      if (mounted) setState(() => _loading = false);
      return;
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final list = await _watchlist.getWatchlist();
    final take6 = list.take(6).toList();

    final watchQuotesFuture = take6.isEmpty
        ? Future<Map<String, MarketQuote>>.value({})
        : _market.getQuotes(take6);
    final trendingFuture = _safeGetGainers(10);
    final cryptoFuture = _market.getQuotes(_cryptoSymbols);

    Map<String, MarketQuote> watchQuotes = {};
    List<PolygonGainer> trendingStocks = [];
    Map<String, MarketQuote> cryptoQuotes = {};
    try {
      final results2 = await Future.wait([
        watchQuotesFuture,
        trendingFuture,
        cryptoFuture,
      ]);
      watchQuotes = results2[0] as Map<String, MarketQuote>;
      trendingStocks = results2[1] as List<PolygonGainer>;
      cryptoQuotes = results2[2] as Map<String, MarketQuote>;
    } catch (_) {
      // 自选/热门/加密货币失败不影响主内容
    }

    if (!mounted) return;
    setState(() {
      _indexQuotes = indexQuotes;
      _gainers = gainers;
      _losers = losers;
      _watchlistSymbols = take6;
      _watchlistQuotes = watchQuotes;
      _trendingStocks = trendingStocks;
      _trendingCryptoQuotes = cryptoQuotes;
      _loading = false;
      _applyMockIndices();
    });

    await _writeIndexCache(_indexQuotes);
  }

  Future<void> _writeIndexCache(Map<String, MarketQuote> out) async {
    final il = <Map<String, dynamic>>[];
    for (final e in _indexList) {
      final q = out[e.$2];
      if (q != null && !q.hasError) il.add({...q.toSnapshotMap(), 'name': e.$1});
    }
    if (il.isNotEmpty) await _cache.setList('market_overview_indices', il);
  }

  Future<List<PolygonGainer>> _safeGetGainers(int limit) async {
    try {
      return await _market.getTopGainers(limit: limit);
    } catch (_) {
      final cached = await _market.getCachedGainersOnly(maxAge: const Duration(hours: 48));
      return cached != null ? cached.take(limit).toList() : [];
    }
  }

  Future<List<PolygonGainer>> _safeGetLosers(int limit) async {
    try {
      return await _market.getTopLosers(limit: limit);
    } catch (_) {
      final cached = await _market.getCachedLosersOnly(maxAge: const Duration(hours: 48));
      return cached != null ? cached.take(limit).toList() : [];
    }
  }

  bool _isUsStock(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty || s.length > 5) return false;
    if (s.contains('/')) return false;
    return s.runes.every((r) => r >= 0x41 && r <= 0x5A);
  }

  void _openDetail(String symbol, {String? name}) {
    final n = name ?? _watchlistQuotes[symbol]?.name ?? symbol;
    if (_isUsStock(symbol)) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StockChartPage(symbol: symbol)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GenericChartPage(symbol: symbol, name: n)),
      );
    }
  }

  bool get _isPcLayout {
    return MediaQuery.sizeOf(context).width >= 1100;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _indexQuotes.isEmpty && _gainers.isEmpty && _watchlistSymbols.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFD4AF37),
      child: _isPcLayout ? _buildPcLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildMobileLayout() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _buildSearchBar(),
        const SizedBox(height: 12),
        _buildSectionLabel('Major Indexes'),
        const SizedBox(height: 6),
        _buildMajorIndexes(),
        const SizedBox(height: 16),
        _buildSectionLabel('Top Movers'),
        const SizedBox(height: 6),
        _buildTopMoversButtons(),
        const SizedBox(height: 4),
        _buildGainersLosersRows(),
        const SizedBox(height: 16),
        _buildWatchlistSection(),
        const SizedBox(height: 16),
        _buildSectionLabel('Trending'),
        const SizedBox(height: 6),
        _buildTrendingSegmented(),
        _buildTrendingList(),
      ],
    );
  }

  /// PC 端与效果图一致：指数卡片 → 上三列（自选|涨跌榜|市场热度）→ 下两列（Heatmap|热门）
  static const _pcCardBg = Color(0xFF0F1722);
  static const _pcCardBorder = Color(0x0FFFFFFF); // 白 6% 透明
  static const _pcRadiusLg = 16.0;

  Widget _buildPcLayout() {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(PcDashboardTheme.contentPadding, 16, PcDashboardTheme.contentPadding, 20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildSearchBar(),
              const SizedBox(height: 24),
              Text('主要指数', style: PcDashboardTheme.titleSmall),
              const SizedBox(height: 12),
              _buildPcIndexCards(),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                _buildPcRow1ThreeCols(),
                const SizedBox(height: 20),
                _buildPcRow2TwoCols(),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 第一行三列等宽：自选 | 涨跌榜 | 市场热度
  Widget _buildPcRow1ThreeCols() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildPcWatchlistPanel()),
        const SizedBox(width: 16),
        Expanded(child: _buildPcGainersLosersCard()),
        const SizedBox(width: 16),
        Expanded(child: _buildPcMarketHeatPanel()),
      ],
    );
  }

  /// 第二行两列：市场热度 Heatmap | 热门
  Widget _buildPcRow2TwoCols() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildPcHeatmapPanel()),
        const SizedBox(width: 20),
        SizedBox(width: 320, child: _buildPcTrendingCard()),
      ],
    );
  }

  /// PC 指数卡片区：四张横排，深色卡片圆角16、hover 边框提亮
  Widget _buildPcIndexCards() {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _indexList.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final label = _indexList[i].$1;
          final symbol = _indexList[i].$2;
          final q = _indexQuotes[symbol];
          final hasError = q?.hasError ?? true;
          final isLoading = q == null && _loading;
          final isUp = (q?.changePercent ?? 0) >= 0;
          final color = MarketColors.forUp(isUp);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (hasError && !isLoading) { _load(); return; }
                if (hasError) return;
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => GenericChartPage(symbol: symbol, name: label)),
                );
              },
              borderRadius: BorderRadius.circular(_pcRadiusLg),
              child: Container(
                width: 160,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _pcCardBg,
                  borderRadius: BorderRadius.circular(_pcRadiusLg),
                  border: Border.all(color: _pcCardBorder, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$label ($symbol)',
                      style: PcDashboardTheme.bodySmall.copyWith(color: PcDashboardTheme.text),
                    ),
                    if (isLoading)
                      const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37)))
                    else
                      Text(
                        hasError ? '—' : (q != null && q.price > 0 ? _formatPrice(q.price) : '—'),
                        style: PcDashboardTheme.titleMedium.copyWith(
                          color: hasError ? PcDashboardTheme.textMuted : PcDashboardTheme.text,
                          fontFamily: 'monospace',
                        ),
                      ),
                    Row(
                      children: [
                        Icon(isUp ? Icons.trending_up : Icons.trending_down, size: 14, color: color),
                        const SizedBox(width: 4),
                        Text(
                          hasError ? '—' : '${q!.changePercent >= 0 ? '+' : ''}${q.changePercent.toStringAsFixed(2)}%',
                          style: PcDashboardTheme.bodySmall.copyWith(color: color),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 涨跌榜整块卡片（含标题+切换+表格）
  Widget _buildPcGainersLosersCard() {
    return Container(
      decoration: BoxDecoration(
        color: _pcCardBg,
        borderRadius: BorderRadius.circular(_pcRadiusLg),
        border: Border.all(color: _pcCardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Text('涨跌榜', style: PcDashboardTheme.titleSmall),
                const SizedBox(width: 16),
                _moverChip('涨幅榜', true, () => setState(() => _showGainers = true)),
                const SizedBox(width: 8),
                _moverChip('跌幅榜', false, () => setState(() => _showGainers = false)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GainersLosersPage())),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('更多 >', style: PcDashboardTheme.bodyMedium.copyWith(color: PcDashboardTheme.accent)),
                ),
              ],
            ),
          ),
          _buildPcGainersLosersTable(),
        ],
      ),
    );
  }

  /// 市场热度面板：涨幅榜/跌幅榜切换 + 紧凑表（名称、最新价、涨跌幅）
  Widget _buildPcMarketHeatPanel() {
    final list = _showMarketHeatGainers ? _gainers : _losers;
    return Container(
      decoration: BoxDecoration(
        color: _pcCardBg,
        borderRadius: BorderRadius.circular(_pcRadiusLg),
        border: Border.all(color: _pcCardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Text('市场热度', style: PcDashboardTheme.titleSmall),
                const Spacer(),
                _moverChip('涨幅榜', true, () => setState(() => _showMarketHeatGainers = true)),
                const SizedBox(width: 8),
                _moverChip('跌幅榜', false, () => setState(() => _showMarketHeatGainers = false)),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GainersLosersPage())),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('更多 >', style: PcDashboardTheme.bodyMedium.copyWith(color: PcDashboardTheme.accent)),
                ),
              ],
            ),
          ),
          Table(
            columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
            children: [
              TableRow(
                decoration: BoxDecoration(color: PcDashboardTheme.surfaceVariant.withValues(alpha: 0.5)),
                children: [
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text('名称', style: PcDashboardTheme.label)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text('最新价', style: PcDashboardTheme.label)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text('涨跌幅', style: PcDashboardTheme.label)),
                ],
              ),
              ...list.take(6).map((g) {
                final color = MarketColors.forChangePercent(g.todaysChangePerc ?? 0);
                final price = (g.price != null && g.price! > 0) ? g.price! : (g.prevClose != null && g.todaysChange != null ? g.prevClose! + g.todaysChange! : null);
                return TableRow(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openDetail(g.ticker),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Text(g.ticker, style: PcDashboardTheme.bodySmall.copyWith(color: PcDashboardTheme.text)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(price != null ? _formatPrice(price) : '—', style: PcDashboardTheme.bodySmall.copyWith(fontFamily: 'monospace')),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        g.todaysChangePerc != null ? '${g.todaysChangePerc! >= 0 ? '+' : ''}${g.todaysChangePerc!.toStringAsFixed(2)}%' : '—',
                        style: PcDashboardTheme.bodySmall.copyWith(color: color),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  /// 市场热度 Heatmap：网格块，块内 ticker、价格、涨跌幅，绿红深浅
  Widget _buildPcHeatmapPanel() {
    final items = _showGainers ? _gainers.take(12) : _losers.take(12);
    final list = items.toList();
    if (list.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: _pcCardBg,
          borderRadius: BorderRadius.circular(_pcRadiusLg),
          border: Border.all(color: _pcCardBorder, width: 1),
        ),
        alignment: Alignment.center,
        child: Text('暂无数据', style: PcDashboardTheme.bodySmall),
      );
    }
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: _pcCardBg,
        borderRadius: BorderRadius.circular(_pcRadiusLg),
        border: Border.all(color: _pcCardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('市场热度 Heatmap', style: PcDashboardTheme.titleSmall),
              const Spacer(),
              Text('S&P 500', style: PcDashboardTheme.bodySmall),
              const SizedBox(width: 8),
              Text('交易子类 >', style: PcDashboardTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const crossCount = 4;
                final itemWidth = (constraints.maxWidth - 12) / crossCount;
                final itemHeight = (constraints.maxHeight - 8) / 3;
                return Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: List.generate(list.length, (i) {
                    final g = list[i];
                    final pct = g.todaysChangePerc ?? 0;
                    final isUp = pct >= 0;
                    final intensity = (pct.abs() / 10).clamp(0.0, 1.0);
                    final bg = isUp
                        ? Color.lerp(const Color(0xFF22C55E).withValues(alpha: 0.15), const Color(0xFF22C55E).withValues(alpha: 0.5), intensity)!
                        : Color.lerp(const Color(0xFFEF4444).withValues(alpha: 0.15), const Color(0xFFEF4444).withValues(alpha: 0.5), intensity)!;
                    final price = (g.price != null && g.price! > 0) ? g.price! : (g.prevClose != null && g.todaysChange != null ? g.prevClose! + g.todaysChange! : null);
                    return SizedBox(
                      width: itemWidth,
                      height: itemHeight,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _openDetail(g.ticker),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: PcDashboardTheme.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(g.ticker, style: PcDashboardTheme.titleSmall.copyWith(fontSize: 12)),
                                if (price != null) Text(_formatPrice(price), style: PcDashboardTheme.bodySmall.copyWith(fontFamily: 'monospace')),
                                Text(
                                  '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                                  style: PcDashboardTheme.bodySmall.copyWith(
                                    color: isUp ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 热门整块卡片（Stocks/Crypto 切换 + 列表）
  Widget _buildPcTrendingCard() {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: _pcCardBg,
        borderRadius: BorderRadius.circular(_pcRadiusLg),
        border: Border.all(color: _pcCardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('热门', style: PcDashboardTheme.titleSmall),
              const Spacer(),
              _segmentChip('Stocks', 0),
              const SizedBox(width: 8),
              _segmentChip('Crypto', 1),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: SingleChildScrollView(child: _buildTrendingList())),
        ],
      ),
    );
  }

  /// PC 涨跌榜：Gainers/Losers 切换 + 更多
  Widget _buildPcGainersLosersHeader() {
    return Row(
      children: [
        Text('涨跌榜', style: PcDashboardTheme.titleSmall),
        const SizedBox(width: 16),
        _moverChip('Gainers', true, () => setState(() => _showGainers = true)),
        const SizedBox(width: 8),
        _moverChip('Losers', false, () => setState(() => _showGainers = false)),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GainersLosersPage())),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('更多 >', style: PcDashboardTheme.bodyMedium.copyWith(color: PcDashboardTheme.accent)),
        ),
      ],
    );
  }

  /// PC 涨跌榜表格：代码、名称、涨跌幅、最新价、涨跌额、今开、昨收、最高、最低、成交量
  Widget _buildPcGainersLosersTable() {
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
    const rowPadding = 10.0;

    final list = _showGainers ? _gainers : _losers;
    final headerRow = Row(
      children: [
        SizedBox(width: colCode, child: Text('代码', style: PcDashboardTheme.label)),
        SizedBox(width: colName, child: Text('名称', style: PcDashboardTheme.label)),
        SizedBox(width: colPct, child: Text('涨跌幅', style: PcDashboardTheme.label)),
        SizedBox(width: colPrice, child: Text('最新价', style: PcDashboardTheme.label)),
        SizedBox(width: colChange, child: Text('涨跌额', style: PcDashboardTheme.label)),
        SizedBox(width: colOpen, child: Text('今开', style: PcDashboardTheme.label)),
        SizedBox(width: colPrev, child: Text('昨收', style: PcDashboardTheme.label)),
        SizedBox(width: colHigh, child: Text('最高', style: PcDashboardTheme.label)),
        SizedBox(width: colLow, child: Text('最低', style: PcDashboardTheme.label)),
        SizedBox(width: colVol, child: Text('成交量', style: PcDashboardTheme.label)),
      ],
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: PcDashboardTheme.surfaceVariant.withValues(alpha: 0.6),
              borderRadius: BorderRadius.vertical(top: Radius.circular(PcDashboardTheme.radiusSm)),
            ),
            child: headerRow,
          ),
          ...list.take(8).map((g) {
              final color = MarketColors.forChangePercent(g.todaysChangePerc ?? 0);
              // 接口有时只返回昨收+涨跌额，无 price：用 最新价 = 昨收 + 涨跌额 回退，避免出现「有涨跌却最新价 —」
              final effectivePrice = (g.price != null && g.price! > 0)
                  ? g.price!
                  : (g.prevClose != null && g.todaysChange != null
                      ? g.prevClose! + g.todaysChange
                      : null);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openDetail(g.ticker),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: rowPadding),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: PcDashboardTheme.border, width: 0.6),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: colCode, child: Text(g.ticker, style: PcDashboardTheme.titleSmall.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: colName, child: Text(g.ticker, style: PcDashboardTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: colPct, child: Text(g.todaysChangePerc != null ? '${g.todaysChangePerc! >= 0 ? '+' : ''}${g.todaysChangePerc!.toStringAsFixed(2)}%' : '—', style: PcDashboardTheme.bodySmall.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: colPrice, child: Text(effectivePrice != null && effectivePrice > 0 ? _formatPrice(effectivePrice) : '—', style: PcDashboardTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: colChange, child: Text(g.todaysChange != null ? '${g.todaysChange! >= 0 ? '+' : ''}${g.todaysChange!.toStringAsFixed(2)}' : '—', style: PcDashboardTheme.bodySmall.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: colOpen, child: Text(g.dayOpen != null && g.dayOpen! > 0 ? _formatPrice(g.dayOpen!) : '—', style: PcDashboardTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: colPrev, child: Text(g.prevClose != null && g.prevClose! > 0 ? _formatPrice(g.prevClose!) : '—', style: PcDashboardTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: colHigh, child: Text(g.dayHigh != null && g.dayHigh! > 0 ? _formatPrice(g.dayHigh!) : '—', style: PcDashboardTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: colLow, child: Text(g.dayLow != null && g.dayLow! > 0 ? _formatPrice(g.dayLow!) : '—', style: PcDashboardTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(width: colVol, child: Text(_formatVolume(g.dayVolume), style: PcDashboardTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  /// PC 涨跌榜下方三大指数栏
  Widget _buildPcIndicesBar() {
    const symbols = ['DJI', 'IXIC', 'SPX'];
    const names = ['道琼斯', '纳斯达克', '标普500'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: PcDashboardTheme.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
        border: Border.all(color: PcDashboardTheme.border),
      ),
      child: Row(
        children: [
          Text('三大指数', style: PcDashboardTheme.label),
          const SizedBox(width: 20),
          ...List.generate(3, (i) {
            final sym = symbols[i];
            final name = names[i];
            final q = _indexQuotes[sym];
            final hasError = q?.hasError ?? true;
            final isUp = (q?.changePercent ?? 0) >= 0;
            final color = MarketColors.forUp(isUp);
            return Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$name ', style: PcDashboardTheme.bodySmall),
                  Text(
                    hasError ? '—' : (q != null && q.price > 0 ? _formatPrice(q.price) : '—'),
                    style: PcDashboardTheme.titleSmall.copyWith(fontSize: 13, color: hasError ? PcDashboardTheme.textMuted : null),
                  ),
                  if (!hasError && q != null && q.price > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${q.change >= 0 ? '+' : ''}${q.change.toStringAsFixed(2)} ${q.changePercent >= 0 ? '+' : ''}${q.changePercent.toStringAsFixed(2)}%',
                      style: PcDashboardTheme.bodySmall.copyWith(color: color),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// PC 自选面板（与效果图一致的卡片样式）
  Widget _buildPcWatchlistPanel() {
    return Container(
      decoration: BoxDecoration(
        color: _pcCardBg,
        borderRadius: BorderRadius.circular(_pcRadiusLg),
        border: Border.all(color: _pcCardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('自选', style: PcDashboardTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WatchlistPage())).then((_) => _load()),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('See all', style: PcDashboardTheme.bodyMedium.copyWith(color: PcDashboardTheme.accent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_watchlistSymbols.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '暂无自选，点击顶部星标添加',
                  style: PcDashboardTheme.bodySmall,
                ),
              ),
            )
          else
            ..._watchlistSymbols.map((symbol) {
              final q = _watchlistQuotes[symbol];
              return _buildPcWatchlistRow(
                symbol: symbol,
                name: q?.name,
                price: q?.price ?? 0,
                change: q?.change ?? 0,
                changePercent: q?.changePercent ?? 0,
                hasError: q?.hasError ?? true,
                onTap: () => _openDetail(symbol),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPcWatchlistRow({
    required String symbol,
    required double price,
    required double change,
    required double changePercent,
    required bool hasError,
    required VoidCallback onTap,
    String? name,
  }) {
    final color = MarketColors.forChangePercent(changePercent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(symbol, style: PcDashboardTheme.titleSmall.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (name != null && name.isNotEmpty)
                      Text(name, style: PcDashboardTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (hasError)
                Text('—', style: PcDashboardTheme.bodySmall)
              else ...[
                Text(price > 0 ? _formatPrice(price) : '—', style: PcDashboardTheme.bodyMedium.copyWith(fontSize: 12)),
                const SizedBox(width: 8),
                Text(
                  '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)} ${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                  style: PcDashboardTheme.bodySmall.copyWith(color: color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final isPc = _isPcLayout;
    return Material(
      color: isPc ? PcDashboardTheme.inputBg : const Color(0xFF111215),
      borderRadius: BorderRadius.circular(isPc ? PcDashboardTheme.radiusMd : 8),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
        borderRadius: BorderRadius.circular(isPc ? PcDashboardTheme.radiusMd : 8),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isPc ? 14 : 12, vertical: isPc ? 12 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isPc ? PcDashboardTheme.radiusMd : 8),
            border: Border.all(color: isPc ? PcDashboardTheme.border : const Color(0xFF1F1F23)),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 20, color: isPc ? PcDashboardTheme.textMuted : const Color(0xFF9CA3AF)),
              SizedBox(width: isPc ? 12 : 10),
              Text(
                'Search symbols',
                style: isPc ? PcDashboardTheme.bodyMedium : const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFE8D5A3),
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }

  Widget _buildMajorIndexes() {
    const cardHeight = 80.0;
    final isPc = _isPcLayout;
    final cardWidth = isPc ? 128.0 : 100.0;
    return SizedBox(
      height: cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _indexList.length,
        separatorBuilder: (_, __) => SizedBox(width: isPc ? 12 : 8),
        itemBuilder: (context, i) {
          final label = _indexList[i].$1;
          final symbol = _indexList[i].$2;
          final q = _indexQuotes[symbol];
          final hasError = q?.hasError ?? true;
          final isLoading = q == null && _loading;
          final isUp = (q?.changePercent ?? 0) >= 0;
          final color = MarketColors.forUp(isUp);
          return Material(
            color: isPc ? PcDashboardTheme.surfaceElevated : const Color(0xFF111215),
            borderRadius: BorderRadius.circular(isPc ? PcDashboardTheme.radiusMd : 8),
            child: InkWell(
              onTap: () {
                if (hasError && !isLoading) {
                  _load();
                  return;
                }
                if (hasError) return;
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => GenericChartPage(symbol: symbol, name: label)),
                );
              },
              borderRadius: BorderRadius.circular(isPc ? PcDashboardTheme.radiusMd : 8),
              child: Container(
                width: cardWidth,
                height: cardHeight,
                padding: EdgeInsets.symmetric(horizontal: isPc ? 14 : 10, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isPc ? PcDashboardTheme.radiusMd : 8),
                  border: isPc
                      ? Border.all(color: PcDashboardTheme.border, width: 1)
                      : const Border(bottom: BorderSide(color: Color(0xFF1F1F23), width: 0.6)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      symbol,
                      style: (isPc ? PcDashboardTheme.label : const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11, decoration: TextDecoration.none)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (isLoading)
                      SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: isPc ? PcDashboardTheme.accent : const Color(0xFFD4AF37)),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              hasError ? '—' : (q != null && q!.price > 0 ? _formatPrice(q!.price) : '—'),
                              style: TextStyle(
                                color: hasError ? (isPc ? PcDashboardTheme.textMuted : const Color(0xFF6B6B70)) : (q != null && q!.price > 0 ? color : (isPc ? PcDashboardTheme.textMuted : const Color(0xFF6B6B70))),
                                fontWeight: FontWeight.w700,
                                fontSize: isPc ? 14 : 13,
                                decoration: TextDecoration.none,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasError ? '' : (q != null && q.price > 0 ? '${q!.changePercent >= 0 ? '+' : ''}${q.changePercent.toStringAsFixed(2)}%' : ''),
                            style: TextStyle(
                              color: (q != null && q.price > 0) ? color : (isPc ? PcDashboardTheme.textMuted : const Color(0xFF6B6B70)),
                              fontSize: isPc ? 11 : 10,
                              decoration: TextDecoration.none,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopMoversButtons() {
    return Row(
      children: [
        _moverChip('Gainers', true, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GainersLosersPage()))),
        const SizedBox(width: 8),
        _moverChip('Losers', false, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GainersLosersPage()))),
      ],
    );
  }

  Widget _moverChip(String label, bool isGainers, VoidCallback onTap) {
    return Material(
      color: (isGainers ? MarketColors.up : MarketColors.down).withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isGainers ? Icons.trending_up : Icons.trending_down,
                size: 16,
                color: isGainers ? MarketColors.up : MarketColors.down,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isGainers ? MarketColors.up : MarketColors.down,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGainersLosersRows() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._gainers.take(5).map((g) => QuoteRow(
          symbol: g.ticker,
          price: g.price ?? 0,
          change: g.todaysChange,
          changePercent: g.todaysChangePerc,
          hasError: g.price == null,
          onTap: () => _openDetail(g.ticker),
        )),
        ..._losers.take(5).map((g) => QuoteRow(
          symbol: g.ticker,
          price: g.price ?? 0,
          change: g.todaysChange,
          changePercent: g.todaysChangePerc,
          hasError: g.price == null,
          onTap: () => _openDetail(g.ticker),
        )),
      ],
    );
  }

  Widget _buildWatchlistSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildSectionLabel('Watchlist'),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WatchlistPage())).then((_) => _load()),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('See all', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_watchlistSymbols.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF111215),
              border: Border(bottom: BorderSide(color: const Color(0xFF1F1F23), width: 0.6)),
            ),
            child: const Center(
              child: Text(
                'No watchlist. Tap star to add.',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
              ),
            ),
          )
        else
          ..._watchlistSymbols.map((symbol) {
            final q = _watchlistQuotes[symbol];
            return QuoteRow(
              symbol: symbol,
              name: q?.name,
              price: q?.price ?? 0,
              change: q?.change ?? 0,
              changePercent: q?.changePercent ?? 0,
              hasError: q?.hasError ?? true,
              onTap: () => _openDetail(symbol),
            );
          }),
      ],
    );
  }

  Widget _buildTrendingSegmented() {
    return Row(
      children: [
        _segmentChip('Stocks', 0),
        const SizedBox(width: 8),
        _segmentChip('Crypto', 1),
      ],
    );
  }

  Widget _segmentChip(String label, int index) {
    final selected = _trendingSegment == index;
    return Material(
      color: selected ? const Color(0xFFD4AF37).withValues(alpha: 0.25) : const Color(0xFF111215),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => setState(() => _trendingSegment = index),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? const Color(0xFFD4AF37) : const Color(0xFF1F1F23),
              width: selected ? 1.2 : 0.6,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFFD4AF37) : const Color(0xFF9CA3AF),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrendingList() {
    if (_trendingSegment == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _trendingStocks.take(10).map((g) => QuoteRow(
          symbol: g.ticker,
          price: g.price ?? 0,
          change: g.todaysChange,
          changePercent: g.todaysChangePerc,
          hasError: g.price == null,
          onTap: () => _openDetail(g.ticker),
        )).toList(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _cryptoSymbols.map((symbol) {
        final q = _trendingCryptoQuotes[symbol];
        return QuoteRow(
          symbol: symbol,
          name: q?.name,
          price: q?.price ?? 0,
          change: q?.change ?? 0,
          changePercent: q?.changePercent ?? 0,
          hasError: q?.hasError ?? true,
          onTap: () => _openDetail(symbol, name: q?.name ?? symbol),
        );
      }).toList(),
    );
  }

  static String _formatPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  static String _formatVolume(int? v) {
    if (v == null || v <= 0) return '—';
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(2)}亿';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(2)}万';
    return v.toString();
  }
}

// ---------- 概况：环球指数 + 外汇 + 加密货币（Twelve Data）----------

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  final _market = MarketRepository();
  final _snapshotRepo = MarketSnapshotRepository();
  static final _cache = TradingCache.instance;
  static const _cacheMaxAge = Duration(days: 7);

  static const _indices = [
    ('道琼斯', 'DJI'),
    ('标普500', 'SPX'),
    ('纳斯达克', 'NDX'),
    ('恒生指数', 'HSI'),
    ('日经225', 'N225'),
  ];
  static const _forex = [
    ('欧元/美元', 'EUR/USD'),
    ('美元/日元', 'USD/JPY'),
    ('英镑/美元', 'GBP/USD'),
  ];
  static const _crypto = [
    ('比特币', 'BTC/USD'),
    ('以太坊', 'ETH/USD'),
    ('Solana', 'SOL/USD'),
  ];

  Map<String, MarketQuote?> _quotes = {};
  bool _loading = true;
  bool _isMockData = false;

  @override
  void initState() {
    super.initState();
    _loadCachedThenRefresh();
  }

  /// 先显示本地/数据库缓存，再后台拉 API；无数据时用模拟数据并提示
  Future<void> _loadCachedThenRefresh() async {
    setState(() { _loading = true; _isMockData = false; });
    await _loadFromCache();
    if (!_market.twelveDataAvailable) {
      _applyMockOverviewIfEmpty();
      if (mounted) setState(() => _loading = false);
      return;
    }
    _load();
  }

  /// 从本地缓存或数据库快速加载，立即展示
  Future<void> _loadFromCache() async {
    final out = <String, MarketQuote?>{};
    final indicesList = await _cache.getList('market_overview_indices', maxAge: _cacheMaxAge);
    if (indicesList != null && indicesList.isNotEmpty) {
      for (final m in indicesList) {
        if (m is Map<String, dynamic>) {
          final q = MarketQuote.fromSnapshotMap(m);
          if (q != null) out[q.symbol] = q;
        }
      }
    }
    if (out.length < _indices.length) {
      final fromDb = await _snapshotRepo.getQuotes('indices');
      for (final m in fromDb) {
        final q = MarketQuote.fromSnapshotMap(m);
        if (q != null && out[q.symbol] == null) out[q.symbol] = q;
      }
    }
    final forexList = await _cache.getList('market_overview_forex', maxAge: _cacheMaxAge);
    if (forexList != null) for (final m in forexList) {
      if (m is Map<String, dynamic>) { final q = MarketQuote.fromSnapshotMap(m); if (q != null) out[q.symbol] = q; }
    }
    final fromDbF = await _snapshotRepo.getQuotes('forex');
    for (final m in fromDbF) { final q = MarketQuote.fromSnapshotMap(m); if (q != null && out[q.symbol] == null) out[q.symbol] = q; }
    final cryptoList = await _cache.getList('market_overview_crypto', maxAge: _cacheMaxAge);
    if (cryptoList != null) for (final m in cryptoList) {
      if (m is Map<String, dynamic>) { final q = MarketQuote.fromSnapshotMap(m); if (q != null) out[q.symbol] = q; }
    }
    final fromDbC = await _snapshotRepo.getQuotes('crypto');
    for (final m in fromDbC) { final q = MarketQuote.fromSnapshotMap(m); if (q != null && out[q.symbol] == null) out[q.symbol] = q; }
    _quotes = out;
    if (_quotes.isEmpty) _applyMockOverviewIfEmpty();
    else _fillMissingWithMock();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _load() async {
    if (!_market.twelveDataAvailable) return;
    final symbols = [
      ..._indices.map((e) => e.$2),
      ..._forex.map((e) => e.$2),
      ..._crypto.map((e) => e.$2),
    ];
    final out = await _market.getQuotes(symbols);
    await _mergeIndices(out);
    await _mergeForex(out);
    await _mergeCrypto(out);
    await _writeOverviewCache(out);
    if (mounted) {
      if (out.isEmpty) _applyMockOverviewIfEmpty();
      else {
        _quotes = out;
        _fillMissingWithMock();
      }
      setState(() => _loading = false);
    }
  }

  void _applyMockOverviewIfEmpty() {
    if (_quotes.isNotEmpty) return;
    final mock = <String, MarketQuote?>{};
    for (final m in MockMarketData.indicesQuotes) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null) mock[q.symbol] = q;
    }
    for (final m in MockMarketData.forexQuotes) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null) mock[q.symbol] = q;
    }
    for (final m in MockMarketData.cryptoQuotes) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null) mock[q.symbol] = q;
    }
    _quotes = mock;
    _isMockData = mock.isNotEmpty;
  }

  /// API 只返回部分标的时，用模拟数据补全缺失项，避免出现「—」
  void _fillMissingWithMock() {
    bool filled = false;
    for (final m in MockMarketData.indicesQuotes) {
      final sym = m['symbol'] as String?;
      if (sym != null && _quotes[sym] == null) {
        final q = MarketQuote.fromSnapshotMap(m);
        if (q != null) {
          _quotes[sym] = q;
          filled = true;
        }
      }
    }
    for (final m in MockMarketData.forexQuotes) {
      final sym = m['symbol'] as String?;
      if (sym != null && _quotes[sym] == null) {
        final q = MarketQuote.fromSnapshotMap(m);
        if (q != null) {
          _quotes[sym] = q;
          filled = true;
        }
      }
    }
    for (final m in MockMarketData.cryptoQuotes) {
      final sym = m['symbol'] as String?;
      if (sym != null && _quotes[sym] == null) {
        final q = MarketQuote.fromSnapshotMap(m);
        if (q != null) {
          _quotes[sym] = q;
          filled = true;
        }
      }
    }
    if (filled) _isMockData = true;
  }

  Future<void> _writeOverviewCache(Map<String, MarketQuote?> out) async {
    final il = <Map<String, dynamic>>[];
    for (final e in _indices) {
      final q = out[e.$2];
      if (q != null && !q.hasError) il.add({...q.toSnapshotMap(), 'name': e.$1});
    }
    if (il.isNotEmpty) await _cache.setList('market_overview_indices', il);
    final fl = <Map<String, dynamic>>[];
    for (final e in _forex) {
      final q = out[e.$2];
      if (q != null && !q.hasError) fl.add({...q.toSnapshotMap(), 'name': e.$1});
    }
    if (fl.isNotEmpty) await _cache.setList('market_overview_forex', fl);
    final cl = <Map<String, dynamic>>[];
    for (final e in _crypto) {
      final q = out[e.$2];
      if (q != null && !q.hasError) cl.add({...q.toSnapshotMap(), 'name': e.$1});
    }
    if (cl.isNotEmpty) await _cache.setList('market_overview_crypto', cl);
  }

  Future<void> _mergeIndices(Map<String, MarketQuote?> out) async {
    final hasAny = _indices.any((e) => out[e.$2] != null);
    if (hasAny) {
      final list = <Map<String, dynamic>>[];
      for (final e in _indices) {
        final q = out[e.$2];
        if (q != null) list.add({...q.toSnapshotMap(), 'name': e.$1});
      }
      if (list.isNotEmpty) await _snapshotRepo.saveQuotes('indices', list);
    }
    final fromDb = await _snapshotRepo.getQuotes('indices');
    for (final m in fromDb) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null && out[q.symbol] == null) out[q.symbol] = q;
    }
  }

  Future<void> _mergeForex(Map<String, MarketQuote?> out) async {
    final hasAny = _forex.any((e) => out[e.$2] != null);
    if (hasAny) {
      final list = <Map<String, dynamic>>[];
      for (final e in _forex) {
        final q = out[e.$2];
        if (q != null) list.add({...q.toSnapshotMap(), 'name': e.$1});
      }
      if (list.isNotEmpty) await _snapshotRepo.saveQuotes('forex', list);
    }
    final fromDb = await _snapshotRepo.getQuotes('forex');
    for (final m in fromDb) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null && out[q.symbol] == null) out[q.symbol] = q;
    }
  }

  Future<void> _mergeCrypto(Map<String, MarketQuote?> out) async {
    final hasAny = _crypto.any((e) => out[e.$2] != null);
    if (hasAny) {
      final list = <Map<String, dynamic>>[];
      for (final e in _crypto) {
        final q = out[e.$2];
        if (q != null) list.add({...q.toSnapshotMap(), 'name': e.$1});
      }
      if (list.isNotEmpty) await _snapshotRepo.saveQuotes('crypto', list);
    }
    final fromDb = await _snapshotRepo.getQuotes('crypto');
    for (final m in fromDb) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null && out[q.symbol] == null) out[q.symbol] = q;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _quotes.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
    }
    if (_quotes.isEmpty) {
      return _buildHint('暂无数据，请配置 TWELVE_DATA_API_KEY 或稍后重试');
    }
    return RefreshIndicator(
      onRefresh: () async {
        if (_market.twelveDataAvailable) await _load();
      },
      color: const Color(0xFFD4AF37),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_isMockData) _buildOverviewMockBanner(),
          _buildMapOverview(context),
          const SizedBox(height: 20),
          _sectionTitle('环球指数'),
          const SizedBox(height: 8),
          _quoteGrid(
            items: _indices,
            onTap: (name, symbol) => _pushChart(context, symbol, name),
          ),
          const SizedBox(height: 20),
          _sectionTitle('资讯'),
          const SizedBox(height: 8),
          _buildNewsSection(),
          const SizedBox(height: 20),
          _sectionTitle('外汇'),
          const SizedBox(height: 8),
          _quoteGrid(
            items: _forex,
            onTap: (name, symbol) => _pushChart(context, symbol, name),
          ),
          const SizedBox(height: 20),
          _sectionTitle('加密货币'),
          const SizedBox(height: 8),
          _quoteGrid(
            items: _crypto,
            onTap: (name, symbol) => _pushChart(context, symbol, name),
          ),
        ],
      ),
    );
  }

  /// 地图概览：世界地图风格背景 + 各指数名称与涨跌幅（与参考看盘软件一致）
  Widget _buildMapOverview(BuildContext context) {
    final items = <(String, String, double?)>[];
    for (final e in _indices) {
      final q = _quotes[e.$2];
      items.add((e.$1, e.$2, q?.changePercent));
    }
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C21),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.2)),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(Icons.public, size: 80, color: const Color(0xFF2A2C32)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: items.map((e) {
                final name = e.$1;
                final pct = e.$3;
                final isUp = (pct ?? 0) >= 0;
                final color = MarketColors.forUp(isUp);
                final text = pct != null
                    ? '$name ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%'
                    : name;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  static const _newsTitles = [
    'A股复市前港股大反弹!科技股转势时刻到了?',
    '华尔街深度解读"特朗普IEEPA关税被否":下半年关税或下调',
  ];

  Widget _buildNewsSection() {
    return Column(
      children: _newsTitles.map((title) {
        return Material(
          color: const Color(0xFF111215),
          child: InkWell(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF1F1F23), width: 0.6)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.article_outlined, size: 20, color: const Color(0xFF9CA3AF)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(color: Color(0xFFE8D5A3), fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHint(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
      ),
    );
  }

  Widget _buildOverviewMockBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFFD4AF37)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前为模拟数据。配置 TWELVE_DATA_API_KEY 后可显示真实行情。',
              style: TextStyle(color: Color(0xFFE8D5A3), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFE8D5A3),
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    );
  }

  Widget _quoteGrid({
    required List<(String, String)> items,
    required void Function(String name, String symbol) onTap,
  }) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.15,
      children: items.map((e) {
        final name = e.$1;
        final symbol = e.$2;
        final q = _quotes[symbol];
        return _QuoteCard(
          name: name,
          symbol: symbol,
          quote: q,
          onTap: () => onTap(name, symbol),
        );
      }).toList(),
    );
  }

  bool _hasAnyQuote(List<String> symbols) {
    for (final s in symbols) {
      if (_quotes[s] != null) return true;
    }
    return false;
  }

  Widget _hintText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF6B6B70),
          fontSize: 11,
        ),
      ),
    );
  }

  void _pushChart(BuildContext context, String symbol, String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GenericChartPage(symbol: symbol, name: name),
      ),
    );
  }
}

/// 迷你走势图（与参考看盘软件卡片内小图一致）
class _MiniSparkline extends StatelessWidget {
  const _MiniSparkline({required this.percentChange});

  final double percentChange;

  @override
  Widget build(BuildContext context) {
    final isUp = percentChange >= 0;
    final color = MarketColors.forUp(isUp);
    const pointCount = 8;
    final points = List<double>.generate(pointCount, (i) {
      final t = i / (pointCount - 1);
      final trend = isUp ? t : (1 - t);
      return 0.2 + 0.6 * trend + (i % 2 == 0 ? 0.05 : -0.05);
    });
    return CustomPaint(
      size: const Size(double.infinity, 28),
      painter: _SparklinePainter(points: points, color: color),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final min = points.reduce((a, b) => a < b ? a : b);
    final max = points.reduce((a, b) => a > b ? a : b);
    final range = (max - min).clamp(0.01, double.infinity);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height * (1 - (points[i] - min) / range);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = color ..strokeWidth = 1.5 ..style = PaintingStyle.stroke ..strokeCap = StrokeCap.round ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.name,
    required this.symbol,
    required this.quote,
    required this.onTap,
  });

  final String name;
  final String symbol;
  final MarketQuote? quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasData = quote != null;
    final isUp = (quote?.changePercent ?? 0) >= 0;
    final color = MarketColors.forUp(isUp);
    return Material(
      color: const Color(0xFF111215),
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: const TextStyle(
                    color: Color(0xFF9CA3AF), fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasData) ...[
                Text(
                  _formatPrice(quote!.price),
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 18),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  (quote!.change >= 0 ? '+' : '') +
                      quote!.change.toStringAsFixed(2) +
                      ' ' +
                      (quote!.changePercent >= 0 ? '+' : '') +
                      quote!.changePercent.toStringAsFixed(2) + '%',
                  style: TextStyle(color: color, fontSize: 11),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 28,
                  width: double.infinity,
                  child: _MiniSparkline(percentChange: quote!.changePercent),
                ),
              ] else
                const Text(
                  '—',
                  style: TextStyle(color: Color(0xFF6B6B70), fontSize: 14),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }
}

// ---------- 美股：Polygon 领涨/领跌 ----------

class _UsStocksTab extends StatefulWidget {
  const _UsStocksTab();

  @override
  State<_UsStocksTab> createState() => _UsStocksTabState();
}

class _UsStocksTabState extends State<_UsStocksTab> {
  final _market = MarketRepository();
  final _watchlist = WatchlistRepository.instance;
  /// 0 = 热门（领涨）, 1 = 自选
  int _listMode = 0;
  List<PolygonGainer> _list = [];
  List<String> _hotSymbols = [];
  List<String> _watchlistSymbols = [];
  Map<String, MarketQuote> _quotes = {};
  Map<String, MarketQuote> _indexQuotes = {};
  bool _loading = true;
  String? _error;
  bool _isMockData = false;

  static const _indexSymbols = ['DJI', 'IXIC', 'SPX'];
  static const _indexNames = ['道琼斯', '纳斯达克', '标普500'];

  @override
  void initState() {
    super.initState();
    _loadCachedThenRefresh();
    _loadIndexQuotes();
  }

  Future<void> _loadIndexQuotes() async {
    try {
      final q = await _market.getQuotes(_indexSymbols);
      if (mounted) setState(() => _indexQuotes = q);
    } catch (_) {}
  }

  Future<void> _loadCachedThenRefresh() async {
    setState(() { _loading = true; _isMockData = false; });
    final list = await _market.getCachedGainersOnly(maxAge: const Duration(hours: 48));
    if (list != null && list.isNotEmpty && mounted) {
      setState(() {
        _list = list;
        _hotSymbols = list.map((g) => g.ticker).toList();
        _loading = false;
      });
      _refreshQuotesForCurrentMode();
      return;
    }
    if (mounted) {
      setState(() {
        _list = MockMarketData.mockGainers;
        _hotSymbols = _list.map((g) => g.ticker).toList();
        _loading = false;
        _isMockData = true;
      });
    }
    _loadHot();
  }

  Future<void> _refreshQuotesForCurrentMode() async {
    if (_listMode == 0) {
      await _loadHot();
    } else {
      await _loadWatchlist();
    }
  }

  Future<void> _loadHot() async {
    if (!mounted) return;
    if (!_market.polygonAvailable) {
      if (mounted) setState(() {
        _loading = false;
        if (_list.isEmpty) {
          _list = MockMarketData.mockGainers;
          _hotSymbols = _list.map((g) => g.ticker).toList();
          _isMockData = true;
        }
        _error = null;
      });
      if (_hotSymbols.isNotEmpty) {
        final q = await _market.getQuotes(_hotSymbols);
        if (mounted) setState(() => _quotes = q);
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final list = await _market.getTopGainers(limit: 20);
      if (!mounted) return;
      final symbols = list.isNotEmpty
          ? list.map((g) => g.ticker).toList()
          : _list.map((g) => g.ticker).toList();
      setState(() {
        _list = list.isNotEmpty ? list : _list;
        _hotSymbols = symbols;
        _loading = false;
        _error = null;
        _isMockData = list.isEmpty;
      });
      final q = await _market.getQuotes(symbols);
      if (mounted) setState(() => _quotes = q);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _list = _list.isEmpty ? MockMarketData.mockGainers : _list;
        _hotSymbols = _list.map((g) => g.ticker).toList();
        _isMockData = true;
        _error = null;
      });
      final q = await _market.getQuotes(_hotSymbols);
      if (mounted) setState(() => _quotes = q);
    }
  }

  Future<void> _loadWatchlist() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final symbols = await _watchlist.getWatchlist();
      if (!mounted) return;
      setState(() {
        _watchlistSymbols = symbols;
        _loading = false;
        _error = null;
      });
      if (symbols.isNotEmpty) {
        final q = await _market.getQuotes(symbols);
        if (mounted) setState(() => _quotes = q);
      } else {
        if (mounted) setState(() => _quotes = {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _watchlistSymbols = [];
        _quotes = {};
        _error = null;
      });
    }
  }

  static String _formatPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  static String _formatVolume(int? v) {
    if (v == null || v <= 0) return '—';
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(2)}亿';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(2)}万';
    return v.toString();
  }

  bool get _isPc => MediaQuery.sizeOf(context).width >= 1100;

  @override
  Widget build(BuildContext context) {
    final symbols = _listMode == 0 ? _hotSymbols : _watchlistSymbols;
    return RefreshIndicator(
      onRefresh: () async {
        await _refreshQuotesForCurrentMode();
        await _loadIndexQuotes();
      },
      color: const Color(0xFFD4AF37),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_isMockData && _listMode == 0) _buildMockBanner(),
          _buildUsIndexCards(),
          const SizedBox(height: 14),
          Row(
            children: [
              _Chip(
                label: '热门',
                selected: _listMode == 0,
                onTap: () {
                  if (_listMode != 0) {
                    setState(() => _listMode = 0);
                    _loadHot();
                  }
                },
              ),
              const SizedBox(width: 8),
              _Chip(
                label: '自选',
                selected: _listMode == 1,
                onTap: () {
                  if (_listMode != 1) {
                    setState(() => _listMode = 1);
                    _loadWatchlist();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 220),
              child: Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFD4AF37)),
                    const SizedBox(height: 16),
                    const Text(
                      '正在加载行情…',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else if (_listMode == 1 && symbols.isEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 200),
              child: Padding(
                padding: const EdgeInsets.only(top: 32, left: 24, right: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_border, size: 56, color: const Color(0xFF6B6B70)),
                    const SizedBox(height: 16),
                    const Text(
                      '暂无自选',
                      style: TextStyle(
                        color: Color(0xFFE8D5A3),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '在搜索或详情页可添加自选',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SearchPage()),
                        );
                      },
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('去添加'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFD4AF37)),
                    ),
                  ],
                ),
              ),
            )
          else if (_error != null)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 220),
              child: Padding(
                padding: const EdgeInsets.only(top: 32, left: 24, right: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 56, color: const Color(0xFF6B6B70)),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFE8D5A3), fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: _refreshQuotesForCurrentMode,
                      icon: const Icon(Icons.refresh, size: 20),
                      label: const Text('重试'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFD4AF37)),
                    ),
                  ],
                ),
              ),
            )
          else if (_listMode == 0 && _list.isNotEmpty)
            _isPc ? _buildUsStocksTablePc() : _buildUsStocksTable()
          else if (symbols.isEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 220),
              child: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('暂无数据', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _refreshQuotesForCurrentMode,
                      icon: const Icon(Icons.refresh, size: 20),
                      label: const Text('重试'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFD4AF37)),
                    ),
                  ],
                ),
              ),
            )
          else
            ...symbols.map((sym) {
              final q = _quotes[sym];
              PolygonGainer? snap;
              for (final g in _list) {
                if (g.ticker == sym) { snap = g; break; }
              }
              return QuoteRow(
                symbol: sym,
                name: q?.name,
                price: q?.price ?? 0,
                change: q?.change ?? 0,
                changePercent: q?.changePercent ?? 0,
                showSparkline: true,
                hasError: q?.hasError ?? false,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StockChartPage(
                        symbol: sym,
                        initialSnapshot: snap,
                        isMockData: _isMockData,
                      ),
                    ),
                  );
                },
              );
            }),
          const SizedBox(height: 14),
          _buildUsIndicesBar(),
        ],
      ),
    );
  }

  /// 美股热门：与首页一致的完整表格（代码、名称、涨跌幅、最新价、涨跌额、今开、昨收、最高、最低、成交量）
  Widget _buildUsStocksTable() {
    const colCode = 56.0;
    const colName = 56.0;
    const colPct = 62.0;
    const colPrice = 58.0;
    const colChange = 52.0;
    const colOpen = 52.0;
    const colPrev = 52.0;
    const colHigh = 52.0;
    const colLow = 52.0;
    const colVol = 64.0;
    const styleLabel = TextStyle(color: Color(0xFF6B6B70), fontSize: 11, fontWeight: FontWeight.w600);
    const styleCell = TextStyle(color: Color(0xFFE8D5A3), fontSize: 12);
    const styleMuted = TextStyle(color: Color(0xFF9CA3AF), fontSize: 12);

    final headerRow = Row(
      children: [
        SizedBox(width: colCode, child: Text('代码', style: styleLabel)),
        SizedBox(width: colName, child: Text('名称', style: styleLabel)),
        SizedBox(width: colPct, child: Text('涨跌幅', style: styleLabel)),
        SizedBox(width: colPrice, child: Text('最新价', style: styleLabel)),
        SizedBox(width: colChange, child: Text('涨跌额', style: styleLabel)),
        SizedBox(width: colOpen, child: Text('今开', style: styleLabel)),
        SizedBox(width: colPrev, child: Text('昨收', style: styleLabel)),
        SizedBox(width: colHigh, child: Text('最高', style: styleLabel)),
        SizedBox(width: colLow, child: Text('最低', style: styleLabel)),
        SizedBox(width: colVol, child: Text('成交量', style: styleLabel)),
      ],
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1C21),
              border: Border(bottom: BorderSide(color: const Color(0xFF1F1F23), width: 0.6)),
            ),
            child: headerRow,
          ),
          ..._list.map((g) {
            final color = MarketColors.forChangePercent(g.todaysChangePerc);
            final effectivePrice = (g.price != null && g.price! > 0)
                ? g.price!
                : (g.prevClose != null ? g.prevClose! + g.todaysChange : null);
            return Material(
              color: const Color(0xFF111215),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StockChartPage(
                        symbol: g.ticker,
                        initialSnapshot: g,
                        isMockData: _isMockData,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFF1F1F23), width: 0.6)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: colCode, child: Text(g.ticker, style: styleCell.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: colName, child: Text(g.ticker, style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: colPct, child: Text('${g.todaysChangePerc >= 0 ? '+' : ''}${g.todaysChangePerc.toStringAsFixed(2)}%', style: styleMuted.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: colPrice, child: Text(effectivePrice != null && effectivePrice > 0 ? _formatPrice(effectivePrice) : '—', style: styleCell, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: colChange, child: Text('${g.todaysChange >= 0 ? '+' : ''}${g.todaysChange.toStringAsFixed(2)}', style: styleMuted.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: colOpen, child: Text(g.dayOpen != null && g.dayOpen! > 0 ? _formatPrice(g.dayOpen!) : '—', style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: colPrev, child: Text(g.prevClose != null && g.prevClose! > 0 ? _formatPrice(g.prevClose!) : '—', style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: colHigh, child: Text(g.dayHigh != null && g.dayHigh! > 0 ? _formatPrice(g.dayHigh!) : '—', style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: colLow, child: Text(g.dayLow != null && g.dayLow! > 0 ? _formatPrice(g.dayLow!) : '—', style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: colVol, child: Text(_formatVolume(g.dayVolume), style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// PC 端：表格铺满可用宽度，右侧不留白
  Widget _buildUsStocksTablePc() {
    const colCode = 56.0;
    const colName = 56.0;
    const colPct = 62.0;
    const colPrice = 58.0;
    const colChange = 52.0;
    const colOpen = 52.0;
    const colPrev = 52.0;
    const colHigh = 52.0;
    const colLow = 52.0;
    const colVol = 64.0;
    const styleLabel = TextStyle(color: Color(0xFF6B6B70), fontSize: 11, fontWeight: FontWeight.w600);
    const styleCell = TextStyle(color: Color(0xFFE8D5A3), fontSize: 12);
    const styleMuted = TextStyle(color: Color(0xFF9CA3AF), fontSize: 12);

    final fullWidth = MediaQuery.sizeOf(context).width - 32;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite && constraints.maxWidth > 0 ? constraints.maxWidth : fullWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: w,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1C21),
                    border: Border(bottom: BorderSide(color: const Color(0xFF1F1F23), width: 0.6)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: colCode, child: Text('代码', style: styleLabel)),
                      SizedBox(width: colName, child: Text('名称', style: styleLabel)),
                      SizedBox(width: colPct, child: Text('涨跌幅', style: styleLabel)),
                      SizedBox(width: colPrice, child: Text('最新价', style: styleLabel)),
                      SizedBox(width: colChange, child: Text('涨跌额', style: styleLabel)),
                      SizedBox(width: colOpen, child: Text('今开', style: styleLabel)),
                      SizedBox(width: colPrev, child: Text('昨收', style: styleLabel)),
                      SizedBox(width: colHigh, child: Text('最高', style: styleLabel)),
                      SizedBox(width: colLow, child: Text('最低', style: styleLabel)),
                      SizedBox(width: colVol, child: Text('成交量', style: styleLabel)),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                ),
                ..._list.map((g) {
                  final color = MarketColors.forChangePercent(g.todaysChangePerc);
                  final effectivePrice = (g.price != null && g.price! > 0)
                      ? g.price!
                      : (g.prevClose != null ? g.prevClose! + g.todaysChange : null);
                  return Material(
                    color: const Color(0xFF111215),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StockChartPage(
                              symbol: g.ticker,
                              initialSnapshot: g,
                              isMockData: _isMockData,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: w,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFF1F1F23), width: 0.6)),
                        ),
                        child: Row(
                          children: [
                            SizedBox(width: colCode, child: Text(g.ticker, style: styleCell.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colName, child: Text(g.ticker, style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colPct, child: Text('${g.todaysChangePerc >= 0 ? '+' : ''}${g.todaysChangePerc.toStringAsFixed(2)}%', style: styleMuted.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colPrice, child: Text(effectivePrice != null && effectivePrice > 0 ? _formatPrice(effectivePrice) : '—', style: styleCell, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colChange, child: Text('${g.todaysChange >= 0 ? '+' : ''}${g.todaysChange.toStringAsFixed(2)}', style: styleMuted.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colOpen, child: Text(g.dayOpen != null && g.dayOpen! > 0 ? _formatPrice(g.dayOpen!) : '—', style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colPrev, child: Text(g.prevClose != null && g.prevClose! > 0 ? _formatPrice(g.prevClose!) : '—', style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colHigh, child: Text(g.dayHigh != null && g.dayHigh! > 0 ? _formatPrice(g.dayHigh!) : '—', style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colLow, child: Text(g.dayLow != null && g.dayLow! > 0 ? _formatPrice(g.dayLow!) : '—', style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: colVol, child: Text(_formatVolume(g.dayVolume), style: styleMuted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            const Expanded(child: SizedBox.shrink()),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUsIndicesBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1F1F23)),
      ),
      child: Row(
        children: [
          const Text('三大指数 ', style: TextStyle(color: Color(0xFF6B6B70), fontSize: 12)),
          ...List.generate(3, (i) {
            final sym = _indexSymbols[i];
            final name = _indexNames[i];
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
                    style: TextStyle(color: hasError ? const Color(0xFF6B6B70) : Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
    );
  }

  Widget _buildMockBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: const Color(0xFFD4AF37)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '当前为模拟数据，仅作界面展示。配置 POLYGON_API_KEY 后可显示真实行情。',
              style: TextStyle(color: Color(0xFFE8D5A3), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 美股三大指数卡：优先用接口数据，无则用 mock
  Widget _buildUsIndexCards() {
    final indices = [
      ('道琼斯', 'DJI'),
      ('纳斯达克', 'IXIC'),
      ('标普500', 'SPX'),
    ];
    final data = <(String, String, double, double, double)>[];
    for (final e in indices) {
      final q = _indexQuotes[e.$2];
      if (q != null && !q.hasError && q.price > 0) {
        data.add((e.$1, e.$2, q.price, q.change, q.changePercent));
      } else {
        final mockList = MockMarketData.indicesQuotes;
        Map<String, dynamic>? m;
        for (final x in mockList) {
          if (x is Map<String, dynamic> && x['symbol'] == e.$2) { m = x; break; }
        }
        if (m != null) {
          final close = (m['close'] as num?)?.toDouble() ?? 0.0;
          final ch = (m['change'] as num?)?.toDouble() ?? 0.0;
          final pct = (m['percent_change'] as num?)?.toDouble() ?? 0.0;
          data.add((e.$1, e.$2, close, ch, pct));
        } else {
          data.add((e.$1, e.$2, 0.0, 0.0, 0.0));
        }
      }
    }
    return Row(
      children: data.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final name = e.$1;
        final value = e.$3;
        final ch = e.$4;
        final pct = e.$5;
        final isUp = pct >= 0;
        final color = MarketColors.forUp(isUp);
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < data.length - 1 ? 6 : 0),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF111215),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  value > 0 ? value.toStringAsFixed(2) : '—',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  value > 0 ? '${ch >= 0 ? '+' : ''}${ch.toStringAsFixed(2)} ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%' : '—',
                  style: TextStyle(color: color, fontSize: 10),
                ),
                const SizedBox(height: 4),
                SizedBox(height: 20, child: _MiniSparkline(percentChange: pct)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFFD4AF37).withOpacity(0.2)
          : const Color(0xFF1F1F23),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFFD4AF37) : const Color(0xFF9CA3AF),
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C21),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          SizedBox(
              width: 28,
              child: Text('#',
                  style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          SizedBox(width: 8),
          SizedBox(
              width: 56,
              child: Text('代码',
                  style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          Spacer(),
          Text('最新',
              style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          SizedBox(width: 12),
          SizedBox(
              width: 56,
              child: Text('涨跌',
                  style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          SizedBox(width: 8),
          SizedBox(
              width: 52,
              child: Text('涨跌幅',
                  style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          SizedBox(width: 8),
          SizedBox(
              width: 56,
              child: Text('成交量',
                  style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

String _formatVolume(int? vol) {
  if (vol == null || vol <= 0) return '—';
  if (vol >= 1000000) return '${(vol / 1000000).toStringAsFixed(1)}M';
  if (vol >= 1000) return '${(vol / 1000).toStringAsFixed(1)}K';
  return vol.toString();
}

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.rank,
    required this.symbol,
    required this.price,
    required this.change,
    required this.changePct,
    this.volume,
    required this.onTap,
  });

  final int rank;
  final String symbol;
  final double price;
  final double change;
  final double changePct;
  final int? volume;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUp = changePct >= 0;
    final color = MarketColors.forUp(isUp);
    final changeStr = (change >= 0 ? '+' : '') + change.toStringAsFixed(2);
    final pctStr =
        (changePct >= 0 ? '+' : '') + changePct.toStringAsFixed(2) + '%';
    return Material(
      color: const Color(0xFF111215),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Color(0xFF1F1F23), width: 0.6)),
          ),
          child: Row(
            children: [
              SizedBox(
                  width: 28,
                  child: Text('$rank',
                      style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 13,
                          fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 56,
                  child: Text(symbol,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              const Spacer(),
              Text(price.toStringAsFixed(2),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(width: 12),
              SizedBox(
                  width: 56,
                  child: Text(changeStr,
                      style: TextStyle(color: color, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              SizedBox(
                  width: 52,
                  child: Text(pctStr,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              SizedBox(
                  width: 56,
                  child: Text(_formatVolume(volume),
                      style: const TextStyle(
                          color: Color(0xFF9CA3AF), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- 外汇：Twelve Data ----------

class _ForexTab extends StatefulWidget {
  const _ForexTab();

  @override
  State<_ForexTab> createState() => _ForexTabState();
}

class _ForexTabState extends State<_ForexTab> {
  final _market = MarketRepository();
  final _snapshotRepo = MarketSnapshotRepository();
  final _pairs = [
    ('欧元/美元', 'EUR/USD'),
    ('美元/日元', 'USD/JPY'),
    ('英镑/美元', 'GBP/USD'),
    ('澳元/美元', 'AUD/USD'),
    ('美元/瑞郎', 'USD/CHF'),
    ('美元/加元', 'USD/CAD'),
  ];
  Map<String, MarketQuote?> _quotes = {};
  bool _loading = true;
  bool _isMockData = false;
  static final _cache = TradingCache.instance;
  static const _cacheMaxAge = Duration(days: 7);

  @override
  void initState() {
    super.initState();
    _loadCachedThenRefresh();
  }

  Future<void> _loadCachedThenRefresh() async {
    setState(() { _loading = true; _isMockData = false; });
    final out = <String, MarketQuote?>{};
    final list = await _cache.getList('market_forex_tab', maxAge: _cacheMaxAge);
    if (list != null) for (final m in list) {
      if (m is Map<String, dynamic>) { final q = MarketQuote.fromSnapshotMap(m); if (q != null) out[q.symbol] = q; }
    }
    if (out.length < _pairs.length) {
      final fromDb = await _snapshotRepo.getQuotes('forex');
      for (final m in fromDb) { final q = MarketQuote.fromSnapshotMap(m); if (q != null) out[q.symbol] = q; }
    }
    if (mounted) setState(() {
      _quotes = out;
      _loading = out.isEmpty;
    });
    _load();
  }

  void _applyMockForex() {
    final out = <String, MarketQuote?>{};
    for (final m in MockMarketData.forexQuotes) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null) out[q.symbol] = q;
    }
    _quotes = out;
    _isMockData = true;
  }

  Future<void> _load() async {
    if (!_market.twelveDataAvailable) {
      if (_quotes.isEmpty) _applyMockForex();
      if (mounted) setState(() => _loading = false);
      return;
    }
    final out = <String, MarketQuote?>{};
    for (final e in _pairs) {
      out[e.$2] = await _market.getQuote(e.$2);
      await Future.delayed(const Duration(milliseconds: 80));
    }
    final hasAny = _pairs.any((e) => out[e.$2] != null);
    if (hasAny) {
      final list = <Map<String, dynamic>>[];
      for (final e in _pairs) {
        final q = out[e.$2];
        if (q != null) list.add({...q.toSnapshotMap(), 'name': e.$1});
      }
      if (list.isNotEmpty) {
        await _snapshotRepo.saveQuotes('forex', list);
        await _cache.setList('market_forex_tab', list);
      }
    }
    final fromDb = await _snapshotRepo.getQuotes('forex');
    for (final m in fromDb) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null && out[q.symbol] == null) out[q.symbol] = q;
    }
    if (mounted) {
      if (out.isEmpty) _applyMockForex();
      else {
        _quotes = out;
        _isMockData = false;
      }
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _quotes.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
    }
    if (_quotes.isEmpty) {
      return const Center(
          child: Text('暂无数据', style: TextStyle(color: Color(0xFF9CA3AF))));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFD4AF37),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_isMockData) _forexCryptoMockBanner(),
          ...List.generate(_pairs.length, (i) {
            final name = _pairs[i].$1;
            final symbol = _pairs[i].$2;
            final q = _quotes[symbol];
            return QuoteRow(
              symbol: symbol,
              name: name,
              price: q?.price ?? 0,
              change: q?.change ?? 0,
              changePercent: q?.changePercent ?? 0,
              hasError: q?.hasError ?? true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GenericChartPage(symbol: symbol, name: name),
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _forexCryptoMockBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFFD4AF37)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前为模拟数据。配置 TWELVE_DATA_API_KEY 后可显示真实行情。',
              style: TextStyle(color: Color(0xFFE8D5A3), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- 加密货币：Twelve Data ----------

class _CryptoTab extends StatefulWidget {
  const _CryptoTab();

  @override
  State<_CryptoTab> createState() => _CryptoTabState();
}

class _CryptoTabState extends State<_CryptoTab> {
  final _market = MarketRepository();
  final _snapshotRepo = MarketSnapshotRepository();
  final _coins = [
    ('比特币', 'BTC/USD'),
    ('以太坊', 'ETH/USD'),
    ('Solana', 'SOL/USD'),
    ('瑞波币', 'XRP/USD'),
    ('狗狗币', 'DOGE/USD'),
    ('雪崩', 'AVAX/USD'),
  ];
  /// 0=市值 1=领涨榜 2=领跌榜
  int _cryptoSubTab = 0;
  Map<String, MarketQuote?> _quotes = {};
  bool _loading = true;
  bool _isMockData = false;
  static final _cache = TradingCache.instance;
  static const _cacheMaxAge = Duration(days: 7);

  static const _hotReads = [
    '比特币价格低于大行ETF成本线!捞底华尔街的时机...',
    '白宫施压银行同意稳定币奖励并推进加密市场结构法案',
    '币价大跌不用慌?特朗普家族加密货币平台海湖庄园...',
  ];

  @override
  void initState() {
    super.initState();
    _loadCachedThenRefresh();
  }

  Future<void> _loadCachedThenRefresh() async {
    setState(() { _loading = true; _isMockData = false; });
    final out = <String, MarketQuote?>{};
    final list = await _cache.getList('market_crypto_tab', maxAge: _cacheMaxAge);
    if (list != null) for (final m in list) {
      if (m is Map<String, dynamic>) { final q = MarketQuote.fromSnapshotMap(m); if (q != null) out[q.symbol] = q; }
    }
    if (out.length < _coins.length) {
      final fromDb = await _snapshotRepo.getQuotes('crypto');
      for (final m in fromDb) { final q = MarketQuote.fromSnapshotMap(m); if (q != null) out[q.symbol] = q; }
    }
    if (mounted) setState(() {
      _quotes = out;
      _loading = out.isEmpty;
    });
    _load();
  }

  void _applyMockCrypto() {
    final out = <String, MarketQuote?>{};
    for (final m in MockMarketData.cryptoQuotes) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null) out[q.symbol] = q;
    }
    _quotes = out;
    _isMockData = true;
  }

  Future<void> _load() async {
    if (!_market.twelveDataAvailable) {
      if (_quotes.isEmpty) _applyMockCrypto();
      if (mounted) setState(() => _loading = false);
      return;
    }
    final list = await _market.getCryptoQuotes(_coins.map((e) => e.$2).toList());
    final out = <String, MarketQuote?>{};
    for (final q in list) {
      out[q.symbol] = q;
    }
    final hasAny = out.isNotEmpty;
    if (hasAny) {
      final toSave = list.map((q) => {...q.toSnapshotMap(), 'name': q.name ?? q.symbol}).toList();
      if (toSave.isNotEmpty) {
        await _snapshotRepo.saveQuotes('crypto', toSave);
        await _cache.setList('market_crypto_tab', toSave);
      }
    }
    final fromDb = await _snapshotRepo.getQuotes('crypto');
    for (final m in fromDb) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null && out[q.symbol] == null) out[q.symbol] = q;
    }
    if (mounted) {
      if (out.isEmpty) _applyMockCrypto();
      else {
        _quotes = out;
        _isMockData = false;
      }
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _quotes.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
    }
    if (_quotes.isEmpty) {
      return const Center(
          child: Text('暂无数据', style: TextStyle(color: Color(0xFF9CA3AF))));
    }
    final sorted = _sortedCryptoList();
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFD4AF37),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_isMockData) _cryptoMockBanner(),
          const SizedBox(height: 8),
          _buildCryptoTopCards(),
          const SizedBox(height: 20),
          _buildHotReads(context),
          const SizedBox(height: 20),
          _buildTradableCryptoSection(context, sorted),
        ],
      ),
    );
  }

  /// 市值=原顺序，领涨=按涨幅降序，领跌=按涨幅升序
  List<(String, String, MarketQuote?)> _sortedCryptoList() {
    final list = _coins.map((e) => (e.$1, e.$2, _quotes[e.$2])).toList();
    if (_cryptoSubTab == 1) {
      list.sort((a, b) {
        final pa = a.$3?.changePercent ?? double.negativeInfinity;
        final pb = b.$3?.changePercent ?? double.negativeInfinity;
        return pb.compareTo(pa);
      });
    } else if (_cryptoSubTab == 2) {
      list.sort((a, b) {
        final pa = a.$3?.changePercent ?? double.infinity;
        final pb = b.$3?.changePercent ?? double.infinity;
        return pa.compareTo(pb);
      });
    }
    return list;
  }

  /// 顶部三卡：比特币、以太坊、Solana（与参考图一致）
  Widget _buildCryptoTopCards() {
    final top3 = _coins.take(3).toList();
    return Row(
      children: top3.asMap().entries.map((entry) {
        final i = entry.key;
        final name = entry.value.$1;
        final symbol = entry.value.$2;
        final q = _quotes[symbol];
        final close = q?.price ?? 0.0;
        final ch = q?.change ?? 0.0;
        final pct = q?.changePercent ?? 0.0;
        final isUp = pct >= 0;
        final color = MarketColors.forUp(isUp);
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF111215),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  close > 0 ? _formatCryptoPrice(close) : '—',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
                ),
                Text(
                  close > 0 ? '${ch >= 0 ? '+' : ''}${ch.toStringAsFixed(2)} ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%' : '—',
                  style: TextStyle(color: color, fontSize: 11),
                ),
                const SizedBox(height: 6),
                SizedBox(height: 22, child: _MiniSparkline(percentChange: pct)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatCryptoPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  /// 热点解读 + 订阅专题（与参考图一致）
  Widget _buildHotReads(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('热点解读', style: TextStyle(color: const Color(0xFFD4AF37), fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios, size: 12, color: const Color(0xFFD4AF37)),
            const Spacer(),
            GestureDetector(
              onTap: () {},
              child: Text('订阅专题 >', style: TextStyle(color: const Color(0xFF9CA3AF), fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._hotReads.map((title) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.local_fire_department, size: 18, color: const Color(0xFFD4AF37)),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 13))),
            ],
          ),
        )),
      ],
    );
  }

  /// 可交易币种：子 Tab 市值/领涨榜/领跌榜 + 列表
  Widget _buildTradableCryptoSection(BuildContext context, List<(String, String, MarketQuote?)> sorted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('可交易币种', style: TextStyle(color: const Color(0xFFE8D5A3), fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios, size: 12, color: const Color(0xFFD4AF37)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _CryptoSubChip(label: '市值', selected: _cryptoSubTab == 0, onTap: () => setState(() => _cryptoSubTab = 0)),
            const SizedBox(width: 8),
            _CryptoSubChip(label: '领涨榜', selected: _cryptoSubTab == 1, onTap: () => setState(() => _cryptoSubTab = 1)),
            const SizedBox(width: 8),
            _CryptoSubChip(label: '领跌榜', selected: _cryptoSubTab == 2, onTap: () => setState(() => _cryptoSubTab = 2)),
          ],
        ),
        const SizedBox(height: 12),
        ...sorted.map((e) => QuoteRow(
          symbol: e.$2,
          name: e.$1,
          price: e.$3?.price ?? 0,
          change: e.$3?.change ?? 0,
          changePercent: e.$3?.changePercent ?? 0,
          hasError: e.$3?.hasError ?? true,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GenericChartPage(symbol: e.$2, name: e.$1),
              ),
            );
          },
        )),
      ],
    );
  }

  Widget _cryptoMockBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFFD4AF37)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前为模拟数据。配置 TWELVE_DATA_API_KEY 后可显示真实行情。',
              style: TextStyle(color: Color(0xFFE8D5A3), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CryptoSubChip extends StatelessWidget {
  const _CryptoSubChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2C2D31) : const Color(0xFF111215),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? const Color(0xFFD4AF37).withValues(alpha: 0.4) : const Color(0xFF2C2D31)),
        ),
        child: Text(label, style: TextStyle(color: selected ? const Color(0xFFE8D5A3) : const Color(0xFF9CA3AF), fontSize: 13)),
      ),
    );
  }
}

