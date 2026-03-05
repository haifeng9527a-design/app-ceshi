import 'package:flutter/material.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_radius.dart';
import '../../../../ui/components/app_input.dart';
import '../../../../l10n/app_localizations.dart';
import '../search_page.dart';

/// 行情页搜索栏：点击跳转 SearchPage
/// 支持 PC/移动端布局，使用 design tokens
class MarketSearchBar extends StatelessWidget {
  const MarketSearchBar({super.key, this.isPc = false});

  final bool isPc;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(isPc ? AppRadius.md : AppRadius.sm);
    return Container(
      decoration: BoxDecoration(
        color: isPc ? AppColors.inputBg : AppColors.surface,
        borderRadius: radius,
      ),
      child: AppInput(
        hintText: AppLocalizations.of(context)!.marketSearchSymbols,
        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
        readOnly: true,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SearchPage()),
        ),
      ),
    );
  }
}
