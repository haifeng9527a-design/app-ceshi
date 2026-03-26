import 'polygon_repository.dart';
import 'twelve_data_repository.dart';

/// 仅用于与 seed SQL（market_snapshots_seed_mock.sql）对齐参考；
/// App 不在此读取假数据，只从接口拿最新数据或从数据库/本地缓存展示。
class MockMarketData {
  MockMarketData._();

  /// 指数：(name, symbol) -> 用于概况 Tab
  static const indices = [
    ('道琼斯', 'DJI'),
    ('标普500', 'SPX'),
    ('纳斯达克', 'NDX'),
    ('恒生指数', 'HSI'),
    ('日经225', 'N225'),
  ];

  /// 外汇
  static const forex = [
    ('欧元/美元', 'EUR/USD'),
    ('美元/日元', 'USD/JPY'),
    ('英镑/美元', 'GBP/USD'),
    ('澳元/美元', 'AUD/USD'),
    ('美元/瑞郎', 'USD/CHF'),
    ('美元/加元', 'USD/CAD'),
  ];

  /// 加密货币
  static const crypto = [
    ('比特币', 'BTC/USD'),
    ('以太坊', 'ETH/USD'),
    ('Solana', 'SOL/USD'),
    ('瑞波币', 'XRP/USD'),
    ('狗狗币', 'DOGE/USD'),
    ('雪崩', 'AVAX/USD'),
  ];

  /// 假报价：指数（close, change, percent_change），与首页主要指数 DJI/SPX/IXIC/VIX/RUT 对齐
  static List<Map<String, dynamic>> get indicesQuotes => [
    {'symbol': 'DJI', 'name': '道琼斯', 'close': 39220.0, 'change': 120.5, 'percent_change': 0.31},
    {'symbol': 'SPX', 'name': '标普500', 'close': 5120.0, 'change': 15.2, 'percent_change': 0.30},
    {'symbol': 'IXIC', 'name': '纳斯达克', 'close': 16500.0, 'change': 85.0, 'percent_change': 0.52},
    {'symbol': 'VIX', 'name': 'VIX', 'close': 13.2, 'change': -0.3, 'percent_change': -2.22},
    {'symbol': 'RUT', 'name': 'Russell 2000', 'close': 2080.0, 'change': 8.5, 'percent_change': 0.41},
    {'symbol': 'NDX', 'name': '纳斯达克', 'close': 17680.0, 'change': 85.0, 'percent_change': 0.48},
    {'symbol': 'HSI', 'name': '恒生指数', 'close': 16520.0, 'change': -120.0, 'percent_change': -0.72},
    {'symbol': 'N225', 'name': '日经225', 'close': 38200.0, 'change': 200.0, 'percent_change': 0.53},
  ];

  static List<Map<String, dynamic>> get forexQuotes => [
    {'symbol': 'EUR/USD', 'name': '欧元/美元', 'close': 1.0856, 'change': 0.0012, 'percent_change': 0.11},
    {'symbol': 'USD/JPY', 'name': '美元/日元', 'close': 149.85, 'change': -0.32, 'percent_change': -0.21},
    {'symbol': 'GBP/USD', 'name': '英镑/美元', 'close': 1.2680, 'change': 0.0020, 'percent_change': 0.16},
    {'symbol': 'AUD/USD', 'name': '澳元/美元', 'close': 0.6520, 'change': -0.0010, 'percent_change': -0.15},
    {'symbol': 'USD/CHF', 'name': '美元/瑞郎', 'close': 0.8780, 'change': 0.0005, 'percent_change': 0.06},
    {'symbol': 'USD/CAD', 'name': '美元/加元', 'close': 1.3520, 'change': -0.0020, 'percent_change': -0.15},
  ];

  static List<Map<String, dynamic>> get cryptoQuotes => [
    {'symbol': 'BTC/USD', 'name': '比特币', 'close': 43250.0, 'change': 850.0, 'percent_change': 2.01},
    {'symbol': 'ETH/USD', 'name': '以太坊', 'close': 2280.0, 'change': 45.0, 'percent_change': 2.01},
    {'symbol': 'SOL/USD', 'name': 'Solana', 'close': 98.50, 'change': 3.20, 'percent_change': 3.36},
    {'symbol': 'XRP/USD', 'name': '瑞波币', 'close': 0.5250, 'change': -0.0120, 'percent_change': -2.24},
    {'symbol': 'DOGE/USD', 'name': '狗狗币', 'close': 0.0820, 'change': 0.0015, 'percent_change': 1.86},
    {'symbol': 'AVAX/USD', 'name': '雪崩', 'close': 36.80, 'change': 0.90, 'percent_change': 2.51},
  ];

  /// 将快照列表转为 symbol -> TwelveDataQuote 的 Map（用于填充 _quotes）
  static Map<String, TwelveDataQuote?> quotesFromSnapshotList(
    List<Map<String, dynamic>> list,
  ) {
    final out = <String, TwelveDataQuote?>{};
    for (final m in list) {
      final q = TwelveDataQuote.fromSnapshotMap(m);
      if (q != null) out[q.symbol] = q;
    }
    return out;
  }

  /// 领涨假数据（Polygon 格式，含 day o/h/l/c/v、prevDay.c，无 API 时展示并标注「模拟数据」）
  static List<Map<String, dynamic>> get rawMockGainers => [
    _gainer('NVDA', 458.20, 18.5, 4.2, 52000000),
    _gainer('AAPL', 195.80, 4.2, 2.1, 48000000),
    _gainer('TSLA', 224.50, 12.3, 5.8, 95000000),
    _gainer('MSFT', 378.20, 6.8, 1.8, 22000000),
    _gainer('META', 489.50, 15.2, 3.2, 18000000),
    _gainer('GOOGL', 142.50, 3.2, 2.3, 28000000),
    _gainer('AMZN', 178.90, 5.1, 2.9, 45000000),
    _gainer('ABTS', 3.73, 1.82, 90.99, 3940000),
    _gainer('NCI', 5.95, 3.62, 80.63, 5600000),
    _gainer('RNG', 39.50, 10.33, 35.16, 14000000),
  ];

  /// 领跌假数据
  static List<Map<String, dynamic>> get rawMockLosers => [
    _gainer('INTC', 33.20, -1.2, -3.5, 62000000),
    _gainer('AMD', 156.80, -4.5, -2.8, 45000000),
    _gainer('NFLX', 422.50, -8.2, -1.9, 5200000),
    _gainer('PYPL', 56.00, -1.4, -2.5, 18000000),
    _gainer('COIN', 200.50, -8.8, -4.2, 12000000),
    _gainer('SHOP', 62.30, -2.1, -3.3, 8500000),
    _gainer('SQ', 58.40, -1.8, -3.0, 12000000),
    _gainer('UBER', 68.20, -2.2, -3.1, 15000000),
    _gainer('ABNB', 132.50, -4.0, -2.9, 4200000),
    _gainer('SNOW', 142.00, -5.2, -3.5, 6800000),
  ];

  static Map<String, dynamic> _gainer(
    String ticker,
    double close,
    double change,
    double changePerc,
    int volume,
  ) {
    final prev = close - change;
    final o = prev;
    final h = close > prev ? close + 0.5 : prev + 0.3;
    final l = close < prev ? close - 0.3 : prev - 0.2;
    return {
      'ticker': ticker,
      'todaysChangePerc': changePerc,
      'todaysChange': change,
      'day': {'o': o, 'h': h, 'l': l, 'c': close, 'v': volume},
      'prevDay': {'c': prev},
    };
  }

  static List<PolygonGainer> get mockGainers {
    return rawMockGainers
        .map((e) => PolygonGainer.fromJson(e))
        .whereType<PolygonGainer>()
        .toList();
  }

  static List<PolygonGainer> get mockLosers {
    return rawMockLosers
        .map((e) => PolygonGainer.fromJson(e))
        .whereType<PolygonGainer>()
        .toList();
  }
}
