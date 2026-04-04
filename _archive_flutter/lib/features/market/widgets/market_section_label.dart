import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';

/// 行情区块标题：如「主要指数」「涨跌榜」「Watchlist」
/// 使用 design tokens
class MarketSectionLabel extends StatelessWidget {
  const MarketSectionLabel({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.body.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }
}
