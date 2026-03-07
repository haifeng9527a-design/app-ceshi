import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../market/market_repository.dart';
import 'backend_realtime_client.dart';

/// 将 WebSocket 成交推送合并进涨跌榜/报价，实现实时价更新
/// 首次加载仍用 REST，后续由 WebSocket 推送更新
/// 优先直连 Polygon 官方 WebSocket（wss://socket.polygon.io/stocks），无 API Key 时走后端代理
class RealtimeQuoteService {
  RealtimeQuoteService();

  PolygonRealtimeMulti? _realtime;
  BackendRealtimeClient? _backendRealtime;
  StreamSubscription<PolygonTradeUpdate>? _sub;
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

  String? get _apiKey => dotenv.env['POLYGON_API_KEY']?.trim();
  String? get _backendUrl =>
      dotenv.env['TONGXIN_API_URL']?.trim() ?? dotenv.env['BACKEND_URL']?.trim();

  /// 优先直连 Polygon 官方 WebSocket；无 API Key 时走后端代理
  bool get _useDirectPolygon => _apiKey != null && _apiKey!.isNotEmpty;

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
    if (!_acceptAllSymbols && _symbolsToFilter.isEmpty) return;
    if (!_useDirectPolygon && (_backendUrl == null || _backendUrl!.isEmpty)) return;

    _realtime?.dispose();
    _backendRealtime?.dispose();
    _sub?.cancel();

    if (_useDirectPolygon) {
      _realtime = PolygonRealtimeMulti(apiKey: _apiKey!, subscribeAll: true);
      _realtime!.connect();
      _sub = _realtime!.stream.listen(_onQuotesTradeFiltered);
    } else {
      _backendRealtime = BackendRealtimeClient(baseUrl: _backendUrl!);
      _backendRealtime!.connect(subscribeAll: true);
      _sub = _backendRealtime!.stream.listen(_onQuotesTradeFiltered);
    }
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
    final symbols = <String>{};
    for (final g in _gainers.take(_maxSubscribeSymbols ~/ 2)) {
      if (g.prevClose != null && g.prevClose! > 0) symbols.add(g.ticker);
    }
    for (final g in _losers.take(_maxSubscribeSymbols ~/ 2)) {
      if (g.prevClose != null && g.prevClose! > 0) symbols.add(g.ticker);
    }
    if (symbols.isEmpty) return;

    _realtime?.dispose();
    _backendRealtime?.dispose();
    _sub?.cancel();

    if (_useDirectPolygon) {
      _realtime = PolygonRealtimeMulti(apiKey: _apiKey!, symbols: symbols.toList());
      _realtime!.connect();
      _sub = _realtime!.stream.listen(_onGainersLosersTrade);
    } else if (_backendUrl != null && _backendUrl!.isNotEmpty) {
      _backendRealtime = BackendRealtimeClient(baseUrl: _backendUrl!);
      _backendRealtime!.connect(symbols: symbols.toList());
      _sub = _backendRealtime!.stream.listen(_onGainersLosersTrade);
    }
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
    _symbolsToFilter = {}; // 切换回按 symbol 订阅模式
    List<String> symbols;
    if (prioritySymbols != null && prioritySymbols.isNotEmpty) {
      // 优先订阅可见区域，即使暂无报价也订阅，WebSocket 推送时可创建新报价
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
    if (!_useDirectPolygon && (_backendUrl == null || _backendUrl!.isEmpty)) return;

    _realtime?.dispose();
    _backendRealtime?.dispose();
    _sub?.cancel();

    if (_useDirectPolygon) {
      _realtime = PolygonRealtimeMulti(apiKey: _apiKey!, symbols: symbols);
      _realtime!.connect();
      _sub = _realtime!.stream.listen(_onQuotesTrade);
    } else {
      _backendRealtime = BackendRealtimeClient(baseUrl: _backendUrl!);
      _backendRealtime!.connect(symbols: symbols);
      _sub = _backendRealtime!.stream.listen(_onQuotesTrade);
    }
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
    _realtime?.dispose();
    _backendRealtime?.dispose();
    _gainersController.close();
    _losersController.close();
    _quotesController.close();
  }
}
