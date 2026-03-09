import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/chat_web_socket_service.dart';
import '../../l10n/app_localizations.dart';
import '../market/chart/intraday_chart.dart';
import '../market/market_colors.dart';
import '../market/market_repository.dart';
import 'trading_api_client.dart';
import 'trading_models.dart';
import 'trading_ui.dart';

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
  final _searchFocusNode = FocusNode();
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

  /// 搜索引导：股票 / 外汇 / 加密货币
  int _searchCategoryIndex = 0;
  static const List<String> _mainstreamCryptoSymbols = <String>[
    'BTC/USD',
    'ETH/USD',
    'SOL/USD',
    'BNB/USD',
    'XRP/USD',
    'DOGE/USD',
    'ADA/USD',
    'TRX/USD',
    'LTC/USD',
  ];
  static const List<String> _mainstreamForexPairs = <String>[
    'EUR/USD',
    'USD/JPY',
    'GBP/USD',
    'AUD/USD',
    'USD/CHF',
    'USD/CAD',
    'NZD/USD',
  ];
  List<String> _searchCategories(BuildContext context) => [
        AppLocalizations.of(context)!.tradingStock,
        AppLocalizations.of(context)!.tradingForex,
        AppLocalizations.of(context)!.tradingCrypto,
      ];

  StreamSubscription<dynamic>? _realtimeSub;

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
      final s = await _tradingApi.getSummary(
        accountType: _selectedProductType.tradingAccountType,
      );
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
      _refreshTradingSummary();
    } catch (_) {}
  }

  void _startRealtime(String symbol) {
    _realtimeSub?.cancel();
    if (!ChatWebSocketService.instance.isConnected) return;
    final symUpper = symbol.trim().toUpperCase();
    ChatWebSocketService.instance.subscribeMarket([symbol]);
    _realtimeSub = ChatWebSocketService.instance.marketQuoteStream.listen((u) {
      if (!mounted || u.symbol.trim().toUpperCase() != symUpper) return;
      setState(() {
        _currentPrice = u.price;
        if (u.percentChange != null) _changePercent = u.percentChange;
        _volume = (_volume ?? 0) + u.size;
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

  /// 美股目标交易日：盘中/收盘后=当天，开盘前=前一交易日
  static DateTime _usTargetTradingDay() {
    final utc = DateTime.now().toUtc();
    final isEDT = _isUsEasternDST(utc);
    final offsetHours = isEDT ? 4 : 5;
    final et = utc.subtract(Duration(hours: offsetHours));
    final hour = et.hour;
    final minute = et.minute;
    final beforeOpen = hour < 9 || (hour == 9 && minute < 30);
    if (beforeOpen) {
      if (et.weekday == DateTime.monday) {
        return DateTime.utc(et.year, et.month, et.day - 3);
      }
      if (et.weekday == DateTime.sunday) {
        return DateTime.utc(et.year, et.month, et.day - 2);
      }
      if (et.weekday == DateTime.saturday) {
        return DateTime.utc(et.year, et.month, et.day - 1);
      }
      return DateTime.utc(et.year, et.month, et.day - 1);
    }
    return DateTime.utc(et.year, et.month, et.day);
  }

  static bool _isUsEasternDST(DateTime utc) {
    final y = utc.year;
    final marchSecondSun = _nthSundayOfMonth(y, 3, 2);
    final novFirstSun = _nthSundayOfMonth(y, 11, 1);
    final at = DateTime.utc(y, utc.month, utc.day);
    return !at.isBefore(marchSecondSun) && at.isBefore(novFirstSun);
  }

  static DateTime _nthSundayOfMonth(int year, int month, int n) {
    var d = DateTime.utc(year, month, 1);
    var count = 0;
    while (d.month == month) {
      if (d.weekday == DateTime.sunday) {
        count++;
        if (count == n) return d;
      }
      d = d.add(const Duration(days: 1));
    }
    return DateTime.utc(year, month, 1);
  }

  /// 美股 9:30-16:00 ET 转为 UTC 毫秒（EST: 14:30-21:00 UTC, EDT: 13:30-20:00 UTC）
  static (int fromMs, int toMs) _usSessionBoundsMs(DateTime targetDayUtc) {
    final isEDT = _isUsEasternDST(targetDayUtc);
    final startHour = isEDT ? 13 : 14;
    final endHour = isEDT ? 20 : 21;
    final fromMs = DateTime.utc(
      targetDayUtc.year, targetDayUtc.month, targetDayUtc.day,
      startHour, 30,
    ).millisecondsSinceEpoch;
    final toMs = DateTime.utc(
      targetDayUtc.year, targetDayUtc.month, targetDayUtc.day,
      endHour, 0,
    ).millisecondsSinceEpoch;
    return (fromMs, toMs);
  }

  /// 过滤 K 线到会话时间范围内
  static List<ChartCandle> _filterCandlesToSession(List<ChartCandle> list, int fromMs, int toMs) {
    final startSec = fromMs / 1000.0;
    final endSec = toMs / 1000.0;
    return list.where((c) => c.time >= startSec && c.time <= endSec).toList();
  }

  /// 过滤到「当天」：取最近 24h 内（加密/外汇无交易日概念）
  static List<ChartCandle> _filterCandlesToToday(List<ChartCandle> list) {
    if (list.isEmpty) return list;
    final nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
    const daySec = 24 * 3600.0;
    final cutoff = nowSec - daySec;
    return list.where((c) => c.time >= cutoff).toList();
  }

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
        final targetDay = _usTargetTradingDay();
        final (fromMs, toMs) = _usSessionBoundsMs(targetDay);
        list = await _market.getAggregates(
          sym,
          multiplier: 1,
          timespan: 'minute',
          fromMs: fromMs,
          toMs: toMs,
        );
        list = _filterCandlesToSession(list, fromMs, toMs);
        // 收盘时兜底：拉近 5 日数据，过滤到上一交易日会话（覆盖周末）
        if (list.isEmpty && _market.useBackend) {
          list = await _market.getCandles(sym, '1min', lastDays: 5);
          if (list.isNotEmpty) {
            list = _filterCandlesToSession(list, fromMs, toMs);
          }
        }
        if (list.isEmpty && _market.useBackend) {
          list = await _market.getCandles(sym, '5min', lastDays: 5);
          if (list.isNotEmpty) {
            list = _filterCandlesToSession(list, fromMs, toMs);
          }
        }
      }
    } else {
      list = await _market.getCandles(
        sym,
        _chartKLine ? '1day' : '1min',
        lastDays: _chartKLine ? null : 1,
      );
      if (!_chartKLine && list.isNotEmpty) {
        list = _filterCandlesToToday(list);
      }
      if (!_chartKLine && list.isEmpty) {
        list = await _market.getCandles(sym, '5min', lastDays: 1);
        if (list.isNotEmpty) list = _filterCandlesToToday(list);
      }
      if (!_chartKLine && list.isEmpty) {
        list = await _market.getCandles(sym, '15min', lastDays: 1);
        if (list.isNotEmpty) list = _filterCandlesToToday(list);
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
    final dur =
        _chartKLine ? const Duration(minutes: 5) : const Duration(minutes: 1);
    _chartRefreshTimer = Timer(dur, () {
      if (mounted && _selectedSymbol != null) _loadCandles();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _chartRefreshTimer?.cancel();
    _realtimeSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _onSearch() async {
    final text = _searchController.text.trim();
    if (text.isEmpty) return;
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
    final ranked = _rankSearchResults(
      query: text,
      categoryIndex: _searchCategoryIndex,
      candidates: candidates,
    );
    if (ranked.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loadingSearch = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到匹配标的')),
      );
      return;
    }
    MarketSearchResult? picked;
    if (ranked.length == 1) {
      picked = ranked.first;
    } else {
      picked = await _showSearchResultPicker(text, ranked.take(30).toList());
    }
    if (picked == null) {
      if (!mounted) return;
      setState(() => _loadingSearch = false);
      return;
    }
    final resolvedSymbol = picked.symbol.trim();
    double? price;
    double? percentChange;
    final quote = await _market.getQuote(resolvedSymbol);
    if (!quote.hasError) {
      price = quote.price > 0 ? quote.price : null;
      percentChange = quote.changePercent;
    }
    if (mounted) {
      _searchFocusNode.unfocus();
      FocusScope.of(context).unfocus();
      setState(() {
        _selectedSymbol = resolvedSymbol;
        _loadingSearch = false;
        _selectedMarket = picked!.market;
        _selectedName = picked.name;
        _currentPrice = price ?? (!_market.polygonAvailable ? 100.0 : null);
        _changePercent = percentChange;
        _volume = 0;
        if (_currentPrice != null) {
          _priceController.text = _currentPrice!.toStringAsFixed(2);
        }
        _candles = [];
        _chartLoading = true;
      });
      _startRealtime(resolvedSymbol);
      _loadCandles();
    }
  }

  String _normalizeSymbolKey(String input) {
    return input.trim().toUpperCase().replaceAll('-', '/').replaceAll('_', '/');
  }

  List<MarketSearchResult> _rankSearchResults({
    required String query,
    required int categoryIndex,
    required List<MarketSearchResult> candidates,
  }) {
    final q = query.trim().toUpperCase();
    final mainstreamMap = <String, int>{
      for (var i = 0; i < _mainstreamCryptoSymbols.length; i += 1)
        _mainstreamCryptoSymbols[i]: i,
    };
    final forexMainstreamMap = <String, int>{
      for (var i = 0; i < _mainstreamForexPairs.length; i += 1)
        _mainstreamForexPairs[i]: i,
    };

    final dedup = <String, MarketSearchResult>{};
    for (final c in candidates) {
      final key = _normalizeSymbolKey(c.symbol);
      dedup.putIfAbsent(key, () => c);
    }
    final list = dedup.values.toList(growable: false);

    int score(MarketSearchResult item) {
      final symbol = _normalizeSymbolKey(item.symbol);
      final name = item.name.trim().toUpperCase();
      var s = 1000;
      if (symbol == q || name == q) {
        s -= 800;
      } else if (symbol.startsWith(q)) {
        s -= 500;
      } else if (symbol.contains('/$q') || symbol.contains(q)) {
        s -= 260;
      } else if (name.startsWith(q)) {
        s -= 220;
      } else if (name.contains(q)) {
        s -= 120;
      }

      if (categoryIndex == 2) {
        final idx = mainstreamMap[symbol];
        if (idx != null) {
          s -= (300 - idx);
        }
        if (symbol.startsWith('0X') || symbol.contains('0X')) {
          s += 260;
        }
      } else if (categoryIndex == 1) {
        final idx = forexMainstreamMap[symbol];
        if (idx != null) {
          s -= (240 - idx);
        }
      }
      return s;
    }

    list.sort((a, b) {
      final sa = score(a);
      final sb = score(b);
      if (sa != sb) return sa.compareTo(sb);
      return _normalizeSymbolKey(a.symbol)
          .compareTo(_normalizeSymbolKey(b.symbol));
    });
    return list;
  }

  Future<MarketSearchResult?> _showSearchResultPicker(
    String query,
    List<MarketSearchResult> candidates,
  ) async {
    if (!mounted) return null;
    return showModalBottomSheet<MarketSearchResult>(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: _accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '选择标的（"$query"）',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0x22FFFFFF)),
                Expanded(
                  child: ListView.separated(
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: Color(0x18FFFFFF),
                    ),
                    itemBuilder: (c, i) {
                      final item = candidates[i];
                      final market = (item.market ?? '').toLowerCase();
                      final marketLabel = market == 'crypto'
                          ? '加密'
                          : market == 'forex'
                              ? '外汇'
                              : '股票';
                      return ListTile(
                        onTap: () => Navigator.of(ctx).pop(item),
                        title: Text(
                          item.symbol,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          item.name,
                          style: const TextStyle(
                            color: Color(0xB3FFFFFF),
                            fontSize: 12,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _accent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            marketLabel,
                            style: const TextStyle(
                              color: _accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
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
        );
      },
    );
  }

  Future<void> _openOrderSheet(bool isBuy) async {
    if (_selectedSymbol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context)!.tradingSearchAndSelectFirst)),
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
      final latestSummary = await _tradingApi.getSummary(
        accountType: _selectedProductType.tradingAccountType,
      );
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
      builder: (ctx) => _OrderSheet(
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
        onSubmit: (orderTypeLimit, productType, positionSide, marginMode,
            leverage) async {
          if (_placingOrder) return;
          setState(() {
            _selectedProductType = productType;
            _selectedPositionSide = positionSide;
            _selectedMarginMode = marginMode;
            _selectedLeverage = leverage;
          });
          _refreshTradingSummary();
          try {
            final latest =
                await _market.getQuote(_selectedSymbol!, realtime: true);
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return TradingPageScaffold(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: RefreshIndicator(
          onRefresh: () async {
            _refreshTradingSummary();
            if (_selectedSymbol != null) await _refreshSelectedQuote();
          },
          color: _accent,
          child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          children: [
            _buildSearchSection(),
            const SizedBox(height: 12),
            _buildAccountSummaryCard(),
            const SizedBox(height: 12),
            if (_selectedSymbol != null)
              _buildSelectedSymbolCard()
            else
              _buildPlaceholderCard(),
            const SizedBox(height: 12),
            _buildTradeModeCard(),
            const SizedBox(height: 12),
            _buildBuySellButtons(),
          ],
        ),
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
              if (_selectedName != null &&
                  _selectedName != _selectedSymbol) ...[
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
                _currentPrice != null
                    ? _currentPrice!.toStringAsFixed(2)
                    : '--',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 28,
                ),
              ),
              const SizedBox(width: 12),
              if (_changePercent != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_changePercent! >= 0 ? Colors.green : Colors.red)
                        .withValues(alpha: 0.2),
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
            Text('${AppLocalizations.of(context)!.tradingVolume} $_volume',
                style: TextStyle(color: _muted, fontSize: 11)),
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
            Icon(Icons.touch_app_rounded,
                color: _muted.withValues(alpha: 0.6), size: 40),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.tradingSearchAndSelectFirst,
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)!.tradingViewRealtimeQuote,
              style:
                  TextStyle(color: _muted.withValues(alpha: 0.8), fontSize: 12),
            ),
          ],
        ),
      ),
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
                padding:
                    EdgeInsets.only(right: i < categories.length - 1 ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _searchCategoryIndex = i),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? _accent.withValues(alpha: 0.25)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            selected ? _accent : _muted.withValues(alpha: 0.3),
                        width: selected ? 1.5 : 0.5,
                      ),
                    ),
                    child: Text(
                      categories[i],
                      style: TextStyle(
                        color: selected ? _accent : _muted,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
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
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: hintByCategory[_searchCategoryIndex],
                    hintStyle: TextStyle(color: _muted, fontSize: 12),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: _muted, size: 18),
                    filled: true,
                    fillColor: _bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    alignment: Alignment.center,
                    child: _loadingSearch
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _bg),
                          )
                        : Text(AppLocalizations.of(context)!.commonSearch,
                            style: const TextStyle(
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
    const chartHeight = 162.0;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _chartTabChip(
                label: AppLocalizations.of(context)!.tradingIntraday,
                selected: !_chartKLine,
                onTap: () {
                  if (_chartKLine) {
                    setState(() => _chartKLine = false);
                    _loadCandles();
                  }
                },
              ),
              _chartTabChip(
                label: AppLocalizations.of(context)!.tradingKline,
                selected: _chartKLine,
                onTap: () {
                  if (!_chartKLine) {
                    setState(() => _chartKLine = true);
                    _loadCandles();
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: chartHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: _chartLoading
              ? Center(
                  child: Text(
                    AppLocalizations.of(context)!.commonLoading,
                    style: TextStyle(color: _muted, fontSize: 13),
                  ),
                )
              : _candles.isEmpty
                  ? Center(
                      child: Text(
                        AppLocalizations.of(context)!.tradingNoChartData,
                        style: TextStyle(color: _muted, fontSize: 13),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: content,
    );
  }

  Widget _chartTabChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _accent : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? _accent : _muted,
          ),
        ),
      ),
    );
  }

  /// 分时：折线图（收盘价连线 + 下方填充），末端接实时价随 WebSocket 跳动，Y 轴显示价格数字
  Widget _buildLineChart() {
    if (_candles.isEmpty && _currentPrice == null) {
      return const SizedBox.shrink();
    }
    final prevClose = (_currentPrice != null &&
            _changePercent != null &&
            (1 + _changePercent! / 100) != 0)
        ? (_currentPrice! / (1 + _changePercent! / 100))
        : null;
    const chartH = 112.0;
    const timeH = 22.0;
    const volH = 24.0;
    return IntradayChart(
      candles: _candles,
      prevClose: prevClose,
      currentPrice: _currentPrice,
      chartHeight: chartH,
      timeAxisHeight: timeH,
      volumeHeight: volH,
      periodLabel: '1m',
      useSessionMarketHours:
          _selectedSymbol != null && SymbolResolver.isUsStock(_selectedSymbol!),
    );
  }

  /// K线：蜡烛图（仅显示最近 50 根）+ 右侧涨幅比例 + 底部时间轴
  static const int _klineDisplayLimit = 50;

  Widget _buildCandlestickChart() {
    if (_candles.isEmpty) return const SizedBox.shrink();
    final displayCandles = _candles.length > _klineDisplayLimit
        ? _candles.sublist(_candles.length - _klineDisplayLimit)
        : _candles;
    double minY = displayCandles.first.low;
    double maxY = displayCandles.first.high;
    for (final c in displayCandles) {
      if (c.low < minY) minY = c.low;
      if (c.high > maxY) maxY = c.high;
    }
    final range = (maxY - minY).clamp(0.01, double.infinity);
    minY = minY - range * 0.02;
    maxY = maxY + range * 0.02;
    final basePrice = displayCandles.first.open;
    const rightAxisW = 44.0;
    const timeAxisH = 20.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalH = constraints.maxHeight.isFinite ? constraints.maxHeight : 160.0;
        final chartH = (totalH - timeAxisH).clamp(80.0, double.infinity);
        final yTicks = List.generate(5, (i) => maxY - (maxY - minY) * i / 4);
        final timeLabels = _klineTimeLabels(displayCandles);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: chartH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CustomPaint(
                      size: Size(constraints.maxWidth - rightAxisW, chartH),
                      painter: _CandlestickPainter(
                        candles: displayCandles,
                        minY: minY,
                        maxY: maxY,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: rightAxisW,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: yTicks.map((v) {
                        final pct = basePrice > 0
                            ? ((v - basePrice) / basePrice * 100)
                            : 0.0;
                        return Text(
                          '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: const Color(0xB3FFFFFF),
                            fontSize: 10,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: timeAxisH,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: timeLabels.map((l) => Text(
                  l,
                  style: const TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 10,
                  ),
                )).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  static List<String> _klineTimeLabels(List<ChartCandle> candles) {
    if (candles.isEmpty) return [];
    final n = candles.length;
    final indices = <int>{0, n ~/ 4, n ~/ 2, n * 3 ~/ 4, (n - 1).clamp(0, n)};
    final sorted = indices.toList()..sort();
    return sorted.map((idx) {
      final t = candles[idx].time * 1000;
      final d = DateTime.fromMillisecondsSinceEpoch(t.toInt());
      return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    }).toList();
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
              _refreshTradingSummary();
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
                          setState(
                              () => _selectedLeverage = value.roundToDouble());
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
            color: enabled
                ? const Color(0xFF2E7D32)
                : _muted.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: enabled ? () => _openOrderSheet(true) : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_upward_rounded,
                        color: enabled ? Colors.white : _muted, size: 18),
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
            color: enabled
                ? const Color(0xFFC62828)
                : _muted.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: enabled ? () => _openOrderSheet(false) : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_downward_rounded,
                        color: enabled ? Colors.white : _muted, size: 18),
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
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
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
                  _miniChip(_productType == ProductType.spot
                      ? '全仓'
                      : widget.marginModeLabel(_marginMode)),
                  _miniChip(
                      '${_productType == ProductType.spot ? 1 : _leverage.toStringAsFixed(0)}x'),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<ProductType>(
                segments: const [
                  ButtonSegment(value: ProductType.spot, label: Text('现货')),
                  ButtonSegment(
                      value: ProductType.perpetual, label: Text('永续')),
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
                          const DropdownMenuItem(
                              value: PositionSide.long, child: Text('做多')),
                          if (widget.allowShort)
                            const DropdownMenuItem(
                                value: PositionSide.short, child: Text('做空')),
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
                          DropdownMenuItem(
                              value: MarginMode.cross, child: Text('全仓')),
                          DropdownMenuItem(
                              value: MarginMode.isolated, child: Text('逐仓')),
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
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
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
                  ButtonSegment(
                      value: true,
                      label: Text(
                          AppLocalizations.of(context)!.tradingLimitOrder)),
                  ButtonSegment(
                      value: false,
                      label: Text(
                          AppLocalizations.of(context)!.tradingMarketOrder)),
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                              ? (_productType == ProductType.spot
                                  ? '预计占用'
                                  : '预计保证金')
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
                                  SnackBar(
                                      content: Text(
                                          AppLocalizations.of(context)!
                                              .tradingEnterValidQuantity)),
                                );
                                return;
                              }
                              if (_orderTypeLimit) {
                                final priceStr =
                                    widget.priceController.text.trim();
                                final price = double.tryParse(priceStr);
                                if (price == null || price <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(AppLocalizations.of(
                                                context)!
                                            .tradingEnterValidPriceForLimit)),
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
                                final label = _productType == ProductType.spot
                                    ? '可用资金不足，无法委托'
                                    : '可用保证金不足，无法委托';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          '$label（需要 ${estimatedFunds.toStringAsFixed(2)}，当前 ${availableFunds.toStringAsFixed(2)}）')),
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
                                  _productType == ProductType.spot
                                      ? MarginMode.cross
                                      : _marginMode,
                                  _productType == ProductType.spot
                                      ? 1
                                      : _leverage,
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => _isSubmitting = false);
                                }
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            widget.isBuy ? Colors.green : Colors.red,
                      ),
                      child: Text(
                        _isSubmitting
                            ? '提交中...'
                            : (widget.isBuy
                                ? AppLocalizations.of(context)!
                                    .tradingConfirmBuy
                                : AppLocalizations.of(context)!
                                    .tradingConfirmSell),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
    final price = double.tryParse(widget.priceController.text.trim()) ??
        widget.defaultPrice;
    if (qty == null || qty <= 0 || price <= 0) return null;
    if (_productType == ProductType.spot) {
      return qty * price;
    }
    final leverage = _leverage <= 0 ? 1 : _leverage;
    return qty * price / leverage;
  }

  Widget _kvText(String label, String value,
      {Color valueColor = Colors.white}) {
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
    final pad = 8.0;
    final chartW = size.width - pad * 2;
    final chartH = size.height - pad * 2;
    final rangeY = (maxY - minY).clamp(0.01, double.infinity);
    final candleW = (chartW / n).clamp(5.0, 28.0);

    final gridPaint = Paint()
      ..color = const Color(0x1AFFFFFF)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    for (var g = 0; g <= 4; g++) {
      final y = pad + chartH * g / 4;
      canvas.drawLine(Offset(pad, y), Offset(size.width - pad, y), gridPaint);
    }

    for (var i = 0; i < n; i++) {
      final c = candles[i];
      final isUp = c.close >= c.open;
      final color = MarketColors.forUp(isUp);
      final x = n > 1 ? pad + (chartW / (n - 1)) * i : pad + chartW / 2;
      final yHigh = pad + chartH - (c.high - minY) / rangeY * chartH;
      final yLow = pad + chartH - (c.low - minY) / rangeY * chartH;
      final yOpen = pad + chartH - (c.open - minY) / rangeY * chartH;
      final yClose = pad + chartH - (c.close - minY) / rangeY * chartH;
      final bodyTop = yOpen < yClose ? yOpen : yClose;
      final bodyBottom = yOpen < yClose ? yClose : yOpen;
      final bodyH = (bodyBottom - bodyTop).clamp(1.0, double.infinity);
      final wickW = 1.2;
      final bodyW = (candleW * 0.75).clamp(4.0, 18.0);

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
