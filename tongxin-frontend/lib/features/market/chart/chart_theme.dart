import 'package:flutter/material.dart';

/// 分时/K线图表页：TradingView 风格深色，克制正负色（禁止荧光绿）
/// 手机端优化：更大字号、更清晰对比度、更易读的网格（参考同花顺/东方财富）
class ChartTheme {
  ChartTheme._();

  static const Color background = Color(0xFF0D1117);
  static const Color cardBackground = Color(0xFF161B22);
  static const Color surface2 = Color(0xFF21262D);
  static const Color border = Color(0xFF30363D);
  static const Color borderSubtle = Color(0xFF21262D);
  /// hover 时背景提亮约 5%
  static const Color surfaceHover = Color(0xFF1C2128);
  /// 网格线：提高对比度，手机端更易读（参考同花顺/东方财富）
  static const Color gridLine = Color(0x28FFFFFF);
  /// 分时图与成交量之间 1px 分割线
  static const Color chartDivider = Color(0xFF21262D);
  /// 主文字：纯白，清晰易读
  static const Color textPrimary = Color(0xFFF0F5FA);
  /// 次要文字：浅灰
  static const Color textSecondary = Color(0xFFB0B8C4);
  /// 辅助/标签：中灰
  static const Color textTertiary = Color(0xFF8B949E);
  /// 涨：柔和绿，不刺眼
  static const Color up = Color(0xFF3FB950);
  /// 跌：柔和红
  static const Color down = Color(0xFFF85149);
  static const Color accentGold = Color(0xFFD29922);
  /// Tab 选中背景（蓝灰，参考主流行情 App）
  static const Color tabSelectedBg = Color(0xFF1E3A5F);
  /// Tab 选中下划线蓝
  static const Color tabUnderline = Color(0xFF3B82F6);
  /// 成交量涨柱（蓝，与参考图一致）
  static const Color volumeUp = Color(0xFF3B82F6);
  /// 均价线：琥珀色，与分时线区分
  static const Color avgLine = Color(0xFFF59E0B);

  static const double topBarHeight = 64.0;
  static const double radiusCard = 10.0;
  static const double radiusButton = 8.0;
  static const double pagePadding = 16.0;
  static const double sectionGap = 16.0;
  static const double innerPadding = 12.0;
  static const double toolbarButtonHeight = 32.0;
  static const double toolbarSpacing = 8.0;

  /// 手机端：关键数据字号加大，确保清晰可读
  static const double fontSizePrice = 22.0;
  static const double fontSizeKey = 14.0;
  static const double fontSizeAxis = 12.0;
  static const double fontSizeLabel = 11.0;

  static const String fontMono = 'monospace';
  static const FontFeature tabularFigures = FontFeature.tabularFigures();

  /// 股票价格格式化：与主流看盘软件一致，低价股显示 4 位小数
  /// v >= 100: 2 位（如 150.25）；v >= 1: 4 位（如 1.2200）；v < 1: 4 位（如 0.5537）
  static String formatPrice(double v) {
    if (v >= 10000) return v.toStringAsFixed(0);
    if (v >= 100) return v.toStringAsFixed(2);
    if (v >= 1) return v.toStringAsFixed(4);
    return v.toStringAsFixed(4);
  }
}
