import 'package:flutter/material.dart';

import '../../core/design/design_tokens.dart';
import '../../core/models.dart';
import '../../ui/components/components.dart';
import '../../l10n/app_localizations.dart';

class TeacherDetailPage extends StatelessWidget {
  const TeacherDetailPage({super.key, required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(teacher.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _HeaderSection(teacher: teacher),
          const SizedBox(height: AppSpacing.md),
          _SectionTitle(title: AppLocalizations.of(context)!.teachersPerformanceSection),
          _BattleStats(teacher: teacher),
          const SizedBox(height: AppSpacing.md),
          _SectionTitle(title: AppLocalizations.of(context)!.teachersIntroSection),
          Text(teacher.bio, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          const _SectionTitle(title: '最新文章'),
          ...teacher.articles.map(
            (article) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(article.title),
              subtitle: Text(article.summary),
              trailing: Text(article.date),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _SectionTitle(title: AppLocalizations.of(context)!.teachersRecentSchedule),
          ...teacher.schedules.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.title),
              subtitle: Text(item.location),
              trailing: Text(item.date),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            onPressed: () {},
            label: AppLocalizations.of(context)!.featuredFollowTrader,
          ),
        ],
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            _initial(teacher.name),
            style: const TextStyle(fontSize: 24),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                teacher.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                teacher.title,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: -6,
                children: teacher.tags
                    .map((tag) => AppChip(label: tag))
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BattleStats extends StatelessWidget {
  const _BattleStats({required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    final total = teacher.wins + teacher.losses;
    final winRate = total == 0 ? 0 : (teacher.wins / total * 100).round();
    return Row(
      children: [
        _StatTile(label: AppLocalizations.of(context)!.featuredWins, value: '${teacher.wins}'),
        const SizedBox(width: 12),
        _StatTile(label: AppLocalizations.of(context)!.featuredLosses, value: '${teacher.losses}'),
        const SizedBox(width: 12),
        _StatTile(label: AppLocalizations.of(context)!.featuredWinRate, value: '$winRate%'),
        const SizedBox(width: 12),
        _StatTile(label: AppLocalizations.of(context)!.teachersRatingLabel, value: '${teacher.rating}'),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 4),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

String _initial(String name) {
  if (name.isEmpty) {
    return '';
  }
  return name[0];
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
