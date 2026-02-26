import 'package:flutter/material.dart';

import 'pc_dashboard_theme.dart';

/// PC 首页：欢迎 + 指标卡片 + 快捷入口（完整可看 UI）
class PcDashboardPage extends StatelessWidget {
  const PcDashboardPage({
    super.key,
    this.onNavigateToSection,
  });

  /// 点击快捷入口时跳转到对应 Tab：1=行情 2=自选 3=消息 4=排行榜
  final ValueChanged<int>? onNavigateToSection;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeSection(),
          const SizedBox(height: 28),
          _MetricCards(),
          const SizedBox(height: 28),
          _QuickEntrySection(onNavigateToSection: onNavigateToSection),
        ],
      ),
    );
  }
}

class _WelcomeSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting = '你好';
    if (hour < 12) greeting = '上午好';
    else if (hour < 18) greeting = '下午好';
    else greeting = '晚上好';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: PcDashboardTheme.display.copyWith(
            color: PcDashboardTheme.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '欢迎回来，这是你的工作台概览',
          style: PcDashboardTheme.bodyLarge.copyWith(color: PcDashboardTheme.textSecondary),
        ),
      ],
    );
  }
}

class _MetricCards extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
        return GridView.count(
          crossAxisCount: count,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 2.2,
          children: const [
            _MetricCard(
              label: '关注',
              value: '0',
              subtitle: '已关注标的',
              icon: Icons.star_outline,
            ),
            _MetricCard(
              label: '今日会话',
              value: '0',
              subtitle: '消息数',
              icon: Icons.chat_bubble_outline,
            ),
            _MetricCard(
              label: '自选',
              value: '0',
              subtitle: '自选标的',
              icon: Icons.list_alt,
            ),
            _MetricCard(
              label: '排名',
              value: '—',
              subtitle: '当前排名',
              icon: Icons.leaderboard_outlined,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String label;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: PcDashboardTheme.cardPadding,
      decoration: PcDashboardTheme.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: PcDashboardTheme.accentSubtle,
              borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 22, color: PcDashboardTheme.accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: PcDashboardTheme.label.copyWith(decoration: TextDecoration.none),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: PcDashboardTheme.titleMedium.copyWith(
                    color: PcDashboardTheme.text,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: PcDashboardTheme.bodySmall.copyWith(decoration: TextDecoration.none),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickEntrySection extends StatelessWidget {
  const _QuickEntrySection({this.onNavigateToSection});

  final ValueChanged<int>? onNavigateToSection;

  static const List<_EntryItem> _entries = [
    _EntryItem(title: '行情', subtitle: '查看市场与指数', icon: Icons.candlestick_chart_outlined, index: 1),
    _EntryItem(title: '自选', subtitle: '管理自选标的', icon: Icons.star_outline, index: 2),
    _EntryItem(title: '消息', subtitle: '会话与好友', icon: Icons.chat_bubble_outline, index: 3),
    _EntryItem(title: '排行榜', subtitle: '查看排名', icon: Icons.leaderboard_outlined, index: 4),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '快捷入口',
          style: PcDashboardTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 500 ? 2 : 1);
            return GridView.count(
              crossAxisCount: crossCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.55,
              children: _entries.map((e) => _QuickEntryCard(
                item: e,
                onTap: onNavigateToSection != null ? () => onNavigateToSection!(e.index) : null,
              )).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _EntryItem {
  const _EntryItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.index,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final int index;
}

class _QuickEntryCard extends StatelessWidget {
  const _QuickEntryCard({
    required this.item,
    this.onTap,
  });

  final _EntryItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PcDashboardTheme.radiusMd),
        child: Container(
          padding: PcDashboardTheme.cardPadding,
          decoration: PcDashboardTheme.cardDecoration(hover: false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: PcDashboardTheme.accentSubtle,
                  borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
                ),
                alignment: Alignment.center,
                child: Icon(item.icon, size: 22, color: PcDashboardTheme.accent),
              ),
              const SizedBox(height: 14),
              Text(
                item.title,
                style: PcDashboardTheme.titleSmall.copyWith(color: PcDashboardTheme.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                item.subtitle,
                style: PcDashboardTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (onTap != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '进入',
                      style: PcDashboardTheme.bodySmall.copyWith(
                        color: PcDashboardTheme.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: PcDashboardTheme.accent,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
