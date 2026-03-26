import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 统一字体层级 Token
/// 与 ThemeData.textTheme 对应，供未接入 Theme 的组件使用
abstract class AppTypography {
  AppTypography._();

  static const String fontMono = 'monospace';
  static const FontFeature tabularFigures = FontFeature.tabularFigures();

  /// Title: 20 / semibold
  static TextStyle get title => const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
        letterSpacing: -0.3,
      );

  /// Subtitle: 16 / semibold
  static TextStyle get subtitle => const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.35,
      );

  /// Body: 14 / medium
  static TextStyle get body => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  /// Body secondary: 13 / medium
  static TextStyle get bodySecondary => const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.4,
      );

  /// Caption: 12 / regular
  static TextStyle get caption => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.35,
      );

  /// Meta: 11 / medium（表头、标签）
  static TextStyle get meta => const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
        letterSpacing: 0.5,
        height: 1.2,
      );

  /// Data: 22 / bold（价格等核心数据）
  static TextStyle get data => const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        fontFamily: fontMono,
        fontFeatures: [tabularFigures],
        height: 1.25,
      );

  /// Data small: 18 / bold
  static TextStyle get dataSmall => const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        fontFamily: fontMono,
        fontFeatures: [tabularFigures],
        height: 1.25,
      );
}
