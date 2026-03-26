import 'package:flutter/material.dart';

/// 统一间距 Token：8px 网格系统
/// 禁止在业务代码中使用魔法数字（如 EdgeInsets.all(14)），必须引用本文件
abstract class AppSpacing {
  AppSpacing._();

  /// xs: 4px（仅用于极紧凑场景，需说明原因）
  static const double xs = 4;

  /// sm: 8px
  static const double sm = 8;

  /// md: 16px
  static const double md = 16;

  /// lg: 24px
  static const double lg = 24;

  /// xl: 32px
  static const double xl = 32;

  /// xxl: 48px
  static const double xxl = 48;

  /// xxxl: 64px
  static const double xxxl = 64;

  // ---------- EdgeInsets 快捷 ----------
  static const allSm = EdgeInsets.all(sm);
  static const allMd = EdgeInsets.all(md);
  static const allLg = EdgeInsets.all(lg);
  static const allXl = EdgeInsets.all(xl);

  static EdgeInsets symmetric({double horizontal = 0, double vertical = 0}) =>
      EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);

  static EdgeInsets only({double left = 0, double top = 0, double right = 0, double bottom = 0}) =>
      EdgeInsets.only(left: left, top: top, right: right, bottom: bottom);

  /// 页面内边距（左右 16，上下 16）
  static const pagePadding = EdgeInsets.all(md);

  /// 卡片内边距
  static const cardPadding = EdgeInsets.all(lg);

  /// 区块间距
  static const double sectionGap = md;
}
