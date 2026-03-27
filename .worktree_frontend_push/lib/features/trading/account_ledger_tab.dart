import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'trading_api_client.dart';
import 'trading_models.dart';
import 'trading_ui.dart';

class AccountLedgerTab extends StatefulWidget {
  const AccountLedgerTab({super.key, required this.teacherId, this.isActive = false});

  final String teacherId;
  final bool isActive;

  @override
  State<AccountLedgerTab> createState() => _AccountLedgerTabState();
}

class _AccountLedgerTabState extends State<AccountLedgerTab> {
  final _api = TradingApiClient.instance;
  final _scrollController = ScrollController();
  static const int _pageSize = 5;

  TradingAccount? _account;
  List<TradingLedgerEntry> _ledger = const [];
  String _entryTypeFilter = 'all';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  Timer? _refreshTimer;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData(showLoading: true);
    _syncPolling();
  }

  @override
  void didUpdateWidget(covariant AccountLedgerTab oldWidget) {
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
      try {
        final account = await _api.getAccount();
        if (!mounted) return;
        setState(() => _account = account);
      } catch (_) {}
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 180) {
      _loadMore();
    }
  }

  Future<void> _loadData({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final account = await _api.getAccount();
      final ledger = await _api.getLedger(page: 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _account = account;
        _ledger = ledger;
        _page = 1;
        _hasMore = ledger.length >= _pageSize;
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
      final ledger = await _api.getLedger(page: nextPage, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        if (ledger.isNotEmpty) {
          _ledger = _appendUniqueLedger(_ledger, ledger);
          _page = nextPage;
        }
        _hasMore = ledger.length >= _pageSize;
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

  List<TradingLedgerEntry> _appendUniqueLedger(
    List<TradingLedgerEntry> current,
    List<TradingLedgerEntry> incoming,
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

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  String _entryTypeLabel(BuildContext context, String v) {
    final l10n = AppLocalizations.of(context)!;
    switch (v) {
      case 'account_reset':
        return l10n.tradingLedgerTypeAccountReset;
      case 'order_cash_frozen':
        return l10n.tradingLedgerTypeOrderCashFrozen;
      case 'order_cancel_unfreeze':
        return l10n.tradingLedgerTypeOrderCancelUnfreeze;
      case 'order_filled_buy':
        return l10n.tradingLedgerTypeOrderFilledBuy;
      case 'order_filled_sell':
        return l10n.tradingLedgerTypeOrderFilledSell;
      case 'position_liquidated':
        return '强制平仓';
      default:
        return v;
    }
  }

  /// 金额带货币后缀：673282.45 USD 或 673282.45 USDT
  String _amountWithCurrency(double value, String currency) {
    final suffix = currency.toUpperCase() == 'USDT' ? ' USDT' : ' USD';
    return '${value.toStringAsFixed(2)}$suffix';
  }

  String _ledgerAssetClassLabel(String ac) {
    return switch (ac.toLowerCase()) {
      'stock' => '股票',
      'forex' => '外汇',
      'crypto' => '加密货币',
      _ => ac,
    };
  }

  String _ledgerProductTypeLabel(ProductType pt) {
    return switch (pt) {
      ProductType.spot => '现货',
      ProductType.perpetual => '永续',
      ProductType.future => '期货',
    };
  }

  String _ledgerSideLabel(String side) {
    return side.toLowerCase() == 'buy' ? '买入' : '卖出';
  }

  String _ledgerPositionSideLabel(PositionSide ps) {
    return ps == PositionSide.long ? '做多' : '做空';
  }

  Future<void> _copyCsv(List<TradingLedgerEntry> rows) async {
    final l10n = AppLocalizations.of(context)!;
    final curr = _account?.currency ?? 'USD';
    final suffix = curr.toUpperCase() == 'USDT' ? ' USDT' : ' USD';
    final b = StringBuffer();
    b.writeln('时间,流水类型,标的,资产类型,产品类型,方向,持仓方向,变动金额$suffix,变动后余额$suffix,备注');
    for (final e in rows) {
      final time = e.createdAt.toIso8601String();
      final typeCn = _entryTypeLabel(context, e.entryType);
      final symbol = e.symbol ?? '';
      final assetClass = e.assetClass != null ? _ledgerAssetClassLabel(e.assetClass!) : '';
      final productType = _ledgerProductTypeLabel(e.productType);
      final side = (e.side ?? '').isNotEmpty ? _ledgerSideLabel(e.side!) : '';
      final positionSide = e.productType != ProductType.spot ? _ledgerPositionSideLabel(e.positionSide) : '';
      final amount = '${e.amount.toStringAsFixed(2)}$suffix';
      final balance = '${e.balanceAfter.toStringAsFixed(2)}$suffix';
      final note = (e.note ?? '').replaceAll(',', '，').replaceAll('\n', ' ');
      b.writeln('$time,$typeCn,$symbol,$assetClass,$productType,$side,$positionSide,$amount,$balance,$note');
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.tradingLedgerCsvCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final acc = _account;
    final l10n = AppLocalizations.of(context)!;
    final timeFmt = DateFormat('MM-dd HH:mm:ss');
    final typeOptions = <String>{
      'all',
      ..._ledger.map((e) => e.entryType).where((e) => e.trim().isNotEmpty),
    }.toList();
    final filteredLedger = _entryTypeFilter == 'all'
        ? _ledger
        : _ledger.where((e) => e.entryType == _entryTypeFilter).toList(growable: false);
    return TradingPageScaffold(
      child: RefreshIndicator(
        onRefresh: () => _loadData(showLoading: true),
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading)
              const TradingStateBlock.loading()
            else if (_error != null)
              TradingStateBlock.error(message: _error!),
            if (acc != null) ...[
              _SummaryCard(account: acc, amountWithCurrency: (v) => _amountWithCurrency(v, acc.currency)),
              const SizedBox(height: 16),
            ],
            TradingSectionHeader(
              title: l10n.tradingLedgerTitle,
              icon: Icons.receipt_long,
            ),
            const SizedBox(height: 10),
            Row(
            children: [
              Text('类型筛选: ', style: const TextStyle(color: Color(0xFF6C6F77), fontSize: 12)),
              DropdownButton<String>(
                value: typeOptions.contains(_entryTypeFilter) ? _entryTypeFilter : 'all',
                items: typeOptions
                    .map((e) => DropdownMenuItem<String>(
                          value: e,
                          child: Text(
                            e == 'all' ? l10n.adminAll : _entryTypeLabel(context, e),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _entryTypeFilter = v);
                  }
                },
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: filteredLedger.isEmpty ? null : () => _copyCsv(filteredLedger),
                icon: const Icon(Icons.download_for_offline_outlined, size: 16),
                label: Text(l10n.marketExportCsv),
              ),
            ],
            ),
            if (filteredLedger.isEmpty)
              TradingStateBlock.empty(message: l10n.tradingLedgerEmpty)
            else
              ...filteredLedger.map(
              (e) {
                final isIn = e.amount >= 0;
                final c = isIn ? Colors.green : Colors.red;
                final curr = acc?.currency ?? 'USD';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: const Color(0xFF1A1C21),
                  child: ListTile(
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_entryTypeLabel(context, e.entryType)}${e.symbol != null ? ' · ${e.symbol}' : ''}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (e.assetClass != null && e.assetClass!.isNotEmpty)
                              _ledgerChip(_ledgerAssetClassLabel(e.assetClass!)),
                            if (e.productType != ProductType.spot)
                              _ledgerChip(_ledgerProductTypeLabel(e.productType)),
                            if ((e.side ?? '').isNotEmpty)
                              _ledgerChip(_ledgerSideLabel(e.side!)),
                            if (e.productType != ProductType.spot)
                              _ledgerChip(_ledgerPositionSideLabel(e.positionSide)),
                          ],
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${timeFmt.format(e.createdAt)}  ${l10n.tradingLedgerBalanceLabel}: ${_amountWithCurrency(e.balanceAfter, curr)}${(e.note ?? '').isNotEmpty ? '  ·  ${e.note}' : ''}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6C6F77)),
                      ),
                    ),
                    trailing: Text(
                      '${isIn ? '+' : ''}${_amountWithCurrency(e.amount, curr)}',
                      style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                );
              },
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
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.account,
    required this.amountWithCurrency,
  });

  final TradingAccount account;
  final String Function(double) amountWithCurrency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final equity = account.equity;
    final available = account.cashAvailable;
    final frozen = account.cashFrozen;
    final realized = account.realizedPnl;
    final unrealized = account.unrealizedPnl;
    final usedMargin = account.usedMargin;
    final maintenanceMargin = account.maintenanceMargin;
    final marginBalance = account.marginBalance;
    final todayPnl = account.todayPnl;
    final availablePct = account.availablePct.clamp(0.0, 1.0);
    final spotMarketPct = account.spotMarketPct.clamp(0.0, 1.0);
    final marginPct = account.marginPct.clamp(0.0, 1.0);
    final frozenPct = account.frozenPct.clamp(0.0, 1.0);
    final todayPnlPct = account.todayPnlPct;
    final pnlColor = todayPnl >= 0 ? Colors.green : Colors.red;

    final chartSections = <PieChartSectionData>[
      if (availablePct > 0.005)
        PieChartSectionData(
          value: availablePct * 100,
          color: const Color(0xFFD4AF37),
          radius: 28,
          showTitle: false,
        ),
      if (spotMarketPct > 0.005)
        PieChartSectionData(
          value: spotMarketPct * 100,
          color: const Color(0xFF2C3E67),
          radius: 28,
          showTitle: false,
        ),
      if (marginPct > 0.005)
        PieChartSectionData(
          value: marginPct * 100,
          color: const Color(0xFF3D5A80),
          radius: 28,
          showTitle: false,
        ),
      if (frozen > 0 && frozenPct > 0.005)
        PieChartSectionData(
          value: frozenPct * 100,
          color: const Color(0xFF4A5470),
          radius: 28,
          showTitle: false,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final leftWidth = (constraints.maxWidth - 36) * 0.54;
        final chartSize = (constraints.maxWidth - 36) * 0.46;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF18233A),
                Color(0xFF101827),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
              width: 0.9,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.tradingSummaryEquity,
                style: const TextStyle(color: Color(0xFF9DA8BC), fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                amountWithCurrency(equity),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _modeChip(_accountTypeLabel(account.accountType)),
                  _modeChip(_marginModeLabel(account.marginMode)),
                  _modeChip('${account.leverage.toStringAsFixed(account.leverage == account.leverage.roundToDouble() ? 0 : 1)}倍'),
                ],
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${l10n.tradingSummaryTodayPnl} ',
                      style: const TextStyle(
                        color: Color(0xFF9DA8BC),
                        fontSize: 14,
                      ),
                    ),
                    TextSpan(
                      text:
                          '${todayPnl >= 0 ? '+' : '-'}${_formatAmount(todayPnl.abs())} (${todayPnlPct >= 0 ? '+' : ''}${todayPnlPct.toStringAsFixed(2)}%)',
                      style: TextStyle(
                        color: pnlColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tradingSummaryFundDistribution,
                      style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: leftWidth,
                          child: Column(
                            children: [
                              _metricRow(l10n.tradingSummaryCashBalance, account.cashBalance),
                              _metricRow(l10n.tradingSummaryAvailableFunds, available),
                              _metricRow(l10n.tradingSummaryFrozenFunds, frozen),
                              if (account.spotMarketValue > 0)
                                _metricRow('现货市值', account.spotMarketValue),
                              if (account.contractNotional > 0)
                                _metricRow('合约名义价值', account.contractNotional),
                              _metricRow('已用保证金', usedMargin),
                              _metricRow('维持保证金', maintenanceMargin),
                              _metricRow('保证金余额', marginBalance),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                l10n.tradingSummaryAssetStructure,
                                style: const TextStyle(
                                  color: Color(0xFFB8C0D0),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: chartSize,
                                height: chartSize,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    PieChart(
                                      PieChartData(
                                        sectionsSpace: 2,
                                        centerSpaceRadius: chartSize * 0.24,
                                        startDegreeOffset: -90,
                                        sections: chartSections,
                                        borderData: FlBorderData(show: false),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${((availablePct + spotMarketPct + marginPct + frozenPct) * 100).toStringAsFixed(0)}%',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '资产结构',
                                          style: const TextStyle(
                                            color: Color(0xFFAAB3C4),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (availablePct > 0.005)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _legendDot(const Color(0xFFD4AF37)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${l10n.tradingSummaryAvailableFunds} ${(availablePct * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(color: Color(0xFFC8D0DF), fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              if (spotMarketPct > 0.005)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _legendDot(const Color(0xFF2C3E67)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '现货市值 ${(spotMarketPct * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(color: Color(0xFFC8D0DF), fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              if (marginPct > 0.005)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _legendDot(const Color(0xFF3D5A80)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '已用保证金 ${(marginPct * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(color: Color(0xFFC8D0DF), fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              if (frozen > 0 && frozenPct > 0.005)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _legendDot(const Color(0xFF4A5470)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${l10n.tradingSummaryFrozenFunds} ${(frozenPct * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(color: Color(0xFFC8D0DF), fontSize: 11),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tradingSummaryProfitOverview,
                      style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _profitCell(
                            l10n.tradingSummaryRealizedPnl,
                            realized,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _profitCell(
                            l10n.tradingSummaryUnrealizedPnl,
                            unrealized,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _legendDot(Color c) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  String _accountTypeLabel(String type) {
    return switch (type.toLowerCase()) {
      'contract' => '合约',
      'spot' => '现货',
      _ => type,
    };
  }

  String _marginModeLabel(String mode) {
    return mode.toLowerCase() == 'isolated' ? '逐仓' : '全仓';
  }

  Widget _modeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFD8E0EE),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _metricRow(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFAAB3C4),
                fontSize: 12.5,
              ),
            ),
          ),
          Text(
            _formatAmount(value),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double value) {
    final curr = account.currency.toUpperCase();
    final suffix = curr == 'USDT' ? ' USDT' : ' USD';
    return '${value.toStringAsFixed(2)}$suffix';
  }

  Widget _profitCell(String label, double value) {
    final c = value >= 0 ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFAAB3C4),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${value >= 0 ? '+' : '-'}${_formatAmount(value.abs())}',
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _ledgerChip(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
