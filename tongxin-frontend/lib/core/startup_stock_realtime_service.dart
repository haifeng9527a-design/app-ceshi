import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/market/market_db.dart';
import '../features/market/market_sync_service.dart';
import '../features/market/market_repository.dart';
import '../features/trading/realtime_quote_service.dart';

/// App 启动后全量股票实时同步：
/// 1) 强制拉全量列表与最新报价并写入 SQLite；
/// 2) 建立全量 WebSocket 订阅，持续写库。
class StartupStockRealtimeService {
  StartupStockRealtimeService._();
  static final StartupStockRealtimeService instance =
      StartupStockRealtimeService._();

  final RealtimeQuoteService _realtime = RealtimeQuoteService();
  StreamSubscription<Map<String, MarketQuote>>? _quotesSub;
  final Map<String, MarketQuote> _pending = <String, MarketQuote>{};
  Timer? _persistDebounce;
  bool _started = false;
  bool _starting = false;

  Future<void> start() async {
    if (_started || _starting) return;
    _starting = true;
    try {
      await MarketSyncService.instance.syncOnEnter();
      await MarketSyncService.instance.syncAllLatestQuotesOnStartup();

      final total = await MarketDb.instance.getTickerCount();
      if (total <= 0) {
        _started = true;
        return;
      }

      final symbols = <String>{};
      const pageSize = 500;
      for (var offset = 0; offset < total; offset += pageSize) {
        final page = await MarketDb.instance.getTickersWithQuotes(
          sortColumn: 'code',
          sortAscending: true,
          limit: pageSize,
          offset: offset,
        );
        if (page.isEmpty) break;
        for (final row in page) {
          final s = row.symbol.trim().toUpperCase();
          if (s.isNotEmpty) symbols.add(s);
        }
      }

      if (symbols.isEmpty) {
        _started = true;
        return;
      }

      _quotesSub?.cancel();
      _quotesSub = _realtime.quotesStream.listen(_onRealtimeQuotes);
      _realtime.subscribeToAllSymbols(
        symbols,
        acceptAllSymbols: true,
      );
      _started = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[StartupStockRealtimeService] start failed: $e');
      }
    } finally {
      _starting = false;
    }
  }

  void _onRealtimeQuotes(Map<String, MarketQuote> delta) {
    if (delta.isEmpty) return;
    _pending.addAll(delta);
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 700), () async {
      if (_pending.isEmpty) return;
      final toSave = Map<String, MarketQuote>.from(_pending);
      _pending.clear();
      try {
        await MarketDb.instance.upsertQuotes(toSave);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[StartupStockRealtimeService] persist failed: $e');
        }
      }
    });
  }

  Future<void> stop() async {
    _started = false;
    _persistDebounce?.cancel();
    _persistDebounce = null;
    _pending.clear();
    await _quotesSub?.cancel();
    _quotesSub = null;
    _realtime.dispose();
  }
}
