import 'package:flutter/material.dart';

/// 行情涨跌颜色统一定义，确保全局一致
abstract final class MarketColors {
  MarketColors._();

  /// 涨（红涨/绿涨按习惯可调：当前为绿涨）
  static const Color up = Color(0xFF22C55E);

  /// 跌
  static const Color down = Color(0xFFEF4444);

  /// 平 / 无数据 / 中性
  static const Color neutral = Color(0xFF9CA3AF);

  /// 根据涨跌取色：changePercent >= 0 为 up，否则为 down
  static Color forChangePercent(double changePercent) {
    return changePercent >= 0 ? up : down;
  }

  /// 根据是否上涨取色
  static Color forUp(bool isUp) {
    return isUp ? up : down;
  }

  /// 涨色带透明度（如背景、标签）
  static Color get upWithAlpha => up.withValues(alpha: 0.7);

  /// 跌色带透明度
  static Color get downWithAlpha => down.withValues(alpha: 0.7);
}
