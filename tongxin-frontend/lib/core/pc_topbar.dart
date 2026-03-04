import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'pc_dashboard_theme.dart';

/// 简洁顶栏：页面标题 + 搜索 + 通知 + 头像
class PcTopbar extends StatelessWidget {
  const PcTopbar({
    super.key,
    this.pageTitle,
    this.unreadCount = 0,
    this.userAvatarUrl,
  });

  final String? pageTitle;
  final int unreadCount;
  final String? userAvatarUrl;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: PcTopbar.height,
      padding: const EdgeInsets.symmetric(horizontal: PcDashboardTheme.contentPadding),
      decoration: BoxDecoration(
        color: PcDashboardTheme.surfaceVariant,
        border: Border(bottom: BorderSide(color: PcDashboardTheme.border, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            pageTitle ?? AppLocalizations.of(context)!.pcHome,
            style: PcDashboardTheme.titleMedium.copyWith(color: PcDashboardTheme.text),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: _SearchField(),
          ),
          const SizedBox(width: 16),
          _IconBtn(
            icon: Icons.notifications_outlined,
            tooltip: AppLocalizations.of(context)!.pcNotify,
            badge: unreadCount > 0 ? (unreadCount > 99 ? '99+' : '$unreadCount') : null,
            onTap: () {},
          ),
          const SizedBox(width: 8),
          _UserAvatar(url: userAvatarUrl),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: TextField(
          decoration: PcDashboardTheme.inputDecoration(
            hintText: AppLocalizations.of(context)!.pcSearchHint,
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: PcDashboardTheme.textMuted),
          ),
          style: PcDashboardTheme.bodyMedium.copyWith(color: PcDashboardTheme.text),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget child = Icon(icon, size: 22, color: PcDashboardTheme.textSecondary);
    if (badge != null) {
      child = Badge(
        label: Text(badge!, style: const TextStyle(fontSize: 10, color: Colors.white)),
        backgroundColor: PcDashboardTheme.danger,
        child: child,
      );
    }
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PcDashboardTheme.radiusSm),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(20),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: PcDashboardTheme.border,
          backgroundImage: (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
          child: (url == null || url!.isEmpty)
              ? Icon(Icons.person_rounded, size: 20, color: PcDashboardTheme.textMuted)
              : null,
        ),
      ),
    );
  }
}
