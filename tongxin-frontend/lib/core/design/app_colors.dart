import 'package:flutter/material.dart';

/// 统一颜色 Token：深色金融风
/// 禁止在业务代码中直接使用 Color(0xFF...)，必须引用本文件
abstract class AppColors {
  AppColors._();

  // ---------- 主色 ----------
  static const Color primary = Color(0xFFD4AF37);
  static const Color primaryDim = Color(0xFFB8923F);
  static const Color secondary = Color(0xFF8A6D1D);

  // ---------- 背景与层级 ----------
  static const Color scaffold = Color(0xFF0B0C0E);
  static const Color surface = Color(0xFF111215);
  static const Color surfaceElevated = Color(0xFF161B22);
  static const Color surfaceHover = Color(0xFF1C2128);
  static const Color surface2 = Color(0xFF21262D);

  // ---------- 边框 ----------
  static const Color border = Color(0xFF30363D);
  static const Color borderSubtle = Color(0xFF21262D);
  static const Color borderFocus = Color(0xFF2A3544);

  // ---------- 文字 ----------
  static const Color textPrimary = Color(0xFFE8E6E1);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textTertiary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF6E7681);

  // ---------- 语义色（涨跌/状态）----------
  static const Color positive = Color(0xFF3FB950);
  static const Color negative = Color(0xFFF85149);
  static const Color warning = Color(0xFFD29922);
  static const Color danger = Color(0xFFE5484D);
  static const Color success = Color(0xFF34C759);

  // ---------- 输入框 ----------
  static const Color inputBg = Color(0xFF0F1419);

  // ---------- 表格/列表 ----------
  static const Color tableHeaderBg = Color(0xFF161B22);
  static const Color rowSelectedBg = Color(0x26238636);

  // ---------- 透明度变体 ----------
  static Color primarySubtle(double opacity) => primary.withValues(alpha: opacity);
  static Color positiveSubtle(double opacity) => positive.withValues(alpha: opacity);
  static Color negativeSubtle(double opacity) => negative.withValues(alpha: opacity);
}
