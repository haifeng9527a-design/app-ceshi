/// 行情页使用的数据模型（指数/外汇/债券/加密货币等）
/// 真实数据来自 Polygon API

class MarketQuote {
  const MarketQuote({
    required this.name,
    required this.symbol,
    required this.value,
    required this.change,
    required this.changePct,
    this.sparkline,
  });

  final String name;
  final String symbol;
  final double value;
  final double change;
  final double changePct;
  /// 用于迷你折线图，如 [v1, v2, ...]
  final List<double>? sparkline;

  bool get isUp => change >= 0;
}

class MarketGainer {
  const MarketGainer({
    required this.rank,
    required this.name,
    required this.symbol,
    required this.price,
    required this.changePct,
  });

  final int rank;
  final String name;
  final String symbol;
  final double price;
  final double changePct;
}
