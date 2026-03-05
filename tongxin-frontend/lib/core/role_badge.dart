import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 角色徽章：普通用户、交易员、管理员、会员 四种角色，各带图标与独立配色
class RoleBadge extends StatelessWidget {
  const RoleBadge({
    required this.roleLabel,
    this.compact = false,
    super.key,
  });

  final String? roleLabel;
  /// true 时更小间距，用于会话列表等紧凑布局
  final bool compact;

  /// 将后端返回的角色标识映射为样式 key（支持中英文）
  static String _toStyleKey(String label) {
    if (label == '客服' || label == 'Customer Service' || label == 'customer_service') return '_cs';
    if (label == '交易员' || label == 'Trader' || label == 'trader') return '_trader';
    if (label == '管理员' || label == 'Admin' || label == 'admin') return '_admin';
    if (label == '会员' || label == 'Member' || label == 'member' || label == 'VIP' || label == 'vip') return '_vip';
    return '_normal';
  }

  static ({IconData icon, Color color, Color? bgColor, List<Color>? gradientColors, FontWeight fontWeight}) _style(String key) {
    switch (key) {
      case '_cs':
        return (
          icon: Icons.support_agent_rounded,
          color: const Color(0xFF2AD37F),
          bgColor: const Color(0x222AD37F),
          gradientColors: null,
          fontWeight: FontWeight.w700,
        );
      case '_trader':
        return (
          icon: Icons.trending_up_rounded,
          color: Colors.white,
          bgColor: null,
          gradientColors: [const Color(0xFF0284C7), const Color(0xFF059669)],
          fontWeight: FontWeight.w600,
        );
      case '_admin':
        return (
          icon: Icons.admin_panel_settings_rounded,
          color: const Color(0xFF5C9EFF),
          bgColor: const Color(0x225C9EFF),
          gradientColors: null,
          fontWeight: FontWeight.w700,
        );
      case '_vip':
        return (
          icon: Icons.workspace_premium_rounded,
          color: const Color(0xFFB388FF),
          bgColor: const Color(0x22B388FF),
          gradientColors: null,
          fontWeight: FontWeight.w600,
        );
      case '_normal':
      default:
        return (
          icon: Icons.person_outline_rounded,
          color: const Color(0xFF8A8D93),
          bgColor: const Color(0x228A8D93),
          gradientColors: null,
          fontWeight: FontWeight.w500,
        );
    }
  }

  static String _customerServiceText(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('en') ? 'Customer Service' : '客服';
  }

  @override
  Widget build(BuildContext context) {
    final raw = roleLabel?.trim() ?? '';
    if (raw.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final displayLabel = switch (_toStyleKey(raw)) {
      '_cs' => _customerServiceText(context),
      '_trader' => l10n.roleTrader,
      '_admin' => l10n.roleAdmin,
      '_vip' => l10n.roleVip,
      _ => l10n.roleNormal,
    };
    final s = _style(_toStyleKey(raw));
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    final fontSize = compact ? 10.0 : 11.0;
    final iconSize = compact ? 12.0 : 14.0;
    final useGradient = s.gradientColors != null && s.gradientColors!.length >= 2;
    return Container(
      margin: EdgeInsets.only(left: compact ? 4 : 6),
      padding: padding,
      decoration: BoxDecoration(
        gradient: useGradient
            ? LinearGradient(
                colors: s.gradientColors!,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : null,
        color: useGradient ? null : s.bgColor,
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        boxShadow: useGradient
            ? [
                BoxShadow(
                  color: s.gradientColors!.first.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
        border: useGradient
            ? null
            : Border.all(color: s.color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: iconSize, color: s.color),
          SizedBox(width: compact ? 3 : 4),
          Text(
            displayLabel,
            style: TextStyle(
              color: s.color,
              fontSize: fontSize,
              fontWeight: s.fontWeight,
            ),
          ),
        ],
      ),
    );
  }
}
