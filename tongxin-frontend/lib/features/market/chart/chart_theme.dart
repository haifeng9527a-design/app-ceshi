import 'package:flutter/material.dart';

/// 分时/K线图表页：TradingView 风格深色，克制正负色（禁止荧光绿）
class ChartTheme {
  ChartTheme._();

  static const Color background = Color(0xFF0D1117);
  static const Color cardBackground = Color(0xFF161B22);
  static const Color surface2 = Color(0xFF21262D);
  static const Color border = Color(0xFF30363D);
  static const Color borderSubtle = Color(0xFF21262D);
  /// hover 时背景提亮约 5%
  static const Color surfaceHover = Color(0xFF1C2128);
  static const Color gridLine = Color(0x0DFFFFFF);
  /// 分时图与成交量之间 1px 分割线
  static const Color chartDivider = Color(0xFF21262D);
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textTertiary = Color(0xFF6E7681);
  static const Color up = Color(0xFF3FB950);
  static const Color down = Color(0xFFF85149);
  static const Color accentGold = Color(0xFFD29922);

  static const double topBarHeight = 48.0;
  static const double radiusCard = 12.0;
  static const double radiusButton = 10.0;
  static const double pagePadding = 24.0;
  static const double sectionGap = 16.0;
  static const double innerPadding = 12.0;
  static const double toolbarButtonHeight = 30.0;
  static const double toolbarSpacing = 8.0;

  static const String fontMono = 'monospace';
  static const FontFeature tabularFigures = FontFeature.tabularFigures();
}
