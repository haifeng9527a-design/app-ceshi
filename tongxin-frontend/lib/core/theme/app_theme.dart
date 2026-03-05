import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/app_typography.dart';

/// 统一 AppTheme：深色金融风
/// 替代 app.dart 内联 ThemeData，并补全 textTheme/inputTheme/buttonTheme 等
class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.scaffold,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.danger,
        onPrimary: Colors.black87,
        onSecondary: Colors.black87,
        onSurface: AppColors.textPrimary,
        onError: Colors.white,
        onSurfaceVariant: AppColors.textSecondary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.scaffold,
        foregroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
        iconTheme: IconThemeData(color: AppColors.primary, size: 24),
      ),
      textTheme: TextTheme(
        displayLarge: AppTypography.title.copyWith(fontSize: 28),
        displayMedium: AppTypography.title.copyWith(fontSize: 24),
        displaySmall: AppTypography.title.copyWith(fontSize: 20),
        headlineLarge: AppTypography.subtitle.copyWith(fontSize: 18),
        headlineMedium: AppTypography.subtitle,
        headlineSmall: AppTypography.subtitle.copyWith(fontSize: 14),
        titleLarge: AppTypography.subtitle,
        titleMedium: AppTypography.body.copyWith(fontSize: 15),
        titleSmall: AppTypography.body.copyWith(fontSize: 13),
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.bodySecondary,
        bodySmall: AppTypography.caption,
        labelLarge: AppTypography.meta.copyWith(fontSize: 12),
        labelMedium: AppTypography.meta,
        labelSmall: AppTypography.meta.copyWith(fontSize: 10),
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: 24,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBg,
        hintStyle: AppTypography.bodySecondary.copyWith(color: AppColors.textTertiary),
        contentPadding: AppSpacing.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        border: OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: AppRadius.mdAll, borderSide: const BorderSide(color: AppColors.danger)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black87,
          padding: AppSpacing.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          elevation: 0,
          textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: AppSpacing.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border),
          padding: AppSpacing.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: const BorderSide(color: AppColors.borderSubtle)),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface2,
        contentTextStyle: AppTypography.body,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        actionTextColor: AppColors.primary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        titleTextStyle: AppTypography.subtitle,
        contentTextStyle: AppTypography.body,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        labelStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTypography.body,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        height: 72,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypography.meta.copyWith(
              fontSize: 11,
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            );
          }
          return AppTypography.meta.copyWith(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(size: 24, color: AppColors.primary);
          }
          return const IconThemeData(size: 22, color: AppColors.textTertiary);
        }),
        indicatorColor: AppColors.primarySubtle(0.16),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        textStyle: AppTypography.bodySecondary,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surface2,
        circularTrackColor: AppColors.surface2,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.borderSubtle, thickness: 1),
      dividerColor: AppColors.borderSubtle,
    );
  }
}
