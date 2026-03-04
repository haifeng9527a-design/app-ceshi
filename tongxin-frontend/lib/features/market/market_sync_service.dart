import 'dart:async';

import 'package:flutter/foundation.dart';

import 'market_db.dart';
import 'market_repository.dart';

/// 行情数据同步：启动时从服务端拉取并合并到本地 DB，定时刷新
class MarketSyncService {
  MarketSyncService._();
  static final MarketSyncService instance = MarketSyncService._();

  final _market = MarketRepository();
  static final _syncCompleteController = StreamController<void>.broadcast();

  /// 同步完成时发出，供 UI 刷新
  static Stream<void> get onSyncComplete => _syncCompleteController.stream;
  Timer? _tickersSyncTimer;
  Timer? _quotesSyncTimer;

  bool get _useBackend => _market.useBackend;

  /// 同步美股列表到本地 DB
  Future<void> syncTickers() async {
    if (!_useBackend) return;
    try {
      var list = await _market.getTickersFromStockQuoteCache();
      if (list.isEmpty) {
        list = await _market.getCachedUsTickers() ?? [];
      }
      if (list.isEmpty) {
        list = await _market.getBundledUsTickers();
      }
      if (list.isNotEmpty) {
        await MarketDb.instance.upsertTickers(list);
        if (kDebugMode) debugPrint('MarketSyncService: synced ${list.length} tickers');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MarketSyncService syncTickers: $e');
    }
  }

  /// 同步指定 symbols 的报价到本地 DB
  Future<void> syncQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return;
    try {
      final q = await _market.getQuotes(symbols);
      final valid = q.entries.where((e) => !e.value.hasError && e.value.price > 0).map((e) => MapEntry(e.key, e.value));
      if (valid.isNotEmpty) {
        await MarketDb.instance.upsertQuotes(Map.fromEntries(valid));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MarketSyncService syncQuotes: $e');
    }
  }

  static const _indexSymbols = ['DJI', 'IXIC', 'SPX'];

  /// 进入行情界面时与服务器同步一次（tickers + 指数报价）
  Future<void> syncOnEnter() async {
    if (!_useBackend) return;
    try {
      await syncTickers();
      await syncQuotes(_indexSymbols);
      if (!_syncCompleteController.isClosed) _syncCompleteController.add(null);
    } catch (e) {
      if (kDebugMode) debugPrint('MarketSyncService syncOnEnter: $e');
    }
  }

  /// 启动定时同步：tickers 每 1 小时，quotes 由调用方按需触发
  void startPeriodicSync() {
    if (!_useBackend) return;
    _tickersSyncTimer?.cancel();
    _tickersSyncTimer = Timer.periodic(const Duration(hours: 1), (_) => syncTickers());
    syncTickers();
  }

  void stopPeriodicSync() {
    _tickersSyncTimer?.cancel();
    _tickersSyncTimer = null;
    _quotesSyncTimer?.cancel();
    _quotesSyncTimer = null;
  }
}
