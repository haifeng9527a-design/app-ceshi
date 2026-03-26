import 'dart:async';

import '../../core/chat_web_socket_service.dart';
import '../market/market_repository.dart';
import 'polygon_realtime.dart';

/// 将 WebSocket 成交推送合并进涨跌榜/报价，实现实时价更新
/// 通过 chat WebSocket 复用连接接收行情（后端 ingestors 推送），不再直连 Polygon/BackendRealtimeClient
class RealtimeQuoteService {
  RealtimeQuoteService();

  /// 是否启用 WebSocket 行情订阅，通过 chat WebSocket 接收
  static const bool _useRealtimeWebSocket = true;

  StreamSubscription<dynamic>? _sub;
  final _gainersController = StreamController<List<PolygonGainer>>.broadcast();
  final _losersController = StreamController<List<PolygonGainer>>.broadcast();
  final _quotesController = StreamController<Map<String, MarketQuote>>.broadcast();

  List<PolygonGainer> _gainers = [];
  List<PolygonGainer> _losers = [];
  Map<String, MarketQuote> _quotes = {};

  /// 涨跌榜实时流（合并 WebSocket 更新后的列表）
  Stream<List<PolygonGainer>> get gainersStream => _gainersController.stream;
  Stream<List<PolygonGainer>> get losersStream => _losersController.stream;

  /// 报价 Map 实时流（合并 WebSocket 更新）
  Stream<Map<String, MarketQuote>> get quotesStream => _quotesController.stream;

  /// 最大订阅数（Polygon 单连接有上限，通常 30～50）
  static const int _maxSubscribeSymbols = 40;

  /// 订阅全部股票时的过滤集合（仅更新此集合内的 symbol）；acceptAllSymbols 时可为空
  Set<String> _symbolsToFilter = {};
  bool _acceptAllSymbols = false;

  /// 订阅所有美股成交（T.*）
  /// [symbolsToFilter] 基础过滤集合；[acceptAllSymbols] 为 true 时接受任意新 symbol（不在集合内也新增）
  /// [initialQuotes] 可选，已有报价时传入以便正确计算涨跌
  void subscribeToAllSymbols(
    Set<String> symbolsToFilter, {
    Map<String, MarketQuote>? initialQuotes,
    bool acceptAllSymbols = false,
  }) {
    if (!acceptAllSymbols && symbolsToFilter.isEmpty) return;
    if (initialQuotes != null && initialQuotes.isNotEmpty) {
      _quotes = Map.from(initialQuotes);
      if (!_quotesController.isClosed) _quotesController.add(_quotes);
    }
    _symbolsToFilter = symbolsToFilter;
    _acceptAllSymbols = acceptAllSymbols;
    _subscribeForQuotesAll();
  }

  void _subscribeForQuotesAll() {
    if (!_useRealtimeWebSocket) return;
    if (!_acceptAllSymbols && _symbolsToFilter.isEmpty) return;
    if (!ChatWebSocketService.instance.isConnected) return;

    _sub?.cancel();

    ChatWebSocketService.instance.subscribeMarket(['*']);
    _sub = ChatWebSocketService.instance.marketQuoteStream.listen((u) {
      _onQuotesTradeFiltered(PolygonTradeUpdate(price: u.price, size: u.size, timestampMs: u.timestampMs, symbol: u.symbol));
    });
  }

  void _onQuotesTradeFiltered(PolygonTradeUpdate u) {
    if (u.symbol == null || u.price <= 0) return;
    if (!_acceptAllSymbols && !_symbolsToFilter.contains(u.symbol)) return;
    _onQuotesTrade(u);
  }

  /// 设置涨跌榜并订阅 WebSocket，有成交即更新并推流
  void setGainersLosers({
    required List<PolygonGainer> gainers,
    required List<PolygonGainer> losers,
  }) {
    _gainers = List.from(gainers);
    _losers = List.from(losers);
    _gainersController.add(_gainers);
    _losersController.add(_losers);
    _subscribeForGainersLosers();
  }

  void _subscribeForGainersLosers() {
    if (!_useRealtimeWebSocket) return;
    final symbols = <String>{};
    for (final g in _gainers.take(_maxSubscribeSymbols ~/ 2)) {
      if (g.prevClose != null && g.prevClose! > 0) symbols.add(g.ticker);
    }
    for (final g in _losers.take(_maxSubscribeSymbols ~/ 2)) {
      if (g.prevClose != null && g.prevClose! > 0) symbols.add(g.ticker);
    }
    if (symbols.isEmpty) return;
    if (!ChatWebSocketService.instance.isConnected) return;

    _sub?.cancel();

    ChatWebSocketService.instance.subscribeMarket(symbols.toList());
    _sub = ChatWebSocketService.instance.marketQuoteStream.listen((u) {
      _onGainersLosersTrade(PolygonTradeUpdate(price: u.price, size: u.size, timestampMs: u.timestampMs, symbol: u.symbol));
    });
  }

  void _onGainersLosersTrade(PolygonTradeUpdate u) {
    if (u.symbol == null || u.price <= 0) return;
    final sym = u.symbol!;
    bool changed = false;

    for (var i = 0; i < _gainers.length; i++) {
      if (_gainers[i].ticker == sym) {
        _gainers[i] = _gainers[i].copyWithRealtimePrice(u.price);
        changed = true;
        break;
      }
    }
    if (!changed) {
      for (var i = 0; i < _losers.length; i++) {
        if (_losers[i].ticker == sym) {
          _losers[i] = _losers[i].copyWithRealtimePrice(u.price);
          changed = true;
          break;
        }
      }
    }
    if (changed && !_gainersController.isClosed) {
      _gainersController.add(_gainers);
      _losersController.add(_losers);
    }
  }

  /// 设置报价 Map 并订阅 WebSocket
  /// [prioritySymbols] 优先订阅的标的（如可见区域），为空则取 map 前 N 个
  void setQuotes(Map<String, MarketQuote> quotes, {List<String>? prioritySymbols}) {
    _quotes = Map.from(quotes);
    _quotesController.add(_quotes);
    _subscribeForQuotes(prioritySymbols: prioritySymbols);
  }

  /// 追加/更新报价（如滚动加载新标的），并重新订阅
  /// [prioritySymbols] 优先订阅的标的（如可见区域）
  void updateQuotes(Map<String, MarketQuote> newQuotes, {List<String>? prioritySymbols}) {
    _quotes.addAll(newQuotes);
    _quotesController.add(_quotes);
    _subscribeForQuotes(prioritySymbols: prioritySymbols);
  }

  /// 仅订阅可见区域 WebSocket（无初始报价时也可订阅，收到推送会创建报价）
  void subscribeToSymbols(List<String> symbols) {
    if (symbols.isEmpty) return;
    _symbolsToFilter = {}; // 清除全量订阅模式
    _subscribeForQuotes(prioritySymbols: symbols);
  }

  void _subscribeForQuotes({List<String>? prioritySymbols}) {
    if (!_useRealtimeWebSocket) return;
    if (!ChatWebSocketService.instance.isConnected) return;
    _symbolsToFilter = {}; // 切换回按 symbol 订阅模式
    List<String> symbols;
    if (prioritySymbols != null && prioritySymbols.isNotEmpty) {
      symbols = prioritySymbols.take(_maxSubscribeSymbols).toList();
    } else {
      symbols = _quotes.keys
          .where((s) {
            final q = _quotes[s];
            return q != null && !q.hasError && q.price > 0;
          })
          .take(_maxSubscribeSymbols)
          .toList();
    }
    if (symbols.isEmpty) return;

    _sub?.cancel();

    ChatWebSocketService.instance.subscribeMarket(symbols);
    _sub = ChatWebSocketService.instance.marketQuoteStream.listen((u) {
      _onQuotesTrade(PolygonTradeUpdate(price: u.price, size: u.size, timestampMs: u.timestampMs, symbol: u.symbol));
    });
  }

  /// 是否处于全量订阅模式（T.*）
  bool get isSubscribeAll => _symbolsToFilter.isNotEmpty || _acceptAllSymbols;

  /// 同步报价到服务（全量订阅模式下，REST 拉取后调用，不触发重连）
  void syncQuotes(Map<String, MarketQuote> quotes) {
    if (quotes.isEmpty) return;
    _quotes.addAll(quotes);
  }

  void _onQuotesTrade(PolygonTradeUpdate u) {
    if (u.symbol == null || u.price <= 0) return;
    final sym = u.symbol!;
    final q = _quotes[sym];

    MarketQuote updated;
    if (q != null && !q.hasError) {
      final prevClose = q.prevClose ?? (q.change != 0 ? q.price - q.change : q.price);
      if (prevClose > 0) {
        final newChange = u.price - prevClose;
        final newChangePct = (newChange / prevClose) * 100;
        updated = MarketQuote(
          symbol: q.symbol,
          name: q.name,
          price: u.price,
          change: newChange,
          changePercent: newChangePct,
          open: q.open,
          high: q.high,
          low: q.low,
          volume: q.volume,
          prevClose: prevClose,
        );
      } else {
        updated = MarketQuote(
          symbol: q.symbol,
          name: q.name,
          price: u.price,
          change: 0,
          changePercent: 0,
          open: q.open,
          high: q.high,
          low: q.low,
          volume: q.volume,
          prevClose: q.prevClose,
        );
      }
    } else {
      // 无初始报价时，WebSocket 推送创建新报价（仅价格，涨跌为 0）
      updated = MarketQuote(
        symbol: sym,
        name: null,
        price: u.price,
        change: 0,
        changePercent: 0,
        open: null,
        high: null,
        low: null,
        volume: null,
        prevClose: null,
      );
    }
    _quotes[sym] = updated;
    if (!_quotesController.isClosed) {
      _quotesController.add(<String, MarketQuote>{sym: updated});
    }
  }

  void dispose() {
    _sub?.cancel();
    _gainersController.close();
    _losersController.close();
    _quotesController.close();
  }
}
