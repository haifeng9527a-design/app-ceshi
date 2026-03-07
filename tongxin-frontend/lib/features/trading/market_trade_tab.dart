import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../market/chart/intraday_chart.dart';
import '../market/market_colors.dart';
import '../market/market_repository.dart';
import 'trading_api_client.dart';
import 'trading_models.dart';
import 'trading_ui.dart';
import 'twelve_data_realtime_client.dart';

/// 行情与交易 Tab：整体行情（Polygon）→ 搜索标的 → 行情区 → 买入/卖出
class MarketTradeTab extends StatefulWidget {
  const MarketTradeTab({
    super.key,
    required this.teacherId,
    this.isActive = false,
  });

  final String teacherId;
  final bool isActive;

  @override
  State<MarketTradeTab> createState() => _MarketTradeTabState();
}

class _MarketTradeTabState extends State<MarketTradeTab> {
  static const Color _accent = Color(0xFFD6B46A);
  static const Color _bg = Color(0xFF0F1722);
  static const Color _muted = Color(0x8CFFFFFF); // rgba(255,255,255,0.55)
  static const Color _surface = Color(0xFF0F1722);

  final _searchController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController();
  final _market = MarketRepository();

  String? _selectedSymbol;
  String? _selectedName;
  String? _selectedMarket;
  double? _currentPrice;
  double? _changePercent;
  int? _volume; // 实时累计成交量（WebSocket 推送累加）
  ProductType _selectedProductType = ProductType.spot;
  PositionSide _selectedPositionSide = PositionSide.long;
  MarginMode _selectedMarginMode = MarginMode.cross;
  double _selectedLeverage = 5;
  double _maxLeverage = 50;
  double _maintenanceMarginRate = 0.005;
  bool _allowShort = true;
  bool _loadingSearch = false;

  bool _orderTypeLimit = true;
  bool _placingOrder = false;
  TradingAccountSummary? _summary;
  final _tradingApi = TradingApiClient.instance;

  Timer? _refreshTimer;
  Timer? _chartRefreshTimer;
  List<ChartCandle> _candles = [];
  bool _chartKLine = false;
  DateTime? _lastUpdate;

  List<PolygonGainer> _gainers = [];
  bool _loadingGainers = false;

  /// 搜索引导：股票 / 外汇 / 加密货币
  int _searchCategoryIndex = 0;
  List<String> _searchCategories(BuildContext context) => [
    AppLocalizations.of(context)!.tradingStock,
    AppLocalizations.of(context)!.tradingForex,
    AppLocalizations.of(context)!.tradingCrypto,
  ];

  PolygonRealtime? _realtime;
  StreamSubscription<PolygonTradeUpdate>? _realtimeSub;
  final _twelveRealtime = TwelveDataRealtimeClient();
  StreamSubscription<TwelveDataRealtimeQuote>? _twelveRealtimeSub;

  String _selectedAssetClass() {
    if (MarketRepository.isCryptoMarket(_selectedMarket)) return 'crypto';
    if (MarketRepository.isForexMarket(_selectedMarket)) return 'forex';
    return 'stock';
  }

  bool get _isContractSelected => _selectedProductType != ProductType.spot;

  String _positionActionForButton(
    bool isBuy, {
    required ProductType productType,
    required PositionSide positionSide,
  }) {
    if (productType == ProductType.spot) {
      return isBuy ? 'open' : 'close';
    }
    if (positionSide == PositionSide.long) {
      return isBuy ? 'open' : 'close';
    }
    return isBuy ? 'close' : 'open';
  }

  String _tradeIntentLabel(bool isBuy) {
    if (!_isContractSelected) {
      return isBuy ? '现货买入' : '现货卖出';
    }
    if (_selectedPositionSide == PositionSide.long) {
      return isBuy ? '开多' : '平多';
    }
    return isBuy ? '平空' : '开空';
  }

  String _productTypeLabel(ProductType type) {
    switch (type) {
      case ProductType.spot:
        return '现货';
      case ProductType.perpetual:
        return '永续';
      case ProductType.future:
        return '期货';
    }
  }

  String _positionSideLabel(PositionSide side) {
    return side == PositionSide.short ? '做空' : '做多';
  }

  String _marginModeLabel(MarginMode mode) {
    return mode == MarginMode.isolated ? '逐仓' : '全仓';
  }

  @override
  void initState() {
    super.initState();
    _applyCachedDataThenLoad();
    _refreshTradingSummary();
    _loadTradingRuntimeConfig();
    _syncRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant MarketTradeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncRefreshTimer();
    }
  }

  void _syncRefreshTimer() {
    _refreshTimer?.cancel();
    if (!widget.isActive) return;
    var tick = 0;
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      tick++;
      _loadGainers();
      if (_selectedSymbol != null &&
          (_selectedMarket == null ||
              MarketRepository.isStockMarket(_selectedMarket))) {
        _refreshSelectedQuote();
      }
      if (tick % 2 == 0) {
        _refreshTradingSummary();
      }
    });
  }

  Future<void> _refreshTradingSummary() async {
    try {
      final s = await _tradingApi.getSummary();
      if (!mounted) return;
      setState(() => _summary = s);
    } catch (_) {}
  }

  Future<void> _loadTradingRuntimeConfig() async {
    try {
      final config = await _tradingApi.getRuntimeConfig();
      if (!mounted) return;
      setState(() {
        _selectedProductType = config.defaultProductType;
        _selectedMarginMode = config.defaultMarginMode;
        _selectedLeverage = config.defaultProductType == ProductType.spot
            ? 1
            : config.defaultLeverage.clamp(1, config.maxLeverage);
        _maxLeverage = config.maxLeverage;
        _maintenanceMarginRate = config.maintenanceMarginRate;
        _allowShort = config.allowShort;
        if (!_allowShort) {
          _selectedPositionSide = PositionSide.long;
        }
      });
    } catch (_) {}
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

  Future<void> _loadGainers() async {
    if (!_market.polygonAvailable) return;
    if (_loadingGainers) return;
    setState(() => _loadingGainers = true);
    try {
      final list = await _market.getTopGainers(limit: 10);
      if (mounted) {
        setState(() {
          _gainers = list;
          _loadingGainers = false;
          _lastUpdate = DateTime.now();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingGainers = false;
          _lastUpdate = DateTime.now();
        });
      }
    }
  }

  void _startRealtime(String symbol) {
    _realtimeSub?.cancel();
    _realtime?.dispose();
    _twelveRealtimeSub?.cancel();
    if (_selectedMarket != null &&
        !MarketRepository.isStockMarket(_selectedMarket)) {
      if (!_twelveRealtime.isAvailable) return;
      _twelveRealtimeSub = _twelveRealtime.stream.listen((update) {
        if (!mounted) return;
        if (update.symbol.trim().toUpperCase() != symbol.trim().toUpperCase()) {
          return;
        }
        setState(() {
          _currentPrice = update.price;
          if (update.percentChange != null) {
            _changePercent = update.percentChange;
          }
        });
      });
      _twelveRealtime.connect();
      _twelveRealtime.subscribeSymbols({symbol});
      return;
    }
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
    if (mounted) {
      setState(() {
        _currentPrice = quote.price;
        _changePercent = quote.changePercent;
      });
    }
  }

  bool _chartLoading = false;

  Future<void> _loadCandles() async {
    if (_selectedSymbol == null) return;
    setState(() => _chartLoading = true);
    final sym = _selectedSymbol!;
    List<ChartCandle> list = [];
    final now = DateTime.now();
    final isStock = MarketRepository.isStockMarket(_selectedMarket) ||
        SymbolResolver.isUsStock(sym);
    if (isStock && _market.polygonAvailable) {
      final toMs = now.millisecondsSinceEpoch;
      if (_chartKLine) {
        final fromMs = toMs - 30 * 24 * 3600 * 1000;
        list = await _market.getAggregates(
          sym,
          multiplier: 1,
          timespan: 'day',
          fromMs: fromMs,
          toMs: toMs,
        );
      } else {
        final fromMs = toMs - 24 * 3600 * 1000;
        list = await _market.getAggregates(
          sym,
          multiplier: 1,
          timespan: 'minute',
          fromMs: fromMs,
          toMs: toMs,
        );
      }
    } else {
      list = await _market.getCandles(
        sym,
        _chartKLine ? '1day' : '1min',
        lastDays: _chartKLine ? null : 1,
      );
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
    _realtimeSub?.cancel();
    _realtime?.dispose();
    _twelveRealtimeSub?.cancel();
    _twelveRealtime.dispose();
    _searchController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _onSearch() async {
    final text = _searchController.text.trim();
    if (text.isEmpty) return;
    final symbol = text.toUpperCase();
    setState(() {
      _selectedName = text;
      _loadingSearch = true;
    });
    List<MarketSearchResult> candidates;
    if (_searchCategoryIndex == 0) {
      candidates = await _market.searchStocks(text);
    } else if (_searchCategoryIndex == 1) {
      candidates = await _market.searchForexPairs(text);
    } else {
      candidates = await _market.searchCryptoPairs(text);
    }
    MarketSearchResult? match;
    final exact = candidates.where((item) =>
        item.symbol.trim().toUpperCase() == symbol ||
        item.name.trim().toLowerCase() == text.toLowerCase());
    if (exact.isNotEmpty) {
      match = exact.first;
    } else if (candidates.isNotEmpty) {
      match = candidates.first;
    }
    if (match == null) {
      if (!mounted) return;
      setState(() {
        _loadingSearch = false;
      });
      return;
    }
    final resolvedSymbol = match.symbol.trim();
    double? price;
    double? percentChange;
    final quote = await _market.getQuote(resolvedSymbol);
    if (!quote.hasError) {
      price = quote.price > 0 ? quote.price : null;
      percentChange = quote.changePercent;
    }
    if (mounted) {
      setState(() {
        _selectedSymbol = resolvedSymbol;
        _loadingSearch = false;
        _selectedMarket = match!.market;
        _selectedName = match.name;
        _currentPrice = price ?? (!_market.polygonAvailable ? 100.0 : null);
        _changePercent = percentChange;
        _volume = 0;
        if (_currentPrice != null) _priceController.text = _currentPrice!.toStringAsFixed(2);
        _candles = [];
        _chartLoading = true;
      });
      _startRealtime(resolvedSymbol);
      _loadCandles();
    }
  }

  Future<void> _openOrderSheet(bool isBuy) async {
    if (_selectedSymbol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.tradingSearchAndSelectFirst)),
      );
      return;
    }
    try {
      final latest = await _market.getQuote(_selectedSymbol!, realtime: true);
      if (!latest.hasError && latest.price > 0 && mounted) {
        setState(() {
          _currentPrice = latest.price;
          _changePercent = latest.changePercent;
        });
      }
    } catch (_) {}
    try {
      final latestSummary = await _tradingApi.getSummary();
      if (mounted) {
        setState(() => _summary = latestSummary);
      }
    } catch (_) {}
    if (!mounted) return;
    _priceController.text = (_currentPrice ?? 0).toStringAsFixed(2);
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
          intentLabel: _tradeIntentLabel(isBuy),
          defaultPrice: _currentPrice ?? 0,
          orderTypeLimit: _orderTypeLimit,
          productType: _selectedProductType,
          positionSide: _selectedPositionSide,
          marginMode: _selectedMarginMode,
          leverage: _selectedLeverage,
          maxLeverage: _maxLeverage,
          allowShort: _allowShort,
          availableFunds: _summary?.cashAvailable,
          productTypeLabel: _productTypeLabel,
          positionSideLabel: _positionSideLabel,
          marginModeLabel: _marginModeLabel,
          priceController: _priceController,
          qtyController: _qtyController,
          onOrderTypeChanged: (limit) => setState(() => _orderTypeLimit = limit),
          onSubmit: (orderTypeLimit, productType, positionSide, marginMode, leverage) async {
            if (_placingOrder) return;
            setState(() {
              _selectedProductType = productType;
              _selectedPositionSide = positionSide;
              _selectedMarginMode = marginMode;
              _selectedLeverage = leverage;
            });
            try {
              final latest = await _market.getQuote(_selectedSymbol!, realtime: true);
              if (!latest.hasError && latest.price > 0 && mounted) {
                setState(() {
                  _currentPrice = latest.price;
                  _changePercent = latest.changePercent;
                });
                if (!orderTypeLimit) {
                  _priceController.text = latest.price.toStringAsFixed(2);
                }
              }
            } catch (_) {}
            final qty = double.tryParse(_qtyController.text.trim());
            final limitPrice = double.tryParse(_priceController.text.trim());
            if (qty == null || qty <= 0) return;
            if (orderTypeLimit && (limitPrice == null || limitPrice <= 0)) return;
            setState(() {
              _placingOrder = true;
              _orderTypeLimit = orderTypeLimit;
            });
            try {
              await _tradingApi.placeOrder(
                symbol: _selectedSymbol!,
                side: isBuy ? OrderSide.buy : OrderSide.sell,
                type: orderTypeLimit ? OrderType.limit : OrderType.market,
                quantity: qty,
                limitPrice: orderTypeLimit ? limitPrice : null,
                assetClass: _selectedAssetClass(),
                productType: productType,
                positionSide: positionSide,
                positionAction: _positionActionForButton(
                  isBuy,
                  productType: productType,
                  positionSide: positionSide,
                ),
                marginMode: marginMode,
                leverage: leverage,
              );
              if (!mounted || !ctx.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已经委托')),
              );
              _refreshTradingSummary();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$e'),
                  backgroundColor: Colors.red.shade700,
                ),
              );
            } finally {
              if (mounted) setState(() => _placingOrder = false);
            }
          },
          onCancel: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TradingPageScaffold(
      child: RefreshIndicator(
        onRefresh: _loadGainers,
        color: _accent,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          children: [
            _buildSearchSection(),
            const SizedBox(height: 12),
            _buildGainersStrip(),
            const SizedBox(height: 14),
            _buildAccountSummaryCard(),
            const SizedBox(height: 12),
            if (_selectedSymbol != null) _buildSelectedSymbolCard() else _buildPlaceholderCard(),
            const SizedBox(height: 12),
            _buildTradeModeCard(),
            const SizedBox(height: 12),
            _buildBuySellButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSummaryCard() {
    return TradingSummaryStrip(
      summary: _summary,
      loading: false,
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
            Text('${AppLocalizations.of(context)!.tradingVolume} $_volume', style: TextStyle(color: _muted, fontSize: 11)),
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
              AppLocalizations.of(context)!.tradingSelectGainersOrSearch,
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)!.tradingViewRealtimeQuote,
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
            Text(AppLocalizations.of(context)!.tradingGainersList, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            if (hasApi && _loadingGainers)
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
            else if (_lastUpdate != null)
              Text(AppLocalizations.of(context)!.tradingUpdateTimeValue(_formatTime(_lastUpdate!)), style: TextStyle(color: _muted, fontSize: 10)),
          ],
        ),
        if (!hasApi)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(AppLocalizations.of(context)!.tradingConfigurePolygonApiKey, style: TextStyle(fontSize: 11, color: _muted)),
          )
        else if (_gainers.isEmpty && !_loadingGainers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Text(AppLocalizations.of(context)!.tradingNoData, style: TextStyle(color: _muted, fontSize: 12))),
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
                          _selectedMarket = 'stocks';
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
    final l10n = AppLocalizations.of(context)!;
    final hintByCategory = [
      l10n.tradingStockCodeOrName,
      l10n.tradingForexCodeExample,
      l10n.tradingCryptoExample,
    ];
    final categories = _searchCategories(context);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(categories.length, (i) {
              final selected = _searchCategoryIndex == i;
              return Padding(
                padding: EdgeInsets.only(right: i < categories.length - 1 ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _searchCategoryIndex = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? _accent.withValues(alpha: 0.25) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? _accent : _muted.withValues(alpha: 0.3),
                        width: selected ? 1.5 : 0.5,
                      ),
                    ),
                    child: Text(
                      categories[i],
                      style: TextStyle(
                        color: selected ? _accent : _muted,
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: hintByCategory[_searchCategoryIndex],
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
                        : Text(AppLocalizations.of(context)!.commonSearch, style: const TextStyle(
                            color: Color(0xFF111215),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          )),
                  ),
                ),
              ),
            ],
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
                segments: [
                  ButtonSegment(value: false, label: Text(AppLocalizations.of(context)!.tradingIntraday, style: const TextStyle(fontSize: 11))),
                  ButtonSegment(value: true, label: Text(AppLocalizations.of(context)!.tradingKline, style: const TextStyle(fontSize: 11))),
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
                      AppLocalizations.of(context)!.commonLoading,
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  )
                : _candles.isEmpty
                    ? Center(
                        child: Text(
                          AppLocalizations.of(context)!.tradingNoChartData,
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
    final prevClose = (_currentPrice != null &&
            _changePercent != null &&
            (1 + _changePercent! / 100) != 0)
        ? (_currentPrice! / (1 + _changePercent! / 100))
        : null;
    return IntradayChart(
      candles: _candles,
      prevClose: prevClose,
      currentPrice: _currentPrice,
      chartHeight: 160,
      timeAxisHeight: 22,
      volumeHeight: 36,
      periodLabel: '1m',
      useSessionMarketHours:
          _selectedSymbol != null && SymbolResolver.isUsStock(_selectedSymbol!),
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

  Widget _buildTradeModeCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 16, color: _accent),
              const SizedBox(width: 6),
              const Text(
                '交易模式',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                _isContractSelected
                    ? '${_productTypeLabel(_selectedProductType)} / ${_positionSideLabel(_selectedPositionSide)} / ${_selectedLeverage.toStringAsFixed(0)}x'
                    : '现货 / 做多 / 1x',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isContractSelected)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '当前维持保证金率 ${(100 * _maintenanceMarginRate).toStringAsFixed(2)}%',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          SegmentedButton<ProductType>(
            segments: const [
              ButtonSegment(value: ProductType.spot, label: Text('现货')),
              ButtonSegment(value: ProductType.perpetual, label: Text('永续')),
              ButtonSegment(value: ProductType.future, label: Text('期货')),
            ],
            selected: {_selectedProductType},
            onSelectionChanged: (selection) {
              final next = selection.first;
              setState(() {
                _selectedProductType = next;
                if (next == ProductType.spot) {
                  _selectedPositionSide = PositionSide.long;
                  _selectedMarginMode = MarginMode.cross;
                  _selectedLeverage = 1;
                } else if (_selectedLeverage < 1) {
                  _selectedLeverage = 5;
                } else if (_selectedLeverage == 1) {
                  _selectedLeverage = 5;
                }
              });
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ),
          if (_isContractSelected) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<PositionSide>(
                    initialValue: _selectedPositionSide,
                    decoration: const InputDecoration(
                      labelText: '持仓方向',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: PositionSide.long,
                        child: Text('做多'),
                      ),
                      if (_allowShort)
                        const DropdownMenuItem(
                          value: PositionSide.short,
                          child: Text('做空'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedPositionSide = value);
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<MarginMode>(
                    initialValue: _selectedMarginMode,
                    decoration: const InputDecoration(
                      labelText: '保证金模式',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: MarginMode.cross,
                        child: Text('全仓'),
                      ),
                      DropdownMenuItem(
                        value: MarginMode.isolated,
                        child: Text('逐仓'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedMarginMode = value);
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '杠杆 ${_selectedLeverage.toStringAsFixed(0)}x / 上限 ${_maxLeverage.toStringAsFixed(0)}x',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                      Slider(
                        value: _selectedLeverage.clamp(1, _maxLeverage),
                        min: 1,
                        max: _maxLeverage,
                        divisions: (_maxLeverage - 1).round().clamp(1, 99),
                        label: '${_selectedLeverage.toStringAsFixed(0)}x',
                        onChanged: (value) {
                          setState(() => _selectedLeverage = value.roundToDouble());
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBuySellButtons() {
    final enabled = _selectedSymbol != null && !_placingOrder;
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
                      AppLocalizations.of(context)!.tradingBuy,
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
                      AppLocalizations.of(context)!.tradingSell,
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
    required this.intentLabel,
    required this.defaultPrice,
    required this.orderTypeLimit,
    required this.productType,
    required this.positionSide,
    required this.marginMode,
    required this.leverage,
    required this.maxLeverage,
    required this.allowShort,
    required this.availableFunds,
    required this.productTypeLabel,
    required this.positionSideLabel,
    required this.marginModeLabel,
    required this.priceController,
    required this.qtyController,
    required this.onOrderTypeChanged,
    required this.onSubmit,
    required this.onCancel,
  });

  final String symbol;
  final String? symbolName;
  final bool isBuy;
  final String intentLabel;
  final double defaultPrice;
  final bool orderTypeLimit;
  final ProductType productType;
  final PositionSide positionSide;
  final MarginMode marginMode;
  final double leverage;
  final double maxLeverage;
  final bool allowShort;
  final double? availableFunds;
  final String Function(ProductType type) productTypeLabel;
  final String Function(PositionSide side) positionSideLabel;
  final String Function(MarginMode mode) marginModeLabel;
  final TextEditingController priceController;
  final TextEditingController qtyController;
  final ValueChanged<bool> onOrderTypeChanged;
  final Future<void> Function(
    bool orderTypeLimit,
    ProductType productType,
    PositionSide positionSide,
    MarginMode marginMode,
    double leverage,
  ) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  static const Color _bg = Color(0xFF111215);

  bool _isSubmitting = false;
  late bool _orderTypeLimit;
  late ProductType _productType;
  late PositionSide _positionSide;
  late MarginMode _marginMode;
  late double _leverage;

  @override
  void initState() {
    super.initState();
    _orderTypeLimit = widget.orderTypeLimit;
    _productType = widget.productType;
    _positionSide = widget.positionSide;
    _marginMode = widget.marginMode;
    _leverage = widget.leverage;
  }

  @override
  Widget build(BuildContext context) {
    final estimatedFunds = _estimatedRequiredFunds();
    final availableFunds = widget.availableFunds;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.intentLabel} ${widget.symbol}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _miniChip(widget.productTypeLabel(_productType)),
                _miniChip(widget.positionSideLabel(_positionSide)),
                _miniChip(_productType == ProductType.spot ? '全仓' : widget.marginModeLabel(_marginMode)),
                _miniChip('${_productType == ProductType.spot ? 1 : _leverage.toStringAsFixed(0)}x'),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<ProductType>(
              segments: const [
                ButtonSegment(value: ProductType.spot, label: Text('现货')),
                ButtonSegment(value: ProductType.perpetual, label: Text('永续')),
                ButtonSegment(value: ProductType.future, label: Text('期货')),
              ],
              selected: {_productType},
              onSelectionChanged: (s) {
                final next = s.first;
                setState(() {
                  _productType = next;
                  if (next == ProductType.spot) {
                    _positionSide = PositionSide.long;
                    _marginMode = MarginMode.cross;
                    _leverage = 1;
                  } else if (_leverage <= 1) {
                    _leverage = 5;
                  }
                });
              },
            ),
            if (_productType != ProductType.spot) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<PositionSide>(
                      initialValue: _positionSide,
                      decoration: InputDecoration(
                        labelText: '方向',
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(value: PositionSide.long, child: Text('做多')),
                        if (widget.allowShort)
                          const DropdownMenuItem(value: PositionSide.short, child: Text('做空')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _positionSide = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<MarginMode>(
                      initialValue: _marginMode,
                      decoration: InputDecoration(
                        labelText: '保证金',
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: MarginMode.cross, child: Text('全仓')),
                        DropdownMenuItem(value: MarginMode.isolated, child: Text('逐仓')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _marginMode = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '杠杆 ${_leverage.toStringAsFixed(0)}x / 上限 ${widget.maxLeverage.toStringAsFixed(0)}x',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _leverage.clamp(1, widget.maxLeverage),
                min: 1,
                max: widget.maxLeverage,
                divisions: (widget.maxLeverage - 1).round().clamp(1, 99),
                label: '${_leverage.toStringAsFixed(0)}x',
                onChanged: (value) {
                  setState(() => _leverage = value.roundToDouble());
                },
              ),
            ],
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(AppLocalizations.of(context)!.tradingLimitOrder)),
                ButtonSegment(value: false, label: Text(AppLocalizations.of(context)!.tradingMarketOrder)),
              ],
              selected: {_orderTypeLimit},
              onSelectionChanged: (s) {
                setState(() => _orderTypeLimit = s.first);
                widget.onOrderTypeChanged(s.first);
              },
            ),
            const SizedBox(height: 16),
            if (_orderTypeLimit)
              TextField(
                controller: widget.priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.tradingPriceLabel,
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
                labelText: AppLocalizations.of(context)!.tradingQuantityLabel,
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            if (availableFunds != null || estimatedFunds != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _kvText(
                        '可用资金',
                        availableFunds != null
                            ? availableFunds.toStringAsFixed(2)
                            : '--',
                      ),
                    ),
                    Expanded(
                      child: _kvText(
                        _requiresFunds()
                            ? (_productType == ProductType.spot ? '预计占用' : '预计保证金')
                            : '预计占用',
                        estimatedFunds != null
                            ? estimatedFunds.toStringAsFixed(2)
                            : (_requiresFunds() ? '--' : '0.00'),
                        valueColor: estimatedFunds != null &&
                                availableFunds != null &&
                                estimatedFunds > availableFunds
                            ? Colors.redAccent
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    child: Text(AppLocalizations.of(context)!.commonCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _isSubmitting
                        ? null
                        : () async {
                            if (_isSubmitting) return;
                            final qtyStr = widget.qtyController.text.trim();
                            final qty = double.tryParse(qtyStr);
                            if (qty == null || qty <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(AppLocalizations.of(context)!.tradingEnterValidQuantity)),
                              );
                              return;
                            }
                            if (_orderTypeLimit) {
                              final priceStr = widget.priceController.text.trim();
                              final price = double.tryParse(priceStr);
                              if (price == null || price <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(AppLocalizations.of(context)!.tradingEnterValidPriceForLimit)),
                                );
                                return;
                              }
                            }
                            final estimatedFunds = _estimatedRequiredFunds();
                            final availableFunds = widget.availableFunds;
                            if (_requiresFunds() &&
                                estimatedFunds != null &&
                                availableFunds != null &&
                                estimatedFunds > availableFunds) {
                              final label = _productType == ProductType.spot ? '可用资金不足，无法委托' : '可用保证金不足，无法委托';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$label（需要 ${estimatedFunds.toStringAsFixed(2)}，当前 ${availableFunds.toStringAsFixed(2)}）')),
                              );
                              return;
                            }
                            setState(() => _isSubmitting = true);
                            widget.onOrderTypeChanged(_orderTypeLimit);
                            try {
                              await widget.onSubmit(
                                _orderTypeLimit,
                                _productType,
                                _positionSide,
                                _productType == ProductType.spot ? MarginMode.cross : _marginMode,
                                _productType == ProductType.spot ? 1 : _leverage,
                              );
                            } finally {
                              if (mounted) setState(() => _isSubmitting = false);
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.isBuy ? Colors.green : Colors.red,
                    ),
                    child: Text(
                      _isSubmitting
                          ? '提交中...'
                          : (widget.isBuy ? AppLocalizations.of(context)!.tradingConfirmBuy : AppLocalizations.of(context)!.tradingConfirmSell),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _requiresFunds() {
    if (_productType == ProductType.spot) {
      return widget.isBuy;
    }
    if (_positionSide == PositionSide.long) {
      return widget.isBuy;
    }
    return !widget.isBuy;
  }

  double? _estimatedRequiredFunds() {
    if (!_requiresFunds()) return 0;
    final qty = double.tryParse(widget.qtyController.text.trim());
    final price = double.tryParse(widget.priceController.text.trim()) ?? widget.defaultPrice;
    if (qty == null || qty <= 0 || price <= 0) return null;
    if (_productType == ProductType.spot) {
      return qty * price;
    }
    final leverage = _leverage <= 0 ? 1 : _leverage;
    return qty * price / leverage;
  }

  Widget _kvText(String label, String value, {Color valueColor = Colors.white}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _miniChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w600,
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
      ..color = const Color(0x14FFFFFF) // rgba(255,255,255,0.08)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
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
