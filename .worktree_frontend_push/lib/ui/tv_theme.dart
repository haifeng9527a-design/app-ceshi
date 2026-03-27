import 'package:flutter/material.dart';

/// TradingView 风格设计系统：深色、通透、专业
/// 用于行情页（美股/外汇/加密货币）统一视觉
///
/// @deprecated 请优先使用 lib/core/design/design_tokens.dart 与 AppTheme。
/// 保留本类用于桥接旧代码，新代码禁止引用。
@Deprecated('Use design_tokens and AppTheme instead')
class TvTheme {
  TvTheme._();

  // ---------- 背景与层级 ----------
  static const Color bg = Color(0xFF0D1117);
  static const Color surface = Color(0xFF161B22);
  static const Color surface2 = Color(0xFF21262D);
  static const Color border = Color(0xFF30363D);
  static const Color borderSubtle = Color(0xFF21262D);

  // ---------- 文字 ----------
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textTertiary = Color(0xFF6E7681);

  // ---------- 语义色（克制、可读，禁止荧光绿）----------
  static const Color positive = Color(0xFF3FB950);
  static const Color negative = Color(0xFFF85149);
  static const Color warning = Color(0xFFD29922);

  // ---------- 圆角与边框 ----------
  static const double radius = 12;
  static const double radiusSm = 10;
  static const double borderWidth = 1;

  // ---------- 间距 ----------
  static const double pagePadding = 24;
  static const double sectionGap = 16;
  static const double innerPadding = 12;
  static const double rowHeight = 46;
  static const double tableHeaderHeight = 40;

  // ---------- 阴影（深色下克制）----------
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 8,
          offset: const Offset(0, 2),
          spreadRadius: -2,
        ),
      ];

  static BoxDecoration cardDecoration({bool hover = false}) => BoxDecoration(
        color: surface2,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: hover ? border : borderSubtle,
          width: borderWidth,
        ),
        boxShadow: cardShadow,
      );

  // ---------- 字体层级 ----------
  static const String fontMono = 'monospace';

  /// Title: 16 / semibold
  static TextStyle get title => const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        height: 1.35,
        decoration: TextDecoration.none,
      );

  /// Data: 22–26 / bold（价格等核心数据）
  static TextStyle get data => const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        fontFamily: fontMono,
        height: 1.25,
        decoration: TextDecoration.none,
      );

  static TextStyle get dataSmall => const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        fontFamily: fontMono,
        height: 1.25,
        decoration: TextDecoration.none,
      );

  /// Body: 13–14 / medium
  static TextStyle get body => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textPrimary,
        height: 1.4,
        decoration: TextDecoration.none,
      );

  static TextStyle get bodySecondary => const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: textSecondary,
        height: 1.4,
        decoration: TextDecoration.none,
      );

  /// Meta: 12 / regular（表头、辅助信息）
  static TextStyle get meta => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textSecondary,
        height: 1.35,
        decoration: TextDecoration.none,
      );

  static TextStyle get metaTertiary => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textTertiary,
        height: 1.35,
        decoration: TextDecoration.none,
      );

  // ---------- 表格 ----------
  static const Color tableHeaderBg = Color(0xFF161B22);
  static const Color rowHoverBg = Color(0xFF1C2128);
  static final Color rowSelectedBg = const Color(0xFF238636).withValues(alpha: 0.15);

  // ---------- Orbit Splash 启动页（深色、克制，无荧光）----------
  static const Color splashBg = Color(0xFF020A2A);
  static const Color splashBg2 = Color(0xFF0B2E6A);
  static const Color splashSurface = Color(0xFF0F3A7A);
  static const Color splashTextPrimary = Color(0xFFEAF3FF);
  static const Color splashTextSecondary = Color(0xFFAFC3DA);
  static const Color splashAccentCyan = Color(0xFF22D3EE);
  static const Color splashAccentPurple = Color(0xFFA78BFA);
  static const Color splashAccentGold = Color(0xFFD4AF37);
  static const Color splashAccentTeal = Color(0xFF2DD4BF);

  static const double splashRadius = 12;
  static const double splashRadiusSm = 8;
  static List<BoxShadow> get splashLogoShadow => [
        BoxShadow(
          color: splashAccentCyan.withValues(alpha: 0.25),
          blurRadius: 24,
          offset: Offset.zero,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ];

  /// Splash 标题 / Logo
  static TextStyle get splashLogoStyle => const TextStyle(
        fontSize: 42,
        fontWeight: FontWeight.w300,
        letterSpacing: 14,
        color: splashTextPrimary,
        height: 1.2,
        fontFeatures: [FontFeature.tabularFigures()],
      );

  /// Splash 副标题
  static TextStyle get splashSubtitleStyle => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 2.5,
        color: splashTextSecondary,
        height: 1.35,
      );
}
