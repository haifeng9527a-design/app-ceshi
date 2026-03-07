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
  static const int _quoteSyncBatchSize = 200;
  static const int _maxMissingQuoteBatchesOnEnter = 12;
  static const int _fullQuoteSyncBatchSize = 200;

  /// 同步美股列表到本地 DB
  /// 优先级：后端 stock_quote_cache → 本地缓存 → 内置 S&P 500 → 全量 Polygon（DB 空时用全量列表补全）
  /// 存储采用异步方式，先 yield 再写入，避免阻塞 UI
  Future<void> syncTickers() async {
    try {
      var list = await _market.getTickersFromStockQuoteCache();
      if (list.isEmpty) {
        list = await _market.getCachedUsTickers() ?? [];
      }
      if (list.isEmpty) {
        list = await _market.getBundledUsTickers();
      }
      // 本地 DB 无数据时，优先用全量美股列表（Polygon v3 reference tickers，约 8000+）
      final dbCount = await MarketDb.instance.getTickersCount();
      if (dbCount == 0) {
        try {
          final fullList = await _market.getAllUsTickers();
          if (fullList.isNotEmpty) {
            list = fullList;
            if (kDebugMode) debugPrint('MarketSyncService: 使用全量美股列表 ${list.length} 条');
          }
        } catch (_) {}
      }
      if (list.isNotEmpty) {
        // 先 yield 再执行存储，避免阻塞 UI
        await Future<void>.delayed(Duration.zero);
        await MarketDb.instance.upsertTickers(list);
        await _market.syncTickersToServer(list);
        if (kDebugMode) debugPrint('MarketSyncService: synced ${list.length} tickers');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MarketSyncService syncTickers: $e');
    }
  }

  /// 同步指定 symbols 的报价到本地 DB（异步存储，先 yield 再写入，避免阻塞 UI）
  Future<void> syncQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return;
    try {
      final q = await _market.getQuotes(symbols);
      final valid = q.entries.where((e) => !e.value.hasError && e.value.price > 0).map((e) => MapEntry(e.key, e.value));
      if (valid.isNotEmpty) {
        await Future<void>.delayed(Duration.zero);
        await MarketDb.instance.upsertQuotes(Map.fromEntries(valid));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MarketSyncService syncQuotes: $e');
    }
  }

  static const _indexSymbols = ['DJI', 'IXIC', 'SPX'];

  /// 进入行情界面时与服务器同步一次（tickers + 指数报价）
  Future<void> syncOnEnter() async {
    try {
      // 后台异步执行：不阻塞 UI 首屏渲染
      unawaited(() async {
        await _syncFullTickersAndQuotesOnEnter();
        await syncQuotes(_indexSymbols);
        if (!_syncCompleteController.isClosed) {
          _syncCompleteController.add(null);
        }
      }());
    } catch (e) {
      if (kDebugMode) debugPrint('MarketSyncService syncOnEnter: $e');
    }
  }

  /// 进入 App 后：
  /// 1) 强制拉全量 reference tickers（/v3/reference/tickers）并 upsert 本地；
  /// 2) 比对本地 quotes 缺失项并分批补齐；
  /// 3) 刷新一批最旧行情，保证本地数据“存在且较新”。
  Future<void> _syncFullTickersAndQuotesOnEnter() async {
    try {
      List<MarketSearchResult> fullTickers = [];
      try {
        fullTickers = await _market.getAllUsTickers();
      } catch (e) {
        if (kDebugMode) debugPrint('MarketSyncService full tickers fallback: $e');
      }

      if (fullTickers.isNotEmpty) {
        await Future<void>.delayed(Duration.zero);
        await MarketDb.instance.upsertTickers(fullTickers);
        if (_useBackend) {
          unawaited(_market.syncTickersToServer(fullTickers));
        }
      } else {
        // 回退到既有流程，避免因第三方波动导致无数据
        await syncTickers();
      }

      // 缺失行情分批补齐（异步、限批次数，避免首轮过重）
      for (var i = 0; i < _maxMissingQuoteBatchesOnEnter; i++) {
        final missing = await MarketDb.instance.getTickerSymbolsMissingQuotes(
          limit: _quoteSyncBatchSize,
        );
        if (missing.isEmpty) break;
        await syncQuotes(missing);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      // 刷新一批最旧行情，确保启动后“最新数据”也在推进
      final oldest = await MarketDb.instance.getOldestQuoteSymbols(
        limit: _quoteSyncBatchSize,
      );
      if (oldest.isNotEmpty) {
        await syncQuotes(oldest);
      }

      if (!_syncCompleteController.isClosed) _syncCompleteController.add(null);
    } catch (e) {
      if (kDebugMode) debugPrint('MarketSyncService _syncFullTickersAndQuotesOnEnter: $e');
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

  /// 启动阶段强制把全量股票最新报价分批拉取并写入本地 DB。
  /// 数据源走 MarketRepository（第三方 API 直连或后端代理）。
  Future<void> syncAllLatestQuotesOnStartup() async {
    try {
      final total = await MarketDb.instance.getTickerCount();
      if (total <= 0) return;
      for (var offset = 0; offset < total; offset += _fullQuoteSyncBatchSize) {
        final page = await MarketDb.instance.getTickersWithQuotes(
          sortColumn: 'code',
          sortAscending: true,
          limit: _fullQuoteSyncBatchSize,
          offset: offset,
        );
        if (page.isEmpty) break;
        final symbols = page.map((e) => e.symbol).toList();
        await syncQuotes(symbols);
        // 轻微让出事件循环，避免启动阶段长任务阻塞 UI。
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      if (!_syncCompleteController.isClosed) {
        _syncCompleteController.add(null);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MarketSyncService syncAllLatestQuotesOnStartup: $e');
      }
    }
  }
}
