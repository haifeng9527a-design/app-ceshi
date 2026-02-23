import 'package:flutter/material.dart';

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

  static const String _normal = '普通用户';
  static const String _trader = '交易员';
  static const String _admin = '管理员';
  static const String _vip = '会员';

  static ({IconData icon, Color color, Color? bgColor, List<Color>? gradientColors, FontWeight fontWeight}) _style(String label) {
    switch (label) {
      case _trader:
        return (
          icon: Icons.trending_up_rounded,
          color: Colors.white,
          bgColor: null,
          gradientColors: [const Color(0xFF0284C7), const Color(0xFF059669)],
          fontWeight: FontWeight.w600,
        );
      case _admin:
        return (
          icon: Icons.admin_panel_settings_rounded,
          color: const Color(0xFF5C9EFF),
          bgColor: const Color(0x225C9EFF),
          gradientColors: null,
          fontWeight: FontWeight.w700,
        );
      case _vip:
        return (
          icon: Icons.workspace_premium_rounded,
          color: const Color(0xFFB388FF),
          bgColor: const Color(0x22B388FF),
          gradientColors: null,
          fontWeight: FontWeight.w600,
        );
      case _normal:
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

  @override
  Widget build(BuildContext context) {
    final label = roleLabel?.trim() ?? '';
    if (label.isEmpty) return const SizedBox.shrink();
    final s = _style(label);
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
                  color: s.gradientColors!.first.withOpacity(0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
        border: useGradient
            ? null
            : Border.all(color: s.color.withOpacity(0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: iconSize, color: s.color),
          SizedBox(width: compact ? 3 : 4),
          Text(
            label,
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
