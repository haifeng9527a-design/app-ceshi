import 'package:flutter/material.dart';

/// PC 端统一主题：安静、克制的深色桌面风格（非交易终端风）
class PcDashboardTheme {
  PcDashboardTheme._();

  // ---- 主色 ----
  static const Color surface = Color(0xFF0B0F14);       // 主背景
  static const Color surfaceVariant = Color(0xFF11161D); // 侧栏、顶栏
  static const Color surfaceElevated = Color(0xFF161D26); // 卡片
  static const Color surfaceHover = Color(0xFF1A222C);

  static const Color border = Color(0xFF1E2630);
  static const Color borderFocus = Color(0xFF2A3544);

  static const Color text = Color(0xFFE8E6E1);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFF6B7280);

  /// 主强调色：暖金/琥珀，用于选中、链接、重点
  static const Color accent = Color(0xFFD4A853);
  static const Color accentDim = Color(0xFFB8923F);
  static const Color success = Color(0xFF34C759);
  static const Color danger = Color(0xFFE5484D);
  static const Color warning = Color(0xFFE8A838);

  static const Color inputBg = Color(0xFF0F1419);

  static final Color accentSubtle = accent.withValues(alpha: 0.12);
  static final Color shadowCard = Colors.black.withValues(alpha: 0.25);

  // ---- 圆角与间距 ----
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const EdgeInsets cardPadding = EdgeInsets.all(20);
  static const double contentPadding = 28;

  // ---- 字体 ----
  static TextStyle get display => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: text,
        letterSpacing: -0.5,
        height: 1.25,
        decoration: TextDecoration.none,
      );

  static TextStyle get titleLarge => TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: text,
        letterSpacing: -0.3,
        height: 1.3,
        decoration: TextDecoration.none,
      );

  static TextStyle get titleMedium => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: text,
        height: 1.35,
        decoration: TextDecoration.none,
      );

  static TextStyle get titleSmall => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: text,
        decoration: TextDecoration.none,
      );

  static TextStyle get bodyLarge => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: text,
        height: 1.45,
        decoration: TextDecoration.none,
      );

  static TextStyle get bodyMedium => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: textSecondary,
        height: 1.4,
        decoration: TextDecoration.none,
      );

  static TextStyle get bodySmall => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textMuted,
        height: 1.35,
        decoration: TextDecoration.none,
      );

  static TextStyle get label => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: textMuted,
        letterSpacing: 0.5,
        height: 1.2,
        decoration: TextDecoration.none,
      );

  // ---- 卡片 ----
  static BoxDecoration cardDecoration({bool hover = false}) => BoxDecoration(
        color: surfaceElevated,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(
          color: hover ? borderFocus : border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: shadowCard,
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      );

  static InputDecoration inputDecoration({
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) =>
      InputDecoration(
        hintText: hintText,
        hintStyle: bodyMedium.copyWith(color: textMuted),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
