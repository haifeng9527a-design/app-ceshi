import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../watchlist_repository.dart';
import 'chart_theme.dart';

/// TradingView 风格导航栏（桌面端，40px 高）
///
/// 布局: ← 返回 | ◁ 符号 ★ ▷ | 分隔线 | "图表" Tab | ... | [Badge] [Badge]
class TvNavBar extends StatefulWidget {
  const TvNavBar({
    super.key,
    required this.symbol,
    this.name,
    this.onBack,
    this.onPrev,
    this.onNext,
    this.marketTypeLabel,
    this.statusLabel,
    this.statusColor,
    this.onSymbolTap,
  });

  final String symbol;
  final String? name;
  final VoidCallback? onBack;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final String? marketTypeLabel;
  final String? statusLabel;
  final Color? statusColor;
  /// 点击符号名称时的回调（弹出币种选择器）
  final VoidCallback? onSymbolTap;

  @override
  State<TvNavBar> createState() => _TvNavBarState();
}

class _TvNavBarState extends State<TvNavBar> {
  bool _inWatchlist = false;

  @override
  void initState() {
    super.initState();
    _checkWatchlist();
  }

  @override
  void didUpdateWidget(covariant TvNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol) {
      _checkWatchlist();
    }
  }

  Future<void> _checkWatchlist() async {
    final list = await WatchlistRepository.instance.getWatchlist();
    if (mounted) {
      setState(() => _inWatchlist = list.contains(widget.symbol.trim()));
    }
  }

  Future<void> _toggleWatchlist() async {
    final s = widget.symbol.trim();
    if (s.isEmpty) return;
    if (_inWatchlist) {
      await WatchlistRepository.instance.removeWatchlist(s);
    } else {
      await WatchlistRepository.instance.addWatchlist(s);
    }
    if (mounted) {
      setState(() => _inWatchlist = !_inWatchlist);
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _inWatchlist
                ? l10n.searchAddedToWatchlist(s)
                : l10n.watchlistRemove,
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ChartTheme.tvNavBarHeight,
      decoration: const BoxDecoration(
        color: ChartTheme.tvTopBarBg,
        border: Border(
          bottom: BorderSide(color: ChartTheme.tvBorder, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 返回按钮
          _iconBtn(Icons.arrow_back_ios_new_rounded, widget.onBack, size: 14),
          // 上一个符号
          if (widget.onPrev != null)
            _iconBtn(Icons.chevron_left_rounded, widget.onPrev),
          // 符号（可点击，弹出币种选择器）
          InkWell(
            onTap: widget.onSymbolTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.symbol,
                    style: const TextStyle(
                      color: ChartTheme.tvTextActive,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: ChartTheme.fontMono,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (widget.name != null && widget.name!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        widget.name!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ChartTheme.tvTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                  if (widget.onSymbolTap != null) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down,
                        size: 16, color: ChartTheme.tvTextMuted),
                  ],
                ],
              ),
            ),
          ),
          // 下一个符号
          if (widget.onNext != null)
            _iconBtn(Icons.chevron_right_rounded, widget.onNext),
          // ★ 自选星标
          const SizedBox(width: 4),
          Tooltip(
            message: _inWatchlist
                ? AppLocalizations.of(context)!.watchlistRemove
                : AppLocalizations.of(context)!.searchAddWatchlist,
            child: _iconBtn(
              _inWatchlist ? Icons.star_rounded : Icons.star_border_rounded,
              _toggleWatchlist,
              size: 18,
              color: _inWatchlist ? ChartTheme.accentGold : ChartTheme.tvTextMuted,
            ),
          ),
          // 分隔线
          _divider(),
          // "图表" Tab — 选中态（蓝色下划线）
          _navTab('图表', selected: true),
          const Spacer(),
          // Badge: 市场类型
          if (widget.marketTypeLabel != null &&
              widget.marketTypeLabel!.isNotEmpty)
            _badge(widget.marketTypeLabel!, ChartTheme.accentGold),
          const SizedBox(width: 6),
          // Badge: 状态
          if (widget.statusLabel != null && widget.statusLabel!.isNotEmpty)
            _badge(
                widget.statusLabel!, widget.statusColor ?? ChartTheme.tvTextMuted),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap,
      {double size = 16, Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Icon(icon, size: size, color: color ?? ChartTheme.tvTextMuted),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: ChartTheme.tvBorder,
    );
  }

  Widget _navTab(String label, {bool selected = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: selected
          ? const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: ChartTheme.tabUnderline, width: 2),
              ),
            )
          : null,
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: selected ? ChartTheme.tvTextActive : ChartTheme.tvTextMuted,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _badge(String label, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
