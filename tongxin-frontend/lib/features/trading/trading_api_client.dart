import 'dart:convert';

import '../../core/api_client.dart';
import '../teachers/teacher_models.dart';
import 'trading_models.dart';

class TradingApiClient {
  TradingApiClient._();
  static final TradingApiClient instance = TradingApiClient._();

  final ApiClient _api = ApiClient.instance;

  Future<List<Order>> getOpenOrders() async {
    final resp = await _api.get(
      'api/trading/orders/open',
      timeout: const Duration(seconds: 15),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '加载当日委托失败'));
    }
    final body = jsonDecode(resp.body);
    if (body is! List) return const [];
    return body.whereType<Map<String, dynamic>>().map(_toOrder).toList();
  }

  Future<List<Order>> getHistoryOrders({int limit = 200}) async {
    final resp = await _api.get(
      'api/trading/orders/history',
      queryParameters: {'limit': '$limit'},
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
  }) async {
    final payload = <String, dynamic>{
      'symbol': symbol.trim().toUpperCase(),
      'side': side == OrderSide.buy ? 'buy' : 'sell',
      'order_type': type == OrderType.limit ? 'limit' : 'market',
      'quantity': quantity,
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

  Future<List<OrderFill>> getFills({int limit = 100}) async {
    final resp = await _api.get(
      'api/trading/fills',
      queryParameters: {'limit': '$limit'},
      timeout: const Duration(seconds: 15),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_extractError(resp.body, fallback: '加载成交记录失败'));
    }
    final body = jsonDecode(resp.body);
    if (body is! List) return const [];
    return body.whereType<Map<String, dynamic>>().map(_toFill).toList();
  }

  Future<List<TeacherPosition>> getPositions() async {
    final resp = await _api.get(
      'api/trading/positions',
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

  Future<List<TradingLedgerEntry>> getLedger({int limit = 200}) async {
    final resp = await _api.get(
      'api/trading/ledger',
      queryParameters: {'limit': '$limit'},
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
    return Order(
      id: (m['id'] ?? '').toString(),
      symbol: (m['symbol'] ?? '').toString(),
      symbolName: m['symbol_name']?.toString(),
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
    return OrderFill(
      id: (m['id'] ?? '').toString(),
      orderId: (m['order_id'] ?? '').toString(),
      symbol: (m['symbol'] ?? '').toString(),
      symbolName: null,
      side: sideRaw == 'sell' ? OrderSide.sell : OrderSide.buy,
      price: (m['fill_price'] as num?)?.toDouble() ?? 0,
      quantity: (m['fill_quantity'] as num?)?.toDouble() ?? 0,
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
    required this.openOrders,
    required this.positions,
  });

  final double cashBalance;
  final double cashAvailable;
  final double cashFrozen;
  final double marketValue;
  final double equity;
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
      openOrders: (m['open_orders'] as num?)?.toInt() ?? 0,
      positions: (m['positions'] as num?)?.toInt() ?? 0,
    );
  }
}

class TradingAccount {
  const TradingAccount({
    required this.cashBalance,
    required this.cashAvailable,
    required this.cashFrozen,
    required this.marketValue,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.equity,
  });

  final double cashBalance;
  final double cashAvailable;
  final double cashFrozen;
  final double marketValue;
  final double realizedPnl;
  final double unrealizedPnl;
  final double equity;

  factory TradingAccount.fromJson(Map<String, dynamic> m) {
    return TradingAccount(
      cashBalance: (m['cash_balance'] as num?)?.toDouble() ?? 0,
      cashAvailable: (m['cash_available'] as num?)?.toDouble() ?? 0,
      cashFrozen: (m['cash_frozen'] as num?)?.toDouble() ?? 0,
      marketValue: (m['market_value'] as num?)?.toDouble() ?? 0,
      realizedPnl: (m['realized_pnl'] as num?)?.toDouble() ?? 0,
      unrealizedPnl: (m['unrealized_pnl'] as num?)?.toDouble() ?? 0,
      equity: (m['equity'] as num?)?.toDouble() ?? 0,
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
    this.side,
    this.note,
  });

  final String id;
  final String entryType;
  final double amount;
  final double balanceAfter;
  final DateTime createdAt;
  final String? orderId;
  final String? symbol;
  final String? side;
  final String? note;

  factory TradingLedgerEntry.fromJson(Map<String, dynamic> m) {
    return TradingLedgerEntry(
      id: (m['id'] ?? '').toString(),
      entryType: (m['entry_type'] ?? '').toString(),
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      balanceAfter: (m['balance_after'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse((m['created_at'] ?? '').toString()) ?? DateTime.now(),
      orderId: m['order_id']?.toString(),
      symbol: m['symbol']?.toString(),
      side: m['side']?.toString(),
      note: m['note']?.toString(),
    );
  }
}
