import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'trading_api_client.dart';
import 'trading_ui.dart';

class AccountLedgerTab extends StatefulWidget {
  const AccountLedgerTab({super.key, required this.teacherId});

  final String teacherId;

  @override
  State<AccountLedgerTab> createState() => _AccountLedgerTabState();
}

class _AccountLedgerTabState extends State<AccountLedgerTab> {
  final _api = TradingApiClient.instance;

  TradingAccount? _account;
  List<TradingLedgerEntry> _ledger = const [];
  String _entryTypeFilter = 'all';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData(showLoading: true);
    _pollRefresh();
  }

  void _pollRefresh() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) break;
      await _loadData();
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
      final ledger = await _api.getLedger(limit: 200);
      if (!mounted) return;
      setState(() {
        _account = account;
        _ledger = ledger;
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
      default:
        return v;
    }
  }

  Future<void> _copyCsv(List<TradingLedgerEntry> rows) async {
    final l10n = AppLocalizations.of(context)!;
    final b = StringBuffer();
    b.writeln('time,entry_type,entry_type_cn,symbol,side,amount,balance_after,note');
    for (final e in rows) {
      final time = e.createdAt.toIso8601String();
      final type = e.entryType;
      final typeCn = _entryTypeLabel(context, type);
      final symbol = e.symbol ?? '';
      final side = e.side ?? '';
      final amount = e.amount.toStringAsFixed(2);
      final balance = e.balanceAfter.toStringAsFixed(2);
      final note = (e.note ?? '').replaceAll(',', '，').replaceAll('\n', ' ');
      b.writeln('$time,$type,$typeCn,$symbol,$side,$amount,$balance,$note');
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
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading)
              const TradingStateBlock.loading()
            else if (_error != null)
              TradingStateBlock.error(message: _error!),
            if (acc != null) ...[
              _SummaryCard(account: acc),
              const SizedBox(height: 16),
            ],
            TradingSectionHeader(
              title: l10n.tradingLedgerTitle,
              icon: Icons.receipt_long,
            ),
            const SizedBox(height: 10),
            Row(
            children: [
              Text(l10n.tradingLedgerTypeFilter, style: const TextStyle(color: Color(0xFF6C6F77), fontSize: 12)),
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
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: const Color(0xFF1A1C21),
                  child: ListTile(
                    title: Text(
                      '${_entryTypeLabel(context, e.entryType)}${e.symbol != null ? ' · ${e.symbol}' : ''}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${timeFmt.format(e.createdAt)}  ${l10n.tradingLedgerBalanceLabel}: ${e.balanceAfter.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6C6F77)),
                    ),
                    trailing: Text(
                      '${isIn ? '+' : ''}${e.amount.toStringAsFixed(2)}',
                      style: TextStyle(color: c, fontWeight: FontWeight.w700),
                    ),
                  ),
                );
              },
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.account});

  final TradingAccount account;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final equity = account.equity;
    final available = account.cashAvailable;
    final frozen = account.cashFrozen;
    final marketValue = account.marketValue;
    final realized = account.realizedPnl;
    final unrealized = account.unrealizedPnl;
    final todayPnl = realized + unrealized;
    final availablePct = equity > 0 ? (available / equity).clamp(0.0, 1.0) : 0.0;
    final marketPct = equity > 0 ? (marketValue / equity).clamp(0.0, 1.0) : 0.0;
    final frozenPct = equity > 0 ? (frozen / equity).clamp(0.0, 1.0) : 0.0;
    final todayPnlPct = equity > 0 ? (todayPnl / equity * 100) : 0.0;
    final pnlColor = todayPnl >= 0 ? Colors.green : Colors.red;

    final chartSections = <PieChartSectionData>[
      PieChartSectionData(
        value: availablePct * 100,
        color: const Color(0xFFD4AF37),
        radius: 28,
        showTitle: false,
      ),
      PieChartSectionData(
        value: marketPct * 100,
        color: const Color(0xFF2C3E67),
        radius: 28,
        showTitle: false,
      ),
      if (frozen > 0)
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
                equity.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
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
                          '${todayPnl >= 0 ? '+' : ''}${todayPnl.toStringAsFixed(2)} (${todayPnlPct >= 0 ? '+' : ''}${todayPnlPct.toStringAsFixed(2)}%)',
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
                              _metricRow(l10n.tradingSummaryAvailableFunds, available),
                              _metricRow(l10n.tradingSummaryFrozenFunds, frozen),
                              _metricRow(l10n.tradingSummaryMarketValue, marketValue),
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
                                          '${(availablePct * 100).toStringAsFixed(0)}%',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          l10n.tradingSummaryAvailableFunds,
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
                              Row(
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
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _legendDot(const Color(0xFF2C3E67)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${l10n.tradingSummaryMarketValue} ${(marketPct * 100).toStringAsFixed(0)}%',
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
            value.toStringAsFixed(2),
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
            '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}',
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
