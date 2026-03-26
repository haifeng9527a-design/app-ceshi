import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/design/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/components.dart';
import 'teacher_center_page.dart';
import 'teacher_models.dart';
import 'teacher_public_page.dart';
import 'teacher_repository.dart';

class TeacherListPage extends StatelessWidget {
  const TeacherListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = TeacherRepository();
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.teachersTeacherHomepage),
        actions: [
          AppButton(
            variant: AppButtonVariant.text,
            onPressed: () {
              final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (userId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(context)!.teachersPleaseLoginFirst)),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TeacherCenterPage(),
                ),
              );
            },
            label: AppLocalizations.of(context)!.teachersBecomeTeacher,
          ),
        ],
      ),
      body: StreamBuilder<List<TeacherProfile>>(
        stream: repository.watchPublicProfiles(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <TeacherProfile>[];
          if (items.isEmpty) {
            return Center(
              child: Text(
                AppLocalizations.of(context)!.teachersNoTeachers,
                style: AppTypography.bodySecondary,
              ),
            );
          }
          return ListView.separated(
            padding: AppSpacing.allMd,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm + AppSpacing.xs / 2),
            itemBuilder: (context, index) {
              final profile = items[index];
              final name = _displayName(profile);
              final title = profile.title?.trim().isNotEmpty == true
                  ? profile.title!
                  : '专业导师';
              final org = profile.organization?.trim();
              return AppCard(
                padding: AppSpacing.symmetric(horizontal: AppSpacing.md - AppSpacing.xs / 2, vertical: AppSpacing.md - AppSpacing.xs / 2),
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.primary,
                            backgroundImage:
                                profile.avatarUrl?.trim().isNotEmpty == true
                                    ? NetworkImage(profile.avatarUrl!.trim())
                                    : null,
                            child: profile.avatarUrl?.trim().isNotEmpty == true
                                ? null
                                : Text(
                                    name.isEmpty ? '' : name[0],
                                    style: const TextStyle(color: AppColors.surface),
                                  ),
                          ),
                          const SizedBox(width: AppSpacing.md - AppSpacing.xs / 2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  title,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (org != null && org.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                                    child: Text(
                                      org,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          AppButton(
                            variant: AppButtonVariant.text,
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TeacherPublicPage(
                                    teacherId: profile.userId,
                                  ),
                                ),
                              );
                            },
                            label: AppLocalizations.of(context)!.teachersHomepage,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: -6,
                        children: [
                          if (profile.style?.trim().isNotEmpty == true)
                            AppChip(label: profile.style!, selected: false),
                          if (profile.riskLevel?.trim().isNotEmpty == true)
                            AppChip(label: profile.riskLevel!, selected: false),
                          ...((profile.specialties ?? const <String>[]).map(
                            (item) => AppChip(label: item, selected: false),
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _displayName(TeacherProfile profile) {
  final name = profile.realName?.trim() ?? '';
  return name.isEmpty ? '交易员' : name;
}
