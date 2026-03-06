import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'trading_api_client.dart';
import 'trading_models.dart';
import 'trading_ui.dart';

/// 历史委托 Tab：历史委托列表，支持按日期/标的筛选与分页（先 mock，分页占位）
class OrderHistoryTab extends StatefulWidget {
  const OrderHistoryTab({super.key, required this.teacherId});

  final String teacherId;

  @override
  State<OrderHistoryTab> createState() => _OrderHistoryTabState();
}

class _OrderHistoryTabState extends State<OrderHistoryTab> {
  static const Color _muted = Color(0xFF6C6F77);
  static const Color _surface = Color(0xFF1A1C21);

  final _api = TradingApiClient.instance;
  List<Order> _orders = const [];
  bool _loading = true;
  String? _error;
  TradingAccountSummary? _summary;
  DateTime? _filterDate;
  String _filterSymbol = '';

  @override
  void initState() {
    super.initState();
    _loadHistory(showLoading: true);
    _loadSummary();
    _pollRefresh();
  }

  void _pollRefresh() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) break;
      await _loadHistory();
      await _loadSummary();
    }
  }

  Future<void> _loadSummary() async {
    try {
      final s = await _api.getSummary();
      if (!mounted) return;
      setState(() => _summary = s);
    } catch (_) {}
  }

  Future<void> _loadHistory({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _api.getHistoryOrders(limit: 300);
      if (!mounted) return;
      setState(() {
        _orders = list;
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

  @override
  Widget build(BuildContext context) {
    final list = _filteredOrders;
    final dateFmt = DateFormat('yyyy-MM-dd');
    final timeFmt = DateFormat('HH:mm');

    return TradingPageScaffold(
      child: RefreshIndicator(
        onRefresh: () async {
          await _loadHistory();
          await _loadSummary();
        },
        child: ListView(
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
                                  o.isBuy
                                      ? AppLocalizations.of(context)!.tradingBuy
                                      : AppLocalizations.of(context)!.tradingSell,
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
