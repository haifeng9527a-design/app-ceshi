import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../watchlist_repository.dart';
import 'chart_theme.dart';

/// 详情页顶栏（参考主流行情 App）：左 返回 | 中 股票代码+左右箭头切换 | 右 加入自选
/// 支持在股票代码区域左右滑动切换上一只/下一只
class DetailHeader extends StatefulWidget {
  const DetailHeader({
    super.key,
    required this.symbol,
    this.name,
    this.exchangeOrName,
    this.onBack,
    this.onShare,
    this.onMore,
    this.onPrev,
    this.onNext,
  });

  final String symbol;
  /// 股票名称（如「特斯拉」），优先于 exchangeOrName
  final String? name;
  final String? exchangeOrName;
  final VoidCallback? onBack;
  final VoidCallback? onShare;
  /// 更多菜单（汉堡菜单），预留扩展入口
  final VoidCallback? onMore;
  /// 切换上一只股票，有值时显示左箭头
  final VoidCallback? onPrev;
  /// 切换下一只股票，有值时显示右箭头
  final VoidCallback? onNext;

  @override
  State<DetailHeader> createState() => _DetailHeaderState();
}

class _DetailHeaderState extends State<DetailHeader> {
  static const double _swipeThreshold = 100.0;
  bool _inWatchlist = false;

  @override
  void initState() {
    super.initState();
    _checkWatchlist();
  }

  @override
  void didUpdateWidget(covariant DetailHeader oldWidget) {
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
          content: Text(_inWatchlist ? l10n.searchAddedToWatchlist(s) : l10n.watchlistRemove),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: ChartTheme.topBarHeight,
        child: Material(
          color: ChartTheme.background,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: ChartTheme.border, width: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _iconButton(
                    icon: Icons.arrow_back_ios_new,
                    size: 18,
                    onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onHorizontalDragEnd: (d) {
                        if (widget.onPrev == null && widget.onNext == null) return;
                        final v = d.velocity.pixelsPerSecond.dx;
                        if (v < -_swipeThreshold && widget.onNext != null) {
                          widget.onNext!();
                        } else if (v > _swipeThreshold && widget.onPrev != null) {
                          widget.onPrev!();
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.onPrev != null) ...[
                            _iconButton(
                              icon: Icons.chevron_left,
                              size: 24,
                              onPressed: widget.onPrev!,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              widget.symbol,
                              style: const TextStyle(
                                color: ChartTheme.up,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                fontFamily: ChartTheme.fontMono,
                                fontFeatures: [ChartTheme.tabularFigures],
                                letterSpacing: 1.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (widget.onNext != null) ...[
                            const SizedBox(width: 4),
                            _iconButton(
                              icon: Icons.chevron_right,
                              size: 24,
                              onPressed: widget.onNext!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Tooltip(
                    message: _inWatchlist
                        ? AppLocalizations.of(context)!.watchlistRemove
                        : AppLocalizations.of(context)!.searchAddWatchlist,
                    child: _iconButton(
                      icon: _inWatchlist ? Icons.star : Icons.star_border_outlined,
                      size: 22,
                      color: _inWatchlist ? ChartTheme.accentGold : ChartTheme.textPrimary,
                      onPressed: _toggleWatchlist,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required double size,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(ChartTheme.radiusButton),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Icon(icon, size: size, color: color ?? ChartTheme.textPrimary),
          ),
        ),
      ),
    );
  }
}
