import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../home/home_page.dart';

class PromoPage extends StatefulWidget {
  const PromoPage({super.key});

  @override
  State<PromoPage> createState() => _PromoPageState();
}

class _PromoPageState extends State<PromoPage> {
  final PageController _pageController = PageController(viewportFraction: 0.85);
  late final Timer _timer;
  int _currentIndex = 0;

  List<_PromoSlide> _slides(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      _PromoSlide(title: l10n.promoSlide1Title, subtitle: l10n.promoSlide1Subtitle, icon: Icons.insights),
      _PromoSlide(title: l10n.promoSlide2Title, subtitle: l10n.promoSlide2Subtitle, icon: Icons.pie_chart_outline),
      _PromoSlide(title: l10n.promoSlide3Title, subtitle: l10n.promoSlide3Subtitle, icon: Icons.groups_outlined),
    ];
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) {
        return;
      }
      final next = (_currentIndex + 1) % 3;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
      setState(() {
        _currentIndex = next;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final slides = _slides(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BrandHeader(),
              const SizedBox(height: 24),
              Text(
                l10n.promoTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.promoSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFE5E5E7),
                    ),
              ),
              const SizedBox(height: 20),
              _FeatureRow(icon: Icons.verified_outlined, text: l10n.promoFeature1),
              const SizedBox(height: 10),
              _FeatureRow(icon: Icons.auto_graph, text: l10n.promoFeature2),
              const SizedBox(height: 10),
              _FeatureRow(icon: Icons.chat_bubble_outline, text: l10n.promoFeature3),
              const Spacer(),
              _CarouselHeader(),
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemCount: slides.length,
                  itemBuilder: (context, index) {
                    final slide = slides[index];
                    return _PromoCard(slide: slide);
                  },
                ),
              ),
              const SizedBox(height: 10),
              _DotsIndicator(
                count: slides.length,
                index: _currentIndex,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const HomePage()),
                    );
                  },
                  child: Text(AppLocalizations.of(context)!.promoEnterSelectTrader),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFD4AF37),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.shield,
            color: Color(0xFF111215),
            size: 18,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          AppLocalizations.of(context)!.promoBrand,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFFD4AF37),
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFD4AF37), size: 18),
        const SizedBox(width: 8),
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _CarouselHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFFD4AF37),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          AppLocalizations.of(context)!.promoCarouselTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _PromoSlide {
  const _PromoSlide({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.slide});

  final _PromoSlide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF111215),
          border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0C0E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD4AF37), width: 0.4),
              ),
              child: Icon(slide.icon, color: const Color(0xFFD4AF37), size: 18),
            ),
            const SizedBox(height: 10),
            Text(
              slide.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFFD4AF37),
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              slide.subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  const _DotsIndicator({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == index ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: i == index ? const Color(0xFFD4AF37) : const Color(0xFF2A2C31),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}
