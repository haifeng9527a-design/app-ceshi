import 'dart:convert';

import '../../core/api_client.dart';
import '../teachers/teacher_models.dart';
import 'trading_models.dart';

class TradingApiClient {
  TradingApiClient._();
  static final TradingApiClient instance = TradingApiClient._();

  final ApiClient _api = ApiClient.instance;

  Future<List<Order>> getOpenOrders({int page = 1, int pageSize = 100}) async {
    final resp = await _api.get(
      'api/trading/orders/open',
      queryParameters: {'page': '$page', 'page_size': '$pageSize'},
      timeout: const Duration(seconds: 15),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '加载当日委托失败'));
    }
    final body = jsonDecode(resp.body);
    if (body is! List) return const [];
    return body.whereType<Map<String, dynamic>>().map(_toOrder).toList();
  }

  Future<List<Order>> getHistoryOrders({int page = 1, int pageSize = 200}) async {
    final resp = await _api.get(
      'api/trading/orders/history',
      queryParameters: {'page': '$page', 'page_size': '$pageSize'},
      timeout: const Duration(seconds: 15),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '加载历史委托失败'));
    }
    final body = jsonDecode(resp.body);
    if (body is! List) return const [];
    return body.whereType<Map<String, dynamic>>().map(_toOrder).toList();
  }

  Future<void> cancelOrder(String orderId) async {
    final resp = await _api.post(
      'api/trading/orders/$orderId/cancel',
      timeout: const Duration(seconds: 15),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '撤单失败'));
    }
  }

  Future<Order> placeOrder({
    required String symbol,
    required OrderSide side,
    required OrderType type,
    required double quantity,
    double? limitPrice,
    String? assetClass,
    ProductType productType = ProductType.spot,
    PositionSide positionSide = PositionSide.long,
    String positionAction = 'open',
    MarginMode marginMode = MarginMode.cross,
    double leverage = 1,
    double contractSize = 1,
    double multiplier = 1,
    String settlementAsset = 'USD',
  }) async {
    final payload = <String, dynamic>{
      'symbol': symbol.trim().toUpperCase(),
      'side': side == OrderSide.buy ? 'buy' : 'sell',
      'order_type': type == OrderType.limit ? 'limit' : 'market',
      'quantity': quantity,
      if (assetClass != null) 'asset_class': assetClass,
      'product_type': switch (productType) {
        ProductType.spot => 'spot',
        ProductType.perpetual => 'perpetual',
        ProductType.future => 'future',
      },
      'position_side': positionSide == PositionSide.short ? 'short' : 'long',
      'position_action': positionAction,
      'margin_mode': marginMode == MarginMode.isolated ? 'isolated' : 'cross',
      'leverage': leverage,
      'contract_size': contractSize,
      'multiplier': multiplier,
      'settlement_asset': settlementAsset,
      if (type == OrderType.limit) 'limit_price': limitPrice,
    };
    final resp = await _api.post(
      'api/trading/orders',
      body: payload,
      timeout: const Duration(seconds: 20),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '下单失败'));
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('下单响应格式错误');
    }
    return _toOrder(body);
  }

  Future<List<OrderFill>> getFills({int page = 1, int pageSize = 100}) async {
    final resp = await _api.get(
      'api/trading/fills',
      queryParameters: {'page': '$page', 'page_size': '$pageSize'},
      timeout: const Duration(seconds: 15),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '加载成交记录失败'));
    }
    final body = jsonDecode(resp.body);
    if (body is! List) return const [];
    return body.whereType<Map<String, dynamic>>().map(_toFill).toList();
  }

  Future<List<TeacherPosition>> getPositions({int page = 1, int pageSize = 50}) async {
    final resp = await _api.get(
      'api/trading/positions',
      queryParameters: {'page': '$page', 'page_size': '$pageSize'},
      timeout: const Duration(seconds: 15),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '加载持仓失败'));
    }
    final body = jsonDecode(resp.body);
    if (body is! List) return const [];
    return body.whereType<Map<String, dynamic>>().map(TeacherPosition.fromMap).toList();
  }

  Future<TradingAccountSummary> getSummary() async {
    final resp = await _api.get(
      'api/trading/summary',
      timeout: const Duration(seconds: 15),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '加载账户摘要失败'));
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('账户摘要格式错误');
    }
    return TradingAccountSummary.fromJson(body);
  }

  Future<TradingRuntimeConfig> getRuntimeConfig() async {
    final resp = await _api.get(
      'api/trading/runtime-config',
      timeout: const Duration(seconds: 15),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '加载交易配置失败'));
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('交易配置格式错误');
    }
    return TradingRuntimeConfig.fromJson(body);
  }

  Future<TradingAccount> getAccount() async {
    final resp = await _api.get(
      'api/trading/account',
      timeout: const Duration(seconds: 15),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '加载交易账户失败'));
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('交易账户响应格式错误');
    }
    return TradingAccount.fromJson(body);
  }

  Future<List<TradingLedgerEntry>> getLedger({int page = 1, int pageSize = 200}) async {
    final resp = await _api.get(
      'api/trading/ledger',
      queryParameters: {'page': '$page', 'page_size': '$pageSize'},
      timeout: const Duration(seconds: 15),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '加载账户流水失败'));
    }
    final body = jsonDecode(resp.body);
    if (body is! List) return const [];
    return body.whereType<Map<String, dynamic>>().map(TradingLedgerEntry.fromJson).toList();
  }

  static String _extractError(String body, {required String fallback}) {
    try {
      final m = jsonDecode(body);
      if (m is Map<String, dynamic>) {
        final s = m['error']?.toString().trim();
        if (s != null && s.isNotEmpty) return s;
      }
    } catch (_) {}
    return fallback;
  }

  static Order _toOrder(Map<String, dynamic> m) {
    final sideRaw = (m['side'] ?? '').toString().toLowerCase();
    final typeRaw = (m['order_type'] ?? '').toString().toLowerCase();
    final statusRaw = (m['status'] ?? '').toString().toLowerCase();
    final productTypeRaw = (m['product_type'] ?? '').toString().toLowerCase();
    final positionSideRaw = (m['position_side'] ?? '').toString().toLowerCase();
    final marginModeRaw = (m['margin_mode'] ?? '').toString().toLowerCase();
    return Order(
      id: (m['id'] ?? '').toString(),
      symbol: (m['symbol'] ?? '').toString(),
      symbolName: m['symbol_name']?.toString(),
      assetClass: m['asset_class']?.toString(),
      productType: productTypeRaw == 'future'
          ? ProductType.future
          : productTypeRaw == 'perpetual'
              ? ProductType.perpetual
              : ProductType.spot,
      positionSide: positionSideRaw == 'short'
          ? PositionSide.short
          : PositionSide.long,
      positionAction: m['position_action']?.toString(),
      marginMode: marginModeRaw == 'isolated'
          ? MarginMode.isolated
          : MarginMode.cross,
      leverage: (m['leverage'] as num?)?.toDouble() ?? 1,
      side: sideRaw == 'sell' ? OrderSide.sell : OrderSide.buy,
      type: typeRaw == 'market' ? OrderType.market : OrderType.limit,
      price: ((m['limit_price'] ?? m['price']) as num?)?.toDouble() ?? 0,
      quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
      filledQuantity: (m['filled_quantity'] as num?)?.toDouble() ?? 0,
      status: _toOrderStatus(statusRaw),
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()) ?? DateTime.now(),
      updatedAt: DateTime.tryParse((m['updated_at'] ?? '').toString()),
    );
  }

  static OrderFill _toFill(Map<String, dynamic> m) {
    final sideRaw = (m['side'] ?? '').toString().toLowerCase();
    final productTypeRaw = (m['product_type'] ?? '').toString().toLowerCase();
    final positionSideRaw = (m['position_side'] ?? '').toString().toLowerCase();
    final marginModeRaw = (m['margin_mode'] ?? '').toString().toLowerCase();
    final realizedPnlRaw = m['realized_pnl'];
    return OrderFill(
      id: (m['id'] ?? '').toString(),
      orderId: (m['order_id'] ?? '').toString(),
      symbol: (m['symbol'] ?? '').toString(),
      symbolName: null,
      assetClass: m['asset_class']?.toString(),
      productType: productTypeRaw == 'future'
          ? ProductType.future
          : productTypeRaw == 'perpetual'
              ? ProductType.perpetual
              : ProductType.spot,
      positionSide: positionSideRaw == 'short'
          ? PositionSide.short
          : PositionSide.long,
      marginMode: marginModeRaw == 'isolated'
          ? MarginMode.isolated
          : MarginMode.cross,
      leverage: (m['leverage'] as num?)?.toDouble() ?? 1,
      side: sideRaw == 'sell' ? OrderSide.sell : OrderSide.buy,
      price: (m['fill_price'] as num?)?.toDouble() ?? 0,
      quantity: (m['fill_quantity'] as num?)?.toDouble() ?? 0,
      notional: (m['fill_notional'] as num?)?.toDouble() ?? 0,
      realizedPnl: realizedPnlRaw != null ? (realizedPnlRaw as num).toDouble() : null,
      filledAt: DateTime.tryParse((m['fill_time'] ?? '').toString()) ?? DateTime.now(),
    );
  }

  static OrderStatus _toOrderStatus(String v) {
    switch (v) {
      case 'pending':
        return OrderStatus.pending;
      case 'partial':
        return OrderStatus.partial;
      case 'filled':
        return OrderStatus.filled;
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'rejected':
        return OrderStatus.rejected;
      default:
        return OrderStatus.pending;
    }
  }
}

class TradingAccountSummary {
  const TradingAccountSummary({
    required this.cashBalance,
    required this.cashAvailable,
    required this.cashFrozen,
    required this.marketValue,
    required this.equity,
    required this.usedMargin,
    required this.maintenanceMargin,
    required this.marginBalance,
    required this.accountType,
    required this.marginMode,
    required this.leverage,
    required this.openOrders,
    required this.positions,
  });

  final double cashBalance;
  final double cashAvailable;
  final double cashFrozen;
  final double marketValue;
  final double equity;
  final double usedMargin;
  final double maintenanceMargin;
  final double marginBalance;
  final String accountType;
  final String marginMode;
  final double leverage;
  final int openOrders;
  final int positions;

  factory TradingAccountSummary.fromJson(Map<String, dynamic> m) {
    final account = m['account'] is Map<String, dynamic>
        ? (m['account'] as Map<String, dynamic>)
        : const <String, dynamic>{};
    return TradingAccountSummary(
      cashBalance: (account['cash_balance'] as num?)?.toDouble() ?? 0,
      cashAvailable: (account['cash_available'] as num?)?.toDouble() ?? 0,
      cashFrozen: (account['cash_frozen'] as num?)?.toDouble() ?? 0,
      marketValue: (account['market_value'] as num?)?.toDouble() ?? 0,
      equity: (account['equity'] as num?)?.toDouble() ?? 0,
      usedMargin: (account['used_margin'] as num?)?.toDouble() ?? 0,
      maintenanceMargin: (account['maintenance_margin'] as num?)?.toDouble() ?? 0,
      marginBalance: (account['margin_balance'] as num?)?.toDouble() ?? 0,
      accountType: (account['account_type'] ?? 'spot').toString(),
      marginMode: (account['margin_mode'] ?? 'cross').toString(),
      leverage: (account['leverage'] as num?)?.toDouble() ?? 1,
      openOrders: (m['open_orders'] as num?)?.toInt() ?? 0,
      positions: (m['positions'] as num?)?.toInt() ?? 0,
    );
  }
}

class TradingRuntimeConfig {
  const TradingRuntimeConfig({
    required this.defaultInitialCashUsd,
    required this.defaultProductType,
    required this.defaultMarginMode,
    required this.defaultLeverage,
    required this.maxLeverage,
    required this.allowShort,
    required this.maintenanceMarginRate,
  });

  final double defaultInitialCashUsd;
  final ProductType defaultProductType;
  final MarginMode defaultMarginMode;
  final double defaultLeverage;
  final double maxLeverage;
  final bool allowShort;
  final double maintenanceMarginRate;

  factory TradingRuntimeConfig.fromJson(Map<String, dynamic> m) {
    final product = (m['default_product_type'] ?? 'spot').toString().toLowerCase();
    final margin = (m['default_margin_mode'] ?? 'cross').toString().toLowerCase();
    return TradingRuntimeConfig(
      defaultInitialCashUsd: (m['default_initial_cash_usd'] as num?)?.toDouble() ?? 1000000,
      defaultProductType: product == 'future'
          ? ProductType.future
          : product == 'perpetual'
              ? ProductType.perpetual
              : ProductType.spot,
      defaultMarginMode: margin == 'isolated'
          ? MarginMode.isolated
          : MarginMode.cross,
      defaultLeverage: (m['default_leverage'] as num?)?.toDouble() ?? 5,
      maxLeverage: (m['max_leverage'] as num?)?.toDouble() ?? 50,
      allowShort: m['allow_short'] == true ||
          '${m['allow_short']}'.toLowerCase() == 'true',
      maintenanceMarginRate:
          (m['maintenance_margin_rate'] as num?)?.toDouble() ?? 0.005,
    );
  }
}

class TradingAccount {
  const TradingAccount({
    this.currency = 'USD',
    required this.cashBalance,
    required this.cashAvailable,
    required this.cashFrozen,
    required this.marketValue,
    this.spotMarketValue = 0,
    this.contractNotional = 0,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.equity,
    required this.usedMargin,
    required this.maintenanceMargin,
    required this.marginBalance,
    required this.accountType,
    required this.marginMode,
    required this.leverage,
    required this.todayPnl,
    required this.todayPnlPct,
    required this.availablePct,
    required this.marketPct,
    this.spotMarketPct = 0,
    this.marginPct = 0,
    required this.frozenPct,
  });

  /// 结算货币，用于金额后缀显示 USD / USDT
  final String currency;
  final double cashBalance;
  final double cashAvailable;
  final double cashFrozen;
  final double marketValue;
  /// 现货持仓市值（不含合约名义价值）
  final double spotMarketValue;
  /// 合约持仓名义价值
  final double contractNotional;
  final double realizedPnl;
  final double unrealizedPnl;
  final double equity;
  final double usedMargin;
  final double maintenanceMargin;
  final double marginBalance;
  final String accountType;
  final String marginMode;
  final double leverage;
  final double todayPnl;
  final double todayPnlPct;
  final double availablePct;
  final double marketPct;
  final double spotMarketPct;
  final double marginPct;
  final double frozenPct;

  factory TradingAccount.fromJson(Map<String, dynamic> m) {
    return TradingAccount(
      currency: (m['currency'] ?? 'USD').toString().toUpperCase(),
      cashBalance: (m['cash_balance'] as num?)?.toDouble() ?? 0,
      cashAvailable: (m['cash_available'] as num?)?.toDouble() ?? 0,
      cashFrozen: (m['cash_frozen'] as num?)?.toDouble() ?? 0,
      marketValue: (m['market_value'] as num?)?.toDouble() ?? 0,
      spotMarketValue: (m['spot_market_value'] as num?)?.toDouble() ?? 0,
      contractNotional: (m['contract_notional'] as num?)?.toDouble() ?? 0,
      realizedPnl: (m['realized_pnl'] as num?)?.toDouble() ?? 0,
      unrealizedPnl: (m['unrealized_pnl'] as num?)?.toDouble() ?? 0,
      equity: (m['equity'] as num?)?.toDouble() ?? 0,
      usedMargin: (m['used_margin'] as num?)?.toDouble() ?? 0,
      maintenanceMargin: (m['maintenance_margin'] as num?)?.toDouble() ?? 0,
      marginBalance: (m['margin_balance'] as num?)?.toDouble() ?? 0,
      accountType: (m['account_type'] ?? 'spot').toString(),
      marginMode: (m['margin_mode'] ?? 'cross').toString(),
      leverage: (m['leverage'] as num?)?.toDouble() ?? 1,
      todayPnl: (m['today_pnl'] as num?)?.toDouble() ?? 0,
      todayPnlPct: (m['today_pnl_pct'] as num?)?.toDouble() ?? 0,
      availablePct: (m['available_pct'] as num?)?.toDouble() ?? 0,
      marketPct: (m['market_pct'] as num?)?.toDouble() ?? 0,
      spotMarketPct: (m['spot_market_pct'] as num?)?.toDouble() ?? 0,
      marginPct: (m['margin_pct'] as num?)?.toDouble() ?? 0,
      frozenPct: (m['frozen_pct'] as num?)?.toDouble() ?? 0,
    );
  }
}

class TradingLedgerEntry {
  const TradingLedgerEntry({
    required this.id,
    required this.entryType,
    required this.amount,
    required this.balanceAfter,
    required this.createdAt,
    this.orderId,
    this.symbol,
    this.assetClass,
    this.productType = ProductType.spot,
    this.side,
    this.positionSide = PositionSide.long,
    this.note,
  });

  final String id;
  final String entryType;
  final double amount;
  final double balanceAfter;
  final DateTime createdAt;
  final String? orderId;
  final String? symbol;
  final String? assetClass;
  final ProductType productType;
  final String? side;
  final PositionSide positionSide;
  final String? note;

  factory TradingLedgerEntry.fromJson(Map<String, dynamic> m) {
    final productTypeRaw = (m['product_type'] ?? '').toString().toLowerCase();
    final positionSideRaw = (m['position_side'] ?? '').toString().toLowerCase();
    return TradingLedgerEntry(
      id: (m['id'] ?? '').toString(),
      entryType: (m['entry_type'] ?? '').toString(),
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      balanceAfter: (m['balance_after'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()) ?? DateTime.now(),
      orderId: m['order_id']?.toString(),
      symbol: m['symbol']?.toString(),
      assetClass: m['asset_class']?.toString(),
      productType: productTypeRaw == 'future'
          ? ProductType.future
          : productTypeRaw == 'perpetual'
              ? ProductType.perpetual
              : ProductType.spot,
      side: m['side']?.toString(),
      positionSide: positionSideRaw == 'short'
          ? PositionSide.short
          : PositionSide.long,
      note: m['note']?.toString(),
    );
  }
}
