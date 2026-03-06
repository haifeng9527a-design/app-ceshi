import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'market_repository.dart';

/// SQLite 本地存储：美股列表与报价
/// 启动时从服务端拉取并合并，加载时优先读本地，排序在 SQL 层完成以提升效率
class MarketDb {
  MarketDb._();
  static final MarketDb instance = MarketDb._();

  Database? _db;
  static const int _version = 4;
  static const String _dbName = 'market_local.db';

  final Map<String, StreamController<Object?>> _tickersControllers = {};
  final Map<String, StreamController<Object?>> _quotesControllers = {};

  Future<Database> _getDb() async {
    if (_db != null && _db!.isOpen) return _db!;
    try {
      final dbDir = await getDatabasesPath();
      final dbPath = join(dbDir, _dbName);
      _db = await openDatabase(
        dbPath,
        version: _version,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      return _db!;
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb _getDb: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tickers (
        symbol TEXT PRIMARY KEY,
        name TEXT,
        market TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE quotes (
        symbol TEXT PRIMARY KEY,
        price REAL NOT NULL DEFAULT 0,
        change_val REAL NOT NULL DEFAULT 0,
        change_percent REAL NOT NULL DEFAULT 0,
        open_val REAL,
        high_val REAL,
        low_val REAL,
        volume INTEGER,
        name TEXT,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_tickers_updated ON tickers(updated_at)');
    await db.execute('CREATE INDEX idx_quotes_change_pct ON quotes(change_percent)');
    await db.execute('CREATE INDEX idx_quotes_price ON quotes(price)');
    await db.execute('CREATE INDEX idx_quotes_volume ON quotes(volume)');
    await db.execute('CREATE INDEX idx_quotes_updated ON quotes(updated_at_ms)');
    await _createForexPairsTable(db);
    await _createForexQuotesTable(db);
    await _createCryptoQuotesTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createForexQuotesTable(db);
    }
    if (oldVersion < 3) {
      await _createCryptoQuotesTable(db);
    }
    if (oldVersion < 4) {
      await _createForexPairsTable(db);
    }
  }

  Future<void> _createForexPairsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS forex_pairs (
        symbol TEXT PRIMARY KEY,
        name TEXT,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_forex_pairs_updated ON forex_pairs(updated_at_ms)');
  }

  Future<void> _createForexQuotesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS forex_quotes (
        symbol TEXT PRIMARY KEY,
        name TEXT,
        price REAL NOT NULL DEFAULT 0,
        change_val REAL NOT NULL DEFAULT 0,
        change_percent REAL NOT NULL DEFAULT 0,
        open_val REAL,
        high_val REAL,
        low_val REAL,
        volume INTEGER,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_forex_quotes_updated ON forex_quotes(updated_at_ms)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_forex_quotes_change_pct ON forex_quotes(change_percent)');
  }

  Future<void> _createCryptoQuotesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS crypto_quotes (
        symbol TEXT PRIMARY KEY,
        name TEXT,
        price REAL NOT NULL DEFAULT 0,
        change_val REAL NOT NULL DEFAULT 0,
        change_percent REAL NOT NULL DEFAULT 0,
        open_val REAL,
        high_val REAL,
        low_val REAL,
        volume INTEGER,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_crypto_quotes_updated ON crypto_quotes(updated_at_ms)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_crypto_quotes_change_pct ON crypto_quotes(change_percent)');
  }

  /// 合并美股列表（以服务端为准，全量替换）
  Future<void> upsertTickers(List<MarketSearchResult> list) async {
    if (list.isEmpty) return;
    try {
      final db = await _getDb();
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = db.batch();
      for (final t in list) {
        batch.insert(
          'tickers',
          {
            'symbol': t.symbol,
            'name': t.name,
            'market': t.market,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      _notifyTickers();
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb upsertTickers: $e');
    }
  }

  /// 合并报价（不存在则插入，已存在则更新）
  Future<void> upsertQuotes(Map<String, MarketQuote> map) async {
    if (map.isEmpty) return;
    try {
      final db = await _getDb();
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = db.batch();
      for (final e in map.entries) {
        final q = e.value;
        if (q.hasError) continue;
        batch.insert(
          'quotes',
          {
            'symbol': q.symbol,
            'price': q.price,
            'change_val': q.change,
            'change_percent': q.changePercent,
            'open_val': q.open,
            'high_val': q.high,
            'low_val': q.low,
            'volume': q.volume,
            'name': q.name,
            'updated_at_ms': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      _notifyQuotes();
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb upsertQuotes: $e');
    }
  }

  /// 外汇独立表：合并报价（不存在则插入，已存在则更新）
  Future<void> upsertForexQuotes(Map<String, MarketQuote> map) async {
    if (map.isEmpty) return;
    try {
      final db = await _getDb();
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = db.batch();
      for (final e in map.entries) {
        final q = e.value;
        if (q.hasError) continue;
        batch.insert(
          'forex_quotes',
          {
            'symbol': q.symbol,
            'name': q.name,
            'price': q.price,
            'change_val': q.change,
            'change_percent': q.changePercent,
            'open_val': q.open,
            'high_val': q.high,
            'low_val': q.low,
            'volume': q.volume,
            'updated_at_ms': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb upsertForexQuotes: $e');
    }
  }

  /// 外汇交易对独立表：symbol+name（用于外汇页首屏/离线恢复）
  Future<void> upsertForexPairs(List<MarketSearchResult> pairs) async {
    if (pairs.isEmpty) return;
    try {
      final db = await _getDb();
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = db.batch();
      for (final p in pairs) {
        final symbol = p.symbol.trim();
        if (symbol.isEmpty) continue;
        batch.insert(
          'forex_pairs',
          {
            'symbol': symbol,
            'name': p.name,
            'updated_at_ms': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb upsertForexPairs: $e');
    }
  }

  /// 外汇交易对独立表：读取全部 symbol+name
  Future<List<MarketSearchResult>> getForexPairs() async {
    try {
      final db = await _getDb();
      final rows = await db.query('forex_pairs', orderBy: 'symbol ASC');
      return rows
          .map((r) {
            final symbol = (r['symbol'] as String?)?.trim() ?? '';
            if (symbol.isEmpty) return null;
            final name = (r['name'] as String?)?.trim();
            return MarketSearchResult(
              symbol: symbol,
              name: (name == null || name.isEmpty) ? symbol : name,
              market: 'forex',
            );
          })
          .whereType<MarketSearchResult>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb getForexPairs: $e');
      return [];
    }
  }

  /// 外汇独立表：按 symbols 读取；symbols 为空时读取全部
  Future<Map<String, MarketQuote>> getForexQuotes([List<String>? symbols]) async {
    try {
      final db = await _getDb();
      final out = <String, MarketQuote>{};
      final list = symbols?.where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toList() ?? <String>[];
      if (list.isEmpty) {
        final rows = await db.query('forex_quotes', orderBy: 'symbol ASC');
        for (final r in rows) {
          final q = _rowToQuote(r);
          if (q != null) out[q.symbol] = q;
        }
        return out;
      }
      for (int i = 0; i < list.length; i += _maxInBatch) {
        final batch = list.sublist(i, (i + _maxInBatch).clamp(0, list.length));
        if (batch.isEmpty) break;
        final placeholders = List.filled(batch.length, '?').join(',');
        final rows = await db.query(
          'forex_quotes',
          where: 'symbol IN ($placeholders)',
          whereArgs: batch,
        );
        for (final r in rows) {
          final q = _rowToQuote(r);
          if (q != null) out[q.symbol] = q;
        }
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb getForexQuotes: $e');
      return {};
    }
  }

  /// 加密货币独立表：合并报价（不存在则插入，已存在则更新）
  Future<void> upsertCryptoQuotes(Map<String, MarketQuote> map) async {
    if (map.isEmpty) return;
    try {
      final db = await _getDb();
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = db.batch();
      for (final e in map.entries) {
        final q = e.value;
        if (q.hasError) continue;
        batch.insert(
          'crypto_quotes',
          {
            'symbol': q.symbol,
            'name': q.name,
            'price': q.price,
            'change_val': q.change,
            'change_percent': q.changePercent,
            'open_val': q.open,
            'high_val': q.high,
            'low_val': q.low,
            'volume': q.volume,
            'updated_at_ms': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb upsertCryptoQuotes: $e');
    }
  }

  /// 加密货币独立表：按 symbols 读取；symbols 为空时读取全部
  Future<Map<String, MarketQuote>> getCryptoQuotes([List<String>? symbols]) async {
    try {
      final db = await _getDb();
      final out = <String, MarketQuote>{};
      final list = symbols?.where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toList() ?? <String>[];
      if (list.isEmpty) {
        final rows = await db.query('crypto_quotes', orderBy: 'symbol ASC');
        for (final r in rows) {
          final q = _rowToQuote(r);
          if (q != null) out[q.symbol] = q;
        }
        return out;
      }
      for (int i = 0; i < list.length; i += _maxInBatch) {
        final batch = list.sublist(i, (i + _maxInBatch).clamp(0, list.length));
        if (batch.isEmpty) break;
        final placeholders = List.filled(batch.length, '?').join(',');
        final rows = await db.query(
          'crypto_quotes',
          where: 'symbol IN ($placeholders)',
          whereArgs: batch,
        );
        for (final r in rows) {
          final q = _rowToQuote(r);
          if (q != null) out[q.symbol] = q;
        }
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb getCryptoQuotes: $e');
      return {};
    }
  }

  /// 获取美股列表（按 symbol 排序）
  Future<List<MarketSearchResult>> getTickers() async {
    try {
      final db = await _getDb();
      final rows = await db.query(
        'tickers',
        orderBy: 'symbol ASC',
      );
      return rows.map(_rowToTicker).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb getTickers: $e');
      return [];
    }
  }

  /// 清空所有股票行情数据（tickers + quotes）
  Future<void> clearAllMarketData() async {
    try {
      final db = await _getDb();
      await db.delete('quotes');
      await db.delete('tickers');
      await db.delete('forex_pairs');
      await db.delete('forex_quotes');
      await db.delete('crypto_quotes');
      _notifyTickers();
      _notifyQuotes();
      if (kDebugMode) debugPrint('MarketDb clearAllMarketData: 已清空 tickers/quotes/forex/crypto');
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb clearAllMarketData: $e');
      rethrow;
    }
  }

  /// 获取美股数量
  Future<int> getTickersCount() async {
    try {
      final db = await _getDb();
      final r = await db.rawQuery('SELECT COUNT(*) as c FROM tickers');
      return (r.first['c'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// SQLite 单次 IN 子句变量上限约 999，分批查询
  static const int _maxInBatch = 500;

  /// 获取报价 Map（按 symbol 列表，超限时分批查询）
  Future<Map<String, MarketQuote>> getQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return {};
    try {
      final db = await _getDb();
      final out = <String, MarketQuote>{};
      for (int i = 0; i < symbols.length; i += _maxInBatch) {
        final batch = symbols.sublist(i, (i + _maxInBatch).clamp(0, symbols.length));
        if (batch.isEmpty) break;
        final placeholders = List.filled(batch.length, '?').join(',');
        final rows = await db.query(
          'quotes',
          where: 'symbol IN ($placeholders)',
          whereArgs: batch,
        );
        for (final r in rows) {
          final q = _rowToQuote(r);
          if (q != null) out[q.symbol] = q;
        }
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb getQuotes: $e');
      return {};
    }
  }

  /// 获取 tickers + quotes 合并列表，支持 SQL 排序（高效）
  /// [sortColumn] 排序字段：code, name, pct, price, change, open, prev, high, low, vol
  /// [sortAscending] true 升序，false 降序
  /// [limit] 限制条数，0 表示不限制
  /// [offset] 偏移量
  Future<List<MarketSearchResult>> getTickersWithQuotes({
    String? sortColumn,
    bool sortAscending = false,
    int limit = 0,
    int offset = 0,
  }) async {
    try {
      final db = await _getDb();
      final orderBy = _buildOrderBy(sortColumn ?? 'pct', sortAscending);
      final limitClause = limit > 0 ? 'LIMIT $limit' : '';
      final offsetClause = offset > 0 ? 'OFFSET $offset' : '';
      final rows = await db.rawQuery('''
        SELECT t.symbol, t.name, t.market,
               q.price, q.change_val, q.change_percent, q.open_val, q.high_val, q.low_val, q.volume
        FROM tickers t
        LEFT JOIN quotes q ON t.symbol = q.symbol
        $orderBy
        $limitClause
        $offsetClause
      '''.trim());
      return rows.map((r) => _rowToTickerWithQuote(r)).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb getTickersWithQuotes: $e');
      return [];
    }
  }

  /// 获取全部 tickers + quotes 合并列表（用于全量展示，支持 SQL 排序）
  Future<List<MarketSearchResult>> getAllTickersWithQuotes({
    String? sortColumn,
    bool sortAscending = false,
  }) async {
    return getTickersWithQuotes(
      sortColumn: sortColumn,
      sortAscending: sortAscending,
      limit: 0,
    );
  }

  String _buildOrderBy(String col, bool asc) {
    final dir = asc ? 'ASC' : 'DESC';
    // COALESCE 将 NULL 排到末尾，兼容旧版 SQLite
    final nullLast = asc ? 999999999.0 : -999999999.0;
    switch (col) {
      case 'code':
        return 'ORDER BY t.symbol $dir';
      case 'name':
        return 'ORDER BY COALESCE(t.name, "") $dir';
      case 'pct':
        return 'ORDER BY COALESCE(q.change_percent, $nullLast) $dir, t.symbol ASC';
      case 'price':
        return 'ORDER BY COALESCE(q.price, 0) $dir, t.symbol ASC';
      case 'change':
        return 'ORDER BY COALESCE(q.change_val, $nullLast) $dir, t.symbol ASC';
      case 'open':
        return 'ORDER BY COALESCE(q.open_val, $nullLast) $dir, t.symbol ASC';
      case 'prev':
        return 'ORDER BY COALESCE(q.price - q.change_val, $nullLast) $dir, t.symbol ASC';
      case 'high':
        return 'ORDER BY COALESCE(q.high_val, $nullLast) $dir, t.symbol ASC';
      case 'low':
        return 'ORDER BY COALESCE(q.low_val, $nullLast) $dir, t.symbol ASC';
      case 'vol':
        return 'ORDER BY COALESCE(q.volume, 0) $dir, t.symbol ASC';
      default:
        return 'ORDER BY COALESCE(q.change_percent, -999999999.0) DESC, t.symbol ASC';
    }
  }

  MarketSearchResult _rowToTicker(Map<String, dynamic> r) {
    final sym = r['symbol'] as String? ?? '';
    return MarketSearchResult(
      symbol: sym,
      name: r['name'] as String? ?? sym,
      market: r['market'] as String?,
    );
  }

  MarketQuote? _rowToQuote(Map<String, dynamic> r) {
    final symbol = r['symbol'] as String?;
    if (symbol == null) return null;
    return MarketQuote(
      symbol: symbol,
      name: r['name'] as String?,
      price: (r['price'] as num?)?.toDouble() ?? 0,
      change: (r['change_val'] as num?)?.toDouble() ?? 0,
      changePercent: (r['change_percent'] as num?)?.toDouble() ?? 0,
      open: (r['open_val'] as num?)?.toDouble(),
      high: (r['high_val'] as num?)?.toDouble(),
      low: (r['low_val'] as num?)?.toDouble(),
      volume: (r['volume'] as int?),
    );
  }

  /// 返回带 quote 的 MarketSearchResult（用于展示，quote 需单独存储或从 JOIN 取）
  MarketSearchResult _rowToTickerWithQuote(Map<String, dynamic> r) {
    final sym = r['symbol'] as String? ?? '';
    return MarketSearchResult(
      symbol: sym,
      name: r['name'] as String? ?? sym,
      market: r['market'] as String?,
    );
  }

  void _notifyTickers() {
    for (final c in _tickersControllers.values) {
      c.add(null);
    }
  }

  void _notifyQuotes() {
    for (final c in _quotesControllers.values) {
      c.add(null);
    }
  }

  /// 监听美股列表变化
  Stream<List<MarketSearchResult>> watchTickers() async* {
    const key = 'us';
    _tickersControllers[key] ??= StreamController<Object?>.broadcast();
    yield await getTickers();
    await for (final _ in _tickersControllers[key]!.stream) {
      yield await getTickers();
    }
  }

  /// 监听 tickers+quotes 合并列表（带排序）
  /// tickers 或 quotes 任一更新时都会重新拉取
  Stream<List<MarketSearchResult>> watchTickersWithQuotes({
    String? sortColumn,
    bool sortAscending = false,
  }) async* {
    final key = 'us_q_${sortColumn ?? "pct"}_$sortAscending';
    final c = StreamController<Object?>.broadcast();
    _tickersControllers[key] = c;
    _quotesControllers[key] = c;
    yield await getAllTickersWithQuotes(sortColumn: sortColumn, sortAscending: sortAscending);
    await for (final _ in c.stream) {
      yield await getAllTickersWithQuotes(sortColumn: sortColumn, sortAscending: sortAscending);
    }
  }

  /// 简化：获取 tickers + 对应 quotes 的 map（用于 UI 展示）
  Future<({List<MarketSearchResult> tickers, Map<String, MarketQuote> quotes})> getTickersAndQuotes({
    String? sortColumn,
    bool sortAscending = false,
  }) async {
    final tickers = await getAllTickersWithQuotes(sortColumn: sortColumn, sortAscending: sortAscending);
    final symbols = tickers.map((t) => t.symbol).toList();
    final quotes = await getQuotes(symbols);
    return (tickers: tickers, quotes: quotes);
  }

  /// tickers 表总条数
  Future<int> getTickerCount() async {
    try {
      final db = await _getDb();
      final r = await db.rawQuery('SELECT COUNT(*) as c FROM tickers');
      return (r.first['c'] as int?) ?? 0;
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb getTickerCount: $e');
      return 0;
    }
  }

  /// 返回尚未写入 quotes 的 ticker symbols（用于首轮补齐缺失行情）
  Future<List<String>> getTickerSymbolsMissingQuotes({int limit = 200}) async {
    try {
      final db = await _getDb();
      final rows = await db.rawQuery('''
        SELECT t.symbol
        FROM tickers t
        LEFT JOIN quotes q ON t.symbol = q.symbol
        WHERE q.symbol IS NULL
        ORDER BY t.symbol ASC
        LIMIT ?
      ''', [limit]);
      return rows
          .map((e) => (e['symbol'] as String?)?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb getTickerSymbolsMissingQuotes: $e');
      return [];
    }
  }

  /// 返回最久未刷新的 symbols（用于后台异步刷新“最新数据”）
  Future<List<String>> getOldestQuoteSymbols({int limit = 200}) async {
    try {
      final db = await _getDb();
      final rows = await db.rawQuery('''
        SELECT t.symbol
        FROM tickers t
        LEFT JOIN quotes q ON t.symbol = q.symbol
        ORDER BY COALESCE(q.updated_at_ms, 0) ASC, t.symbol ASC
        LIMIT ?
      ''', [limit]);
      return rows
          .map((e) => (e['symbol'] as String?)?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('MarketDb getOldestQuoteSymbols: $e');
      return [];
    }
  }

  /// 分页获取 tickers + 对应 quotes（用于避免一次性加载过多导致 UI 卡顿）
  Future<({List<MarketSearchResult> tickers, Map<String, MarketQuote> quotes})> getTickersAndQuotesPage({
    String? sortColumn,
    bool sortAscending = false,
    required int limit,
    int offset = 0,
  }) async {
    final tickers = await getTickersWithQuotes(
      sortColumn: sortColumn,
      sortAscending: sortAscending,
      limit: limit,
      offset: offset,
    );
    if (tickers.isEmpty) return (tickers: <MarketSearchResult>[], quotes: <String, MarketQuote>{});
    final symbols = tickers.map((t) => t.symbol).toList();
    final quotes = await getQuotes(symbols);
    return (tickers: tickers, quotes: quotes);
  }

  Future<void> close() async {
    for (final c in _tickersControllers.values) {
      await c.close();
    }
    for (final c in _quotesControllers.values) {
      await c.close();
    }
    _tickersControllers.clear();
    _quotesControllers.clear();
    await _db?.close();
    _db = null;
  }
}
