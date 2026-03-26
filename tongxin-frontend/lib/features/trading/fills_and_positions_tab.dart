import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../market/chart/intraday_chart.dart';
import '../market/market_repository.dart';
import '../teachers/teacher_models.dart';
import 'trading_api_client.dart';
import 'trading_models.dart';
import 'trading_ui.dart';

/// 成交与持仓 Tab：成交记录列表 + 当前持仓（可点持仓快捷卖出）
/// 成交记录先 mock，持仓来自 Supabase
class FillsAndPositionsTab extends StatefulWidget {
  const FillsAndPositionsTab({
    super.key,
    required this.teacherId,
    required this.accountType,
    this.isActive = false,
  });

  final String teacherId;
  final TradingAccountType accountType;
  final bool isActive;

  @override
  State<FillsAndPositionsTab> createState() => _FillsAndPositionsTabState();
}

class _FillsAndPositionsTabState extends State<FillsAndPositionsTab> {
  final _api = TradingApiClient.instance;
  final _market = MarketRepository();
  final _scrollController = ScrollController();

  static const int _pageSize = 5;

  List<OrderFill> _fills = const [];
  List<TeacherPosition> _positions = const [];
  TradingAccountSummary? _summary;
  Map<String, MarketQuote> _liveQuotes = const {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMoreFills = true;
  bool _hasMorePositions = true;
  String? _error;
  final Set<String> _sellingPositionIds = <String>{};
  Timer? _refreshTimer;
  Timer? _liveQuoteTimer;
  int _fillsPage = 1;
  int _positionsPage = 1;

  static const Color _surface = Color(0xFF1A1C21);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData(showLoading: true);
    _syncPolling();
  }

  @override
  void didUpdateWidget(covariant FillsAndPositionsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountType != widget.accountType) {
      _loadData(showLoading: true);
    }
    if (oldWidget.isActive != widget.isActive) {
      _syncPolling();
    }
  }

  void _syncPolling() {
    _refreshTimer?.cancel();
    _liveQuoteTimer?.cancel();
    if (!widget.isActive) return;
    _refreshTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (!mounted) return;
      await _refreshSummaryOnly();
    });
    _liveQuoteTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      await _refreshLiveQuotes();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 180) {
      _loadMore();
    }
  }

  Future<void> _refreshSummaryOnly() async {
    try {
      final summary = await _api.getSummary(accountType: widget.accountType);
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (_) {}
  }

  Future<void> _refreshLiveQuotes() async {
    final symbols = _positions
        .map((p) => p.asset.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (symbols.isEmpty) return;
    final next = <String, MarketQuote>{};
    for (final symbol in symbols) {
      try {
        final q = await _market.getQuote(symbol, realtime: true);
        if (!q.hasError && q.price > 0) {
          next[symbol] = q;
        }
      } catch (_) {}
    }
    if (!mounted || next.isEmpty) return;
    setState(() {
      _liveQuotes = {
        ..._liveQuotes,
        ...next,
      };
    });
  }

  Future<void> _loadData({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final fills = await _api.getFills(
        page: 1,
        pageSize: _pageSize,
        accountType: widget.accountType,
      );
      final positions = await _api.getPositions(
        page: 1,
        pageSize: _pageSize,
        accountType: widget.accountType,
      );
      final summary = await _api.getSummary(accountType: widget.accountType);
      if (!mounted) return;
      setState(() {
        _fills = fills;
        _positions = positions;
        _summary = summary;
        _loading = false;
        _loadingMore = false;
        _fillsPage = 1;
        _positionsPage = 1;
        _hasMoreFills = fills.length >= _pageSize;
        _hasMorePositions = positions.length >= _pageSize;
        _error = null;
      });
      await _refreshLiveQuotes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore) return;
    if (!_hasMoreFills && !_hasMorePositions) return;
    setState(() => _loadingMore = true);
    try {
      final nextFillsPage = _fillsPage + 1;
      final nextPositionsPage = _positionsPage + 1;
      final futures = await Future.wait([
        _hasMoreFills
            ? _api.getFills(
                page: nextFillsPage,
                pageSize: _pageSize,
                accountType: widget.accountType,
              )
            : Future.value(const <OrderFill>[]),
        _hasMorePositions
            ? _api.getPositions(
                page: nextPositionsPage,
                pageSize: _pageSize,
                accountType: widget.accountType,
              )
            : Future.value(const <TeacherPosition>[]),
      ]);
      final moreFills = futures[0] as List<OrderFill>;
      final morePositions = futures[1] as List<TeacherPosition>;
      if (!mounted) return;
      setState(() {
        if (moreFills.isNotEmpty) {
          _fills = _appendUniqueFills(_fills, moreFills);
          _fillsPage = nextFillsPage;
        }
        if (morePositions.isNotEmpty) {
          _positions = _appendUniquePositions(_positions, morePositions);
          _positionsPage = nextPositionsPage;
        }
        _hasMoreFills = moreFills.length >= _pageSize;
        _hasMorePositions = morePositions.length >= _pageSize;
        _loadingMore = false;
      });
      await _refreshLiveQuotes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = '$e';
      });
    }
  }

  List<OrderFill> _appendUniqueFills(
    List<OrderFill> current,
    List<OrderFill> incoming,
  ) {
    final existingIds = current.map((e) => e.id).toSet();
    final merged = [...current];
    for (final item in incoming) {
      if (existingIds.add(item.id)) {
        merged.add(item);
      }
    }
    return merged;
  }

  List<TeacherPosition> _appendUniquePositions(
    List<TeacherPosition> current,
    List<TeacherPosition> incoming,
  ) {
    final existingIds = current.map((e) => e.id).toSet();
    final merged = [...current];
    for (final item in incoming) {
      if (existingIds.add(item.id)) {
        merged.add(item);
      }
    }
    return merged;
  }

  Future<void> _submitSellPosition(
    TeacherPosition p, {
    required double quantity,
    required OrderType type,
    double? limitPrice,
  }) async {
    final availableQty = p.buyShares ?? 0;
    final isShort = _isShortPosition(p);
    final closeLabel = _closeActionLabel(context, p);
    if (quantity <= 0) return;
    if (_sellingPositionIds.contains(p.id)) return;
    if (quantity > availableQty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.tradingCloseQuantityExceeded(
              _closeQuantityLabel(context, p),
              availableQty.toStringAsFixed(0),
            ),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    setState(() => _sellingPositionIds.add(p.id));
    try {
      await _api.placeOrder(
        symbol: p.asset,
        assetClass: p.assetClass,
        productType: (p.productType ?? '').toLowerCase() == 'future'
            ? ProductType.future
            : (p.productType ?? '').toLowerCase() == 'perpetual'
                ? ProductType.perpetual
                : ProductType.spot,
        positionSide: (p.positionSide ?? '').toLowerCase() == 'short'
            ? PositionSide.short
            : PositionSide.long,
        positionAction: 'close',
        marginMode: (p.marginMode ?? '').toLowerCase() == 'isolated'
            ? MarginMode.isolated
            : MarginMode.cross,
        leverage: p.leverage ?? 1,
        side: isShort ? OrderSide.buy : OrderSide.sell,
        type: type,
        quantity: quantity,
        limitPrice: type == OrderType.limit ? limitPrice : null,
      );
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!
                .tradingBuySellSubmitted(closeLabel, p.asset),
          ),
        ),
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
      if (mounted) {
        setState(() => _sellingPositionIds.remove(p.id));
      }
    }
  }

  Future<void> _openPositionSheet(TeacherPosition p) async {
    final qty = p.buyShares ?? 0;
    if (qty <= 0) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PositionDetailSheet(
        position: p,
        initialQuote: _liveQuotes[p.asset.trim()],
        submitting: _sellingPositionIds.contains(p.id),
        onSubmitSell: (quantity, type, limitPrice) async {
          await _submitSellPosition(
            p,
            quantity: quantity,
            type: type,
            limitPrice: limitPrice,
          );
          if (ctx.mounted && !_sellingPositionIds.contains(p.id)) {
            Navigator.of(ctx).pop();
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _liveQuoteTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final timeFmt = DateFormat('MM-dd HH:mm');

    return TradingPageScaffold(
      child: RefreshIndicator(
        onRefresh: () => _loadData(showLoading: true),
        child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          TradingSectionHeader(
            title: l10n.tradesCurrentPositions,
            icon: Icons.pie_chart_outline,
          ),
          const SizedBox(height: 10),
          TradingSummaryStrip(summary: _summary),
          const SizedBox(height: 12),
          if (_loading)
            const TradingStateBlock.loading()
          else if (_error != null)
            TradingStateBlock.error(message: _error!)
          else if (_positions.isEmpty)
            TradingStateBlock.empty(
              message: l10n.tradesNoPosition,
            )
          else
            ..._positions.map(
              (p) => _PositionCard(
                position: p,
                liveQuote: _liveQuotes[p.asset.trim()],
                selling: _sellingPositionIds.contains(p.id),
                onTap: () => _openPositionSheet(p),
              ),
            ),
          const SizedBox(height: 20),
          TradingSectionHeader(
            title: l10n.tradesFillsRecord,
            icon: Icons.receipt_long,
          ),
          const SizedBox(height: 10),
          if (_fills.isEmpty)
            TradingStateBlock.empty(
              message: l10n.tradesNoFills,
            )
          else
            ..._fills.map((f) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: _surface,
                child: ListTile(
                  title: Text(
                    '${f.symbol} ${f.symbolName ?? ""}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        '${f.price.toStringAsFixed(2)} × ${f.quantity.toStringAsFixed(0)}  ${timeFmt.format(f.filledAt)}',
                        style: const TextStyle(color: TradingUi.textMuted, fontSize: 12),
                      ),
                      if (f.assetClass != null || f.productType != ProductType.spot) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _fillTag('${_fillAssetClassLabel(context, f.assetClass)} / ${_fillProductTypeLabel(context, f.productType)}'),
                            _fillTag(_fillPositionSideLabel(context, f.positionSide)),
                            if (f.productType != ProductType.spot)
                              _fillTag(
                                AppLocalizations.of(context)!.tradingLeverageX(
                                  f.leverage.toStringAsFixed(
                                    f.leverage.truncateToDouble() == f.leverage
                                        ? 0
                                        : 1,
                                  ),
                                ),
                              ),
                            if (f.notional > 0)
                              _fillTag(
                                AppLocalizations.of(context)!.tradingNotionalValue(
                                  f.notional.toStringAsFixed(2),
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (f.realizedPnl != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${AppLocalizations.of(context)!.tradesPnl} ${f.realizedPnl! >= 0 ? "+" : ""}${f.realizedPnl!.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: (f.realizedPnl ?? 0) >= 0 ? Colors.green : Colors.red,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: f.isBuy
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _fillIntentLabel(context, f),
                      style: TextStyle(
                        color: f.isBuy ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              )),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_hasMoreFills || _hasMorePositions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: OutlinedButton(
                  onPressed: _loadMore,
                  child: Text(
                    AppLocalizations.of(context)!.tradingLoadMore,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

String _fillAssetClassLabel(BuildContext context, String? assetClass) {
  return switch (assetClass?.toLowerCase()) {
    'stock' => AppLocalizations.of(context)!.tradingStock,
    'forex' => AppLocalizations.of(context)!.tradingForex,
    'crypto' => AppLocalizations.of(context)!.tradingCrypto,
    _ => assetClass ?? AppLocalizations.of(context)!.tradingAssetGeneric,
  };
}

String _fillProductTypeLabel(BuildContext context, ProductType type) {
  return switch (type) {
    ProductType.spot => AppLocalizations.of(context)!.tradingProductSpot,
    ProductType.perpetual =>
      AppLocalizations.of(context)!.tradingProductPerpetual,
    ProductType.future => AppLocalizations.of(context)!.tradingProductFuture,
  };
}

String _fillPositionSideLabel(BuildContext context, PositionSide side) {
  return side == PositionSide.long
      ? AppLocalizations.of(context)!.tradingPositionLong
      : AppLocalizations.of(context)!.tradingPositionShort;
}

String _positionProductTypeLabel(BuildContext context, String productType) {
  return switch (productType.toLowerCase()) {
    'spot' => AppLocalizations.of(context)!.tradingProductSpot,
    'perpetual' => AppLocalizations.of(context)!.tradingProductPerpetual,
    'future' => AppLocalizations.of(context)!.tradingProductFuture,
    _ => productType,
  };
}

String _positionPositionSideLabel(BuildContext context, String positionSide) {
  return positionSide.toLowerCase() == 'short'
      ? AppLocalizations.of(context)!.tradingPositionShort
      : AppLocalizations.of(context)!.tradingPositionLong;
}

String _positionMarginModeLabel(BuildContext context, String marginMode) {
  return marginMode.toLowerCase() == 'isolated'
      ? AppLocalizations.of(context)!.tradingMarginIsolated
      : AppLocalizations.of(context)!.tradingMarginCross;
}

Widget _fillTag(String text) {
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

bool _isShortPosition(TeacherPosition position) {
  return (position.positionSide ?? '').toLowerCase() == 'short';
}

double _positionUnitFactor(TeacherPosition position) {
  return (position.contractSize ?? 1) * (position.multiplier ?? 1);
}

double _floatingPnlForPosition(
  TeacherPosition position,
  double current,
  double cost,
  double quantity,
) {
  final diff = _isShortPosition(position) ? (cost - current) : (current - cost);
  return diff * quantity * _positionUnitFactor(position);
}

double? _pnlRatioForPosition(
  TeacherPosition position,
  double current,
  double cost,
) {
  if (!(current > 0) || !(cost > 0)) return null;
  final diff = _isShortPosition(position) ? (cost - current) : (current - cost);
  return diff / cost * 100;
}

Color _priceColorForPosition(
  TeacherPosition position,
  double current,
  double cost,
) {
  final favorable = _isShortPosition(position) ? current <= cost : current >= cost;
  return favorable ? Colors.green : Colors.red;
}

String _closeActionLabel(BuildContext context, TeacherPosition position) {
  if ((position.productType ?? '').toLowerCase() == 'spot') {
    return AppLocalizations.of(context)!.tradingSell;
  }
  return _isShortPosition(position)
      ? AppLocalizations.of(context)!.tradingCloseShort
      : AppLocalizations.of(context)!.tradingCloseLong;
}

String _closeQuantityLabel(BuildContext context, TeacherPosition position) {
  if ((position.productType ?? '').toLowerCase() == 'spot') {
    return AppLocalizations.of(context)!.tradingSellableQuantity;
  }
  return AppLocalizations.of(context)!.tradingClosableQuantity;
}

String _fillIntentLabel(BuildContext context, OrderFill fill) {
  if (fill.productType == ProductType.spot) {
    return fill.isBuy
        ? AppLocalizations.of(context)!.tradingBuy
        : AppLocalizations.of(context)!.tradingSell;
  }
  final isLong = fill.positionSide == PositionSide.long;
  if (isLong && fill.side == OrderSide.buy) {
    return AppLocalizations.of(context)!.tradingOpenLong;
  }
  if (isLong && fill.side == OrderSide.sell) {
    return AppLocalizations.of(context)!.tradingCloseLong;
  }
  if (!isLong && fill.side == OrderSide.sell) {
    return AppLocalizations.of(context)!.tradingOpenShort;
  }
  return AppLocalizations.of(context)!.tradingCloseShort;
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.position,
    required this.liveQuote,
    required this.selling,
    required this.onTap,
  });

  final TeacherPosition position;
  final MarketQuote? liveQuote;
  final bool selling;
  final VoidCallback onTap;

  static const Color _accent = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF6C6F77);
  static const Color _surface = Color(0xFF171E2B);
  static const Color _surfaceSoft = Color(0xFF1E2738);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final qty = position.buyShares ?? 0;
    final cost = position.costPrice ?? position.buyPrice ?? 0;
    final current = liveQuote?.price ?? position.currentPrice ?? 0;
    final factor = _positionUnitFactor(position);
    final buyMarketValue = qty > 0 && cost > 0 ? qty * cost * factor : 0;
    final currentMarketValue = qty > 0 && current > 0 ? qty * current * factor : 0;
    final computedFloatingPnl =
        qty > 0 && cost > 0 && current > 0
            ? _floatingPnlForPosition(position, current, cost, qty)
            : null;
    final totalPnl =
        computedFloatingPnl ?? position.pnlAmount ?? position.floatingPnl ?? 0.0;
    final dayFloatingPnl =
        computedFloatingPnl ?? position.floatingPnl ?? 0.0;
    final pnlColor = totalPnl >= 0 ? Colors.green : Colors.red;
    final dayPnlColor = dayFloatingPnl >= 0 ? Colors.green : Colors.red;
    final dateFmt = DateFormat('MM-dd HH:mm');
    final buyTimeText =
        position.buyTime == null ? '--' : dateFmt.format(position.buyTime!);
    final ratioValue = qty > 0 && cost > 0 && current > 0
        ? _pnlRatioForPosition(position, current, cost)
        : (position.pnlRatio ?? position.realizedPnlRatioPercent);
    final ratioText = ratioValue != null
        ? '${ratioValue >= 0 ? "+" : ""}${ratioValue.toStringAsFixed(2)}%'
        : null;
    final priceColor = _priceColorForPosition(position, current, cost);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.28), width: 0.8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          position.asset,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _miniTag(
                              '${(position.productType ?? '').toLowerCase() == 'spot' ? l10n.tradesPositionShares : l10n.tradingPositionHolding} ${qty <= 0 ? "--" : qty.toStringAsFixed(0)}',
                            ),
                            if ((position.assetClass ?? '').isNotEmpty)
                              _miniTag(_fillAssetClassLabel(context, position.assetClass)),
                            if ((position.productType ?? '').isNotEmpty)
                              _miniTag(_positionProductTypeLabel(context, position.productType!)),
                            if ((position.positionSide ?? '').isNotEmpty)
                              _miniTag(_positionPositionSideLabel(context, position.positionSide!)),
                            _miniTag(_closeActionLabel(context, position)),
                            _miniTag(
                              '${l10n.tradingCurrentPriceLabel} ${current > 0 ? current.toStringAsFixed(2) : "--"}',
                              textColor: priceColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        totalPnl >= 0
                            ? '+${totalPnl.toStringAsFixed(2)}'
                            : totalPnl.toStringAsFixed(2),
                        style: TextStyle(
                          color: pnlColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      if (ratioText != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: pnlColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            ratioText,
                            style: TextStyle(
                              color: pnlColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _metricCell(
                      l10n.tradingBuyPrice,
                      cost > 0 ? cost.toStringAsFixed(2) : '--',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metricCell(
                      l10n.tradesPositionBuyMarketValue,
                      buyMarketValue <= 0
                          ? '--'
                          : buyMarketValue.toStringAsFixed(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metricCell(
                      l10n.tradesPositionCurrentMarketValue,
                      currentMarketValue <= 0
                          ? '--'
                          : currentMarketValue.toStringAsFixed(2),
                    ),
                  ),
                ],
              ),
              if ((position.marginMode ?? '').isNotEmpty ||
                  position.leverage != null ||
                  position.liquidationPrice != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if ((position.marginMode ?? '').isNotEmpty)
                      Expanded(
                        child: _metricCell(
                          AppLocalizations.of(context)!.tradingMarginMode,
                          _positionMarginModeLabel(context, position.marginMode!),
                        ),
                      ),
                    if (position.leverage != null) ...[
                      if ((position.marginMode ?? '').isNotEmpty)
                        const SizedBox(width: 8),
                      Expanded(
                        child: _metricCell(
                          AppLocalizations.of(context)!.tradingLeverage,
                          AppLocalizations.of(context)!.tradingLeverageX(
                            position.leverage!.toStringAsFixed(
                              position.leverage!.truncateToDouble() ==
                                      position.leverage!
                                  ? 0
                                  : 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (position.liquidationPrice != null) ...[
                      if ((position.marginMode ?? '').isNotEmpty ||
                          position.leverage != null)
                        const SizedBox(width: 8),
                      Expanded(
                        child: _metricCell(
                          AppLocalizations.of(context)!.tradingLiquidationPrice,
                          position.liquidationPrice!.toStringAsFixed(2),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l10n.tradingBuyTime}  $buyTimeText',
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${dayFloatingPnl >= 0 ? "+" : ""}${dayFloatingPnl.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: dayPnlColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selling
                          ? Colors.white.withValues(alpha: 0.06)
                          : _accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: selling
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _closeActionLabel(context, position),
                                style: const TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right,
                                color: _accent,
                                size: 16,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniTag(String text, {Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor ?? Colors.white70,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _metricCell(String k, String v, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: _surfaceSoft,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            v,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionDetailSheet extends StatefulWidget {
  const _PositionDetailSheet({
    required this.position,
    required this.initialQuote,
    required this.submitting,
    required this.onSubmitSell,
  });

  final TeacherPosition position;
  final MarketQuote? initialQuote;
  final bool submitting;
  final Future<void> Function(
    double quantity,
    OrderType type,
    double? limitPrice,
  ) onSubmitSell;

  @override
  State<_PositionDetailSheet> createState() => _PositionDetailSheetState();
}

class _PositionDetailSheetState extends State<_PositionDetailSheet> {
  final _market = MarketRepository();
  final _qtyController = TextEditingController();
  final _priceController = TextEditingController();

  Timer? _quoteTimer;
  MarketQuote? _quote;
  List<ChartCandle> _candles = const [];
  bool _loadingChart = true;
  bool _marketOrder = true;
  bool _submitting = false;

  static const Color _sheetBg = Color(0xFF101827);
  static const Color _cardBg = Color(0xFF171E2B);
  static const Color _accent = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _quote = widget.initialQuote;
    _qtyController.text =
        (widget.position.buyShares ?? 0).toStringAsFixed(0);
    _priceController.text =
        (widget.initialQuote?.price ?? widget.position.currentPrice ?? 0)
            .toStringAsFixed(2);
    _loadChart();
    _startQuotePolling();
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _startQuotePolling() {
    _refreshQuote();
    _quoteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshQuote();
    });
  }

  Future<void> _refreshQuote() async {
    try {
      final q = await _market.getQuote(
        widget.position.asset,
        realtime: true,
      );
      if (!mounted || q.hasError || q.price <= 0) return;
      setState(() {
        _quote = q;
        if (_marketOrder) {
          _priceController.text = q.price.toStringAsFixed(2);
        }
      });
    } catch (_) {}
  }

  Future<void> _loadChart() async {
    setState(() => _loadingChart = true);
    try {
      final list = await _market.getCandles(
        widget.position.asset,
        '1min',
        lastDays: 1,
      );
      if (!mounted) return;
      final now = DateTime.now();
      final todayOnly = list.where((c) {
        final dt = DateTime.fromMillisecondsSinceEpoch(
          (c.time * 1000).toInt(),
        );
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      }).toList(growable: false);
      setState(() {
        _candles = todayOnly;
        _loadingChart = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingChart = false);
    }
  }

  Future<void> _submit() async {
    final available = widget.position.buyShares ?? 0;
    final closeLabel = _closeActionLabel(context, widget.position);
    final qty = double.tryParse(_qtyController.text.trim());
    final price = double.tryParse(_priceController.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.tradingEnterValidCloseQuantity(
              closeLabel,
            ),
          ),
        ),
      );
      return;
    }
    if (qty > available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.tradingCloseQuantityExceeded(
              _closeQuantityLabel(context, widget.position),
              available.toStringAsFixed(0),
            ),
          ),
        ),
      );
      return;
    }
    if (!_marketOrder && (price == null || price <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.tradingEnterValidLimitPriceFor(
              closeLabel,
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmitSell(
        qty,
        _marketOrder ? OrderType.market : OrderType.limit,
        _marketOrder ? null : price,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.position.buyShares ?? 0;
    final cost = widget.position.costPrice ?? widget.position.buyPrice ?? 0;
    final current = _quote?.price ?? widget.position.currentPrice ?? 0;
    final closeLabel = _closeActionLabel(context, widget.position);
    final floating =
        available > 0 && cost > 0 && current > 0
            ? _floatingPnlForPosition(widget.position, current, cost, available)
            : 0.0;
    final pnlColor = floating >= 0 ? Colors.green : Colors.red;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _sheetBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 46,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.position.asset,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppLocalizations.of(context)!.tradingCurrentAndFloating(
                              current > 0 ? current.toStringAsFixed(2) : "--",
                              '${floating >= 0 ? "+" : ""}${floating.toStringAsFixed(2)}',
                            ),
                            style: TextStyle(
                              color: pnlColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_closeQuantityLabel(context, widget.position).replaceAll(AppLocalizations.of(context)!.tradingQuantityWord, '')} ${available.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _accent.withValues(alpha: 0.22)),
                ),
                child: SizedBox(
                  height: 250,
                  child: _loadingChart
                      ? const Center(child: CircularProgressIndicator())
                      : _candles.isEmpty
                          ? Center(
                              child: Text(
                                AppLocalizations.of(context)!.chartNoData,
                                style: const TextStyle(color: Colors.white54),
                              ),
                            )
                          : IntradayChart(
                              candles: _candles,
                              prevClose: _quote?.prevClose,
                              currentPrice: current > 0 ? current : null,
                              chartHeight: 180,
                              timeAxisHeight: 22,
                              volumeHeight: 42,
                              periodLabel: '1m',
                              useSessionMarketHours: false,
                            ),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _orderTypeChip(
                            label: AppLocalizations.of(context)!.tradingMarketOrder,
                            selected: _marketOrder,
                            onTap: () => setState(() {
                              _marketOrder = true;
                              if (current > 0) {
                                _priceController.text = current.toStringAsFixed(2);
                              }
                            }),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _orderTypeChip(
                            label: AppLocalizations.of(context)!.tradingLimitOrder,
                            selected: !_marketOrder,
                            onTap: () => setState(() => _marketOrder = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _fieldBox(
                            label: _closeQuantityLabel(context, widget.position),
                            child: Text(
                              available.toStringAsFixed(0),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _fieldBox(
                            label: AppLocalizations.of(context)!.tradingCurrentPriceLabel,
                            child: Text(
                              current > 0 ? current.toStringAsFixed(2) : '--',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _qtyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                        AppLocalizations.of(context)!.tradingQuantityLabel,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _priceController,
                      enabled: !_marketOrder,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(
                        color: _marketOrder ? Colors.white38 : Colors.white,
                      ),
                      decoration: _inputDecoration(
                        (widget.position.productType ?? '').toLowerCase() ==
                                'spot'
                            ? AppLocalizations.of(context)!.tradingSellPrice
                            : AppLocalizations.of(context)!.tradingPriceForAction(
                                closeLabel,
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (_submitting || widget.submitting) ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: (_submitting || widget.submitting)
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                AppLocalizations.of(context)!.tradingConfirmAction(
                                  closeLabel,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orderTypeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _accent : Colors.white24),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _accent : Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _fieldBox({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.03),
    );
  }
}
