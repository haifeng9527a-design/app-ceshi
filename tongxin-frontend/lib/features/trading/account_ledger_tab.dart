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
  const AccountLedgerTab({
    super.key,
    required this.teacherId,
    required this.accountType,
    this.isActive = false,
  });

  final String teacherId;
  final TradingAccountType accountType;
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
  bool _transferring = false;
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
    if (oldWidget.accountType != widget.accountType) {
      _loadData(showLoading: true);
    }
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
        final account = await _api.getAccount(accountType: widget.accountType);
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
      final account = await _api.getAccount(accountType: widget.accountType);
      final ledger = await _api.getLedger(
        page: 1,
        pageSize: _pageSize,
        accountType: widget.accountType,
      );
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
      final ledger = await _api.getLedger(
        page: nextPage,
        pageSize: _pageSize,
        accountType: widget.accountType,
      );
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

  Future<void> _openTransferDialog() async {
    final account = _account;
    if (account == null || _transferring) return;
    final fromType = widget.accountType;
    final toType = fromType == TradingAccountType.spot
        ? TradingAccountType.contract
        : TradingAccountType.spot;
    final amountController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171E2B),
          title: const Text('资金划转', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '从 ${fromType == TradingAccountType.spot ? '现货账户' : '合约账户'} 划转到 ${toType == TradingAccountType.spot ? '现货账户' : '合约账户'}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                '可用资金 ${_amountWithCurrency(account.cashAvailable, account.currency)}',
                style: const TextStyle(color: Color(0xFFAAB3C4), fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: '划转金额',
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD4AF37)),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.03),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _transferring ? null : () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _transferring
                  ? null
                  : () async {
                      final amount =
                          double.tryParse(amountController.text.trim());
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入有效划转金额')),
                        );
                        return;
                      }
                      if (amount > account.cashAvailable) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('可用资金不足')),
                        );
                        return;
                      }
                      setState(() => _transferring = true);
                      try {
                        await _api.transferFunds(
                          fromAccountType: fromType,
                          toAccountType: toType,
                          amount: amount,
                        );
                        if (!mounted) return;
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                        await _loadData(showLoading: true);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('资金划转成功')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      } finally {
                        if (mounted) {
                          setState(() => _transferring = false);
                        }
                      }
                    },
              child: _transferring
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('确认'),
            ),
          ],
        );
      },
    );
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
      case 'account_transfer_out':
        return '账户划转转出';
      case 'account_transfer_in':
        return '账户划转转入';
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

  // 用户侧展示名：后台管理员 admin 统一显示为“系统”。
  String _displayLedgerNote(String? raw) {
    final note = (raw ?? '').trim();
    if (note.isEmpty) {
      return '';
    }
    final lower = note.toLowerCase();
    if (lower == 'admin' || lower == '管理员') {
      return '系统';
    }
    return note.replaceAll(RegExp(r'\badmin\b', caseSensitive: false), '系统');
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
      final assetClass =
          e.assetClass != null ? _ledgerAssetClassLabel(e.assetClass!) : '';
      final productType = _ledgerProductTypeLabel(e.productType);
      final side = (e.side ?? '').isNotEmpty ? _ledgerSideLabel(e.side!) : '';
      final positionSide = e.productType != ProductType.spot
          ? _ledgerPositionSideLabel(e.positionSide)
          : '';
      final amount = '${e.amount.toStringAsFixed(2)}$suffix';
      final balance = '${e.balanceAfter.toStringAsFixed(2)}$suffix';
      final note =
          _displayLedgerNote(e.note).replaceAll(',', '，').replaceAll('\n', ' ');
      b.writeln(
          '$time,$typeCn,$symbol,$assetClass,$productType,$side,$positionSide,$amount,$balance,$note');
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
        : _ledger
            .where((e) => e.entryType == _entryTypeFilter)
            .toList(growable: false);
    return TradingPageScaffold(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF070D1C), Color(0xFF0A1225), Color(0xFF0B1428)],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: () => _loadData(showLoading: true),
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            children: [
              if (_loading)
                const TradingStateBlock.loading()
              else if (_error != null)
                TradingStateBlock.error(message: _error!),
              if (acc != null) ...[
                _SummaryCard(
                  account: acc,
                  transferring: _transferring,
                  onTransfer: _openTransferDialog,
                ),
                const SizedBox(height: 16),
              ],
              TradingSectionHeader(
                title: l10n.tradingLedgerTitle,
                icon: Icons.receipt_long,
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF101A30),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    const Text('类型筛选: ',
                        style:
                            TextStyle(color: Color(0xFFA6B4CE), fontSize: 12)),
                    DropdownButton<String>(
                      value: typeOptions.contains(_entryTypeFilter)
                          ? _entryTypeFilter
                          : 'all',
                      dropdownColor: const Color(0xFF16223D),
                      borderRadius: BorderRadius.circular(12),
                      style: const TextStyle(
                          color: Color(0xFFE2EAFE), fontSize: 12),
                      underline: const SizedBox.shrink(),
                      items: typeOptions
                          .map((e) => DropdownMenuItem<String>(
                                value: e,
                                child: Text(
                                  e == 'all'
                                      ? l10n.adminAll
                                      : _entryTypeLabel(context, e),
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
                      onPressed: filteredLedger.isEmpty
                          ? null
                          : () => _copyCsv(filteredLedger),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFAFC8FF),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.download_for_offline_outlined,
                          size: 16),
                      label: Text(l10n.marketExportCsv),
                    ),
                  ],
                ),
              ),
              if (filteredLedger.isEmpty)
                TradingStateBlock.empty(message: l10n.tradingLedgerEmpty)
              else
                ...filteredLedger.map(
                  (e) {
                    final isIn = e.amount >= 0;
                    final c = isIn ? Colors.green : Colors.red;
                    final curr = acc?.currency ?? 'USD';
                    final noteText = _displayLedgerNote(e.note);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: const Color(0xFF111A2F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF15213D), Color(0xFF10192E)],
                          ),
                        ),
                        child: ListTile(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_entryTypeLabel(context, e.entryType)}${e.symbol != null ? ' · ${e.symbol}' : ''}',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFEAF1FF),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (e.assetClass != null &&
                                      e.assetClass!.isNotEmpty)
                                    _ledgerChip(
                                        _ledgerAssetClassLabel(e.assetClass!)),
                                  if (e.productType != ProductType.spot)
                                    _ledgerChip(
                                        _ledgerProductTypeLabel(e.productType)),
                                  if ((e.side ?? '').isNotEmpty)
                                    _ledgerChip(_ledgerSideLabel(e.side!)),
                                  if (e.productType != ProductType.spot)
                                    _ledgerChip(_ledgerPositionSideLabel(
                                        e.positionSide)),
                                ],
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${timeFmt.format(e.createdAt)}  ${l10n.tradingLedgerBalanceLabel}: ${_amountWithCurrency(e.balanceAfter, curr)}${noteText.isNotEmpty ? '  ·  $noteText' : ''}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF90A2C4)),
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: c.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              '${isIn ? '+' : ''}${_amountWithCurrency(e.amount, curr)}',
                              style: TextStyle(
                                  color: c,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5),
                            ),
                          ),
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
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD4AF37),
                        side: BorderSide(
                          color:
                              const Color(0xFFD4AF37).withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Text(
                        '加载更多',
                        style:
                            TextStyle(color: Color(0xFFECD59E), fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.account,
    required this.transferring,
    required this.onTransfer,
  });

  final TradingAccount account;
  final bool transferring;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 380;
    final titleSize = compact ? 25.0 : 28.0;
    final amountSize = compact ? 44.0 : 50.0;
    final sectionTitleSize = compact ? 22.0 : 24.0;
    final equity = account.equity;
    final available = account.cashAvailable;
    final frozen = account.cashFrozen;
    final todayPnl = account.todayPnl;
    final todayPnlPct = account.todayPnlPct;
    final availableRatio =
        equity <= 0 ? 0.0 : (available / equity).clamp(0.0, 1.0);
    final cashBalance = account.cashBalance;

    return Column(
      children: [
        _glowPanel(
          panelGradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF11264F), Color(0xFF0B1A34)],
          ),
          borderColor: const Color(0xFF3C8BFF),
          glowColor: const Color(0x663A87FF),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '总资产',
                          style: TextStyle(
                            color: const Color(0xFFEAF2FF),
                            fontSize: titleSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.visibility_outlined,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 16),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: compact ? 60 : 66,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _money(equity, compact: false),
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: amountSize,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Text(
                                _currencyCode,
                                style: const TextStyle(
                                  color: Color(0xFFF4F6FF),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: '今日盈亏  ',
                              style: TextStyle(
                                color: Color(0xFFDBE5FF),
                                fontSize: 14,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '${todayPnl >= 0 ? '+' : ''}${_money(todayPnl.abs())} $_currencyCode',
                              style: TextStyle(
                                color: todayPnl >= 0
                                    ? const Color(0xFF2CE5B0)
                                    : const Color(0xFFFF6D6D),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '   (${todayPnlPct >= 0 ? '+' : ''}${todayPnlPct.toStringAsFixed(2)}%)',
                              style: TextStyle(
                                color: todayPnl >= 0
                                    ? const Color(0xFF2CE5B0)
                                    : const Color(0xFFFF6D6D),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    child: _coinBadge(size: compact ? 94 : 108),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: compact ? 96 : 110,
                    child: OutlinedButton.icon(
                      onPressed: transferring ? null : onTransfer,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF4CC68),
                        side: BorderSide(
                          color:
                              const Color(0xFFF4CC68).withValues(alpha: 0.55),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      icon: transferring
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.swap_horiz, size: 14),
                      label: const Text('账户划转'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _glowPanel(
          panelGradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1D3B), Color(0xFF0B162D)],
          ),
          borderColor: const Color(0xFF2E73E8),
          glowColor: const Color(0x44367DFF),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.pie_chart_rounded,
                      color: Color(0xFFD4AF37), size: 21),
                  const SizedBox(width: 8),
                  Text(
                    '资金分布',
                    style: TextStyle(
                      color: const Color(0xFFF6D98A),
                      fontSize: sectionTitleSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '查看详情',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 14,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.75), size: 18),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _distributionRow(
                            '现金余额', cashBalance, const Color(0xFF20AEFF)),
                        _distributionRow(
                            '可用资金', available, const Color(0xFFF4A048)),
                        _distributionRow(
                            '冻结资金', frozen, const Color(0xFF7082FF)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 128,
                    height: 128,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 128,
                          height: 128,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [Color(0x33527CFF), Color(0x00325CCC)],
                            ),
                          ),
                        ),
                        PieChart(
                          PieChartData(
                            startDegreeOffset: -90,
                            centerSpaceRadius: 36,
                            sectionsSpace: 0,
                            borderData: FlBorderData(show: false),
                            sections: [
                              PieChartSectionData(
                                value: (availableRatio * 100).clamp(0.0, 100.0),
                                color: const Color(0xFFDAB241),
                                radius: 16,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: (100 - availableRatio * 100)
                                    .clamp(0.0, 100.0),
                                color: const Color(0x253C4A63),
                                radius: 16,
                                showTitle: false,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(availableRatio * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              '可用资金',
                              style: TextStyle(
                                color: Color(0xFFD2D9E8),
                                fontSize: 11,
                              ),
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
      ],
    );
  }

  Widget _coinBadge({double size = 112}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.asset(
        'assets/trading/coin_orbit.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0E265A), Color(0xFF0B1838)],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              'T',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.3,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _distributionRow(String label, double value, Color dot) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD8E2F2),
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_money(value)} $_currencyCode',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowPanel({
    required Widget child,
    LinearGradient? panelGradient,
    Color borderColor = const Color(0xFF2B72FF),
    Color glowColor = const Color(0x44206EFF),
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: panelGradient ??
            const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F1B34), Color(0xFF0A1326)],
            ),
        border: Border.all(color: borderColor.withValues(alpha: 0.62)),
        boxShadow: [
          BoxShadow(
            color: glowColor,
            blurRadius: 16,
            spreadRadius: 0.5,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  String _money(double value, {bool compact = true}) {
    final fmt = NumberFormat(compact ? '#,##0.00' : '#,##0.00');
    return fmt.format(value);
  }

  String get _currencyCode =>
      account.currency.toUpperCase() == 'USDT' ? 'USDT' : 'USD';
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
