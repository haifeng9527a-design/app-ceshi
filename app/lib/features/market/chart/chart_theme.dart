import 'package:flutter/material.dart';

/// 分时/K线图表页统一视觉规范（深色交易终端）
class ChartTheme {
  ChartTheme._();

  static const Color background = Color(0xFF0B0F14);
  static const Color cardBackground = Color(0xFF0F1722);
  static const Color border = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
  static const Color borderSubtle = Color(0x24FFFFFF); // rgba(255,255,255,0.14)
  static const Color gridLine = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const Color textPrimary = Color(0xFFEBEBEB); // rgba(255,255,255,0.92)
  static const Color textSecondary = Color(0x8CFFFFFF); // rgba(255,255,255,0.55)
  static const Color up = Color(0xFF22C55E);
  static const Color down = Color(0xFFEF4444);
  static const Color accentGold = Color(0xFFD6B46A);

  static const double topBarHeight = 64.0;
  static const double radiusCard = 16.0;
  static const double radiusButton = 12.0;

  static const String fontMono = 'monospace';
}
