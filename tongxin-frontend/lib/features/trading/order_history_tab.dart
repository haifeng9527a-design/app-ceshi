import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'trading_api_client.dart';
import 'trading_models.dart';
import 'trading_ui.dart';

/// 历史委托 Tab：历史委托列表，支持按日期/标的筛选与分页（先 mock，分页占位）
class OrderHistoryTab extends StatefulWidget {
  const OrderHistoryTab({super.key, required this.teacherId, this.isActive = false});

  final String teacherId;
  final bool isActive;

  @override
  State<OrderHistoryTab> createState() => _OrderHistoryTabState();
}

class _OrderHistoryTabState extends State<OrderHistoryTab> {
  static const Color _muted = Color(0xFF6C6F77);
  static const Color _surface = Color(0xFF1A1C21);
  static const int _pageSize = 5;

  final _api = TradingApiClient.instance;
  final _scrollController = ScrollController();
  List<Order> _orders = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  TradingAccountSummary? _summary;
  DateTime? _filterDate;
  String _filterSymbol = '';
  Timer? _refreshTimer;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadHistory(showLoading: true);
    _loadSummary();
    _syncPolling();
  }

  @override
  void didUpdateWidget(covariant OrderHistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncPolling();
    }
  }

  void _syncPolling() {
    _refreshTimer?.cancel();
    if (!widget.isActive) return;
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
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
      final s = await _api.getSummary();
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

  Future<void> _loadHistory({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _api.getHistoryOrders(page: 1, pageSize: _pageSize);
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
      final list = await _api.getHistoryOrders(page: nextPage, pageSize: _pageSize);
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

  List<Order> get _filteredOrders {
    var list = _orders;
    if (_filterDate != null) {
      final d = _filterDate!;
      list = list.where((o) {
        final od = DateTime(o.createdAt.year, o.createdAt.month, o.createdAt.day);
        return od == DateTime(d.year, d.month, d.day);
      }).toList();
    }
    if (_filterSymbol.trim().isNotEmpty) {
      final q = _filterSymbol.trim().toLowerCase();
      list = list.where((o) =>
          o.symbol.toLowerCase().contains(q) ||
          (o.symbolName?.toLowerCase().contains(q) ?? false)).toList();
    }
    return list;
  }

  String _statusText(BuildContext context, OrderStatus s) {
    final l10n = AppLocalizations.of(context)!;
    switch (s) {
      case OrderStatus.pending:
        return l10n.orderStatusPending;
      case OrderStatus.partial:
        return l10n.orderStatusPartial;
      case OrderStatus.filled:
        return l10n.orderFilled;
      case OrderStatus.cancelled:
        return l10n.orderStatusCancelled;
      case OrderStatus.rejected:
        return l10n.orderStatusRejected;
    }
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

  String _intentLabel(BuildContext context, Order order) {
    final l10n = AppLocalizations.of(context)!;
    if (order.productType == ProductType.spot) {
      return order.isBuy ? l10n.tradingBuy : l10n.tradingSell;
    }
    final isLong = order.positionSide == PositionSide.long;
    final action = (order.positionAction ?? 'open').toLowerCase();
    if (isLong && action == 'open') return '开多';
    if (isLong && action == 'close') return '平多';
    if (!isLong && action == 'open') return '开空';
    if (!isLong && action == 'close') return '平空';
    return order.isBuy ? l10n.tradingBuy : l10n.tradingSell;
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredOrders;
    final dateFmt = DateFormat('yyyy-MM-dd');
    final timeFmt = DateFormat('HH:mm');

    return TradingPageScaffold(
      child: RefreshIndicator(
        onRefresh: () async {
          await _loadHistory(showLoading: true);
          await _loadSummary();
        },
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            TradingSectionHeader(
              title: AppLocalizations.of(context)!.teachersHistoryOrderTab,
              icon: Icons.history,
              trailing: IconButton(
                onPressed: _loading ? null : () => _loadHistory(showLoading: true),
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
            else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _filterDate ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _filterDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        _filterDate != null
                            ? dateFmt.format(_filterDate!)
                            : AppLocalizations.of(context)!.orderDate,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _filterSymbol = v),
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context)!.tradingSymbolLabel,
                        hintStyle: const TextStyle(color: _muted),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      _filterDate = null;
                      _filterSymbol = '';
                    }),
                    child: Text(AppLocalizations.of(context)!.orderClear),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (list.isEmpty)
                TradingStateBlock.empty(message: AppLocalizations.of(context)!.orderNoHistory)
              else
                ...list.map(
                  (o) => Card(
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
                                o.symbol,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              if (o.symbolName != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  o.symbolName!,
                                  style: const TextStyle(color: _muted, fontSize: 13),
                                ),
                              ],
                              if (o.productType != ProductType.spot ||
                                  o.assetClass != null) ...[
                                const SizedBox(width: 8),
                                _tag('${o.assetClass ?? 'asset'} / ${o.productType.name}'),
                              ],
                              if (o.productType != ProductType.spot) ...[
                                const SizedBox(width: 6),
                                _tag('${o.positionSide.name} / ${o.positionAction ?? '--'}'),
                              ],
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: o.isBuy
                                      ? Colors.green.withValues(alpha: 0.2)
                                      : Colors.red.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _intentLabel(context, o),
                                  style: TextStyle(
                                    color: o.isBuy ? Colors.green : Colors.red,
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
                              _labelValue(
                                AppLocalizations.of(context)!.orderPrice,
                                o.type == OrderType.market
                                    ? AppLocalizations.of(context)!.tradingMarketOrder
                                    : o.price.toStringAsFixed(2),
                              ),
                              const SizedBox(width: 16),
                              _labelValue(
                                AppLocalizations.of(context)!.tradingQuantityLabel,
                                o.quantity.toStringAsFixed(0),
                              ),
                              const SizedBox(width: 16),
                              _labelValue(
                                AppLocalizations.of(context)!.orderFilled,
                                o.filledQuantity.toStringAsFixed(0),
                              ),
                              if (o.productType != ProductType.spot) ...[
                                const SizedBox(width: 16),
                                _labelValue(
                                  '杠杆',
                                  '${o.leverage.toStringAsFixed(o.leverage.truncateToDouble() == o.leverage ? 0 : 1)}x',
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                _statusText(context, o.status),
                                style: const TextStyle(color: _muted, fontSize: 13),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${dateFmt.format(o.createdAt)} ${timeFmt.format(o.createdAt)}',
                                style: const TextStyle(color: _muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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

  Widget _labelValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
