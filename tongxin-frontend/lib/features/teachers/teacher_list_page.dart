import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
        title: const Text('交易员主页'),
        actions: [
          TextButton(
            onPressed: () {
              final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (userId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请先登录')),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TeacherCenterPage(),
                ),
              );
            },
            child: const Text('成为交易员'),
          ),
        ],
      ),
      body: StreamBuilder<List<TeacherProfile>>(
        stream: repository.watchPublicProfiles(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <TeacherProfile>[];
          if (items.isEmpty) {
            return const Center(child: Text('暂无交易员'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final profile = items[index];
              final name = _displayName(profile);
              final title = profile.title?.trim().isNotEmpty == true
                  ? profile.title!
                  : '专业导师';
              final org = profile.organization?.trim();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFFD4AF37),
                            backgroundImage:
                                profile.avatarUrl?.trim().isNotEmpty == true
                                    ? NetworkImage(profile.avatarUrl!.trim())
                                    : null,
                            child: profile.avatarUrl?.trim().isNotEmpty == true
                                ? null
                                : Text(
                                    name.isEmpty ? '' : name[0],
                                    style: const TextStyle(
                                      color: Color(0xFF111215),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  title,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (org != null && org.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      org,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TeacherPublicPage(
                                    teacherId: profile.userId,
                                  ),
                                ),
                              );
                            },
                            child: const Text('主页'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: -6,
                        children: [
                          if (profile.style?.trim().isNotEmpty == true)
                            Chip(label: Text(profile.style!)),
                          if (profile.riskLevel?.trim().isNotEmpty == true)
                            Chip(label: Text(profile.riskLevel!)),
                          ...((profile.specialties ?? const <String>[]).map(
                            (item) => Chip(label: Text(item)),
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
