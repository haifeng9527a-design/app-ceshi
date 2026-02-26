import 'package:flutter/material.dart';

import 'chart_theme.dart';

/// 图表壳：surface2 背景 + 1px border + 12 圆角，内边距 12~16，顶部留白给 tooltip
class TvChartContainer extends StatelessWidget {
  const TvChartContainer({
    super.key,
    required this.child,
    this.padding,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: ChartTheme.pagePadding),
      decoration: BoxDecoration(
        color: ChartTheme.surface2,
        borderRadius: BorderRadius.circular(ChartTheme.radiusCard),
        border: Border.all(color: ChartTheme.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
            spreadRadius: -2,
          ),
        ],
      ),
      clipBehavior: clipBehavior,
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(ChartTheme.innerPadding, 16, ChartTheme.innerPadding, ChartTheme.innerPadding),
        child: child,
      ),
    );
  }
}
