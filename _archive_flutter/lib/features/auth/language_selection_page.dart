import 'package:flutter/material.dart';

import '../../core/locale_provider.dart';
import '../../ui/tv_theme.dart';

/// 首次安装时让用户选择语言
class LanguageSelectionPage extends StatelessWidget {
  const LanguageSelectionPage({
    super.key,
    required this.onSelected,
  });

  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Text(
                'Select Language',
                style: TextStyle(
                  color: TvTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your preferred language for the app',
                style: TextStyle(
                  color: TvTheme.textSecondary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 48),
              _LanguageOption(
                label: 'English',
                onTap: () => _selectAndContinue(context, 'en'),
              ),
              const SizedBox(height: 16),
              _LanguageOption(
                label: '中文',
                onTap: () => _selectAndContinue(context, 'zh'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectAndContinue(BuildContext context, String code) async {
    await LocaleProvider.instance.setLocale(Locale(code));
    if (context.mounted) {
      onSelected();
    }
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFF0F5FA),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(Icons.arrow_forward_ios, size: 16, color: TvTheme.warning),
            ],
          ),
        ),
      ),
    );
  }
}
