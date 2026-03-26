import 'package:flutter/material.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_typography.dart';

/// 统一按钮组件：primary / secondary / text 三种
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.iconPosition = AppButtonIconPosition.leading,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final Widget? icon;
  final AppButtonIconPosition iconPosition;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = loading ? null : onPressed;

    return switch (variant) {
      AppButtonVariant.primary => _PrimaryButton(
          label: label,
          onPressed: effectiveOnPressed,
          icon: icon,
          iconPosition: iconPosition,
          loading: loading,
        ),
      AppButtonVariant.secondary => _SecondaryButton(
          label: label,
          onPressed: effectiveOnPressed,
          icon: icon,
          iconPosition: iconPosition,
          loading: loading,
        ),
      AppButtonVariant.text => _TextButton(
          label: label,
          onPressed: effectiveOnPressed,
          icon: icon,
          iconPosition: iconPosition,
          loading: loading,
        ),
    };
  }
}

enum AppButtonVariant { primary, secondary, text }

enum AppButtonIconPosition { leading, trailing }

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    this.onPressed,
    this.icon,
    required this.iconPosition,
    required this.loading,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final AppButtonIconPosition iconPosition;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black87,
        padding: AppSpacing.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      ),
      child: _buildChild(context),
    );
  }

  Widget _buildChild(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return _ButtonContent(label: label, icon: icon, iconPosition: iconPosition);
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    this.onPressed,
    this.icon,
    required this.iconPosition,
    required this.loading,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final AppButtonIconPosition iconPosition;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border),
        padding: AppSpacing.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      ),
      child: _buildChild(context),
    );
  }

  Widget _buildChild(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return _ButtonContent(label: label, icon: icon, iconPosition: iconPosition);
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.label,
    this.onPressed,
    this.icon,
    required this.iconPosition,
    required this.loading,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final AppButtonIconPosition iconPosition;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: AppSpacing.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      ),
      child: _buildChild(context),
    );
  }

  Widget _buildChild(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return _ButtonContent(label: label, icon: icon, iconPosition: iconPosition);
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    this.icon,
    required this.iconPosition,
  });

  final String label;
  final Widget? icon;
  final AppButtonIconPosition iconPosition;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return Text(label, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600));
    }
    final gap = const SizedBox(width: AppSpacing.sm);
    if (iconPosition == AppButtonIconPosition.leading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [icon!, gap, Text(label, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600))],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Text(label, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)), gap, icon!],
    );
  }
}
