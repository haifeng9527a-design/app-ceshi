import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../market/market_repository.dart';
import 'polygon_realtime.dart';

/// 将 WebSocket 成交推送合并进涨跌榜/报价，实现实时价更新
/// 首次加载仍用 REST，后续由 WebSocket 推送更新
class RealtimeQuoteService {
  RealtimeQuoteService();

  PolygonRealtimeMulti? _realtime;
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

  /// 最大订阅数（Polygon 单连接有上限，通常 30～50）
  static const int _maxSubscribeSymbols = 40;

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
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    final symbols = <String>{};
    for (final g in _gainers.take(_maxSubscribeSymbols ~/ 2)) {
      if (g.prevClose != null && g.prevClose! > 0) symbols.add(g.ticker);
    }
    for (final g in _losers.take(_maxSubscribeSymbols ~/ 2)) {
      if (g.prevClose != null && g.prevClose! > 0) symbols.add(g.ticker);
    }
    if (symbols.isEmpty) return;

    _realtime?.dispose();
    _sub?.cancel();
    _realtime = PolygonRealtimeMulti(apiKey: apiKey, symbols: symbols.toList());
    _realtime!.connect();
    _sub = _realtime!.stream.listen(_onGainersLosersTrade);
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

  void _subscribeForQuotes({List<String>? prioritySymbols}) {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    List<String> symbols;
    if (prioritySymbols != null && prioritySymbols.isNotEmpty) {
      symbols = prioritySymbols
          .where((s) {
            final q = _quotes[s];
            return q != null && !q.hasError && q.price > 0;
          })
          .take(_maxSubscribeSymbols)
          .toList();
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

    _realtime?.dispose();
    _sub?.cancel();
    _realtime = PolygonRealtimeMulti(apiKey: apiKey, symbols: symbols);
    _realtime!.connect();
    _sub = _realtime!.stream.listen(_onQuotesTrade);
  }

  void _onQuotesTrade(PolygonTradeUpdate u) {
    if (u.symbol == null || u.price <= 0) return;
    final q = _quotes[u.symbol!];
    if (q == null || q.hasError) return;

    final prevClose = q.change != 0 ? q.price - q.change : q.price;
    if (prevClose <= 0) return;

    final newChange = u.price - prevClose;
    final newChangePct = (newChange / prevClose) * 100;
    final updated = MarketQuote(
      symbol: q.symbol,
      name: q.name,
      price: u.price,
      change: newChange,
      changePercent: newChangePct,
      open: q.open,
      high: q.high,
      low: q.low,
      volume: q.volume,
    );
    _quotes[u.symbol!] = updated;
    if (!_quotesController.isClosed) _quotesController.add(_quotes);
  }

  void dispose() {
    _sub?.cancel();
    _realtime?.dispose();
    _gainersController.close();
    _losersController.close();
    _quotesController.close();
  }
}
