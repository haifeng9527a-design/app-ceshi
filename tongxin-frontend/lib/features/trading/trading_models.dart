/// 本地交易记录模型（用于统计：买入时机、买入价格、卖出时间等）
/// 后续接入数据源 API 时可与此结构对齐或扩展
class LocalTradeRecord {
  const LocalTradeRecord({
    required this.id,
    required this.symbol,
    required this.stockName,
    required this.buyTime,
    required this.buyPrice,
    required this.buyQty,
    required this.sellTime,
    required this.sellPrice,
    required this.sellQty,
  });

  final String id;
  /// 股票/品种代码
  final String symbol;
  /// 股票名称（可选，便于展示）
  final String stockName;
  /// 买入时机（时间）
  final DateTime buyTime;
  /// 买入价格
  final double buyPrice;
  /// 买入数量（股/手）
  final double buyQty;
  /// 卖出时间
  final DateTime sellTime;
  /// 卖出价格
  final double sellPrice;
  /// 卖出数量（股/手）
  final double sellQty;

  /// 盈亏金额：(卖出价 - 买入价) * 数量（简化，未考虑手续费等）
  double get pnlAmount =>
      (sellPrice - buyPrice) * sellQty;

  /// 盈亏比例（%）
  double get pnlRatioPercent =>
      buyPrice > 0 ? ((sellPrice - buyPrice) / buyPrice * 100) : 0;

  /// 从服务端 TradeRecord 转成本地展示用（需 teacher_models.TradeRecord 有完整买卖字段）
  factory LocalTradeRecord.fromTradeRecord(
    String id,
    String symbol,
    String stockName,
    DateTime? buyTime,
    double? buyPrice,
    double? buyQty,
    DateTime? sellTime,
    double? sellPrice,
    double? sellQty,
  ) {
    final buy = buyTime ?? DateTime.now();
    final sell = sellTime ?? DateTime.now();
    final bp = buyPrice ?? 0.0;
    final sp = sellPrice ?? 0.0;
    final bq = buyQty ?? 0.0;
    final sq = sellQty ?? 0.0;
    return LocalTradeRecord(
      id: id,
      symbol: symbol,
      stockName: stockName,
      buyTime: buy,
      buyPrice: bp,
      buyQty: bq,
      sellTime: sell,
      sellPrice: sp,
      sellQty: sq,
    );
  }

  LocalTradeRecord copyWith({
    String? id,
    String? symbol,
    String? stockName,
    DateTime? buyTime,
    double? buyPrice,
    double? buyQty,
    DateTime? sellTime,
    double? sellPrice,
    double? sellQty,
  }) {
    return LocalTradeRecord(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      stockName: stockName ?? this.stockName,
      buyTime: buyTime ?? this.buyTime,
      buyPrice: buyPrice ?? this.buyPrice,
      buyQty: buyQty ?? this.buyQty,
      sellTime: sellTime ?? this.sellTime,
      sellPrice: sellPrice ?? this.sellPrice,
      sellQty: sellQty ?? this.sellQty,
    );
  }
}

/// 委托单（订单）状态
enum OrderStatus {
  pending,   // 待报/待成交
  partial,   // 部分成交
  filled,    // 全部成交
  cancelled, // 已撤单
  rejected,  // 已拒绝
}

/// 委托类型
enum OrderType {
  limit,  // 限价
  market, // 市价
}

/// 委托方向
enum OrderSide {
  buy,
  sell,
}

enum ProductType {
  spot,
  perpetual,
  future,
}

enum TradingAccountType {
  spot,
  contract,
}

extension TradingAccountTypeX on TradingAccountType {
  String get wireValue => this == TradingAccountType.contract ? 'contract' : 'spot';
}

TradingAccountType tradingAccountTypeFromWire(String? value) {
  return (value ?? '').toLowerCase() == 'contract'
      ? TradingAccountType.contract
      : TradingAccountType.spot;
}

extension ProductTypeTradingAccountX on ProductType {
  TradingAccountType get tradingAccountType =>
      this == ProductType.spot ? TradingAccountType.spot : TradingAccountType.contract;
}

enum PositionSide {
  long,
  short,
}

enum MarginMode {
  cross,
  isolated,
}

/// 委托单模型（先本地/模拟，后续对接交易 API）
class Order {
  const Order({
    required this.id,
    required this.symbol,
    this.symbolName,
    this.assetClass,
    this.productType = ProductType.spot,
    this.positionSide = PositionSide.long,
    this.positionAction,
    this.marginMode = MarginMode.cross,
    this.leverage = 1,
    required this.side,
    required this.type,
    required this.price,
    required this.quantity,
    this.filledQuantity = 0,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String symbol;
  final String? symbolName;
  final String? assetClass;
  final ProductType productType;
  final PositionSide positionSide;
  final String? positionAction;
  final MarginMode marginMode;
  final double leverage;
  final OrderSide side;
  final OrderType type;
  /// 限价单价格；市价单可为 0
  final double price;
  final double quantity;
  final double filledQuantity;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isBuy => side == OrderSide.buy;
  bool get canCancel =>
      status == OrderStatus.pending || status == OrderStatus.partial;
}

/// 成交记录（单笔成交）
class OrderFill {
  const OrderFill({
    required this.id,
    required this.orderId,
    required this.symbol,
    this.symbolName,
    this.assetClass,
    this.productType = ProductType.spot,
    this.positionSide = PositionSide.long,
    this.marginMode = MarginMode.cross,
    this.leverage = 1,
    required this.side,
    required this.price,
    required this.quantity,
    this.notional = 0,
    this.realizedPnl,
    required this.filledAt,
  });

  final String id;
  final String orderId;
  final String symbol;
  final String? symbolName;
  final String? assetClass;
  final ProductType productType;
  final PositionSide positionSide;
  final MarginMode marginMode;
  final double leverage;
  final OrderSide side;
  final double price;
  final double quantity;
  final double notional;
  /// 平仓成交时的已实现盈亏，开仓为 null
  final double? realizedPnl;
  final DateTime filledAt;

  bool get isBuy => side == OrderSide.buy;
}
