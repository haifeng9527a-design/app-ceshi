import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'trading_api_client.dart';
import 'trading_models.dart';
import 'trading_ui.dart';

/// 当日委托 Tab：委托列表（标的、方向、委托价/量、已成交、状态、时间、撤单）
/// 数据先 mock，接口就绪后替换为 API
class OrdersTab extends StatefulWidget {
  const OrdersTab({
    super.key,
    required this.teacherId,
    required this.accountType,
    this.isActive = false,
  });

  final String teacherId;
  final TradingAccountType accountType;
  final bool isActive;

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  final _api = TradingApiClient.instance;
  final _scrollController = ScrollController();
  static const int _pageSize = 5;
  List<Order> _orders = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  bool _actioning = false;
  TradingAccountSummary? _summary;
  late final DateFormat _timeFmt;
  Timer? _refreshTimer;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _timeFmt = DateFormat('HH:mm');
    _scrollController.addListener(_onScroll);
    _loadOrders(showLoading: true);
    _loadSummary();
    _syncPolling();
  }

  @override
  void didUpdateWidget(covariant OrdersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountType != widget.accountType) {
      _loadOrders(showLoading: true);
      _loadSummary();
    }
    if (oldWidget.isActive != widget.isActive) {
      _syncPolling();
    }
  }

  void _syncPolling() {
    _refreshTimer?.cancel();
    if (!widget.isActive) return;
    _refreshTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (!mounted) return;
      await _loadSummary();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 180) {
      _loadMore();
    }
  }

  Future<void> _loadSummary() async {
    try {
      final s = await _api.getSummary(accountType: widget.accountType);
      if (!mounted) return;
      setState(() => _summary = s);
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _api.getOpenOrders(
        page: 1,
        pageSize: _pageSize,
        accountType: widget.accountType,
      );
      if (!mounted) return;
      setState(() {
        _orders = list;
        _page = 1;
        _hasMore = list.length >= _pageSize;
        _loadingMore = false;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final list = await _api.getOpenOrders(
        page: nextPage,
        pageSize: _pageSize,
        accountType: widget.accountType,
      );
      if (!mounted) return;
      setState(() {
        if (list.isNotEmpty) {
          _orders = _appendUniqueOrders(_orders, list);
          _page = nextPage;
        }
        _hasMore = list.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = '$e';
      });
    }
  }

  List<Order> _appendUniqueOrders(List<Order> current, List<Order> incoming) {
    final existingIds = current.map((e) => e.id).toSet();
    final merged = [...current];
    for (final item in incoming) {
      if (existingIds.add(item.id)) {
        merged.add(item);
      }
    }
    return merged;
  }

  Future<void> _cancelOrder(Order order) async {
    if (!order.canCancel || _actioning) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.ordersConfirmCancel),
        content: Text(AppLocalizations.of(context)!.orderConfirmCancel(order.symbol, order.isBuy ? AppLocalizations.of(context)!.orderCancelBuy : AppLocalizations.of(context)!.orderCancelSell)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context)!.ordersConfirmCancel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actioning = true);
    try {
      await _api.cancelOrder(order.id);
      await _loadOrders();
      await _loadSummary();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.orderCancelSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _actioning = false);
    }
  }

  String _statusText(BuildContext context, OrderStatus s) {
    final l10n = AppLocalizations.of(context)!;
    switch (s) {
      case OrderStatus.pending:
        return l10n.ordersStatusPending;
      case OrderStatus.partial:
        return l10n.ordersStatusPartial;
      case OrderStatus.filled:
        return l10n.ordersStatusFilled;
      case OrderStatus.cancelled:
        return l10n.ordersStatusCancelled;
      case OrderStatus.rejected:
        return l10n.ordersStatusRejected;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _orders.where((o) => o.status == OrderStatus.pending).toList(growable: false);
    final partial = _orders.where((o) => o.status == OrderStatus.partial).toList(growable: false);
    final rest = _orders.where((o) => o.status != OrderStatus.pending && o.status != OrderStatus.partial).toList(growable: false);

    return TradingPageScaffold(
      child: RefreshIndicator(
        onRefresh: () async {
          await _loadOrders(showLoading: true);
          await _loadSummary();
        },
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            TradingSectionHeader(
              title: AppLocalizations.of(context)!.ordersTodayOrders,
              icon: Icons.pending_actions,
              trailing: IconButton(
                tooltip: AppLocalizations.of(context)!.adminRefresh,
                onPressed: _loading ? null : () => _loadOrders(showLoading: true),
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TradingSummaryStrip(summary: _summary),
            const SizedBox(height: 12),
            if (_loading)
              const TradingStateBlock.loading()
            else if (_error != null)
              TradingStateBlock.error(message: _error!)
            else if (_orders.isEmpty)
              TradingStateBlock.empty(
                message: AppLocalizations.of(context)!.ordersNoTodayOrders,
              )
            else ...[
              if (pending.isNotEmpty) ...[
                _GroupTitle(title: AppLocalizations.of(context)!.ordersStatusPending),
                ...pending.map((o) => _OrderCard(
                      order: o,
                      statusText: _statusText(context, o.status),
                      timeFmt: _timeFmt,
                      onCancel: o.canCancel && !_actioning ? () => _cancelOrder(o) : null,
                    )),
              ],
              if (partial.isNotEmpty) ...[
                _GroupTitle(title: AppLocalizations.of(context)!.ordersStatusPartial),
                ...partial.map((o) => _OrderCard(
                      order: o,
                      statusText: _statusText(context, o.status),
                      timeFmt: _timeFmt,
                      onCancel: o.canCancel && !_actioning ? () => _cancelOrder(o) : null,
                    )),
              ],
              if (rest.isNotEmpty) ...[
                _GroupTitle(title: AppLocalizations.of(context)!.commonOther),
                ...rest.map((o) => _OrderCard(
                      order: o,
                      statusText: _statusText(context, o.status),
                      timeFmt: _timeFmt,
                      onCancel: o.canCancel && !_actioning ? () => _cancelOrder(o) : null,
                    )),
              ],
              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_hasMore)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: _loadMore,
                      child: Text(
                        '加载更多',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: TradingUi.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.statusText,
    required this.timeFmt,
    this.onCancel,
  });

  final Order order;
  final String statusText;
  final DateFormat timeFmt;
  final VoidCallback? onCancel;

  static const Color _muted = Color(0xFF6C6F77);
  static const Color _surface = Color(0xFF1A1C21);

  String _intentLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (order.productType == ProductType.spot) {
      return order.isBuy ? l10n.ordersBuy : l10n.ordersSell;
    }
    final isLong = order.positionSide == PositionSide.long;
    final action = (order.positionAction ?? 'open').toLowerCase();
    if (isLong && action == 'open') return '开多';
    if (isLong && action == 'close') return '平多';
    if (!isLong && action == 'open') return '开空';
    if (!isLong && action == 'close') return '平空';
    return order.isBuy ? l10n.ordersBuy : l10n.ordersSell;
  }

  @override
  Widget build(BuildContext context) {
    final isBuy = order.isBuy;
    final isEndState = order.status == OrderStatus.filled || order.status == OrderStatus.cancelled;
    return Opacity(
      opacity: isEndState ? 0.65 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: _surface,
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  order.symbol,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if (order.symbolName != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    order.symbolName!,
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ],
                if (order.productType != ProductType.spot ||
                    order.assetClass != null) ...[
                  const SizedBox(width: 8),
                  _tag('${order.assetClass ?? 'asset'} / ${order.productType.name}'),
                ],
                if (order.productType != ProductType.spot) ...[
                  const SizedBox(width: 6),
                  _tag('${order.positionSide.name} / ${order.positionAction ?? '--'}'),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isBuy
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _intentLabel(context),
                    style: TextStyle(
                      color: isBuy ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _labelValue(context, AppLocalizations.of(context)!.ordersOrderPrice, order.type == OrderType.market ? AppLocalizations.of(context)!.ordersMarket : order.price.toStringAsFixed(2)),
                const SizedBox(width: 16),
                _labelValue(context, AppLocalizations.of(context)!.ordersQuantity, order.quantity.toStringAsFixed(0)),
                const SizedBox(width: 16),
                _labelValue(context, AppLocalizations.of(context)!.ordersFilled, order.filledQuantity.toStringAsFixed(0)),
                if (order.productType != ProductType.spot) ...[
                  const SizedBox(width: 16),
                  _labelValue(
                    context,
                    '杠杆',
                    '${order.leverage.toStringAsFixed(order.leverage.truncateToDouble() == order.leverage ? 0 : 1)}x',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  statusText,
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(width: 12),
                Text(
                  timeFmt.format(order.createdAt),
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const Spacer(),
                if (onCancel != null)
                  TextButton(
                    onPressed: onCancel,
                    child: Text(AppLocalizations.of(context)!.ordersCancelOrder),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _labelValue(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
