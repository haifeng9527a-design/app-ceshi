import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// 详情页顶栏（参考主流行情 App）：左 返回 | 中 股票代码+左右箭头切换 | 右 分享
class DetailHeader extends StatelessWidget {
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
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onPrev != null) ...[
                          _iconButton(
                            icon: Icons.chevron_left,
                            size: 24,
                            onPressed: onPrev!,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            symbol,
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
                        if (onNext != null) ...[
                          const SizedBox(width: 4),
                          _iconButton(
                            icon: Icons.chevron_right,
                            size: 24,
                            onPressed: onNext!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  _iconButton(
                    icon: Icons.share_outlined,
                    size: 20,
                    onPressed: onShare ?? () {},
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
            child: Icon(icon, size: size, color: ChartTheme.textPrimary),
          ),
        ),
      ),
    );
  }
}
