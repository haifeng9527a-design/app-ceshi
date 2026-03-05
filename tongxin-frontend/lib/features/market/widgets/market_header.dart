import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../search_page.dart';
import '../watchlist_page.dart';

/// 行情页头部：图标 + 标题 + 操作按钮（AI/自选/搜索/消息）
/// 使用 design tokens，禁止硬编码
class MarketHeader extends StatelessWidget {
  const MarketHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.only(left: AppSpacing.md, top: AppSpacing.md - AppSpacing.xs, right: AppSpacing.xs, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.public_rounded, color: AppColors.primary, size: 26),
          SizedBox(width: AppSpacing.sm),
          Text(
            AppLocalizations.of(context)!.marketTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            color: AppColors.textSecondary,
            onPressed: () {},
            tooltip: 'AI',
          ),
          IconButton(
            icon: const Icon(Icons.star_border),
            color: AppColors.textSecondary,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WatchlistPage()),
              );
            },
            tooltip: AppLocalizations.of(context)!.navWatchlist,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            color: AppColors.textSecondary,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchPage()),
              );
            },
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.mail_outline),
                color: AppColors.textSecondary,
                onPressed: () {},
              ),
              Positioned(
                right: AppSpacing.sm,
                top: AppSpacing.sm,
                child: Container(
                  width: AppSpacing.sm,
                  height: AppSpacing.sm,
                  decoration: BoxDecoration(
                    color: AppColors.negative,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
