import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'trading_api_client.dart';

class TradingUi {
  static const Color pageBg = Color(0xFF0F1722);
  static const Color surface = Color(0xFF141E2E);
  static const Color accent = Color(0xFFD4AF37);
  static const Color textMuted = Color(0xFF8A93A6);
  static const Color border = Color(0xFF263249);
}

class TradingPageScaffold extends StatelessWidget {
  const TradingPageScaffold({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TradingUi.pageBg,
      child: child,
    );
  }
}

class TradingSectionHeader extends StatelessWidget {
  const TradingSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: TradingUi.accent, size: 18),
          const SizedBox(width: 6),
        ],
        Text(
          title,
          style: const TextStyle(
            color: TradingUi.accent,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class TradingStateBlock extends StatelessWidget {
  const TradingStateBlock.loading({super.key})
      : isLoading = true,
        message = null,
        isError = false;

  const TradingStateBlock.empty({
    super.key,
    required this.message,
  })  : isLoading = false,
        isError = false;

  const TradingStateBlock.error({
    super.key,
    required this.message,
  })  : isLoading = false,
        isError = true;

  final bool isLoading;
  final bool isError;
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message ?? '',
          style: TextStyle(
            color: isError ? Colors.red.shade300 : TradingUi.textMuted,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class TradingSummaryStrip extends StatelessWidget {
  const TradingSummaryStrip({
    super.key,
    required this.summary,
    this.loading = false,
    this.errorText,
  });

  final TradingAccountSummary? summary;
  final bool loading;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: TradingUi.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TradingUi.border),
      ),
      child: loading
          ? const SizedBox(
              height: 30,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : errorText != null
              ? Text(
                  errorText!,
                  style: TextStyle(color: Colors.red.shade300, fontSize: 12),
                )
              : _summaryContent(context, summary),
    );
  }

  Widget _summaryContent(BuildContext context, TradingAccountSummary? s) {
    if (s == null) {
      return Text(
        AppLocalizations.of(context)!.tradingSummaryUnavailable,
        style: const TextStyle(color: TradingUi.textMuted, fontSize: 12),
      );
    }
    // 顺序：总资产 → 可用资金 → 市值（已移除挂单）
    return Row(
      children: [
        Expanded(child: _item(AppLocalizations.of(context)!.tradingSummaryEquity, s.equity)),
        Expanded(child: _item(AppLocalizations.of(context)!.tradingSummaryAvailableFunds, s.cashAvailable)),
        Expanded(child: _item(AppLocalizations.of(context)!.tradingSummaryMarketValue, s.marketValue)),
      ],
    );
  }

  Widget _item(String label, double value, {bool isInt = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: TradingUi.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          isInt ? value.toStringAsFixed(0) : value.toStringAsFixed(2),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
