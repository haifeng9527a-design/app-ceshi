import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/layout_mode.dart';
import '../../core/pc_dashboard_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/app_button.dart';
import '../../ui/components/app_card.dart';
import '../../ui/components/app_chip.dart';
import '../../ui/tv_theme.dart';
import '../../ui/widgets/index_card.dart';
import '../../ui/widgets/quote_table.dart';
import '../../ui/widgets/segmented_tabs.dart';
import 'widgets/market_header.dart';
import 'widgets/market_section_label.dart';
import 'widgets/market_search_bar.dart';
import '../trading/market_snapshot_repository.dart';
import '../trading/mock_market_data.dart';
import '../../core/chat_web_socket_service.dart';
import '../trading/realtime_quote_service.dart';
import '../trading/trading_cache.dart';
import 'gainers_losers_page.dart';
import 'generic_chart_page.dart';
import 'market_colors.dart';
import 'market_db.dart';
import 'market_repository.dart';
import 'market_sync_service.dart';
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
  static const int _tabCount = 4;

  List<String> _tabs(BuildContext context) => [
        AppLocalizations.of(context)!.marketTabHome,
        AppLocalizations.of(context)!.marketTabUsStock,
        AppLocalizations.of(context)!.marketTabForex,
        AppLocalizations.of(context)!.marketTabCrypto,
      ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    MarketSyncService.instance.syncOnEnter();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isPc => LayoutMode.useDesktopLikeLayout(context);

  @override
  Widget build(BuildContext context) {
    if (_isPc) return _buildPcPage(context);
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            const MarketHeader(),
            SizedBox(
              height: 46,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                labelPadding: AppSpacing.symmetric(horizontal: AppSpacing.md),
                tabs: _tabs(context).map((e) => Tab(text: e)).toList(),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _HomeTab(onSwitchToTab: (i) => _tabController.animateTo(i)),
                  _UsStocksTab(tabController: _tabController),
                  const _ForexTab(),
                  const _CryptoTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// PC 端：TradingView 风格，Shell 已有顶栏
  Widget _buildPcPage(BuildContext context) {
    return Material(
      color: TvTheme.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPcTabBar(context),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _HomeTab(onSwitchToTab: (i) => _tabController.animateTo(i)),
                _UsStocksTab(tabController: _tabController),
                const _ForexTab(),
                const _CryptoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// PC 端 Tab 栏：SegmentedTabs（首页/美股/外汇/加密货币）+ 自选入口
  Widget _buildPcTabBar(BuildContext context) {
    return ListenableBuilder(
      listenable: _tabController,
      builder: (context, _) {
        final idx = _tabController.index;
        return Container(
          padding: const EdgeInsets.symmetric(
              vertical: 12, horizontal: TvTheme.pagePadding),
          decoration: BoxDecoration(
            color: TvTheme.bg,
            border: Border(bottom: BorderSide(color: TvTheme.border, width: 1)),
          ),
          child: Row(
            children: [
              SegmentedTabs(
                labels: _tabs(context),
                selectedIndex: idx,
                onSelected: (i) => _tabController.animateTo(i),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WatchlistPage()),
                  );
                },
                icon: Icon(Icons.star_border_rounded,
                    size: 18, color: TvTheme.textSecondary),
                label: Text(AppLocalizations.of(context)!.navWatchlist,
                    style: TvTheme.bodySecondary
                        .copyWith(color: TvTheme.positive)),
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
}

// ---------- 首页：Market Dashboard（列表为主，国际习惯）---------

class _HomeTab extends StatefulWidget {
  const _HomeTab({this.onSwitchToTab});
  final void Function(int index)? onSwitchToTab;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with WidgetsBindingObserver {
  final _market = MarketRepository();
  final _watchlist = WatchlistRepository.instance;
  static final _cache = TradingCache.instance;
  final _snapshotRepo = MarketSnapshotRepository();
  final _realtime = RealtimeQuoteService();
  StreamSubscription<List<PolygonGainer>>? _gainersSub;
  StreamSubscription<List<PolygonGainer>>? _losersSub;
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

  /// PC 右列（加密货币）面板：true = 涨幅榜，false = 跌幅榜
  bool _showMarketHeatGainers = true;

  static const _cryptoSymbols = [
    'BTC',
    'ETH',
    'SOL',
    'XRP',
    'DOGE',
    'ADA',
    'AVAX',
    'DOT',
    'MATIC',
    'LINK'
  ];

  /// 首页左列展示的外汇品种（名称, symbol），6 条与涨跌榜/加密货币列等高对齐
  static const _forexForHome = [
    ('欧元/美元', 'EUR/USD'),
    ('美元/日元', 'USD/JPY'),
    ('英镑/美元', 'GBP/USD'),
    ('澳元/美元', 'AUD/USD'),
    ('美元/瑞郎', 'USD/CHF'),
    ('美元/加元', 'USD/CAD'),
  ];
  Map<String, MarketQuote> _forexQuotes = {};
  static const _loadTimeout = Duration(seconds: 12);
  static const int _homeMoverFetchLimit = 50;
  static const int _homeMoverDisplayLimit = 5;
  static const _homeRefreshInterval = Duration(seconds: 15);
  Timer? _homeRefreshTimer;
  bool _loadingLatest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gainersSub = _realtime.gainersStream.listen((list) {
      if (mounted) setState(() => _gainers = list);
    });
    _losersSub = _realtime.losersStream.listen((list) {
      if (mounted) setState(() => _losers = list);
    });
    _loadCachedThenRefresh();
    _startHomeLatestTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _homeRefreshTimer?.cancel();
    _gainersSub?.cancel();
    _losersSub?.cancel();
    _realtime.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshHomeLatest();
    }
  }

  /// 先读本地/缓存并展示，再后台拉接口；有缓存或超时后也会结束 loading，避免一直转圈
  Future<void> _loadCachedThenRefresh() async {
    setState(() => _loading = true);
    await _loadFromCache();
    if (mounted) setState(() => _loading = false);
    _load();
  }

  void _startHomeLatestTimer() {
    _homeRefreshTimer?.cancel();
    _homeRefreshTimer = Timer.periodic(_homeRefreshInterval, (_) {
      _refreshHomeLatest();
    });
  }

  Future<void> _refreshHomeLatest() async {
    if (!mounted || _loadingLatest) return;
    _loadingLatest = true;
    try {
      await _load();
    } finally {
      _loadingLatest = false;
    }
  }

  /// 从本地缓存快速加载：指数（TradingCache + Supabase 快照）、涨跌榜缓存
  Future<void> _loadFromCache() async {
    final indexQuotes = <String, MarketQuote>{};
    final indicesList =
        await _cache.getList('market_overview_indices', maxAge: _cacheMaxAge);
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
        if (q != null && !indexQuotes.containsKey(q.symbol))
          indexQuotes[q.symbol] = q;
      }
    }
    List<PolygonGainer> gainers = [];
    List<PolygonGainer> losers = [];
    // 首屏尽量展示旧缓存（与指数一致 7 天），避免空白；后续 _load() 会拉实时数据更新
    final cachedG = await _market.getCachedGainersOnly(maxAge: _cacheMaxAge);
    if (cachedG != null && cachedG.isNotEmpty) {
      gainers = cachedG.take(_homeMoverFetchLimit).toList();
    }
    final cachedL = await _market.getCachedLosersOnly(maxAge: _cacheMaxAge);
    if (cachedL != null && cachedL.isNotEmpty) {
      losers = cachedL.take(_homeMoverFetchLimit).toList();
    }

    final list = await _watchlist.getWatchlist();
    final take6 = list.take(6).toList();

    final forexQuotes = <String, MarketQuote>{};
    final forexList =
        await _cache.getList('market_overview_forex', maxAge: _cacheMaxAge);
    if (forexList != null) {
      for (final m in forexList) {
        if (m is Map<String, dynamic>) {
          final q = MarketQuote.fromSnapshotMap(m);
          if (q != null && !q.hasError) forexQuotes[q.symbol] = q;
        }
      }
    }
    final homeForexSymbols = _forexForHome.map((e) => e.$2).toList();
    final forexFromSqlite =
        await MarketDb.instance.getForexQuotes(homeForexSymbols);
    for (final sym in homeForexSymbols) {
      final q = forexFromSqlite[sym];
      if (q != null && !q.hasError && !forexQuotes.containsKey(sym)) {
        forexQuotes[sym] = q;
      }
    }
    final cryptoQuotes = <String, MarketQuote>{};
    final cryptoList =
        await _cache.getList('market_overview_crypto', maxAge: _cacheMaxAge);
    if (cryptoList != null) {
      for (final m in cryptoList) {
        if (m is Map<String, dynamic>) {
          final q = MarketQuote.fromSnapshotMap(m);
          if (q != null && !q.hasError) {
            final key =
                q.symbol.contains('/') ? q.symbol.split('/').first : q.symbol;
            cryptoQuotes[key] = q;
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _indexQuotes = indexQuotes;
      _gainers = gainers;
      _losers = losers;
      _watchlistSymbols = take6;
      _forexQuotes = forexQuotes;
      _trendingCryptoQuotes = cryptoQuotes;
      if (indexQuotes.isEmpty) _applyMockIndices();
      if (gainers.isEmpty && losers.isEmpty) _applyMockGainersLosers();
      // 首屏即展示外汇/加密货币（无接口时用 Mock），避免一直显示「暂无数据」
      _applyMockForexIfEmpty();
      _applyMockCryptoIfEmpty();
    });
    if (_gainers.isNotEmpty || _losers.isNotEmpty) {
      _realtime.setGainersLosers(gainers: _gainers, losers: _losers);
    }
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
          _safeGetGainers(_homeMoverFetchLimit),
          _safeGetLosers(_homeMoverFetchLimit),
        ]),
        Future.delayed(_loadTimeout, () => throw TimeoutException('首页行情请求超时')),
      ]);
      indexQuotes = result[0] as Map<String, MarketQuote>;
      gainers = result[1] as List<PolygonGainer>;
      losers = result[2] as List<PolygonGainer>;
    } on TimeoutException catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _applyMockForexIfEmpty();
          _applyMockCryptoIfEmpty();
        });
      return;
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _applyMockForexIfEmpty();
          _applyMockCryptoIfEmpty();
        });
      return;
    }

    final list = await _watchlist.getWatchlist();
    final take6 = list.take(6).toList();

    final watchQuotesFuture = take6.isEmpty
        ? Future<Map<String, MarketQuote>>.value({})
        : _market.getQuotes(take6);
    final trendingFuture = _safeGetGainers(10);
    final cryptoFuture = _market.getQuotes(_cryptoSymbols);
    final forexSymbols = _forexForHome.map((e) => e.$2).toList();
    final forexFuture = _market.getQuotes(forexSymbols);

    Map<String, MarketQuote> watchQuotes = {};
    List<PolygonGainer> trendingStocks = [];
    Map<String, MarketQuote> cryptoQuotes = {};
    Map<String, MarketQuote> forexQuotes = {};
    try {
      final results2 = await Future.wait([
        watchQuotesFuture,
        trendingFuture,
        cryptoFuture,
        forexFuture,
      ]);
      watchQuotes = results2[0] as Map<String, MarketQuote>;
      trendingStocks = results2[1] as List<PolygonGainer>;
      cryptoQuotes = results2[2] as Map<String, MarketQuote>;
      forexQuotes = results2[3] as Map<String, MarketQuote>;
    } catch (_) {
      // 自选/热门/加密货币/外汇失败不影响主内容
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
      _forexQuotes = forexQuotes;
      _loading = false;
      _applyMockIndices();
      _applyMockForexIfEmpty();
      _applyMockCryptoIfEmpty();
    });
    if (gainers.isNotEmpty || losers.isNotEmpty) {
      _realtime.setGainersLosers(gainers: gainers, losers: losers);
    }

    await _writeIndexCache(_indexQuotes);
    await _writeForexCache();
    await _writeCryptoCache();
  }

  Future<void> _writeForexCache() async {
    final fl = <Map<String, dynamic>>[];
    final toSave = <String, MarketQuote>{};
    for (final e in _forexForHome) {
      final q = _forexQuotes[e.$2];
      if (q != null && !q.hasError) {
        fl.add({...q.toSnapshotMap(), 'name': e.$1});
        toSave[e.$2] = q;
      }
    }
    if (fl.isNotEmpty) await _cache.setList('market_overview_forex', fl);
    if (toSave.isNotEmpty) await MarketDb.instance.upsertForexQuotes(toSave);
  }

  Future<void> _writeCryptoCache() async {
    final cl = <Map<String, dynamic>>[];
    for (final sym in _cryptoSymbols) {
      final q = _trendingCryptoQuotes[sym];
      if (q != null && !q.hasError) cl.add(q.toSnapshotMap());
    }
    if (cl.isNotEmpty) await _cache.setList('market_overview_crypto', cl);
  }

  /// 外汇 API 无数据时用 Mock 填充，保证首页左列有展示
  void _applyMockForexIfEmpty() {
    final hasValid =
        _forexQuotes.isNotEmpty && _forexQuotes.values.any((q) => !q.hasError);
    if (hasValid) return;
    final mock = <String, MarketQuote>{};
    for (final m in MockMarketData.forexQuotes) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null) mock[q.symbol] = q;
    }
    for (final e in _forexForHome) {
      final sym = e.$2;
      if (mock[sym] != null) _forexQuotes[sym] = mock[sym]!;
    }
  }

  /// 加密货币 API 无数据时用 Mock 填充，保证首页右列有展示
  void _applyMockCryptoIfEmpty() {
    final hasValid = _trendingCryptoQuotes.isNotEmpty &&
        _trendingCryptoQuotes.values.any((q) => !q.hasError);
    if (hasValid) return;
    final mock = <String, MarketQuote>{};
    for (final m in MockMarketData.cryptoQuotes) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null) {
        final key = q.symbol.split('/').first;
        mock[key] = q;
      }
    }
    for (final sym in _cryptoSymbols) {
      if (mock[sym] != null) _trendingCryptoQuotes[sym] = mock[sym]!;
    }
  }

  Future<void> _writeIndexCache(Map<String, MarketQuote> out) async {
    final il = <Map<String, dynamic>>[];
    for (final e in _indexList) {
      final q = out[e.$2];
      if (q != null && !q.hasError)
        il.add({...q.toSnapshotMap(), 'name': e.$1});
    }
    if (il.isNotEmpty) await _cache.setList('market_overview_indices', il);
  }

  Future<List<PolygonGainer>> _safeGetGainers(int limit) async {
    try {
      return await _market.getTopGainers(limit: limit);
    } catch (_) {
      final cached =
          await _market.getCachedGainersOnly(maxAge: const Duration(hours: 48));
      return cached != null ? cached.take(limit).toList() : [];
    }
  }

  Future<List<PolygonGainer>> _safeGetLosers(int limit) async {
    try {
      return await _market.getTopLosers(limit: limit);
    } catch (_) {
      final cached =
          await _market.getCachedLosersOnly(maxAge: const Duration(hours: 48));
      return cached != null ? cached.take(limit).toList() : [];
    }
  }

  bool _isUsStock(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (s.isEmpty || s.length > 5) return false;
    if (s.contains('/')) return false;
    return s.runes.every((r) => r >= 0x41 && r <= 0x5A);
  }

  void _openDetail(String symbol,
      {String? name, List<String>? symbolList, int? symbolIndex}) {
    final n = name ?? _watchlistQuotes[symbol]?.name ?? symbol;
    if (_isUsStock(symbol)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StockChartPage(
            symbol: symbol,
            name: n != symbol ? n : null,
            symbolList: symbolList,
            symbolIndex: symbolIndex,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GenericChartPage(
            symbol: symbol,
            name: n,
            symbolList: symbolList,
            symbolIndex: symbolIndex,
          ),
        ),
      );
    }
  }

  bool get _isPcLayout {
    return LayoutMode.useDesktopLikeLayout(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading &&
        _indexQuotes.isEmpty &&
        _gainers.isEmpty &&
        _watchlistSymbols.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: _isPcLayout ? _buildPcLayout() : _buildMobileLayout(),
    );
  }

  Widget _buildMobileLayout() {
    return ListView(
      padding: AppSpacing.only(
          left: AppSpacing.md - AppSpacing.xs,
          top: AppSpacing.sm,
          right: AppSpacing.md - AppSpacing.xs,
          bottom: AppSpacing.lg),
      children: [
        MarketSearchBar(isPc: false),
        const SizedBox(height: AppSpacing.md - AppSpacing.xs),
        MarketSectionLabel(
            title: AppLocalizations.of(context)!.marketMajorIndexes),
        const SizedBox(height: AppSpacing.sm),
        _buildMajorIndexes(),
        const SizedBox(height: AppSpacing.md),
        MarketSectionLabel(
            title: AppLocalizations.of(context)!.marketTopMovers),
        const SizedBox(height: AppSpacing.sm),
        _buildTopMoversButtons(),
        const SizedBox(height: AppSpacing.xs),
        _buildGainersLosersRows(),
        const SizedBox(height: AppSpacing.md),
        _buildWatchlistSection(),
        const SizedBox(height: AppSpacing.md),
        const MarketSectionLabel(title: 'Trending'),
        const SizedBox(height: AppSpacing.sm),
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
          padding: const EdgeInsets.fromLTRB(
              TvTheme.pagePadding, TvTheme.sectionGap, TvTheme.pagePadding, 20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildPcIndicesShowcase(),
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

  /// 第一行三列等宽且等高对齐
  Widget _buildPcRow1ThreeCols() {
    return SizedBox(
      height: 438,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildPcWatchlistPanel()),
          const SizedBox(width: 16),
          Expanded(child: _buildPcGainersLosersCard()),
          const SizedBox(width: 16),
          Expanded(child: _buildPcMarketHeatPanel()),
        ],
      ),
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
                if (hasError && !isLoading) {
                  _load();
                  return;
                }
                if (hasError) return;
                final symbolList = _indexList.map((e) => e.$2).toList();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => GenericChartPage(
                          symbol: symbol,
                          name: label,
                          symbolList: symbolList,
                          symbolIndex: i)),
                );
              },
              borderRadius: BorderRadius.circular(_pcRadiusLg),
              child: Container(
                width: 160,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      style: PcDashboardTheme.bodySmall
                          .copyWith(color: PcDashboardTheme.text),
                    ),
                    if (isLoading)
                      const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFFD4AF37)))
                    else
                      Text(
                        hasError
                            ? '—'
                            : (q != null && q.price > 0
                                ? _formatPrice(q.price)
                                : '—'),
                        style: PcDashboardTheme.titleMedium.copyWith(
                          color: hasError
                              ? PcDashboardTheme.textMuted
                              : PcDashboardTheme.text,
                          fontFamily: 'monospace',
                        ),
                      ),
                    Row(
                      children: [
                        Icon(isUp ? Icons.trending_up : Icons.trending_down,
                            size: 14, color: color),
                        const SizedBox(width: 4),
                        Text(
                          hasError
                              ? '—'
                              : '${q!.changePercent >= 0 ? '+' : ''}${q.changePercent.toStringAsFixed(2)}%',
                          style:
                              PcDashboardTheme.bodySmall.copyWith(color: color),
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

  Widget _buildPcIndicesShowcase() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplitLayout = constraints.maxWidth >= 1080;
        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _pcCardBg,
            borderRadius: BorderRadius.circular(_pcRadiusLg + 2),
            border: Border.all(color: _pcCardBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: -6,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.marketMajorIndices,
                          style: PcDashboardTheme.titleMedium.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '聚焦全球核心指数，先看风险偏好，再判断今天的市场节奏。',
                          style: PcDashboardTheme.bodySmall.copyWith(
                            color: PcDashboardTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: PcDashboardTheme.surfaceVariant
                          .withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: PcDashboardTheme.border),
                    ),
                    child: Text(
                      'Global snapshot',
                      style: PcDashboardTheme.label,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (useSplitLayout)
                SizedBox(
                  height: 288,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _buildPcFeaturedIndexCard(0),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 7,
                        child: _buildPcIndexCardsTv(),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      height: 228,
                      width: double.infinity,
                      child: _buildPcFeaturedIndexCard(0),
                    ),
                    const SizedBox(height: 16),
                    _buildPcIndexCardsTv(),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPcFeaturedIndexCard(int index) {
    final label = _indexList[index].$1;
    final symbol = _indexList[index].$2;
    final resolved = _resolveIndexDisplayQuote(symbol);
    final q = resolved.quote;
    final hasError = resolved.hasError;
    final isLoading = q == null && _loading && !resolved.usedMock;
    final change = q?.change ?? 0;
    final changePercent = q?.changePercent ?? 0;
    final isUp = changePercent >= 0;
    final accent = MarketColors.forUp(isUp);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openPcIndexDetail(index),
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF172333),
                accent.withValues(alpha: 0.12),
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: 0.22),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        '$label ($symbol)',
                        style: PcDashboardTheme.label.copyWith(
                          color: PcDashboardTheme.text,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      isUp
                          ? Icons.north_east_rounded
                          : Icons.south_east_rounded,
                      color: accent,
                      size: 22,
                    ),
                  ],
                ),
                const Spacer(),
                if (isLoading)
                  const SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Color(0xFFD4AF37),
                    ),
                  )
                else
                  Text(
                    hasError || q == null || q.price <= 0
                        ? '—'
                        : _formatPrice(q.price),
                    style: PcDashboardTheme.titleLarge.copyWith(
                      fontSize: 34,
                      fontFamily: 'monospace',
                      color: hasError
                          ? PcDashboardTheme.textMuted
                          : PcDashboardTheme.text,
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  hasError
                      ? '点击重试加载指数数据'
                      : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}  (${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%)',
                  style: PcDashboardTheme.bodyMedium.copyWith(
                    color: hasError ? PcDashboardTheme.textMuted : accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildPcIndexMeta(
                          '方向',
                          hasError ? '--' : (isUp ? 'Risk On' : 'Risk Off'),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                      Expanded(
                        child: _buildPcIndexMeta(
                          '波动',
                          hasError
                              ? '--'
                              : '${changePercent.abs().toStringAsFixed(2)}%',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPcIndexMeta(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PcDashboardTheme.label.copyWith(
              color: PcDashboardTheme.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: PcDashboardTheme.bodyMedium.copyWith(
              color: PcDashboardTheme.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// PC 主要指数：副卡 2x2 网格
  Widget _buildPcIndexCardsTv() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        const minCardWidth = 220.0;
        final secondaryCount =
            (_indexList.length - 1).clamp(0, _indexList.length);
        final crossCount =
            (constraints.maxWidth / (minCardWidth + gap)).floor().clamp(1, 2);
        final cardWidth =
            (constraints.maxWidth - gap * (crossCount - 1)) / crossCount;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(secondaryCount, (gridIndex) {
            final i = gridIndex + 1;
            final label = _indexList[i].$1;
            final symbol = _indexList[i].$2;
            final resolved = _resolveIndexDisplayQuote(symbol);
            final q = resolved.quote;
            final hasError = resolved.hasError;
            final isLoading = q == null && _loading && !resolved.usedMock;
            final changePercent = q?.changePercent ?? 0;
            final accent = MarketColors.forChangePercent(changePercent);
            final isUp = changePercent >= 0;
            return SizedBox(
              width: cardWidth,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openPcIndexDetail(i),
                  borderRadius: BorderRadius.circular(18),
                  child: Ink(
                    height: 136,
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B28),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: PcDashboardTheme.bodyMedium.copyWith(
                                    color: PcDashboardTheme.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  symbol,
                                  style: PcDashboardTheme.label.copyWith(
                                    color: accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (isLoading)
                            const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFD4AF37),
                              ),
                            )
                          else
                            Text(
                              hasError || q == null || q.price <= 0
                                  ? '—'
                                  : _formatPrice(q.price),
                              style: PcDashboardTheme.titleMedium.copyWith(
                                fontSize: 24,
                                color: hasError
                                    ? PcDashboardTheme.textMuted
                                    : PcDashboardTheme.text,
                                fontFamily: 'monospace',
                              ),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                isUp
                                    ? Icons.trending_up_rounded
                                    : Icons.trending_down_rounded,
                                size: 16,
                                color: accent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  hasError
                                      ? '暂不可用'
                                      : '${q!.change >= 0 ? '+' : ''}${q.change.toStringAsFixed(2)} · ${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                                  style: PcDashboardTheme.bodySmall.copyWith(
                                    color: hasError
                                        ? PcDashboardTheme.textMuted
                                        : accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  void _openPcIndexDetail(int index) {
    final label = _indexList[index].$1;
    final symbol = _indexList[index].$2;
    final q = _indexQuotes[symbol];
    final hasError = q?.hasError ?? true;
    final isLoading = q == null && _loading;
    if (hasError && !isLoading) {
      _load();
      return;
    }
    if (hasError) return;
    final symbolList = _indexList.map((e) => e.$2).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GenericChartPage(
          symbol: symbol,
          name: label,
          symbolList: symbolList,
          symbolIndex: index,
        ),
      ),
    );
  }

  ({MarketQuote? quote, bool hasError, bool usedMock})
      _resolveIndexDisplayQuote(
    String symbol,
  ) {
    final live = _indexQuotes[symbol];
    if (live != null && !live.hasError && live.price > 0) {
      return (quote: live, hasError: false, usedMock: false);
    }
    for (final item in MockMarketData.indicesQuotes) {
      if (item['symbol'] == symbol) {
        final mock = MarketQuote.fromSnapshotMap(item);
        if (mock != null && mock.price > 0) {
          return (quote: mock, hasError: false, usedMock: true);
        }
        break;
      }
    }
    return (quote: live, hasError: live?.hasError ?? true, usedMock: false);
  }

  /// 涨跌榜整块卡片（含标题+切换+表格），内容区 Expanded 以与左/右列等高
  Widget _buildPcGainersLosersCard() {
    final list = _showGainers ? _gainers : _losers;
    final rows = list.take(6).toList().asMap().entries.map((entry) {
      final i = entry.key;
      final g = entry.value;
      final price = (g.price != null && g.price! > 0)
          ? g.price!
          : (g.prevClose != null && g.todaysChange != null
              ? g.prevClose! + g.todaysChange!
              : 0.0);
      final changePct = g.todaysChangePerc ?? 0;
      final symbols = list.take(6).map((x) => x.ticker).toList();
      return _PcCompactMarketRowData(
        title: g.ticker,
        subtitle: '成交量 ${_formatVolume(g.dayVolume)}',
        priceText: price > 0 ? _formatPrice(price) : '—',
        changeText:
            '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
        changeColor: MarketColors.forChangePercent(changePct),
        onTap: () => _openDetail(
          g.ticker,
          symbolList: symbols,
          symbolIndex: i,
        ),
      );
    }).toList();

    return _buildPcCompactMarketPanel(
      title: AppLocalizations.of(context)!.marketGainersLosers,
      subtitle: _showGainers ? '股票领涨观察' : '股票领跌观察',
      actions: [
        _moverChip(AppLocalizations.of(context)!.marketGainersList, true,
            () => setState(() => _showGainers = true)),
        const SizedBox(width: 8),
        _moverChip(AppLocalizations.of(context)!.marketLosersList, false,
            () => setState(() => _showGainers = false)),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GainersLosersPage())),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            AppLocalizations.of(context)!.marketMore,
            style: PcDashboardTheme.bodyMedium
                .copyWith(color: PcDashboardTheme.accent),
          ),
        ),
      ],
      rows: rows,
      emptyText: AppLocalizations.of(context)!.marketNoData,
    );
  }

  /// 首页右列：加密货币面板，内容区 Expanded 以与左/中列等高
  Widget _buildPcMarketHeatPanel() {
    final cryptoList = _trendingCryptoQuotes.entries
        .map((e) => (e.key, e.value))
        .where((e) => e.$2.hasError == false)
        .toList();
    if (!_showMarketHeatGainers) {
      cryptoList
          .sort((a, b) => a.$2.changePercent.compareTo(b.$2.changePercent));
    } else {
      cryptoList
          .sort((a, b) => b.$2.changePercent.compareTo(a.$2.changePercent));
    }
    final displayList = cryptoList.take(6).toList();
    final rows = displayList.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      final symbol = item.$1;
      final q = item.$2;
      final name = q.name ?? symbol;
      final symbolList = displayList.map((x) => x.$1).toList();
      return _PcCompactMarketRowData(
        title: name,
        subtitle: symbol,
        priceText: q.price > 0 ? _formatPrice(q.price) : '—',
        changeText:
            '${q.changePercent >= 0 ? '+' : ''}${q.changePercent.toStringAsFixed(2)}%',
        changeColor: MarketColors.forChangePercent(q.changePercent),
        onTap: () => _openDetail(
          symbol,
          name: name,
          symbolList: symbolList,
          symbolIndex: i,
        ),
      );
    }).toList();

    return _buildPcCompactMarketPanel(
      title: AppLocalizations.of(context)!.marketTabCrypto,
      subtitle: _showMarketHeatGainers ? '加密强势榜' : '加密弱势榜',
      actions: [
        _moverChip(AppLocalizations.of(context)!.marketGainersList, true,
            () => setState(() => _showMarketHeatGainers = true)),
        const SizedBox(width: 8),
        _moverChip(AppLocalizations.of(context)!.marketLosersList, false,
            () => setState(() => _showMarketHeatGainers = false)),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => widget.onSwitchToTab?.call(3),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            AppLocalizations.of(context)!.marketMore,
            style: PcDashboardTheme.bodyMedium
                .copyWith(color: PcDashboardTheme.accent),
          ),
        ),
      ],
      rows: rows,
      emptyText: AppLocalizations.of(context)!.marketNoData,
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
        child: Text(AppLocalizations.of(context)!.marketNoData,
            style: PcDashboardTheme.bodySmall),
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
              Text(AppLocalizations.of(context)!.marketHeatmap,
                  style: PcDashboardTheme.titleSmall),
              const Spacer(),
              Text(
                AppLocalizations.of(context)!.marketIndexSp500,
                style: PcDashboardTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              Text('${AppLocalizations.of(context)!.marketTradeSubcategory} >',
                  style: PcDashboardTheme.bodySmall),
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
                        ? Color.lerp(
                            const Color(0xFF22C55E).withValues(alpha: 0.15),
                            const Color(0xFF22C55E).withValues(alpha: 0.5),
                            intensity)!
                        : Color.lerp(
                            const Color(0xFFEF4444).withValues(alpha: 0.15),
                            const Color(0xFFEF4444).withValues(alpha: 0.5),
                            intensity)!;
                    final price = (g.price != null && g.price! > 0)
                        ? g.price!
                        : (g.prevClose != null && g.todaysChange != null
                            ? g.prevClose! + g.todaysChange!
                            : null);
                    final symbols = list.map((x) => x.ticker).toList();
                    return SizedBox(
                      width: itemWidth,
                      height: itemHeight,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _openDetail(g.ticker,
                              symbolList: symbols, symbolIndex: i),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: PcDashboardTheme.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(g.ticker,
                                    style: PcDashboardTheme.titleSmall
                                        .copyWith(fontSize: 12)),
                                if (price != null)
                                  Text(_formatPrice(price),
                                      style: PcDashboardTheme.bodySmall
                                          .copyWith(fontFamily: 'monospace')),
                                Text(
                                  '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                                  style: PcDashboardTheme.bodySmall.copyWith(
                                    color: isUp
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFFEF4444),
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
              Text(AppLocalizations.of(context)!.marketHot,
                  style: PcDashboardTheme.titleSmall),
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
        Text(AppLocalizations.of(context)!.marketGainersLosers,
            style: PcDashboardTheme.titleSmall),
        const SizedBox(width: 16),
        _moverChip(AppLocalizations.of(context)!.marketGainers, true,
            () => setState(() => _showGainers = true)),
        const SizedBox(width: 8),
        _moverChip(AppLocalizations.of(context)!.marketLosers, false,
            () => setState(() => _showGainers = false)),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GainersLosersPage())),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('${AppLocalizations.of(context)!.marketMore} >',
              style: PcDashboardTheme.bodyMedium
                  .copyWith(color: PcDashboardTheme.accent)),
        ),
      ],
    );
  }

  /// PC 涨跌榜表格：代码、名称、涨跌幅、最新价、涨跌额、今开、昨收、最高、最低、成交量
  Widget _buildPcGainersLosersTable() {
    const colCode = 64.0;
    const colName = 72.0;
    const colPct = 76.0;
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
        SizedBox(
            width: colCode,
            child: Text(AppLocalizations.of(context)!.marketCode,
                style: PcDashboardTheme.label)),
        SizedBox(
            width: colName,
            child: Text(AppLocalizations.of(context)!.marketName,
                style: PcDashboardTheme.label)),
        SizedBox(
            width: colPct,
            child: Text(AppLocalizations.of(context)!.marketChangePct,
                style: PcDashboardTheme.label)),
        SizedBox(
            width: colPrice,
            child: Text(AppLocalizations.of(context)!.marketLatestPrice,
                style: PcDashboardTheme.label)),
        SizedBox(
            width: colChange,
            child: Text(AppLocalizations.of(context)!.marketChangeAmount,
                style: PcDashboardTheme.label)),
        SizedBox(
            width: colOpen,
            child: Text(AppLocalizations.of(context)!.marketOpen,
                style: PcDashboardTheme.label)),
        SizedBox(
            width: colPrev,
            child: Text(AppLocalizations.of(context)!.marketPrevClose,
                style: PcDashboardTheme.label)),
        SizedBox(
            width: colHigh,
            child: Text(AppLocalizations.of(context)!.marketHigh,
                style: PcDashboardTheme.label)),
        SizedBox(
            width: colLow,
            child: Text(AppLocalizations.of(context)!.marketLow,
                style: PcDashboardTheme.label)),
        SizedBox(
            width: colVol,
            child: Text(AppLocalizations.of(context)!.marketVolume,
                style: PcDashboardTheme.label)),
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
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(PcDashboardTheme.radiusSm)),
            ),
            child: headerRow,
          ),
          ...list.take(8).toList().asMap().entries.map((e) {
            final i = e.key;
            final g = e.value;
            final color =
                MarketColors.forChangePercent(g.todaysChangePerc ?? 0);
            // 接口有时只返回昨收+涨跌额，无 price：用 最新价 = 昨收 + 涨跌额 回退，避免出现「有涨跌却最新价 —」
            final effectivePrice = (g.price != null && g.price! > 0)
                ? g.price!
                : (g.prevClose != null && g.todaysChange != null
                    ? g.prevClose! + g.todaysChange
                    : null);
            final symbols = list.take(8).map((x) => x.ticker).toList();
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    _openDetail(g.ticker, symbolList: symbols, symbolIndex: i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: rowPadding),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: PcDashboardTheme.border, width: 0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                          width: colCode,
                          child: Text(g.ticker,
                              style: PcDashboardTheme.titleSmall
                                  .copyWith(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      SizedBox(
                          width: colName,
                          child: Text(g.ticker,
                              style: PcDashboardTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      SizedBox(
                          width: colPct,
                          child: Text(
                              g.todaysChangePerc != null
                                  ? '${g.todaysChangePerc! >= 0 ? '+' : ''}${g.todaysChangePerc!.toStringAsFixed(2)}%'
                                  : '—',
                              style: PcDashboardTheme.bodySmall
                                  .copyWith(color: color),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      SizedBox(
                          width: colPrice,
                          child: Text(
                              effectivePrice != null && effectivePrice > 0
                                  ? _formatPrice(effectivePrice)
                                  : '—',
                              style: PcDashboardTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      SizedBox(
                          width: colChange,
                          child: Text(
                              g.todaysChange != null
                                  ? '${g.todaysChange! >= 0 ? '+' : ''}${g.todaysChange!.toStringAsFixed(2)}'
                                  : '—',
                              style: PcDashboardTheme.bodySmall
                                  .copyWith(color: color),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      SizedBox(
                          width: colOpen,
                          child: Text(
                              g.dayOpen != null && g.dayOpen! > 0
                                  ? _formatPrice(g.dayOpen!)
                                  : '—',
                              style: PcDashboardTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      SizedBox(
                          width: colPrev,
                          child: Text(
                              g.prevClose != null && g.prevClose! > 0
                                  ? _formatPrice(g.prevClose!)
                                  : '—',
                              style: PcDashboardTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      SizedBox(
                          width: colHigh,
                          child: Text(
                              g.dayHigh != null && g.dayHigh! > 0
                                  ? _formatPrice(g.dayHigh!)
                                  : '—',
                              style: PcDashboardTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      SizedBox(
                          width: colLow,
                          child: Text(
                              g.dayLow != null && g.dayLow! > 0
                                  ? _formatPrice(g.dayLow!)
                                  : '—',
                              style: PcDashboardTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      SizedBox(
                          width: colVol,
                          child: Text(_formatVolume(g.dayVolume),
                              style: PcDashboardTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
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
    final l10n = AppLocalizations.of(context)!;
    final names = [
      l10n.marketIndexDowJones,
      l10n.marketIndexNasdaq,
      l10n.marketIndexSp500
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: PcDashboardTheme.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
        border: Border.all(color: PcDashboardTheme.border),
      ),
      child: Row(
        children: [
          Text(AppLocalizations.of(context)!.marketThreeIndices,
              style: PcDashboardTheme.label),
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
                    hasError
                        ? '—'
                        : (q != null && q.price > 0
                            ? _formatPrice(q.price)
                            : '—'),
                    style: PcDashboardTheme.titleSmall.copyWith(
                        fontSize: 13,
                        color: hasError ? PcDashboardTheme.textMuted : null),
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

  /// PC 首页左列：外汇面板（表头与涨跌榜/加密货币一致：名称、最新价、涨跌幅）
  Widget _buildPcWatchlistPanel() {
    final hasForex =
        _forexQuotes.isNotEmpty && _forexQuotes.values.any((q) => !q.hasError);
    final rows = _forexForHome.toList().asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      final name = item.$1;
      final symbol = item.$2;
      final q = _forexQuotes[symbol];
      final changePercent = q?.changePercent ?? 0;
      final symbolList = _forexForHome.map((x) => x.$2).toList();
      return _PcCompactMarketRowData(
        title: name,
        subtitle: symbol,
        priceText: (q != null && !q.hasError && q.price > 0)
            ? _formatPrice(q.price)
            : '—',
        changeText: (q == null || q.hasError)
            ? '—'
            : '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
        changeColor: MarketColors.forChangePercent(changePercent),
        onTap: () => _openDetail(
          symbol,
          name: name,
          symbolList: symbolList,
          symbolIndex: i,
        ),
      );
    }).toList();

    return _buildPcCompactMarketPanel(
      title: AppLocalizations.of(context)!.marketTabForex,
      subtitle: '主流货币对',
      actions: [
        TextButton(
          onPressed: () => widget.onSwitchToTab?.call(2),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            AppLocalizations.of(context)!.marketMore,
            style: PcDashboardTheme.bodyMedium
                .copyWith(color: PcDashboardTheme.accent),
          ),
        ),
      ],
      rows: hasForex ? rows : const [],
      emptyText: AppLocalizations.of(context)!.marketNoForexData,
    );
  }

  Widget _buildPcCompactMarketPanel({
    required String title,
    required String subtitle,
    required List<Widget> actions,
    required List<_PcCompactMarketRowData> rows,
    required String emptyText,
  }) {
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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: PcDashboardTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: PcDashboardTheme.bodySmall.copyWith(
                          color: PcDashboardTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: PcDashboardTheme.surfaceVariant.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
              border: Border.all(color: PcDashboardTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    AppLocalizations.of(context)!.marketName,
                    style: PcDashboardTheme.label,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    AppLocalizations.of(context)!.marketLatestPrice,
                    style: PcDashboardTheme.label,
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    AppLocalizations.of(context)!.marketChangePct,
                    style: PcDashboardTheme.label,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      emptyText,
                      style: PcDashboardTheme.bodySmall,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: PcDashboardTheme.border.withValues(alpha: 0.8),
                    ),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: row.onTap,
                          borderRadius:
                              BorderRadius.circular(PcDashboardTheme.radiusSm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.title,
                                        style: PcDashboardTheme.bodyMedium
                                            .copyWith(
                                          color: PcDashboardTheme.text,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        row.subtitle,
                                        style:
                                            PcDashboardTheme.bodySmall.copyWith(
                                          color: PcDashboardTheme.textMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    row.priceText,
                                    style: PcDashboardTheme.bodySmall.copyWith(
                                      fontFamily: 'monospace',
                                      color: PcDashboardTheme.text,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    row.changeText,
                                    style: PcDashboardTheme.bodySmall.copyWith(
                                      color: row.changeColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return const MarketSearchBar(isPc: true);
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
            color: isPc
                ? PcDashboardTheme.surfaceElevated
                : const Color(0xFF111215),
            borderRadius:
                BorderRadius.circular(isPc ? PcDashboardTheme.radiusMd : 8),
            child: InkWell(
              onTap: () {
                if (hasError && !isLoading) {
                  _load();
                  return;
                }
                if (hasError) return;
                final symbolList = _indexList.map((e) => e.$2).toList();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => GenericChartPage(
                          symbol: symbol,
                          name: label,
                          symbolList: symbolList,
                          symbolIndex: i)),
                );
              },
              borderRadius:
                  BorderRadius.circular(isPc ? PcDashboardTheme.radiusMd : 8),
              child: Container(
                width: cardWidth,
                height: cardHeight,
                padding: EdgeInsets.symmetric(
                    horizontal: isPc ? 14 : 10, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                      isPc ? PcDashboardTheme.radiusMd : 8),
                  border: isPc
                      ? Border.all(color: PcDashboardTheme.border, width: 1)
                      : const Border(
                          bottom:
                              BorderSide(color: Color(0xFF1F1F23), width: 0.6)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      symbol,
                      style: (isPc
                          ? PcDashboardTheme.label
                          : const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 11,
                              decoration: TextDecoration.none)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (isLoading)
                      SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isPc
                                ? PcDashboardTheme.accent
                                : const Color(0xFFD4AF37)),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              hasError
                                  ? '—'
                                  : (q != null && q!.price > 0
                                      ? _formatPrice(q!.price)
                                      : '—'),
                              style: TextStyle(
                                color: hasError
                                    ? (isPc
                                        ? PcDashboardTheme.textMuted
                                        : const Color(0xFF6B6B70))
                                    : (q != null && q!.price > 0
                                        ? color
                                        : (isPc
                                            ? PcDashboardTheme.textMuted
                                            : const Color(0xFF6B6B70))),
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
                            hasError
                                ? ''
                                : (q != null && q.price > 0
                                    ? '${q!.changePercent >= 0 ? '+' : ''}${q.changePercent.toStringAsFixed(2)}%'
                                    : ''),
                            style: TextStyle(
                              color: (q != null && q.price > 0)
                                  ? color
                                  : (isPc
                                      ? PcDashboardTheme.textMuted
                                      : const Color(0xFF6B6B70)),
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
        AppChip(
          label: AppLocalizations.of(context)!.marketGainers,
          selected: true,
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GainersLosersPage())),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppChip(
          label: AppLocalizations.of(context)!.marketLosers,
          selected: false,
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GainersLosersPage())),
        ),
      ],
    );
  }

  /// 兼容旧调用点：统一迁移到 AppChip
  Widget _moverChip(String label, bool isGainers, VoidCallback onTap) {
    return AppChip(
      label: label,
      selected: isGainers,
      onTap: onTap,
    );
  }

  Widget _buildGainersLosersRows() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._gainers
            .take(_homeMoverDisplayLimit)
            .toList()
            .asMap()
            .entries
            .map((e) {
          final i = e.key;
          final g = e.value;
          final symbols = [
            ..._gainers.take(_homeMoverDisplayLimit).map((x) => x.ticker),
            ..._losers.take(_homeMoverDisplayLimit).map((x) => x.ticker),
          ];
          return QuoteRow(
            symbol: g.ticker,
            price: g.price ?? 0,
            change: g.todaysChange,
            changePercent: g.todaysChangePerc,
            hasError: g.price == null,
            onTap: () =>
                _openDetail(g.ticker, symbolList: symbols, symbolIndex: i),
          );
        }),
        ..._losers
            .take(_homeMoverDisplayLimit)
            .toList()
            .asMap()
            .entries
            .map((e) {
          final i = e.key;
          final g = e.value;
          final symbols = [
            ..._gainers.take(_homeMoverDisplayLimit).map((x) => x.ticker),
            ..._losers.take(_homeMoverDisplayLimit).map((x) => x.ticker),
          ];
          return QuoteRow(
            symbol: g.ticker,
            price: g.price ?? 0,
            change: g.todaysChange,
            changePercent: g.todaysChangePerc,
            hasError: g.price == null,
            onTap: () => _openDetail(g.ticker,
                symbolList: symbols, symbolIndex: _homeMoverDisplayLimit + i),
          );
        }),
      ],
    );
  }

  Widget _buildWatchlistSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildSectionLabel(AppLocalizations.of(context)!.marketWatchlist),
            const Spacer(),
            AppButton(
              label: AppLocalizations.of(context)!.marketMore,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.of(context)
                  .push(
                      MaterialPageRoute(builder: (_) => const WatchlistPage()))
                  .then((_) => _load()),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_watchlistSymbols.isEmpty)
          AppCard(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
              child: Text(AppLocalizations.of(context)!.marketAddWatchlistHint),
            ),
          )
        else
          ..._watchlistSymbols.toList().asMap().entries.map((e) {
            final i = e.key;
            final symbol = e.value;
            final q = _watchlistQuotes[symbol];
            return QuoteRow(
              symbol: symbol,
              name: q?.name,
              price: q?.price ?? 0,
              change: q?.change ?? 0,
              changePercent: q?.changePercent ?? 0,
              hasError: q?.hasError ?? true,
              onTap: () => _openDetail(symbol,
                  symbolList: _watchlistSymbols.toList(), symbolIndex: i),
            );
          }),
      ],
    );
  }

  Widget _buildTrendingSegmented() {
    return Row(
      children: [
        _segmentChip(AppLocalizations.of(context)!.marketTabUsStock, 0),
        const SizedBox(width: 8),
        _segmentChip(AppLocalizations.of(context)!.marketTabCrypto, 1),
      ],
    );
  }

  Widget _segmentChip(String label, int index) {
    final selected = _trendingSegment == index;
    return Material(
      color: selected
          ? const Color(0xFFD4AF37).withValues(alpha: 0.25)
          : const Color(0xFF111215),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () => setState(() => _trendingSegment = index),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color:
                  selected ? const Color(0xFFD4AF37) : const Color(0xFF1F1F23),
              width: selected ? 1.2 : 0.6,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? const Color(0xFFD4AF37) : const Color(0xFF9CA3AF),
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
        children: _trendingStocks.take(10).toList().asMap().entries.map((e) {
          final i = e.key;
          final g = e.value;
          final symbols =
              _trendingStocks.take(10).map((x) => x.ticker).toList();
          return QuoteRow(
            symbol: g.ticker,
            price: g.price ?? 0,
            change: g.todaysChange,
            changePercent: g.todaysChangePerc,
            hasError: g.price == null,
            onTap: () =>
                _openDetail(g.ticker, symbolList: symbols, symbolIndex: i),
          );
        }).toList(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _cryptoSymbols.toList().asMap().entries.map((e) {
        final i = e.key;
        final symbol = e.value;
        final q = _trendingCryptoQuotes[symbol];
        return QuoteRow(
          symbol: symbol,
          name: q?.name,
          price: q?.price ?? 0,
          change: q?.change ?? 0,
          changePercent: q?.changePercent ?? 0,
          hasError: q?.hasError ?? true,
          onTap: () => _openDetail(symbol,
              name: q?.name ?? symbol,
              symbolList: _cryptoSymbols.toList(),
              symbolIndex: i),
        );
      }).toList(),
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
}

class _PcCompactMarketRowData {
  const _PcCompactMarketRowData({
    required this.title,
    required this.subtitle,
    required this.priceText,
    required this.changeText,
    required this.changeColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String priceText;
  final String changeText;
  final Color changeColor;
  final VoidCallback onTap;
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
    setState(() {
      _loading = true;
      _isMockData = false;
    });
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
    final indicesList =
        await _cache.getList('market_overview_indices', maxAge: _cacheMaxAge);
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
    final forexList =
        await _cache.getList('market_overview_forex', maxAge: _cacheMaxAge);
    if (forexList != null)
      for (final m in forexList) {
        if (m is Map<String, dynamic>) {
          final q = MarketQuote.fromSnapshotMap(m);
          if (q != null) out[q.symbol] = q;
        }
      }
    final forexSymbols = _forex.map((e) => e.$2).toList();
    final forexFromSqlite =
        await MarketDb.instance.getForexQuotes(forexSymbols);
    for (final sym in forexSymbols) {
      final q = forexFromSqlite[sym];
      if (q != null && out[sym] == null) out[sym] = q;
    }
    final fromDbF = await _snapshotRepo.getQuotes('forex');
    for (final m in fromDbF) {
      final q = MarketQuote.fromSnapshotMap(m);
      if (q != null && out[q.symbol] == null) out[q.symbol] = q;
    }
    final cryptoList =
        await _cache.getList('market_overview_crypto', maxAge: _cacheMaxAge);
    if (cryptoList != null)
      for (final m in cryptoList) {
        if (m is Map<String, dynamic>) {
          final q = MarketQuote.fromSnapshotMap(m);
          if (q != null) out[q.symbol] = q;
        }
      }
    final cryptoSymbols = _crypto.map((e) => e.$2).toList();
    final cryptoFromSqlite =
        await MarketDb.instance.getCryptoQuotes(cryptoSymbols);
    for (final sym in cryptoSymbols) {
      final q = cryptoFromSqlite[sym];
      if (q != null && out[sym] == null) out[sym] = q;
    }
    _quotes = out;
    if (_quotes.isEmpty)
      _applyMockOverviewIfEmpty();
    else
      _fillMissingWithMock();
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
      if (out.isEmpty)
        _applyMockOverviewIfEmpty();
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
      if (q != null && !q.hasError)
        il.add({...q.toSnapshotMap(), 'name': e.$1});
    }
    if (il.isNotEmpty) await _cache.setList('market_overview_indices', il);
    final fl = <Map<String, dynamic>>[];
    for (final e in _forex) {
      final q = out[e.$2];
      if (q != null && !q.hasError)
        fl.add({...q.toSnapshotMap(), 'name': e.$1});
    }
    if (fl.isNotEmpty) await _cache.setList('market_overview_forex', fl);
    final cl = <Map<String, dynamic>>[];
    for (final e in _crypto) {
      final q = out[e.$2];
      if (q != null && !q.hasError)
        cl.add({...q.toSnapshotMap(), 'name': e.$1});
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
      final toSave = <String, MarketQuote>{};
      for (final e in _forex) {
        final q = out[e.$2];
        if (q != null) {
          list.add({...q.toSnapshotMap(), 'name': e.$1});
          if (!q.hasError) toSave[e.$2] = q;
        }
      }
      if (toSave.isNotEmpty) await MarketDb.instance.upsertForexQuotes(toSave);
      if (list.isNotEmpty) await _snapshotRepo.saveQuotes('forex', list);
    }
    final forexSymbols = _forex.map((e) => e.$2).toList();
    final fromSqlite = await MarketDb.instance.getForexQuotes(forexSymbols);
    for (final sym in forexSymbols) {
      final q = fromSqlite[sym];
      if (q != null && out[sym] == null) out[sym] = q;
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
      final toSave = <String, MarketQuote>{};
      for (final e in _crypto) {
        final q = out[e.$2];
        if (q != null && !q.hasError) toSave[e.$2] = q;
      }
      if (toSave.isNotEmpty) await MarketDb.instance.upsertCryptoQuotes(toSave);
    }
    final cryptoSymbols = _crypto.map((e) => e.$2).toList();
    final fromSqlite = await MarketDb.instance.getCryptoQuotes(cryptoSymbols);
    for (final sym in cryptoSymbols) {
      final q = fromSqlite[sym];
      if (q != null && out[sym] == null) out[sym] = q;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _quotes.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
    }
    if (_quotes.isEmpty) {
      return _buildHint(AppLocalizations.of(context)!.marketNoDataConfigHint);
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
          _sectionTitle(AppLocalizations.of(context)!.marketGlobalIndices),
          const SizedBox(height: 8),
          _quoteGrid(
            items: _indices,
            onTap: (name, symbol, i) => _pushChart(context, symbol, name,
                symbolList: _indices.map((e) => e.$2).toList(), symbolIndex: i),
          ),
          const SizedBox(height: 20),
          _sectionTitle(AppLocalizations.of(context)!.marketNews),
          const SizedBox(height: 8),
          _buildNewsSection(),
          const SizedBox(height: 20),
          _sectionTitle(AppLocalizations.of(context)!.marketTabForex),
          const SizedBox(height: 8),
          _quoteGrid(
            items: _forex,
            onTap: (name, symbol, i) => _pushChart(context, symbol, name,
                symbolList: _forex.map((e) => e.$2).toList(), symbolIndex: i),
          ),
          const SizedBox(height: 20),
          _sectionTitle(AppLocalizations.of(context)!.marketTabCrypto),
          const SizedBox(height: 8),
          _quoteGrid(
            items: _crypto,
            onTap: (name, symbol, i) => _pushChart(context, symbol, name,
                symbolList: _crypto.map((e) => e.$2).toList(), symbolIndex: i),
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
        border:
            Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.2)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
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
                border: Border(
                    bottom: BorderSide(color: Color(0xFF1F1F23), width: 0.6)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.article_outlined,
                      size: 20, color: const Color(0xFF9CA3AF)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          color: Color(0xFFE8D5A3), fontSize: 14),
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
        border:
            Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
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
    required void Function(String name, String symbol, int index) onTap,
  }) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.15,
      children: items.toList().asMap().entries.map((e) {
        final i = e.key;
        final item = e.value;
        final name = item.$1;
        final symbol = item.$2;
        final q = _quotes[symbol];
        return _QuoteCard(
          name: name,
          symbol: symbol,
          quote: q,
          onTap: () => onTap(name, symbol, i),
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

  void _pushChart(BuildContext context, String symbol, String name,
      {List<String>? symbolList, int? symbolIndex}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GenericChartPage(
            symbol: symbol,
            name: name,
            symbolList: symbolList,
            symbolIndex: symbolIndex),
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
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
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
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasData) ...[
                Text(
                  _formatPrice(quote!.price),
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w700, fontSize: 18),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  (quote!.change >= 0 ? '+' : '') +
                      quote!.change.toStringAsFixed(2) +
                      ' ' +
                      (quote!.changePercent >= 0 ? '+' : '') +
                      quote!.changePercent.toStringAsFixed(2) +
                      '%',
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
    if (v >= 100) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }
}

// ---------- 美股：Polygon 领涨/领跌 ----------

class _UsStocksTab extends StatefulWidget {
  const _UsStocksTab({required this.tabController});

  final TabController tabController;

  @override
  State<_UsStocksTab> createState() => _UsStocksTabState();
}

class _UsStocksTabState extends State<_UsStocksTab> {
  static const int _usStocksTabIndex = 1;

  bool get _isUsStocksVisible =>
      widget.tabController.index == _usStocksTabIndex;
  final _market = MarketRepository();
  final _watchlist = WatchlistRepository.instance;
  final _realtime = RealtimeQuoteService();
  StreamSubscription<Map<String, MarketQuote>>? _quotesSub;
  StreamSubscription<void>? _syncCompleteSub;
  static final _cache = TradingCache.instance;

  /// 美股列表报价本地缓存 key，切换页/滑动后再回来可先展示
  static const _usListQuotesCacheKey = 'us_list_quotes';
  static const _usListQuotesCacheMaxAge = Duration(days: 7);

  /// 0 = 全部（约 8000+ 美股）, 1 = 自选
  int _listMode = 0;

  /// 全量美股列表（代码+名称，来自 Polygon v3 reference tickers）
  List<MarketSearchResult> _allTickers = [];
  List<String> _watchlistSymbols = [];
  Map<String, MarketQuote> _quotes = {};
  Map<String, MarketQuote> _indexQuotes = {};
  bool _loading = true;
  String? _error;

  /// 仅「全部」列表：可见范围报价拉取失败时的提示（如后端未启动）
  String? _quoteLoadError;
  bool _isMockData = false;

  /// PC 表格选中行，用于高亮与详情
  String? _selectedSymbol;

  /// 列表排序列：code/name/pct/price/change/open/prev/high/low/vol；默认按涨跌幅降序（涨幅高的在前）
  String? _sortColumn = 'pct';
  bool _sortAscending = false;

  /// 分页加载：每次从后端 API 读取 20 条
  static const int _pageSize = 20;
  bool _hasMoreTickers = true;
  bool _loadingMore = false;
  int _currentPage = 1;

  static const _indexSymbols = ['DJI', 'IXIC', 'SPX'];

  /// 是否已有有效行情（有最新价且无错误），用于排序
  bool _hasValidQuote(String symbol) {
    final q = _quotes[symbol];
    return q != null && !q.hasError && q.price > 0;
  }

  bool _isValidQuoteData(MarketQuote quote) {
    return !quote.hasError && quote.price > 0;
  }

  /// 合并新报价时优先保留“最后一次有效值”：
  /// 当新值是错误/空价，而本地已有有效值时，不覆盖，避免 UI 从数字回退成「—」。
  Map<String, MarketQuote> _mergeQuotesKeepingLastGood(
      Map<String, MarketQuote> incoming) {
    final merged = Map<String, MarketQuote>.from(_quotes);
    incoming.forEach((symbol, next) {
      final prev = merged[symbol];
      final prevValid = prev != null && _isValidQuoteData(prev);
      final nextValid = _isValidQuoteData(next);
      if (!nextValid && prevValid) return;
      merged[symbol] = next;
    });
    return merged;
  }

  /// 展示用列表：有数据的股票排前面（保持原有顺序），无数据的排后面，用户第一眼先看到已拿到数据的
  List<MarketSearchResult> get _displayTickers {
    if (_allTickers.isEmpty) return [];
    final withData = <MarketSearchResult>[];
    final withoutData = <MarketSearchResult>[];
    for (final t in _allTickers) {
      if (_hasValidQuote(t.symbol))
        withData.add(t);
      else
        withoutData.add(t);
    }
    return [...withData, ...withoutData];
  }

  /// 全部列表排序后的展示顺序（点击表头排序时使用）
  /// 始终使用 SQLite 排序：_allTickers 来自 getTickersFromLocalDb，已按 SQL ORDER BY 排序
  List<MarketSearchResult> get _sortedTickers => _allTickers;

  /// 自选列表排序后的顺序
  List<String> get _sortedWatchlistSymbols {
    final symbols = _watchlistSymbols;
    if (_sortColumn == null || symbols.isEmpty) return symbols;
    final q = _quotes;
    final sorted = List<String>.from(symbols);
    sorted.sort((a, b) {
      final qa = q[a];
      final qb = q[b];
      final na = qa?.name ?? a;
      final nb = qb?.name ?? b;
      int cmp = 0;
      switch (_sortColumn!) {
        case 'code':
          cmp = a.compareTo(b);
          break;
        case 'name':
          cmp = na.compareTo(nb);
          break;
        case 'pct':
          cmp = ((qa?.changePercent ?? 0) - (qb?.changePercent ?? 0))
              .sign
              .toInt();
          if (cmp == 0) cmp = a.compareTo(b);
          break;
        case 'price':
          cmp = ((qa?.price ?? 0) - (qb?.price ?? 0)).sign.toInt();
          if (cmp == 0) cmp = a.compareTo(b);
          break;
        case 'change':
          cmp = ((qa?.change ?? 0) - (qb?.change ?? 0)).sign.toInt();
          if (cmp == 0) cmp = a.compareTo(b);
          break;
        case 'open':
          cmp = ((qa?.open ?? 0) - (qb?.open ?? 0)).sign.toInt();
          if (cmp == 0) cmp = a.compareTo(b);
          break;
        case 'prev':
          final pa = qa != null && qa.price > 0 && qa.change != 0
              ? qa.price - qa.change
              : null;
          final pb = qb != null && qb.price > 0 && qb.change != 0
              ? qb.price - qb.change
              : null;
          cmp = ((pa ?? 0) - (pb ?? 0)).sign.toInt();
          if (cmp == 0) cmp = a.compareTo(b);
          break;
        case 'high':
          cmp = ((qa?.high ?? 0) - (qb?.high ?? 0)).sign.toInt();
          if (cmp == 0) cmp = a.compareTo(b);
          break;
        case 'low':
          cmp = ((qa?.low ?? 0) - (qb?.low ?? 0)).sign.toInt();
          if (cmp == 0) cmp = a.compareTo(b);
          break;
        case 'vol':
          cmp = ((qa?.volume ?? 0) - (qb?.volume ?? 0)).sign.toInt();
          if (cmp == 0) cmp = a.compareTo(b);
          break;
        default:
          break;
      }
      if (!_sortAscending) cmp = -cmp;
      return cmp;
    });
    return sorted;
  }

  /// 「全部」列表视口高度：PC 固定，移动端按可视区域动态计算
  static const double _allListHeightPc = 700;
  static const double _allListRowHeightPc = 44;
  static const double _allListRowHeightMobile = 48;

  /// 视口外上下各多加载的行数，预加载更多以减少滚动白屏
  static const int _visibleBuffer = 25;
  final ScrollController _allListScrollController = ScrollController();

  /// 右侧数据列垂直滚动，与左侧同步
  final ScrollController _allListRightScrollController = ScrollController();

  /// 横向滚动：表头与数据行共用，保证同步
  final ScrollController _horizontalScrollController = ScrollController();
  bool _syncingVerticalScroll = false;
  int? _lastVisibleStart;
  int? _lastVisibleEnd;

  /// 当前可视区域（含 buffer）的 symbol 集合，用于订阅回调中仅更新可视区域 UI
  Set<String> get _visibleSymbolSet {
    final start = _lastVisibleStart ?? 0;
    final end = _lastVisibleEnd ?? 0;
    final display = _sortedTickers;
    if (display.isEmpty || start > end) return {};
    final s = (start - _visibleBuffer).clamp(0, display.length - 1);
    final e = (end + _visibleBuffer).clamp(0, display.length - 1);
    return display.sublist(s, e + 1).map((t) => t.symbol).toSet();
  }

  Timer? _quoteRefreshTimer;
  Timer? _scrollSubscribeDebounce;
  Timer? _visibleRangeFetchDebounce;
  bool _isPcList = false;
  int? _pendingFetchStart;
  int? _pendingFetchEnd;
  final Map<String, int> _lastLatestFetchAtMs = <String, int>{};
  static const int _latestFetchMinIntervalMs = 2500;

  Timer? _persistDebounceTimer;

  @override
  void initState() {
    super.initState();
    _syncCompleteSub = MarketSyncService.onSyncComplete.listen((_) {
      if (mounted && _listMode == 0 && _allTickers.isNotEmpty) {
        _reloadFromServerAfterSync();
      }
    });
    _quotesSub = _realtime.quotesStream.listen((q) {
      if (!mounted || q.isEmpty) return;
      // 仅可视区域更新 UI，其余只写入 SQLite；自选模式下整表视为可视
      final visibleSymbols =
          _listMode == 1 ? _watchlistSymbols.toSet() : _visibleSymbolSet;
      final visibleQuotes = <String, MarketQuote>{};
      final nonVisibleQuotes = <String, MarketQuote>{};
      for (final e in q.entries) {
        if (visibleSymbols.contains(e.key)) {
          visibleQuotes[e.key] = e.value;
        } else {
          nonVisibleQuotes[e.key] = e.value;
        }
      }
      if (visibleQuotes.isNotEmpty) {
        setState(() {
          _quotes = Map<String, MarketQuote>.from(_quotes)
            ..addAll(visibleQuotes);
        });
      }
      // 所有推送数据都写入 SQLite（可视+非可视）
      _debouncedPersistQuotes({...visibleQuotes, ...nonVisibleQuotes});
    });
    widget.tabController.addListener(_onMarketTabChanged);
    _loadCachedThenRefresh();
    _loadIndexQuotes();
    _allListScrollController.addListener(_onAllListScroll);
    _allListScrollController.addListener(_syncRightListScroll);
    _allListRightScrollController.addListener(_syncLeftListScroll);
  }

  void _syncRightListScroll() {
    if (_syncingVerticalScroll ||
        !_allListScrollController.hasClients ||
        !_allListRightScrollController.hasClients) return;
    final offset = _allListScrollController.offset;
    if ((_allListRightScrollController.offset - offset).abs() > 2) {
      _syncingVerticalScroll = true;
      _allListRightScrollController.jumpTo(offset);
      _syncingVerticalScroll = false;
    }
  }

  void _syncLeftListScroll() {
    if (_syncingVerticalScroll ||
        !_allListScrollController.hasClients ||
        !_allListRightScrollController.hasClients) return;
    final offset = _allListRightScrollController.offset;
    if ((_allListScrollController.offset - offset).abs() > 2) {
      _syncingVerticalScroll = true;
      _allListScrollController.jumpTo(offset);
      _syncingVerticalScroll = false;
    }
  }

  /// 改为纯后端链路：不再写本地行情 DB
  void _debouncedPersistQuotes(Map<String, MarketQuote> q) {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = null;
  }

  /// 服务端同步完成后刷新列表（后端分页接口）
  Future<void> _reloadFromServerAfterSync() async {
    if (_listMode != 0) return;
    await _reloadFromDbWithSort();
  }

  @override
  void dispose() {
    _persistDebounceTimer?.cancel();
    _syncCompleteSub?.cancel();
    _quotesSub?.cancel();
    _realtime.dispose();
    MarketSyncService.instance.stopPeriodicSync();
    widget.tabController.removeListener(_onMarketTabChanged);
    _allListScrollController.removeListener(_onAllListScroll);
    _allListScrollController.removeListener(_syncRightListScroll);
    _allListRightScrollController.removeListener(_syncLeftListScroll);
    _allListScrollController.dispose();
    _allListRightScrollController.dispose();
    _horizontalScrollController.dispose();
    _quoteRefreshTimer?.cancel();
    _scrollSubscribeDebounce?.cancel();
    _visibleRangeFetchDebounce?.cancel();
    super.dispose();
  }

  void _onMarketTabChanged() {
    if (!mounted) return;
    if (_isUsStocksVisible) {
      if (_listMode == 0 && _allTickers.isNotEmpty) {
        // 切回美股列表时，首帧强制拉首屏报价，避免必须滚动才显示。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_isUsStocksVisible || _listMode != 0) return;
          _loadFirstVisibleQuotesAndStartTimer();
          _onAllListScroll();
        });
      }
    } else {
      _stopQuoteRefreshTimer();
    }
  }

  /// 根据滚动位置计算当前可见行范围（含 buffer），并拉取该范围报价（基于展示顺序 _sortedTickers）
  /// 可视区域变化时：立即拉取报价；WebSocket 订阅防抖 400ms 避免滚动时频繁重连
  /// 滚动到底部附近时触发分页加载更多
  void _onAllListScroll() {
    if (_listMode != 0 || _allTickers.isEmpty) return;
    final display = _sortedTickers;
    if (display.isEmpty) return;
    final rowHeight = _allListRowHeight;
    final offset = _allListScrollController.offset;
    final first = (offset / rowHeight).floor();
    final last = ((offset + _allListHeight) / rowHeight).floor();
    final start = (first - _visibleBuffer).clamp(0, display.length - 1);
    final end = (last + _visibleBuffer).clamp(0, display.length - 1);
    if (_lastVisibleStart != start || _lastVisibleEnd != end) {
      _lastVisibleStart = start;
      _lastVisibleEnd = end;
    }
    // 滚动到底部附近时加载下一页（距底部 10 行内触发）
    if (_hasMoreTickers && !_loadingMore && end >= display.length - 10) {
      unawaited(_loadMoreTickers());
    }
    _scrollSubscribeDebounce?.cancel();
    _scrollSubscribeDebounce = Timer(const Duration(milliseconds: 400), () {
      _scrollSubscribeDebounce = null;
      if (!mounted || _listMode != 0 || _allTickers.isEmpty) return;
      final visibleSymbols =
          display.sublist(start, end + 1).map((t) => t.symbol).toList();
      _resubscribeVisibleSymbols(visibleSymbols);
    });
  }

  void _resubscribeVisibleSymbols(List<String> visibleSymbols) {
    if (visibleSymbols.isEmpty) return;
    final visibleQuotes = <String, MarketQuote>{};
    for (final symbol in visibleSymbols) {
      final quote = _quotes[symbol];
      if (quote != null && _isValidQuoteData(quote)) {
        visibleQuotes[symbol] = quote;
      }
    }
    if (visibleQuotes.isNotEmpty) {
      _realtime.updateQuotes(visibleQuotes, prioritySymbols: visibleSymbols);
    } else {
      _realtime.subscribeToSymbols(visibleSymbols);
    }
  }

  /// 可视范围变化时防抖拉取最新报价，避免快速滚动期间频繁请求。
  void _scheduleVisibleRangeLatestFetch(int start, int end,
      {bool immediate = false}) {
    // 美股列表关闭可视区轮询拉取：只保留范围记录，报价由 WebSocket 推送更新。
    _pendingFetchStart = start;
    _pendingFetchEnd = end;
  }

  /// 美股列表不再使用定时轮询：改为首次拉取 + WebSocket 实时推送更新。
  void _startQuoteRefreshTimer() {
    _stopQuoteRefreshTimer();
  }

  void _stopQuoteRefreshTimer() {
    _quoteRefreshTimer?.cancel();
    _quoteRefreshTimer = null;
  }

  Future<void> _loadIndexQuotes() async {
    try {
      final q = await _market.getQuotes(_indexSymbols);
      if (mounted) setState(() => _indexQuotes = q);
    } catch (_) {}
  }

  void _openDetail(String symbol,
      {String? name, List<String>? symbolList, int? symbolIndex}) {
    final n = name ?? _quotes[symbol]?.name ?? symbol;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StockChartPage(
          symbol: symbol,
          name: n != symbol ? n : null,
          symbolList: symbolList,
          symbolIndex: symbolIndex,
        ),
      ),
    );
  }

  Future<void> _loadCachedThenRefresh() async {
    setState(() {
      _loading = true;
      _isMockData = false;
      _error = null;
    });
    if (_listMode == 0) {
      await _loadAllTickers();
    } else {
      await _loadWatchlist();
    }
  }

  Future<void> _refreshQuotesForCurrentMode() async {
    setState(() => _quoteLoadError = null);
    if (_listMode == 0) {
      await _loadAllTickers();
    } else {
      await _loadWatchlist();
    }
  }

  /// 从本地缓存恢复报价（切换页/滑动后再进「全部」时先展示，再后台刷新）
  Future<void> _restoreQuotesFromCache() async {
    try {
      final raw = await _cache.get(_usListQuotesCacheKey,
          maxAge: _usListQuotesCacheMaxAge);
      if (raw == null || raw is! Map<String, dynamic> || !mounted) return;
      final restored = <String, MarketQuote>{};
      for (final e in raw.entries) {
        if (e.value is Map<String, dynamic>) {
          final q =
              MarketQuote.fromSnapshotMap(e.value as Map<String, dynamic>);
          if (q != null) restored[e.key] = q;
        }
      }
      if (restored.isNotEmpty && mounted) {
        setState(() => _quotes = _mergeQuotesKeepingLastGood(restored));
      }
    } catch (_) {}
  }

  /// 将当前 _quotes 写入本地缓存与 DB（异步存储，不阻塞 UI；最多存 3000 条避免文件过大）
  void _persistQuotesToCache() {
    try {
      final map = _quotes;
      if (map.isEmpty) return;
      final entries = map.entries.take(3000);
      final data = <String, dynamic>{};
      for (final e in entries) {
        data[e.key] = e.value.toSnapshotMap();
      }
      final quotesToPersist =
          Map.fromEntries(entries.map((e) => MapEntry(e.key, e.value)));
      // 异步存储，不 await，避免影响 UI 显示
      unawaited(_cache
          .set(_usListQuotesCacheKey, data)
          .then((_) => _market.persistQuotesToLocalDb(quotesToPersist)));
    } catch (_) {}
  }

  /// 兼容旧逻辑标记：当前「全部」列表始终由后端分页 API 提供
  bool _useDbForAll = false;

  String get _serverSortColumn {
    final c = (_sortColumn ?? 'pct').trim();
    switch (c) {
      case 'code':
      case 'name':
      case 'pct':
      case 'price':
      case 'change':
      case 'open':
      case 'prev':
      case 'high':
      case 'low':
      case 'vol':
        return c;
      default:
        return 'pct';
    }
  }

  Future<void> _loadTickerPageFromServer(
      {required int page, required bool append}) async {
    final result = await _market.getStockTickersPageFromServer(
      page: page,
      pageSize: _pageSize,
      sortColumn: _serverSortColumn,
      sortAscending: _sortAscending,
    );
    if (!mounted) return;
    setState(() {
      _allTickers = append ? [..._allTickers, ...result.items] : result.items;
      _quotes = _mergeQuotesKeepingLastGood(result.quotes);
      _hasMoreTickers = result.hasMore;
      _currentPage = result.page;
      _useDbForAll = true;
      _loading = false;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isUsStocksVisible || _listMode != 0) return;
      _loadFirstVisibleQuotesAndStartTimer();
    });
    // 分页拉到股票后，对当前页无价格项做一次性补拉；后续由 WebSocket 推送更新。
    final pageSymbols = result.items.map((e) => e.symbol).toList();
    unawaited(_fetchMissingPageQuotesOnce(pageSymbols));
  }

  Future<void> _fetchMissingPageQuotesOnce(List<String> symbols) async {
    if (!mounted || symbols.isEmpty) return;
    final missing = symbols.where((s) => !_hasValidQuote(s)).take(80).toList();
    if (missing.isEmpty) return;
    try {
      final q = await _market.getQuotes(missing);
      if (!mounted || q.isEmpty) return;
      setState(() => _quotes = _mergeQuotesKeepingLastGood(q));
      _realtime.syncQuotes(_quotes);
    } catch (_) {}
  }

  /// 加载美股列表（纯后端分页接口）
  Future<void> _loadAllTickers() async {
    if (!mounted) return;
    try {
      setState(() {
        _loading = true;
        _error = null;
        _allTickers = [];
        _hasMoreTickers = true;
        _currentPage = 1;
      });
      await _loadTickerPageFromServer(page: 1, append: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// 后台同步 tickers 并分批拉取报价写入 DB
  Future<void> _syncTickersAndQuotesInBackground() async {
    return;
  }

  /// 首屏可见范围：优先拉取可视区域报价（含昨日数据+实时订阅），再后台分批拉取其余
  void _loadFirstVisibleQuotesAndStartTimer() {
    if (_allTickers.isEmpty) return;
    if (!_isUsStocksVisible) return;
    final sorted = _sortedTickers;
    final endIndex =
        (_allListHeight / _allListRowHeight).ceil() + _visibleBuffer;
    final end = (sorted.isEmpty ? 0 : endIndex.clamp(0, sorted.length - 1));
    _lastVisibleStart = 0;
    _lastVisibleEnd = end;
    final visibleSymbols = sorted.isEmpty
        ? <String>[]
        : sorted.sublist(0, end + 1).map((t) => t.symbol).toList();
    _resubscribeVisibleSymbols(visibleSymbols);
    // 不做分块轮询拉取，仅对首屏缺失项补拉一次；后续由 WebSocket 推送更新。
    unawaited(_fetchMissingPageQuotesOnce(visibleSymbols));
    _startQuoteRefreshTimer();
  }

  /// 后台分批拉取非可视区域报价（纯后端，内存更新，不落本地 DB）
  static const int _prefetchChunkSize = 500;
  void _prefetchAllQuotesInChunks() {
    if (_allTickers.isEmpty || _listMode != 0) return;
    final total = _allTickers.length;
    final visibleEnd = (_lastVisibleEnd ?? 0).clamp(0, total);
    Future<void>(() async {
      for (int start = visibleEnd + 1;
          start < total && mounted && _listMode == 0 && _isUsStocksVisible;
          start += _prefetchChunkSize) {
        final end = (start + _prefetchChunkSize).clamp(0, total);
        final symbols =
            _allTickers.sublist(start, end).map((t) => t.symbol).toList();
        if (symbols.isEmpty) continue;
        try {
          final q = await _market.getQuotes(symbols);
          if (!mounted || _listMode != 0 || !_isUsStocksVisible) return;
          if (q.isNotEmpty) {
            setState(() => _quotes = _mergeQuotesKeepingLastGood(q));
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    });
  }

  /// 为「可见范围」[start, end] 的标的拉取报价并更新 _quotes（纯后端 API）
  Future<void> _loadQuotesForVisibleRange(int start, int end) async {
    if (start > end || _allTickers.isEmpty || !mounted) return;
    final display = _sortedTickers;
    if (display.isEmpty) return;
    final symbols =
        display.sublist(start, end + 1).map((t) => t.symbol).toList();
    if (symbols.isEmpty) return;
    try {
      // 可视区域必须拉最新；为避免滚动抖动导致频繁请求，对单个 symbol 做短间隔限频
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final latestTargets = symbols.where((s) {
        final lastMs = _lastLatestFetchAtMs[s] ?? 0;
        return nowMs - lastMs >= _latestFetchMinIntervalMs;
      }).toList();
      if (latestTargets.isEmpty) return;
      for (final sym in latestTargets) {
        _lastLatestFetchAtMs[sym] = nowMs;
      }

      final q = await _market.getQuotes(latestTargets);
      if (mounted) {
        setState(() {
          _quotes = _mergeQuotesKeepingLastGood(q);
          _quoteLoadError = null;
        });
        _realtime.syncQuotes(_quotes);
        // 对最新拉取后仍失败/无效的 symbol 延迟补拉一次
        final stillMissing = latestTargets.where((s) {
          final quote = q[s];
          return quote == null ||
              quote.hasError ||
              (quote.price <= 0 &&
                  (quote.errorReason == null || quote.errorReason!.isEmpty));
        }).toList();
        if (stillMissing.isNotEmpty) {
          Future<void>.delayed(const Duration(seconds: 2), () async {
            if (!mounted || _listMode != 0) return;
            try {
              final q2 = await _market.getQuotes(stillMissing);
              if (mounted && q2.isNotEmpty) {
                setState(() => _quotes = _mergeQuotesKeepingLastGood(q2));
                _realtime.syncQuotes(_quotes);
              }
            } catch (_) {}
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final msg = e.toString().contains('Connection refused') ||
              e.toString().contains('Failed host lookup')
          ? l10n.marketConnectFailed
          : l10n.marketQuoteLoadFailed(e.toString());
      setState(() => _quoteLoadError = msg);
    }
  }

  Future<void> _loadWatchlist() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final symbols = await _watchlist.getWatchlist(forceSync: true);
      if (!mounted) return;
      setState(() {
        _watchlistSymbols = symbols;
        _loading = false;
        _error = null;
      });
      if (symbols.isNotEmpty) {
        final q = await _market.getQuotes(symbols);
        if (mounted) {
          final merged = _mergeQuotesKeepingLastGood(q);
          setState(() => _quotes = merged);
          _realtime.setQuotes(merged, prioritySymbols: symbols);
        }
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
    if (v >= 100) return v.toStringAsFixed(2);
    return v.toStringAsFixed(4);
  }

  static String _formatVolume(int? v) {
    if (v == null || v <= 0) return '—';
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(2)}亿';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(2)}万';
    return v.toString();
  }

  bool get _isPc => LayoutMode.useDesktopLikeLayout(context);
  double get _mobileListViewportHeight {
    final mediaQuery = MediaQuery.of(context);
    final estimated = mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom -
        kBottomNavigationBarHeight -
        260;
    return estimated.clamp(420.0, 620.0);
  }

  double get _allListHeight =>
      _isPcList ? _allListHeightPc : _mobileListViewportHeight;
  double get _allListRowHeight =>
      _isPcList ? _allListRowHeightPc : _allListRowHeightMobile;

  @override
  Widget build(BuildContext context) {
    _isPcList = _isPc;
    final symbols = _listMode == 0 ? <String>[] : _watchlistSymbols;
    return RefreshIndicator(
      onRefresh: () async {
        await _refreshQuotesForCurrentMode();
        await _loadIndexQuotes();
      },
      color: TvTheme.positive,
      child: ListView(
        padding: EdgeInsets.fromLTRB(_isPc ? TvTheme.pagePadding : 16, 12,
            _isPc ? TvTheme.pagePadding : 16, 24),
        children: [
          if (_isMockData && _listMode == 0) _buildMockBanner(),
          _isPc ? _buildUsIndexCardsTv() : _buildUsIndexCards(),
          const SizedBox(height: TvTheme.sectionGap),
          _isPc
              ? Row(
                  children: [
                    SegmentedTabs(
                      labels: [
                        AppLocalizations.of(context)!.marketAll,
                        AppLocalizations.of(context)!.marketWatchlist
                      ],
                      selectedIndex: _listMode,
                      onSelected: (i) {
                        if (i == 0) {
                          if (_listMode != 0) {
                            setState(() => _listMode = 0);
                            _loadAllTickers();
                          }
                        } else {
                          if (_listMode != 1) {
                            _stopQuoteRefreshTimer();
                            setState(() => _listMode = 1);
                            _loadWatchlist();
                          }
                        }
                      },
                    ),
                    if (_listMode == 0 && _allTickers.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      TextButton.icon(
                        onPressed: _exportAllTickersToCsv,
                        icon: const Icon(Icons.download, size: 18),
                        label:
                            Text(AppLocalizations.of(context)!.marketExportCsv),
                        style: TextButton.styleFrom(
                            foregroundColor: TvTheme.positive),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    _Chip(
                        label: AppLocalizations.of(context)!.marketAll,
                        selected: _listMode == 0,
                        onTap: () {
                          if (_listMode != 0) {
                            setState(() => _listMode = 0);
                            _loadAllTickers();
                          }
                        }),
                    const SizedBox(width: 8),
                    _Chip(
                        label: AppLocalizations.of(context)!.marketWatchlist,
                        selected: _listMode == 1,
                        onTap: () {
                          if (_listMode != 1) {
                            _stopQuoteRefreshTimer();
                            setState(() => _listMode = 1);
                            _loadWatchlist();
                          }
                        }),
                  ],
                ),
          const SizedBox(height: TvTheme.sectionGap),
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
                    Text(
                      _listMode == 0
                          ? AppLocalizations.of(context)!
                              .marketLoadingUsStockList
                          : AppLocalizations.of(context)!.marketLoadingQuote,
                      style: const TextStyle(
                          color: Color(0xFF9CA3AF), fontSize: 14),
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
                    Icon(Icons.star_border,
                        size: 56, color: const Color(0xFF6B6B70)),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.marketNoWatchlist,
                      style: const TextStyle(
                        color: Color(0xFFE8D5A3),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)!.marketAddWatchlistHint,
                      style: const TextStyle(
                          color: Color(0xFF9CA3AF), fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SearchPage()),
                        );
                      },
                      icon: const Icon(Icons.add, size: 20),
                      label: Text(AppLocalizations.of(context)!.marketGoAdd),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFD4AF37)),
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
                    Icon(Icons.cloud_off,
                        size: 56, color: const Color(0xFF6B6B70)),
                    const SizedBox(height: 16),
                    Text(
                      _error! == 'POLYGON_NOT_CONFIGURED'
                          ? AppLocalizations.of(context)!
                              .tradingConfigurePolygonApiKey
                          : _error! == 'STOCK_QUOTE_CACHE_EMPTY'
                              ? AppLocalizations.of(context)!
                                  .marketStockQuoteCacheEmpty
                              : _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFFE8D5A3), fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: _refreshQuotesForCurrentMode,
                      icon: const Icon(Icons.refresh, size: 20),
                      label: Text(AppLocalizations.of(context)!.commonRetry),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFD4AF37)),
                    ),
                  ],
                ),
              ),
            )
          else if (_listMode == 0 && _allTickers.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_quoteLoadError != null) _buildQuoteLoadErrorBanner(),
                if (_quoteLoadError != null) const SizedBox(height: 12),
                _isPc
                    ? LayoutBuilder(
                        builder: (context, c) =>
                            _buildAllTickersTablePc(availableWidth: c.maxWidth),
                      )
                    : _buildAllTickersTable(),
              ],
            )
          else if (_listMode == 0 && _allTickers.isEmpty && !_loading)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 200),
              child: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(AppLocalizations.of(context)!.marketNoUsStockList,
                        style: const TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 14)),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _loadAllTickers,
                      icon: const Icon(Icons.refresh, size: 20),
                      label: Text(AppLocalizations.of(context)!.commonRetry),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFD4AF37)),
                    ),
                  ],
                ),
              ),
            )
          else if (symbols.isEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 220),
              child: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(AppLocalizations.of(context)!.marketNoData,
                        style: const TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 14)),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _refreshQuotesForCurrentMode,
                      icon: const Icon(Icons.refresh, size: 20),
                      label: Text(AppLocalizations.of(context)!.commonRetry),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFD4AF37)),
                    ),
                  ],
                ),
              ),
            )
          else if (_isPc && symbols.isNotEmpty)
            _buildWatchlistTablePc(_sortedWatchlistSymbols)
          else if (symbols.isNotEmpty)
            _buildWatchlistTableMobile(),
        ],
      ),
    );
  }

  /// 自选表格（PC）：与「全部」列表同一套 10 列与布局（代码/名称 Expanded，其余列宽一致）
  Widget _buildWatchlistTablePc(List<String> symbols) {
    const rowHeight = 44.0;
    const colPct = 76.0;
    const colPrice = 68.0;
    const colChange = 60.0;
    const colOpen = 60.0;
    const colPrev = 60.0;
    const colHigh = 60.0;
    const colLow = 60.0;
    const colVol = 72.0;

    return Container(
      decoration: BoxDecoration(
        color: TvTheme.surface,
        borderRadius: BorderRadius.circular(TvTheme.radius),
        border: Border.all(color: TvTheme.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: TvTheme.tableHeaderBg,
            child: Container(
              height: TvTheme.tableHeaderHeight,
              padding:
                  const EdgeInsets.symmetric(horizontal: TvTheme.innerPadding),
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: TvTheme.border, width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                      flex: 1,
                      child: InkWell(
                          onTap: () => _onSortColumnTap('code'),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(AppLocalizations.of(context)!.marketCode,
                                style: TvTheme.meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            if (_sortColumn == 'code')
                              Icon(
                                  _sortAscending
                                      ? Icons.arrow_drop_up
                                      : Icons.arrow_drop_down,
                                  size: 18,
                                  color: TvTheme.positive)
                          ]))),
                  Expanded(
                      flex: 2,
                      child: InkWell(
                          onTap: () => _onSortColumnTap('name'),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(AppLocalizations.of(context)!.marketName,
                                style: TvTheme.meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            if (_sortColumn == 'name')
                              Icon(
                                  _sortAscending
                                      ? Icons.arrow_drop_up
                                      : Icons.arrow_drop_down,
                                  size: 18,
                                  color: TvTheme.positive)
                          ]))),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketChangePct, 'pct',
                      width: colPct),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketLatestPrice, 'price',
                      width: colPrice),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketChangeAmount,
                      'change',
                      width: colChange),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketOpen, 'open',
                      width: colOpen),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketPrevClose, 'prev',
                      width: colPrev),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketHigh, 'high',
                      width: colHigh),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketLow, 'low',
                      width: colLow),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketVolume, 'vol',
                      width: colVol),
                ],
              ),
            ),
          ),
          ...symbols.toList().asMap().entries.map((e) {
            final i = e.key;
            final sym = e.value;
            final q = _quotes[sym];
            final hasError = q?.hasError ?? true;
            final price = q?.price ?? 0;
            final change = q?.change ?? 0;
            final pct = q?.changePercent ?? 0;
            final open = q?.open;
            final high = q?.high;
            final low = q?.low;
            final vol = q?.volume;
            final prevClose = price > 0 ? (price - change) : null;
            final color = MarketColors.forChangePercent(pct);
            final isSelected = _selectedSymbol == sym;
            return Material(
              color: isSelected ? TvTheme.rowSelectedBg : Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() => _selectedSymbol = sym);
                  _openDetail(sym, symbolList: symbols, symbolIndex: i);
                },
                child: Container(
                  height: rowHeight,
                  padding: const EdgeInsets.symmetric(
                      horizontal: TvTheme.innerPadding),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: TvTheme.borderSubtle, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 1,
                          child: Text(sym,
                              style: TvTheme.body
                                  .copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      Expanded(
                          flex: 2,
                          child: Text(q?.name ?? sym,
                              style: TvTheme.meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      SizedBox(
                          width: colPct,
                          child: Text(
                              hasError
                                  ? '—'
                                  : '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                              style: TvTheme.meta.copyWith(color: color),
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      SizedBox(
                          width: colPrice,
                          child: Text(
                              hasError || price <= 0
                                  ? '—'
                                  : _formatPrice(price),
                              style: TvTheme.meta,
                              textAlign: TextAlign.right)),
                      SizedBox(
                          width: colChange,
                          child: Text(
                              hasError
                                  ? '—'
                                  : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}',
                              style: TvTheme.meta.copyWith(color: color),
                              textAlign: TextAlign.right)),
                      SizedBox(
                          width: colOpen,
                          child: Text(
                              open == null || open <= 0
                                  ? '—'
                                  : _formatPrice(open),
                              style: TvTheme.meta,
                              textAlign: TextAlign.right)),
                      SizedBox(
                          width: colPrev,
                          child: Text(
                              prevClose == null || prevClose <= 0
                                  ? '—'
                                  : _formatPrice(prevClose),
                              style: TvTheme.meta,
                              textAlign: TextAlign.right)),
                      SizedBox(
                          width: colHigh,
                          child: Text(
                              high == null || high <= 0
                                  ? '—'
                                  : _formatPrice(high),
                              style: TvTheme.meta,
                              textAlign: TextAlign.right)),
                      SizedBox(
                          width: colLow,
                          child: Text(
                              low == null || low <= 0 ? '—' : _formatPrice(low),
                              style: TvTheme.meta,
                              textAlign: TextAlign.right)),
                      SizedBox(
                          width: colVol,
                          child: Text(_formatVolume(vol),
                              style: TvTheme.meta, textAlign: TextAlign.right)),
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

  /// 自选表格（移动端）：与「全部」列表同一套 10 列（代码、名称、涨跌幅、最新价、涨跌额、今开、昨收、最高、最低、成交量）
  Widget _buildWatchlistTableMobile() {
    const rowHeight = 48.0;
    const colCode = 56.0;
    const colName = 100.0;
    const colPct = 72.0;
    const colPrice = 56.0;
    const colChange = 52.0;
    const colOpen = 52.0;
    const colPrev = 52.0;
    const colHigh = 52.0;
    const colLow = 52.0;
    const colVol = 60.0;
    const styleLabel = TextStyle(
        color: Color(0xFF6B6B70), fontSize: 11, fontWeight: FontWeight.w600);
    const styleCell = TextStyle(color: Color(0xFFE8D5A3), fontSize: 12);
    const styleMuted = TextStyle(color: Color(0xFF9CA3AF), fontSize: 12);

    Widget sortHeader(String label, String col, double w,
        {TextAlign align = TextAlign.left}) {
      final isActive = _sortColumn == col;
      return SizedBox(
        width: w,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onSortColumnTap(col),
          child: Row(
            mainAxisAlignment: align == TextAlign.right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: styleLabel,
                  textAlign: align,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                      _sortAscending
                          ? Icons.arrow_drop_up
                          : Icons.arrow_drop_down,
                      size: 16,
                      color: const Color(0xFFD4AF37)),
                ),
            ],
          ),
        ),
      );
    }

    final headerRow = Row(
      children: [
        sortHeader(AppLocalizations.of(context)!.marketCode, 'code', colCode),
        sortHeader(AppLocalizations.of(context)!.marketName, 'name', colName),
        sortHeader(AppLocalizations.of(context)!.marketChangePct, 'pct', colPct,
            align: TextAlign.right),
        sortHeader(
            AppLocalizations.of(context)!.marketLatestPrice, 'price', colPrice,
            align: TextAlign.right),
        sortHeader(AppLocalizations.of(context)!.marketChangeAmount, 'change',
            colChange,
            align: TextAlign.right),
        sortHeader(AppLocalizations.of(context)!.marketOpen, 'open', colOpen,
            align: TextAlign.right),
        sortHeader(
            AppLocalizations.of(context)!.marketPrevClose, 'prev', colPrev,
            align: TextAlign.right),
        sortHeader(AppLocalizations.of(context)!.marketHigh, 'high', colHigh,
            align: TextAlign.right),
        sortHeader(AppLocalizations.of(context)!.marketLow, 'low', colLow,
            align: TextAlign.right),
        sortHeader(AppLocalizations.of(context)!.marketVolume, 'vol', colVol,
            align: TextAlign.right),
      ],
    );

    final symbols = _sortedWatchlistSymbols;
    return SizedBox(
      height: _allListHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1C21),
              border: Border(
                  bottom:
                      BorderSide(color: const Color(0xFF1F1F23), width: 0.6)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: headerRow,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: symbols.length,
              itemExtent: rowHeight,
              itemBuilder: (context, i) {
                final sym = symbols[i];
                final q = _quotes[sym];
                final name = q?.name ?? sym;
                final hasError = q?.hasError ?? true;
                final price = q?.price ?? 0;
                final change = q?.change ?? 0;
                final pct = q?.changePercent ?? 0;
                final open = q?.open;
                final high = q?.high;
                final low = q?.low;
                final vol = q?.volume;
                final prevClose =
                    q?.prevClose ?? (price > 0 ? (price - change) : null);
                final effectiveChange = (prevClose != null && prevClose > 0)
                    ? (price - prevClose)
                    : change;
                final effectivePct = (prevClose != null && prevClose > 0)
                    ? ((effectiveChange / prevClose) * 100)
                    : pct;
                final color = MarketColors.forChangePercent(effectivePct);
                return Material(
                  color: const Color(0xFF111215),
                  child: InkWell(
                    onTap: () =>
                        _openDetail(sym, symbolList: symbols, symbolIndex: i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: Color(0xFF1F1F23), width: 0.6)),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            SizedBox(
                                width: colCode,
                                child: Text(sym,
                                    style: styleCell.copyWith(
                                        fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            SizedBox(
                                width: colName,
                                child: Text(name,
                                    style: styleMuted,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            SizedBox(
                                width: colPct,
                                child: Text(
                                    hasError
                                        ? '—'
                                        : '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                                    style: styleMuted.copyWith(color: color),
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            SizedBox(
                                width: colPrice,
                                child: Text(
                                    hasError || price <= 0
                                        ? '—'
                                        : _formatPrice(price),
                                    style: styleMuted,
                                    textAlign: TextAlign.right)),
                            SizedBox(
                                width: colChange,
                                child: Text(
                                    hasError
                                        ? '—'
                                        : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}',
                                    style: styleMuted.copyWith(color: color),
                                    textAlign: TextAlign.right)),
                            SizedBox(
                                width: colOpen,
                                child: Text(
                                    open == null || open <= 0
                                        ? '—'
                                        : _formatPrice(open),
                                    style: styleMuted,
                                    textAlign: TextAlign.right)),
                            SizedBox(
                                width: colPrev,
                                child: Text(
                                    prevClose == null || prevClose <= 0
                                        ? '—'
                                        : _formatPrice(prevClose),
                                    style: styleMuted,
                                    textAlign: TextAlign.right)),
                            SizedBox(
                                width: colHigh,
                                child: Text(
                                    high == null || high <= 0
                                        ? '—'
                                        : _formatPrice(high),
                                    style: styleMuted,
                                    textAlign: TextAlign.right)),
                            SizedBox(
                                width: colLow,
                                child: Text(
                                    low == null || low <= 0
                                        ? '—'
                                        : _formatPrice(low),
                                    style: styleMuted,
                                    textAlign: TextAlign.right)),
                            SizedBox(
                                width: colVol,
                                child: Text(_formatVolume(vol),
                                    style: styleMuted,
                                    textAlign: TextAlign.right)),
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
      ),
    );
  }

  void _onSortColumnTap(String columnId) {
    setState(() {
      if (_sortColumn == columnId) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = columnId;
        _sortAscending =
            columnId == 'code' || columnId == 'name' || columnId == 'vol';
      }
    });
    if (_listMode == 0) _reloadFromDbWithSort();
  }

  Future<void> _reloadFromDbWithSort() async {
    if (_listMode != 0) return;
    try {
      setState(() {
        _allTickers = [];
        _quotes = {};
        _hasMoreTickers = true;
        _currentPage = 1;
      });
      await _loadTickerPageFromServer(page: 1, append: false);
    } catch (_) {}
  }

  /// 滚动到底部附近时加载下一页（每次 30 条）
  Future<void> _loadMoreTickers() async {
    if (_loadingMore || !_hasMoreTickers || _allTickers.isEmpty) return;
    _loadingMore = true;
    try {
      await _loadTickerPageFromServer(page: _currentPage + 1, append: true);
    } catch (_) {}
    _loadingMore = false;
  }

  String _stockSymbolWithMeta(MarketSearchResult t) {
    if (t.is24HourTrading == true) {
      return '${t.symbol} ·24H';
    }
    return t.symbol;
  }

  String _stockNameWithMeta(MarketSearchResult t) {
    final type = (t.stockType ?? '').trim().toUpperCase();
    if (type.isEmpty) return t.name;
    return '${t.name} ($type)';
  }

  Widget _sortableHeader(String label, String columnId,
      {required double width, TextAlign align = TextAlign.right}) {
    final isActive = _sortColumn == columnId;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () => _onSortColumnTap(columnId),
        child: Row(
          mainAxisAlignment: align == TextAlign.right
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TvTheme.meta,
                textAlign: align,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (isActive)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                    _sortAscending
                        ? Icons.arrow_drop_up
                        : Icons.arrow_drop_down,
                    size: 18,
                    color: TvTheme.positive),
              ),
          ],
        ),
      ),
    );
  }

  /// 全量美股表格（PC）：与涨跌榜一致 10 列，虚拟列表约 8000+ 行；填满可用宽度避免右侧大片空白
  Widget _buildAllTickersTablePc({double? availableWidth}) {
    const rowHeight = 44.0;
    const colPct = 76.0;
    const colPrice = 68.0;
    const colChange = 60.0;
    const colOpen = 60.0;
    const colPrev = 60.0;
    const colHigh = 60.0;
    const colLow = 60.0;
    const colVol = 72.0;
    const fixedColsWidth = colPct +
        colPrice +
        colChange +
        colOpen +
        colPrev +
        colHigh +
        colLow +
        colVol;

    final content = Container(
      decoration: BoxDecoration(
        color: TvTheme.surface,
        borderRadius: BorderRadius.circular(TvTheme.radius),
        border: Border.all(color: TvTheme.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: TvTheme.tableHeaderBg,
            child: Container(
              height: TvTheme.tableHeaderHeight,
              padding:
                  const EdgeInsets.symmetric(horizontal: TvTheme.innerPadding),
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: TvTheme.border, width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                      flex: 1,
                      child: InkWell(
                          onTap: () => _onSortColumnTap('code'),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(AppLocalizations.of(context)!.marketCode,
                                style: TvTheme.meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            if (_sortColumn == 'code')
                              Icon(
                                  _sortAscending
                                      ? Icons.arrow_drop_up
                                      : Icons.arrow_drop_down,
                                  size: 18,
                                  color: TvTheme.positive)
                          ]))),
                  Expanded(
                      flex: 2,
                      child: InkWell(
                          onTap: () => _onSortColumnTap('name'),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(AppLocalizations.of(context)!.marketName,
                                style: TvTheme.meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            if (_sortColumn == 'name')
                              Icon(
                                  _sortAscending
                                      ? Icons.arrow_drop_up
                                      : Icons.arrow_drop_down,
                                  size: 18,
                                  color: TvTheme.positive)
                          ]))),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketChangePct, 'pct',
                      width: colPct),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketLatestPrice, 'price',
                      width: colPrice),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketChangeAmount,
                      'change',
                      width: colChange),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketOpen, 'open',
                      width: colOpen),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketPrevClose, 'prev',
                      width: colPrev),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketHigh, 'high',
                      width: colHigh),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketLow, 'low',
                      width: colLow),
                  _sortableHeader(
                      AppLocalizations.of(context)!.marketVolume, 'vol',
                      width: colVol),
                ],
              ),
            ),
          ),
          SizedBox(
            height: _allListHeight,
            child: ListView.builder(
              controller: _allListScrollController,
              itemCount: _sortedTickers.length,
              itemExtent: rowHeight,
              itemBuilder: (context, i) {
                final t = _sortedTickers[i];
                final q = _quotes[t.symbol];
                final hasError = q?.hasError ?? true;
                final price = q?.price ?? 0;
                final change = q?.change ?? 0;
                final pct = q?.changePercent ?? 0;
                final open = q?.open;
                final high = q?.high;
                final low = q?.low;
                final vol = q?.volume;
                final prevClose =
                    q?.prevClose ?? (price > 0 ? (price - change) : null);
                final effectiveChange = (prevClose != null && prevClose > 0)
                    ? (price - prevClose)
                    : change;
                final effectivePct = (prevClose != null && prevClose > 0)
                    ? ((effectiveChange / prevClose) * 100)
                    : pct;
                final color = MarketColors.forChangePercent(effectivePct);
                final isSelected = _selectedSymbol == t.symbol;
                return Material(
                  color:
                      isSelected ? TvTheme.rowSelectedBg : Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedSymbol = t.symbol);
                      final symbolList =
                          _sortedTickers.map((x) => x.symbol).toList();
                      _openDetail(t.symbol,
                          name: t.name, symbolList: symbolList, symbolIndex: i);
                    },
                    child: Container(
                      height: rowHeight,
                      padding: const EdgeInsets.symmetric(
                          horizontal: TvTheme.innerPadding),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: TvTheme.borderSubtle, width: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                              flex: 1,
                              child: Text(_stockSymbolWithMeta(t),
                                  style: TvTheme.body
                                      .copyWith(fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          Expanded(
                              flex: 2,
                              child: Text(_stockNameWithMeta(t),
                                  style: TvTheme.meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          SizedBox(
                              width: colPct,
                              child: Text(
                                  hasError
                                      ? '—'
                                      : '${effectivePct >= 0 ? '+' : ''}${effectivePct.toStringAsFixed(2)}%',
                                  style: TvTheme.meta.copyWith(color: color),
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          SizedBox(
                              width: colPrice,
                              child: Text(
                                  hasError || price <= 0
                                      ? '—'
                                      : _formatPrice(price),
                                  style: TvTheme.meta,
                                  textAlign: TextAlign.right)),
                          SizedBox(
                              width: colChange,
                              child: Text(
                                  hasError
                                      ? '—'
                                      : '${effectiveChange >= 0 ? '+' : ''}${effectiveChange.toStringAsFixed(2)}',
                                  style: TvTheme.meta.copyWith(color: color),
                                  textAlign: TextAlign.right)),
                          SizedBox(
                              width: colOpen,
                              child: Text(
                                  open == null || open <= 0
                                      ? '—'
                                      : _formatPrice(open),
                                  style: TvTheme.meta,
                                  textAlign: TextAlign.right)),
                          SizedBox(
                              width: colPrev,
                              child: Text(
                                  prevClose == null || prevClose <= 0
                                      ? '—'
                                      : _formatPrice(prevClose),
                                  style: TvTheme.meta,
                                  textAlign: TextAlign.right)),
                          SizedBox(
                              width: colHigh,
                              child: Text(
                                  high == null || high <= 0
                                      ? '—'
                                      : _formatPrice(high),
                                  style: TvTheme.meta,
                                  textAlign: TextAlign.right)),
                          SizedBox(
                              width: colLow,
                              child: Text(
                                  low == null || low <= 0
                                      ? '—'
                                      : _formatPrice(low),
                                  style: TvTheme.meta,
                                  textAlign: TextAlign.right)),
                          SizedBox(
                              width: colVol,
                              child: Text(_formatVolume(vol),
                                  style: TvTheme.meta,
                                  textAlign: TextAlign.right)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    if (availableWidth != null && availableWidth > fixedColsWidth) {
      return SizedBox(width: availableWidth, child: content);
    }
    return content;
  }

  /// 全量美股表格（移动端）：代码/名称固定，涨跌幅等可横向滑动，表头与数据行同步滚动
  Widget _buildAllTickersTable() {
    const rowHeight = 48.0;
    const colCode = 56.0;
    const colName = 100.0;
    const colPct = 72.0;
    const colPrice = 56.0;
    const colChange = 52.0;
    const colOpen = 52.0;
    const colPrev = 52.0;
    const colHigh = 52.0;
    const colLow = 52.0;
    const colVol = 60.0;
    const dataColsWidth = colPct +
        colPrice +
        colChange +
        colOpen +
        colPrev +
        colHigh +
        colLow +
        colVol;
    const styleLabel = TextStyle(
        color: Color(0xFF6B6B70), fontSize: 11, fontWeight: FontWeight.w600);
    const styleCell = TextStyle(color: Color(0xFFE8D5A3), fontSize: 12);
    const styleMuted = TextStyle(color: Color(0xFF9CA3AF), fontSize: 12);

    Widget sortHeader(String label, String col, double w,
        {TextAlign align = TextAlign.left}) {
      final isActive = _sortColumn == col;
      return SizedBox(
        width: w,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onSortColumnTap(col),
          child: Row(
            mainAxisAlignment: align == TextAlign.right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: styleLabel,
                  textAlign: align,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                      _sortAscending
                          ? Icons.arrow_drop_up
                          : Icons.arrow_drop_down,
                      size: 16,
                      color: const Color(0xFFD4AF37)),
                ),
            ],
          ),
        ),
      );
    }

    final headerDataRow = Row(
      children: [
        sortHeader(AppLocalizations.of(context)!.marketChangePct, 'pct', colPct,
            align: TextAlign.right),
        sortHeader(
            AppLocalizations.of(context)!.marketLatestPrice, 'price', colPrice,
            align: TextAlign.right),
        sortHeader(AppLocalizations.of(context)!.marketChangeAmount, 'change',
            colChange,
            align: TextAlign.right),
        sortHeader(AppLocalizations.of(context)!.marketOpen, 'open', colOpen,
            align: TextAlign.right),
        sortHeader(
            AppLocalizations.of(context)!.marketPrevClose, 'prev', colPrev,
            align: TextAlign.right),
        sortHeader(AppLocalizations.of(context)!.marketHigh, 'high', colHigh,
            align: TextAlign.right),
        sortHeader(AppLocalizations.of(context)!.marketLow, 'low', colLow,
            align: TextAlign.right),
        sortHeader(AppLocalizations.of(context)!.marketVolume, 'vol', colVol,
            align: TextAlign.right),
      ],
    );

    return SizedBox(
      height: _allListHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: colCode + colName + 20,
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1C21),
                    border: Border(
                        bottom: BorderSide(
                            color: const Color(0xFF1F1F23), width: 0.6)),
                  ),
                  child: Row(
                    children: [
                      sortHeader(AppLocalizations.of(context)!.marketCode,
                          'code', colCode),
                      sortHeader(AppLocalizations.of(context)!.marketName,
                          'name', colName),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _allListScrollController,
                    itemCount: _sortedTickers.length,
                    itemExtent: rowHeight,
                    itemBuilder: (context, i) {
                      final t = _sortedTickers[i];
                      return Material(
                        color: const Color(0xFF111215),
                        child: InkWell(
                          onTap: () {
                            final symbolList =
                                _sortedTickers.map((x) => x.symbol).toList();
                            _openDetail(t.symbol,
                                name: t.name,
                                symbolList: symbolList,
                                symbolIndex: i);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: const BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: Color(0xFF1F1F23), width: 0.6)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                    width: colCode,
                                    child: Text(_stockSymbolWithMeta(t),
                                        style: styleCell.copyWith(
                                            fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                                SizedBox(
                                    width: colName,
                                    child: Text(_stockNameWithMeta(t),
                                        style: styleMuted,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _horizontalScrollController,
              child: SizedBox(
                width: dataColsWidth + 20,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1C21),
                        border: Border(
                            bottom: BorderSide(
                                color: const Color(0xFF1F1F23), width: 0.6)),
                      ),
                      child: headerDataRow,
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _allListRightScrollController,
                        itemCount: _sortedTickers.length,
                        itemExtent: rowHeight,
                        itemBuilder: (context, i) {
                          final t = _sortedTickers[i];
                          final q = _quotes[t.symbol];
                          final hasError = q?.hasError ?? true;
                          final price = q?.price ?? 0;
                          final change = q?.change ?? 0;
                          final pct = q?.changePercent ?? 0;
                          final open = q?.open;
                          final high = q?.high;
                          final low = q?.low;
                          final vol = q?.volume;
                          final prevClose = q?.prevClose ??
                              (price > 0 ? (price - change) : null);
                          final effectiveChange =
                              (prevClose != null && prevClose > 0)
                                  ? (price - prevClose)
                                  : change;
                          final effectivePct =
                              (prevClose != null && prevClose > 0)
                                  ? ((effectiveChange / prevClose) * 100)
                                  : pct;
                          final color =
                              MarketColors.forChangePercent(effectivePct);
                          return Material(
                            color: const Color(0xFF111215),
                            child: InkWell(
                              onTap: () {
                                final symbolList = _sortedTickers
                                    .map((x) => x.symbol)
                                    .toList();
                                _openDetail(t.symbol,
                                    name: t.name,
                                    symbolList: symbolList,
                                    symbolIndex: i);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: const BoxDecoration(
                                  border: Border(
                                      bottom: BorderSide(
                                          color: Color(0xFF1F1F23),
                                          width: 0.6)),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                        width: colPct,
                                        child: Text(
                                            hasError
                                                ? '—'
                                                : '${effectivePct >= 0 ? '+' : ''}${effectivePct.toStringAsFixed(2)}%',
                                            style: styleMuted.copyWith(
                                                color: color),
                                            textAlign: TextAlign.right,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)),
                                    SizedBox(
                                        width: colPrice,
                                        child: Text(
                                            hasError || price <= 0
                                                ? '—'
                                                : _formatPrice(price),
                                            style: styleMuted,
                                            textAlign: TextAlign.right)),
                                    SizedBox(
                                        width: colChange,
                                        child: Text(
                                            hasError
                                                ? '—'
                                                : '${effectiveChange >= 0 ? '+' : ''}${effectiveChange.toStringAsFixed(2)}',
                                            style: styleMuted.copyWith(
                                                color: color),
                                            textAlign: TextAlign.right)),
                                    SizedBox(
                                        width: colOpen,
                                        child: Text(
                                            open == null || open <= 0
                                                ? '—'
                                                : _formatPrice(open),
                                            style: styleMuted,
                                            textAlign: TextAlign.right)),
                                    SizedBox(
                                        width: colPrev,
                                        child: Text(
                                            prevClose == null || prevClose <= 0
                                                ? '—'
                                                : _formatPrice(prevClose),
                                            style: styleMuted,
                                            textAlign: TextAlign.right)),
                                    SizedBox(
                                        width: colHigh,
                                        child: Text(
                                            high == null || high <= 0
                                                ? '—'
                                                : _formatPrice(high),
                                            style: styleMuted,
                                            textAlign: TextAlign.right)),
                                    SizedBox(
                                        width: colLow,
                                        child: Text(
                                            low == null || low <= 0
                                                ? '—'
                                                : _formatPrice(low),
                                            style: styleMuted,
                                            textAlign: TextAlign.right)),
                                    SizedBox(
                                        width: colVol,
                                        child: Text(_formatVolume(vol),
                                            style: styleMuted,
                                            textAlign: TextAlign.right)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _exportAllTickersToCsv() {
    const maxRows = 2000;
    final display = _displayTickers;
    final sb = StringBuffer();
    sb.writeln(AppLocalizations.of(context)!.marketCsvHeader);
    final end = display.length > maxRows ? maxRows : display.length;
    for (var i = 0; i < end; i++) {
      final t = display[i];
      final q = _quotes[t.symbol];
      final pct = q?.changePercent;
      final price = q?.price ?? 0;
      final change = q?.change ?? 0;
      final prevClose = price > 0 ? price - change : null;
      sb.writeln([
        t.symbol,
        '"${t.name.replaceAll('"', '""')}"',
        pct != null ? pct.toStringAsFixed(2) : '—',
        price > 0 ? price.toStringAsFixed(2) : '—',
        change.toStringAsFixed(2),
        q?.open != null && q!.open! > 0 ? q.open!.toStringAsFixed(2) : '—',
        prevClose != null && prevClose > 0 ? prevClose.toStringAsFixed(2) : '—',
        q?.high != null && q!.high! > 0 ? q.high!.toStringAsFixed(2) : '—',
        q?.low != null && q!.low! > 0 ? q.low!.toStringAsFixed(2) : '—',
        q?.volume != null && q!.volume! > 0 ? q.volume.toString() : '—',
      ].join(','));
    }
    final csv = sb.toString();
    Clipboard.setData(ClipboardData(text: csv));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context)!.marketCopyCsvSuccess(end),
              style: const TextStyle(color: Colors.white))),
    );
  }

  Widget _buildQuoteLoadErrorBanner() {
    final msg = _quoteLoadError ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded,
              size: 20, color: const Color(0xFFD4AF37)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: Color(0xFFE8D5A3), fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _quoteLoadError = null);
              _loadFirstVisibleQuotesAndStartTimer();
            },
            child: Text(AppLocalizations.of(context)!.commonRetry,
                style: const TextStyle(
                    color: Color(0xFFD4AF37), fontWeight: FontWeight.w600)),
          ),
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
        border:
            Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: const Color(0xFFD4AF37)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.marketMockDataPcHint,
              style: TextStyle(color: Color(0xFFE8D5A3), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 美股三大指数卡：优先用接口数据，无则用 mock
  Widget _buildUsIndexCards() {
    final l10n = AppLocalizations.of(context)!;
    final indices = [
      (l10n.marketIndexDowJones, 'DJI'),
      (l10n.marketIndexNasdaq, 'IXIC'),
      (l10n.marketIndexSp500, 'SPX'),
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
          if (x is Map<String, dynamic> && x['symbol'] == e.$2) {
            m = x;
            break;
          }
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
              border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Color(0xFF9CA3AF), fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  value > 0 ? value.toStringAsFixed(2) : '—',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  value > 0
                      ? '${ch >= 0 ? '+' : ''}${ch.toStringAsFixed(2)} ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%'
                      : '—',
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

  /// PC 美股三大指数：TvIndexCard 横排
  Widget _buildUsIndexCardsTv() {
    final l10n = AppLocalizations.of(context)!;
    final indices = [
      (l10n.marketIndexDowJones, 'DJI'),
      (l10n.marketIndexNasdaq, 'IXIC'),
      (l10n.marketIndexSp500, 'SPX')
    ];
    return Row(
      children: indices.asMap().entries.map((entry) {
        final label = entry.value.$1;
        final symbol = entry.value.$2;
        final isLast = entry.key == indices.length - 1;
        final q = _indexQuotes[symbol];
        double? price;
        double? change;
        double? changePercent;
        bool hasError = true;
        if (q != null && !q.hasError && q.price > 0) {
          price = q.price;
          change = q.change;
          changePercent = q.changePercent;
          hasError = false;
        } else {
          for (final x in MockMarketData.indicesQuotes) {
            if (x is Map<String, dynamic> && x['symbol'] == symbol) {
              price = (x['close'] as num?)?.toDouble();
              change = (x['change'] as num?)?.toDouble();
              changePercent = (x['percent_change'] as num?)?.toDouble();
              hasError = price == null;
              break;
            }
          }
        }
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : TvTheme.sectionGap),
            child: TvIndexCard(
              label: label,
              symbol: symbol,
              price: price,
              change: change,
              changePercent: changePercent,
              hasError: hasError,
              isLoading: q == null && _loading,
              onTap: () {
                final symbolList = indices.map((e) => e.$2).toList();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => GenericChartPage(
                          symbol: symbol,
                          name: label,
                          symbolList: symbolList,
                          symbolIndex: entry.key)),
                );
              },
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
              color:
                  selected ? const Color(0xFFD4AF37) : const Color(0xFF9CA3AF),
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
      child: Row(
        children: [
          const SizedBox(
              width: 28,
              child: Text('#',
                  style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          SizedBox(
              width: 56,
              child: Text(AppLocalizations.of(context)!.marketCode,
                  style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          const Spacer(),
          Text(AppLocalizations.of(context)!.marketLatestPrice,
              style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          SizedBox(
              width: 56,
              child: Text(AppLocalizations.of(context)!.marketChange,
                  style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          SizedBox(
              width: 72,
              child: Text(AppLocalizations.of(context)!.marketChangePct,
                  style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          SizedBox(
              width: 56,
              child: Text(AppLocalizations.of(context)!.marketVolume,
                  style: const TextStyle(
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
                  width: 72,
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
  StreamSubscription<MarketQuoteUpdate>? _realtimeSub;

  /// 热门外汇排前面，全量列表以热门为首
  static const _popularSymbols = [
    'EUR/USD',
    'USD/JPY',
    'GBP/USD',
    'AUD/USD',
    'USD/CHF',
    'USD/CAD',
    'NZD/USD',
    'EUR/GBP',
    'EUR/JPY',
    'GBP/JPY',
    'EUR/AUD',
    'AUD/JPY',
    'EUR/CHF',
    'USD/CNY',
    'USD/HKD',
    'USD/SGD',
    'USD/INR',
    'USD/KRW',
    'USD/MXN',
    'EUR/CAD',
  ];

  static const _fallbackPairs = [
    ('欧元/美元', 'EUR/USD'),
    ('美元/日元', 'USD/JPY'),
    ('英镑/美元', 'GBP/USD'),
    ('澳元/美元', 'AUD/USD'),
    ('美元/瑞郎', 'USD/CHF'),
    ('美元/加元', 'USD/CAD'),
  ];
  List<(String, String)> _pairs = List<(String, String)>.from(_fallbackPairs);
  Map<String, MarketQuote?> _quotes = {};
  bool _loading = true;
  bool _isMockData = false;
  static const _quoteChunkSize = 80;
  static const _forexPageSize = 30;
  Set<String> _attemptedSymbols = <String>{};
  bool _loadingMorePairs = false;
  bool _hasMorePairs = true;
  int _forexPage = 1;
  Set<String> _pairSymbolSet = <String>{};
  Set<String> _realtimeSubscribedSymbols = <String>{};

  bool _isValidQuote(MarketQuote? quote) {
    return quote != null && !quote.hasError && quote.price > 0;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
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
    if (mounted) {
      setState(() {
        _loading = true;
        _isMockData = false;
      });
    }
    if (!_market.forexBackendAvailable) {
      final directQuotes =
          await _market.getQuotes(_pairs.map((e) => e.$2).toList());
      if (directQuotes.isNotEmpty) {
        _pairSymbolSet = _pairs.map((e) => e.$2).toSet();
        _attemptedSymbols.addAll(_pairSymbolSet);
        if (mounted) {
          setState(() {
            _quotes = directQuotes;
            _isMockData = false;
            _loading = false;
          });
        }
        _startRealtimeAndSubscribeCurrentPairs();
        return;
      }
      if (_quotes.isEmpty) {
        _applyMockForex();
      }
      _startRealtimeAndSubscribeCurrentPairs();
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    _forexPage = 1;
    _hasMorePairs = true;
    await _loadMorePairs(reset: true);
    await _fetchQuotesBySymbols(_pairs.map((e) => e.$2).toList(), reset: true);
    _startRealtimeAndSubscribeCurrentPairs();
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _fetchQuotesBySymbols(List<String> symbols,
      {bool reset = false}) async {
    if (symbols.isEmpty) return;
    final uniqueSymbols = <String>{
      for (final s in symbols)
        if (s.trim().isNotEmpty) s.trim()
    }.toList();
    final merged = reset
        ? <String, MarketQuote?>{}
        : Map<String, MarketQuote?>.from(_quotes);
    try {
      for (var i = 0; i < uniqueSymbols.length; i += _quoteChunkSize) {
        final end = (i + _quoteChunkSize > uniqueSymbols.length)
            ? uniqueSymbols.length
            : i + _quoteChunkSize;
        final chunk = uniqueSymbols.sublist(i, end);
        if (chunk.isEmpty) continue;
        final chunkQuotes = await _market.getForexQuotesBySymbols(chunk);
        for (final entry in chunkQuotes.entries) {
          final next = entry.value;
          final prev = merged[entry.key];
          final nextValid = _isValidQuote(next);
          final prevValid = _isValidQuote(prev);
          if (!nextValid && prevValid) continue;
          if (!nextValid && !prevValid) continue;
          merged[entry.key] = next;
        }
      }
      _attemptedSymbols.addAll(uniqueSymbols);
      if (mounted) {
        setState(() {
          _quotes = merged;
          if (merged.values.any(_isValidQuote)) _isMockData = false;
        });
      }
    } catch (_) {
      _attemptedSymbols.addAll(uniqueSymbols);
    }
  }

  Future<void> _loadMorePairs({bool reset = false}) async {
    if (_loadingMorePairs) return;
    if (!reset && !_hasMorePairs) return;
    _loadingMorePairs = true;
    try {
      final targetPage = reset ? 1 : _forexPage;
      final page = await _market.getForexPairsPage(
        page: targetPage,
        pageSize: _forexPageSize,
      );
      if (page.items.isEmpty) {
        _hasMorePairs = false;
        return;
      }
      final incoming = page.items;
      final incomingOrdered = (() {
        if (!reset || incoming.length <= 1) return incoming;
        final map = <String, dynamic>{
          for (final item in incoming) item.symbol: item
        };
        final out = <dynamic>[];
        final seen = <String>{};
        for (final sym in _popularSymbols) {
          final hit = map[sym];
          if (hit == null) continue;
          out.add(hit);
          seen.add(sym);
        }
        for (final item in incoming) {
          if (seen.contains(item.symbol)) continue;
          out.add(item);
        }
        return out;
      })();
      final merged = <(String, String)>[];
      final seen = <String>{};
      if (!reset) {
        for (final p in _pairs) {
          merged.add(p);
          seen.add(p.$2);
        }
      }
      for (final p in incomingOrdered) {
        if (seen.contains(p.symbol)) continue;
        merged.add((p.name, p.symbol));
        seen.add(p.symbol);
      }
      _pairs = merged;
      _pairSymbolSet = _pairs.map((e) => e.$2).toSet();
      _forexPage = targetPage + 1;
      _hasMorePairs = page.hasMore;
      if (!reset && incomingOrdered.isNotEmpty) {
        await _fetchQuotesBySymbols(
          incomingOrdered.map<String>((e) => e.symbol as String).toList(),
        );
      }
      _startRealtimeAndSubscribeCurrentPairs();
      if (mounted) setState(() {});
    } catch (_) {
    } finally {
      _loadingMorePairs = false;
    }
  }

  void _startRealtimeAndSubscribeCurrentPairs() {
    if (!ChatWebSocketService.instance.isConnected || _pairs.isEmpty) return;
    final symbols = _pairs.map((e) => e.$2).toSet();
    if (_sameSet(symbols, _realtimeSubscribedSymbols)) return;
    _realtimeSub?.cancel();
    _realtimeSubscribedSymbols = symbols;
    ChatWebSocketService.instance.subscribeMarket(symbols.toList());
    _realtimeSub ??= ChatWebSocketService.instance.marketQuoteStream
        .listen(_onRealtimeQuote);
  }

  bool _sameSet(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  void _onRealtimeQuote(MarketQuoteUpdate u) {
    if (!mounted) return;
    final symbol = u.symbol;
    if (!_pairSymbolSet.contains(symbol)) return;
    final prev = _quotes[symbol];
    if (prev != null &&
        !prev.hasError &&
        (prev.price - u.price).abs() < 0.0000001) return;
    final prevClose = prev?.prevClose ??
        ((prev != null && prev.change != 0)
            ? (prev.price - prev.change)
            : null);
    final effectiveChange = (prevClose != null && prevClose > 0)
        ? (u.price - prevClose)
        : (u.change ?? 0);
    final effectivePct = (prevClose != null && prevClose > 0)
        ? ((effectiveChange / prevClose) * 100)
        : (u.percentChange ?? 0);
    final next = MarketQuote(
      symbol: symbol,
      name: prev?.name ?? symbol,
      price: u.price,
      change: effectiveChange,
      changePercent: effectivePct,
      open: prev?.open,
      high: prev != null && prev.high != null
          ? (u.price > prev.high! ? u.price : prev.high)
          : u.price,
      low: prev != null && prev.low != null
          ? (u.price < prev.low! ? u.price : prev.low)
          : u.price,
      volume: prev?.volume,
      prevClose: prevClose,
    );
    _attemptedSymbols.add(symbol);
    setState(() {
      _quotes[symbol] = next;
      _isMockData = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _quotes.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
    }
    if (_quotes.isEmpty) {
      return Center(
          child: Text(AppLocalizations.of(context)!.marketNoData,
              style: const TextStyle(color: Color(0xFF9CA3AF))));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFD4AF37),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _pairs.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _isMockData
                ? _forexCryptoMockBanner(context)
                : const SizedBox.shrink();
          }

          final rowIndex = index - 1;
          if (rowIndex < _pairs.length) {
            if (_hasMorePairs &&
                !_loadingMorePairs &&
                rowIndex >= _pairs.length - 5) {
              unawaited(_loadMorePairs());
            }
            final name = _pairs[rowIndex].$1;
            final symbol = _pairs[rowIndex].$2;
            final q = _quotes[symbol];
            final tried = _attemptedSymbols.contains(symbol);
            final notYetLoaded = q == null && !tried;
            return QuoteRow(
              symbol: symbol,
              name: name,
              price: q?.price ?? 0,
              change: q?.change ?? 0,
              changePercent: q?.changePercent ?? 0,
              hasError: q?.hasError ?? tried,
              isLoading: notYetLoaded,
              onTap: () {
                final symbolList = _pairs.map((p) => p.$2).toList();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GenericChartPage(
                        symbol: symbol,
                        name: name,
                        symbolList: symbolList,
                        symbolIndex: rowIndex),
                  ),
                );
              },
            );
          }

          if (_loadingMorePairs) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _forexCryptoMockBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFFD4AF37)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.marketMockDataHint,
              style: const TextStyle(color: Color(0xFFE8D5A3), fontSize: 12),
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
  StreamSubscription<MarketQuoteUpdate>? _realtimeSub;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _cryptoRowsAnchorKey = GlobalKey();
  Set<String> _attemptedSymbols = <String>{};

  bool _isValidQuote(MarketQuote? quote) {
    return quote != null && !quote.hasError && quote.price > 0;
  }

  bool get _hasAnyValidQuotes => _quotes.values.any(_isValidQuote);

  static const _popularCryptoSymbols = [
    'BTC/USD',
    'ETH/USD',
    'SOL/USD',
    'XRP/USD',
    'DOGE/USD',
    'AVAX/USD',
    'BNB/USD',
    'ADA/USD',
    'DOT/USD',
    'MATIC/USD',
    'LINK/USD',
    'LTC/USD',
    'TRX/USD',
    'ATOM/USD',
    'UNI/USD',
  ];

  static const _fallbackCoins = [
    ('BTC/USD', 'BTC/USD'),
    ('ETH/USD', 'ETH/USD'),
    ('SOL/USD', 'SOL/USD'),
    ('XRP/USD', 'XRP/USD'),
    ('DOGE/USD', 'DOGE/USD'),
    ('AVAX/USD', 'AVAX/USD'),
  ];
  List<(String, String)> _coins = List<(String, String)>.from(_fallbackCoins);

  /// 0=市值 1=领涨榜 2=领跌榜
  int _cryptoSubTab = 0;
  Map<String, MarketQuote?> _quotes = {};
  bool _loading = true;
  bool _isMockData = false;
  bool _loadingMoreCoins = false;
  bool _hasMoreCoins = true;
  int _cryptoPage = 1;
  Set<String> _coinSymbolSet = <String>{};
  Map<String, String> _coinSymbolByUpper = <String, String>{};
  Set<String> _realtimeSubscribedSymbols = <String>{};
  static const _quoteChunkSize = 80;
  static const _cryptoRowExtentEstimate = 56.0;
  static const _realtimeVisibleOverscanRows = 6;
  static const _realtimeFlushInterval = Duration(milliseconds: 250);
  static const _realtimeResubscribeDebounce = Duration(milliseconds: 120);
  static const _realtimeMinResubscribeInterval = Duration(seconds: 1);
  final Map<String, MarketQuoteUpdate> _pendingRealtimeUpdates =
      <String, MarketQuoteUpdate>{};
  Timer? _realtimeFlushTimer;
  Timer? _realtimeResubscribeTimer;
  int _lastRealtimeResubscribeAtMs = 0;

  static const _hotReads = [
    '比特币价格低于大行ETF成本线!捞底华尔街的时机...',
    '白宫施压银行同意稳定币奖励并推进加密市场结构法案',
    '币价大跌不用慌?特朗普家族加密货币平台海湖庄园...',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onListScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onListScroll);
    _scrollController.dispose();
    _realtimeFlushTimer?.cancel();
    _realtimeResubscribeTimer?.cancel();
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _onListScroll() {
    if (!_scrollController.hasClients) return;
    if (_hasMoreCoins &&
        !_loadingMoreCoins &&
        _scrollController.position.extentAfter < 900) {
      unawaited(_loadMoreCoins());
    }
    _scheduleCryptoRealtimeResubscribe();
  }

  Future<void> _loadCachedThenRefresh() async {
    await _load();
  }

  void _rebuildCoinSymbolLookup() {
    final symbolSet = <String>{};
    final symbolByUpper = <String, String>{};
    for (final item in _coins) {
      final original = item.$2.trim();
      if (original.isEmpty) continue;
      final upper = original.toUpperCase();
      symbolSet.add(upper);
      symbolByUpper[upper] = original;
    }
    _coinSymbolSet = symbolSet;
    _coinSymbolByUpper = symbolByUpper;
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
    if (mounted) {
      setState(() {
        _loading = true;
        _isMockData = false;
      });
    }
    if (!_market.cryptoBackendAvailable) {
      final directQuotes =
          await _market.getQuotes(_coins.map((e) => e.$2).toList());
      if (directQuotes.isNotEmpty) {
        _rebuildCoinSymbolLookup();
        _attemptedSymbols.addAll(_coins.map((e) => e.$2));
        if (mounted) {
          setState(() {
            _quotes = directQuotes;
            _isMockData = false;
            _loading = false;
          });
        }
        _startCryptoRealtimeAndSubscribeCurrentPairs();
        return;
      }
      if (_quotes.isEmpty) _applyMockCrypto();
      _startCryptoRealtimeAndSubscribeCurrentPairs();
      if (mounted) setState(() => _loading = false);
      return;
    }

    _coins = List<(String, String)>.from(_fallbackCoins);
    _rebuildCoinSymbolLookup();
    _attemptedSymbols.clear();
    await _fetchCryptoQuotesBySymbols(
      _coins.map((e) => e.$2).toList(),
      reset: true,
    );

    _cryptoPage = 1;
    _hasMoreCoins = true;
    await _loadMoreCoins(reset: true);
    await _fetchCryptoQuotesBySymbols(
      _coins.map((e) => e.$2).toList(),
      reset: false,
    );
    if (!_hasAnyValidQuotes) {
      _applyMockCrypto();
    }
    _startCryptoRealtimeAndSubscribeCurrentPairs();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchCryptoQuotesBySymbols(List<String> symbols,
      {bool reset = false}) async {
    if (symbols.isEmpty) return;
    final uniqueSymbols = <String>{
      for (final s in symbols)
        if (s.trim().isNotEmpty) s.trim()
    }.toList();
    final merged = reset
        ? <String, MarketQuote?>{}
        : Map<String, MarketQuote?>.from(_quotes);
    try {
      for (var i = 0; i < uniqueSymbols.length; i += _quoteChunkSize) {
        final end = (i + _quoteChunkSize > uniqueSymbols.length)
            ? uniqueSymbols.length
            : i + _quoteChunkSize;
        final chunk = uniqueSymbols.sublist(i, end);
        if (chunk.isEmpty) continue;
        final chunkQuotes = await _market.getCryptoQuotesBySymbols(chunk);
        for (final entry in chunkQuotes.entries) {
          final next = entry.value;
          final prev = merged[entry.key];
          final nextValid = _isValidQuote(next);
          final prevValid = _isValidQuote(prev);
          if (!nextValid && prevValid) continue;
          if (!nextValid && !prevValid) continue;
          merged[entry.key] = next;
        }
      }
      _attemptedSymbols.addAll(uniqueSymbols);
      if (mounted) {
        setState(() {
          _quotes = merged;
          if (merged.values.any(_isValidQuote)) _isMockData = false;
        });
      }
    } catch (_) {
      _attemptedSymbols.addAll(uniqueSymbols);
    }
  }

  Future<void> _loadMoreCoins({bool reset = false}) async {
    if (_loadingMoreCoins) return;
    if (!reset && !_hasMoreCoins) return;
    _loadingMoreCoins = true;
    try {
      final targetPage = reset ? 1 : _cryptoPage;
      final page = await _market.getCryptoPairsPage(
        page: targetPage,
        pageSize: 30,
      );
      if (page.items.isEmpty) {
        _hasMoreCoins = false;
        return;
      }
      final incoming = page.items;
      final incomingOrdered = (() {
        if (!reset || incoming.length <= 1) return incoming;
        final map = <String, dynamic>{
          for (final item in incoming) item.symbol: item
        };
        final out = <dynamic>[];
        final seen = <String>{};
        for (final sym in _popularCryptoSymbols) {
          final hit = map[sym];
          if (hit == null) continue;
          out.add(hit);
          seen.add(sym);
        }
        for (final item in incoming) {
          if (seen.contains(item.symbol)) continue;
          out.add(item);
        }
        return out;
      })();
      final merged = <(String, String)>[];
      final seen = <String>{};
      if (reset) {
        for (final p in _coins) {
          if (seen.contains(p.$2)) continue;
          merged.add(p);
          seen.add(p.$2);
        }
      } else {
        for (final p in _coins) {
          merged.add(p);
          seen.add(p.$2);
        }
      }
      for (final p in incomingOrdered) {
        if (seen.contains(p.symbol)) continue;
        merged.add((p.name, p.symbol));
        seen.add(p.symbol);
      }
      _coins = merged;
      _rebuildCoinSymbolLookup();
      _cryptoPage = targetPage + 1;
      _hasMoreCoins = page.hasMore;
      if (!reset && incomingOrdered.isNotEmpty) {
        await _fetchCryptoQuotesBySymbols(
          incomingOrdered.map<String>((e) => e.symbol as String).toList(),
        );
      }
      _startCryptoRealtimeAndSubscribeCurrentPairs();
      if (mounted) setState(() {});
    } catch (_) {
    } finally {
      _loadingMoreCoins = false;
    }
  }

  void _startCryptoRealtimeAndSubscribeCurrentPairs() {
    if (!ChatWebSocketService.instance.isConnected) return;
    final symbols = _visibleCryptoSymbolsForRealtime();
    if (symbols.isEmpty) return;
    if (_sameSet(symbols, _realtimeSubscribedSymbols)) return;
    _realtimeSub?.cancel();
    _realtimeSubscribedSymbols = symbols;
    ChatWebSocketService.instance.subscribeMarket(symbols.toList());
    _realtimeSub ??= ChatWebSocketService.instance.marketQuoteStream
        .listen(_onCryptoRealtimeQuote);
  }

  void _scheduleCryptoRealtimeResubscribe({bool force = false}) {
    if (_realtimeResubscribeTimer != null && !force) return;
    if (force) {
      _realtimeResubscribeTimer?.cancel();
      _realtimeResubscribeTimer = null;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final sinceLast = now - _lastRealtimeResubscribeAtMs;
    final waitByCooldown =
        _realtimeMinResubscribeInterval.inMilliseconds - sinceLast;
    final delayMs = waitByCooldown > 0
        ? (waitByCooldown > _realtimeResubscribeDebounce.inMilliseconds
            ? waitByCooldown
            : _realtimeResubscribeDebounce.inMilliseconds)
        : _realtimeResubscribeDebounce.inMilliseconds;
    _realtimeResubscribeTimer = Timer(Duration(milliseconds: delayMs), () {
      _realtimeResubscribeTimer = null;
      _lastRealtimeResubscribeAtMs = DateTime.now().millisecondsSinceEpoch;
      _startCryptoRealtimeAndSubscribeCurrentPairs();
    });
  }

  Set<String> _visibleCryptoSymbolsForRealtime() {
    final sortedSymbols =
        _sortedCryptoList().map((e) => e.$2).toList(growable: false);
    if (sortedSymbols.isEmpty) return <String>{};
    if (!_scrollController.hasClients) {
      return sortedSymbols.take(_realtimeVisibleOverscanRows * 3).toSet();
    }
    final anchorContext = _cryptoRowsAnchorKey.currentContext;
    final scrollContext =
        _scrollController.position.context.notificationContext;
    final anchorBox = anchorContext?.findRenderObject() as RenderBox?;
    final scrollBox = scrollContext?.findRenderObject() as RenderBox?;
    if (anchorBox == null || scrollBox == null) {
      return sortedSymbols.take(_realtimeVisibleOverscanRows * 3).toSet();
    }
    final viewportTop = scrollBox.localToGlobal(Offset.zero).dy;
    final anchorTop = anchorBox.localToGlobal(Offset.zero).dy;
    final anchorInViewport = anchorTop - viewportTop;
    final viewportHeight = _scrollController.position.viewportDimension;

    var first = ((-anchorInViewport) / _cryptoRowExtentEstimate).floor();
    var last =
        ((viewportHeight - anchorInViewport) / _cryptoRowExtentEstimate).ceil();
    first -= _realtimeVisibleOverscanRows;
    last += _realtimeVisibleOverscanRows;
    if (last < 0 || first >= sortedSymbols.length) {
      return <String>{};
    }
    first = first.clamp(0, sortedSymbols.length - 1).toInt();
    last = last.clamp(0, sortedSymbols.length).toInt();
    if (last <= first) {
      last = (first + 1).clamp(0, sortedSymbols.length).toInt();
    }
    return sortedSymbols.sublist(first, last).toSet();
  }

  bool _sameSet(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  void _onCryptoRealtimeQuote(MarketQuoteUpdate u) {
    if (!mounted) return;
    final upper = u.symbol.trim().toUpperCase();
    if (!_coinSymbolSet.contains(upper)) return;
    _pendingRealtimeUpdates[upper] = u;
    _realtimeFlushTimer ??=
        Timer(_realtimeFlushInterval, _flushPendingRealtimeUpdates);
  }

  void _flushPendingRealtimeUpdates() {
    _realtimeFlushTimer = null;
    if (!mounted || _pendingRealtimeUpdates.isEmpty) return;
    final updates =
        Map<String, MarketQuoteUpdate>.from(_pendingRealtimeUpdates);
    _pendingRealtimeUpdates.clear();
    var changed = false;
    for (final entry in updates.entries) {
      final symbol = _coinSymbolByUpper[entry.key] ?? entry.value.symbol.trim();
      final u = entry.value;
      final prev = _quotes[symbol];
      if (prev != null &&
          !prev.hasError &&
          (prev.price - u.price).abs() < 0.0000001) {
        continue;
      }
      final prevClose = prev?.prevClose ??
          ((prev != null && prev.change != 0)
              ? (prev.price - prev.change)
              : null);
      final effectiveChange = (prevClose != null && prevClose > 0)
          ? (u.price - prevClose)
          : (u.change ?? 0);
      final effectivePct = (prevClose != null && prevClose > 0)
          ? ((effectiveChange / prevClose) * 100)
          : (u.percentChange ?? 0);
      final high = prev != null && prev.high != null
          ? (u.price > prev.high! ? u.price : prev.high)
          : u.price;
      final low = prev != null && prev.low != null
          ? (u.price < prev.low! ? u.price : prev.low)
          : u.price;
      _quotes[symbol] = MarketQuote(
        symbol: symbol,
        name: prev?.name ?? symbol,
        price: u.price,
        change: effectiveChange,
        changePercent: effectivePct,
        open: prev?.open,
        high: high,
        low: low,
        volume: prev?.volume,
        prevClose: prevClose,
      );
      _attemptedSymbols.add(symbol);
      changed = true;
    }
    if (!changed) return;
    setState(() {
      _isMockData = false;
    });
    if (_cryptoSubTab != 0 && _realtimeSubscribedSymbols.isNotEmpty) {
      _scheduleCryptoRealtimeResubscribe();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _quotes.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
    }
    if (_quotes.isEmpty) {
      return Center(
          child: Text(AppLocalizations.of(context)!.marketNoData,
              style: const TextStyle(color: Color(0xFF9CA3AF))));
    }
    final sorted = _sortedCryptoList();
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFD4AF37),
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_isMockData) _cryptoMockBanner(context),
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
              border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Color(0xFF9CA3AF), fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  close > 0 ? _formatCryptoPrice(close) : '—',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w700, fontSize: 15),
                ),
                Text(
                  close > 0
                      ? '${ch >= 0 ? '+' : ''}${ch.toStringAsFixed(2)} ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%'
                      : '—',
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
            Text(AppLocalizations.of(context)!.marketHotNews,
                style: TextStyle(
                    color: const Color(0xFFD4AF37),
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios,
                size: 12, color: const Color(0xFFD4AF37)),
            const Spacer(),
            GestureDetector(
              onTap: () {},
              child: Text(
                  '${AppLocalizations.of(context)!.marketSubscribeTopic} >',
                  style:
                      TextStyle(color: const Color(0xFF9CA3AF), fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._hotReads.map((title) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.local_fire_department,
                      size: 18, color: const Color(0xFFD4AF37)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              color: Color(0xFFE5E7EB), fontSize: 13))),
                ],
              ),
            )),
      ],
    );
  }

  /// 可交易币种：子 Tab 市值/领涨榜/领跌榜 + 列表
  Widget _buildTradableCryptoSection(
      BuildContext context, List<(String, String, MarketQuote?)> sorted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(AppLocalizations.of(context)!.marketTradableCoins,
                style: TextStyle(
                    color: const Color(0xFFE8D5A3),
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios,
                size: 12, color: const Color(0xFFD4AF37)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _CryptoSubChip(
                label: AppLocalizations.of(context)!.marketMarketCap,
                selected: _cryptoSubTab == 0,
                onTap: () {
                  if (_cryptoSubTab == 0) return;
                  setState(() => _cryptoSubTab = 0);
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scheduleCryptoRealtimeResubscribe(force: true));
                }),
            const SizedBox(width: 8),
            _CryptoSubChip(
                label: AppLocalizations.of(context)!.marketTopGainers,
                selected: _cryptoSubTab == 1,
                onTap: () {
                  if (_cryptoSubTab == 1) return;
                  setState(() => _cryptoSubTab = 1);
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scheduleCryptoRealtimeResubscribe(force: true));
                }),
            const SizedBox(width: 8),
            _CryptoSubChip(
                label: AppLocalizations.of(context)!.marketTopLosers,
                selected: _cryptoSubTab == 2,
                onTap: () {
                  if (_cryptoSubTab == 2) return;
                  setState(() => _cryptoSubTab = 2);
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scheduleCryptoRealtimeResubscribe(force: true));
                }),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(key: _cryptoRowsAnchorKey),
        ...sorted.toList().asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          final q = item.$3;
          final tried = _attemptedSymbols.contains(item.$2);
          final notYetLoaded = q == null && !tried;
          return QuoteRow(
            symbol: item.$2,
            name: item.$1,
            price: q?.price ?? 0,
            change: q?.change ?? 0,
            changePercent: q?.changePercent ?? 0,
            hasError: q?.hasError ?? tried,
            isLoading: notYetLoaded,
            onTap: () {
              final symbolList = sorted.map((x) => x.$2).toList();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GenericChartPage(
                      symbol: item.$2,
                      name: item.$1,
                      symbolList: symbolList,
                      symbolIndex: i),
                ),
              );
            },
          );
        }),
        if (_loadingMoreCoins)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cryptoMockBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFFD4AF37)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.marketMockDataHint,
              style: const TextStyle(color: Color(0xFFE8D5A3), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CryptoSubChip extends StatelessWidget {
  const _CryptoSubChip(
      {required this.label, required this.selected, required this.onTap});
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
          border: Border.all(
              color: selected
                  ? const Color(0xFFD4AF37).withValues(alpha: 0.4)
                  : const Color(0xFF2C2D31)),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected
                    ? const Color(0xFFE8D5A3)
                    : const Color(0xFF9CA3AF),
                fontSize: 13)),
      ),
    );
  }
}
