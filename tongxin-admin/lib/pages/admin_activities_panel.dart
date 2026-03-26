import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/admin_api_client.dart';

class AdminActivitiesPanel extends StatefulWidget {
  const AdminActivitiesPanel({super.key});

  @override
  State<AdminActivitiesPanel> createState() => _AdminActivitiesPanelState();
}

class _AdminActivitiesPanelState extends State<AdminActivitiesPanel> {
  static const Color _accent = Color(0xFFD4AF37);
  final _api = AdminApiClient.instance;

  final List<_CardDraft> _cards = [];

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _onPreviewChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    for (final card in _cards) {
      card.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final resp = await _api.get('api/admin/rankings/content');
      if (resp.statusCode != 200) {
        throw StateError('加载失败(${resp.statusCode})：${resp.body}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final cardsRaw = (data['cards'] as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList()
        ..sort((a, b) => _sortOrderOf(a).compareTo(_sortOrderOf(b)));
      final cards = cardsRaw.isNotEmpty ? cardsRaw : _defaultCards();
      if (!mounted) return;
      setState(() {
        for (final c in _cards) {
          c.dispose();
        }
        _cards
          ..clear()
          ..addAll(cards.map((c) {
            final draft = _CardDraft.fromMap(c);
            draft.bind(_onPreviewChanged);
            return draft;
          }));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  static int _sortOrderOf(Map<String, dynamic> row) {
    final v = row['sort_order'];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<void> _save() async {
    if (_cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少保留一张卡片')),
      );
      return;
    }
    for (var i = 0; i < _cards.length; i += 1) {
      final c = _cards[i];
      if (c.titleCtrl.text.trim().isEmpty ||
          c.summaryCtrl.text.trim().isEmpty ||
          c.detailCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('卡片${i + 1} 的标题/摘要/详情不能为空')),
        );
        return;
      }
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final cards = _cards.asMap().entries.map((entry) {
        return entry.value.toPayload(sortOrder: entry.key + 1);
      }).toList();
      final resp = await _api.put(
        'api/admin/rankings/content',
        body: {'cards': cards},
      );
      if (resp.statusCode != 200) {
        throw StateError('保存失败(${resp.statusCode})：${resp.body}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('卡片已保存，前端会自动刷新')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text(
              '活动管理',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
              tooltip: '刷新',
            ),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? '保存中' : '保存'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '这里可管理排行榜页轮播卡，支持新增第1/2/3/4...张卡片。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 20),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: _accent),
            ),
          )
        else if (_loadError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(_loadError!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          )
        else
          Column(
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              final card = _CardDraft.create();
                              card.bind(_onPreviewChanged);
                              _cards.add(card);
                            });
                          },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新增卡片'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _cards.length; i++) ...[
                _editorCard(
                  index: i,
                  card: _cards[i],
                  onMoveUp: i == 0
                      ? null
                      : () => setState(() {
                            final c = _cards.removeAt(i);
                            _cards.insert(i - 1, c);
                          }),
                  onMoveDown: i == _cards.length - 1
                      ? null
                      : () => setState(() {
                            final c = _cards.removeAt(i);
                            _cards.insert(i + 1, c);
                          }),
                  onDelete: _cards.length <= 1
                      ? null
                      : () => setState(() {
                            final c = _cards.removeAt(i);
                            c.dispose();
                          }),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF111215),
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
                    width: 0.7,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '轮播卡预览（按顺序）',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _cards.length; i++) ...[
                      _previewTile(
                        index: i,
                        title: _cards[i].titleCtrl.text.trim(),
                        summary: _cards[i].summaryCtrl.text.trim(),
                      ),
                      if (i != _cards.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _editorCard({
    required int index,
    required _CardDraft card,
    VoidCallback? onMoveUp,
    VoidCallback? onMoveDown,
    VoidCallback? onDelete,
  }) {
    final accentColor = _accentByIndex(index);
    final icon = _iconByIndex(index);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        color: Colors.white.withValues(alpha: 0.02),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Text(
                '卡片${index + 1}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFFE8D5A3),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '上移',
                onPressed: onMoveUp,
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                tooltip: '下移',
                onPressed: onMoveDown,
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: card.titleCtrl,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: card.summaryCtrl,
            decoration: const InputDecoration(
              labelText: '摘要',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: card.detailCtrl,
            decoration: const InputDecoration(
              labelText: '详情（点“了解更多”弹窗显示）',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 6,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: card.extraLinkCtrl,
            decoration: const InputDecoration(
              labelText: '附加链接（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '标识：${card.cardKeyCtrl.text.trim().isEmpty ? '(新增时自动生成)' : card.cardKeyCtrl.text.trim()}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                ),
          ),
          if (card.cardKeyCtrl.text.trim().isEmpty) ...[
            const SizedBox(height: 10),
            TextField(
              controller: card.cardKeyCtrl,
              decoration: const InputDecoration(
                labelText: '自定义标识（可选，仅限英文字母/数字/_/-）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewTile({
    required int index,
    required String title,
    required String summary,
  }) {
    final icon = _iconByIndex(index);
    final iconColor = _accentByIndex(index);
    final safeTitle = title.trim().isEmpty ? '未填写标题' : title.trim();
    final safeSummary = summary.trim().isEmpty ? '未填写摘要' : summary.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: iconColor.withValues(alpha: 0.35), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '卡片${index + 1} · $safeTitle',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFFE8D5A3),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            safeSummary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB8B8BC),
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _defaultCards() {
    return [
      {
        'card_key': 'intro',
        'title': '排行榜简介',
        'summary': '榜单基于导师收益与稳定性综合展示，帮助学员快速发现值得长期跟踪的导师。',
        'detail':
            '排行榜按不同周期展示导师表现。你可以查看周榜、月榜、季度榜、年度榜和总榜，结合胜率与盈亏趋势，评估导师风格是否与你匹配。',
        'extra_link': null,
        'sort_order': 1,
      },
      {
        'card_key': 'signup',
        'title': '报名须知与入口',
        'summary': '参与导师评选或活动报名前，请先阅读规则说明与资格要求。',
        'detail':
            '报名须知：\n1. 需完成实名认证；\n2. 近30天有有效交易记录；\n3. 严禁刷单或虚假收益展示。\n\n通过入口链接提交报名信息，审核结果将在1-3个工作日内反馈。',
        'extra_link': 'https://example.com/rankings-signup',
        'sort_order': 2,
      },
      {
        'card_key': 'activity',
        'title': '最新活动介绍',
        'summary': '本月导师挑战赛进行中，完成阶段目标可获得曝光位与奖励。',
        'detail':
            '活动时间：每月1日-25日\n活动内容：按收益稳定性、回撤控制和互动质量综合评定。\n奖励说明：Top榜单导师将获得首页推荐位和官方流量支持。',
        'extra_link': null,
        'sort_order': 3,
      },
    ];
  }

  static IconData _iconByIndex(int index) {
    const icons = [
      Icons.emoji_events_outlined,
      Icons.how_to_reg_outlined,
      Icons.campaign_outlined,
      Icons.star_border_outlined,
      Icons.auto_awesome_outlined,
    ];
    return icons[index % icons.length];
  }

  static Color _accentByIndex(int index) {
    const colors = [
      Color(0xFFD4AF37),
      Color(0xFF4F9D8A),
      Color(0xFF7A87D8),
      Color(0xFFEF9F4A),
      Color(0xFFCC78E6),
    ];
    return colors[index % colors.length];
  }
}

class _CardDraft {
  _CardDraft({
    required this.cardKeyCtrl,
    required this.titleCtrl,
    required this.summaryCtrl,
    required this.detailCtrl,
    required this.extraLinkCtrl,
  });

  final TextEditingController cardKeyCtrl;
  final TextEditingController titleCtrl;
  final TextEditingController summaryCtrl;
  final TextEditingController detailCtrl;
  final TextEditingController extraLinkCtrl;

  factory _CardDraft.fromMap(Map<String, dynamic> map) {
    return _CardDraft(
      cardKeyCtrl: TextEditingController(text: map['card_key']?.toString() ?? ''),
      titleCtrl: TextEditingController(text: map['title']?.toString() ?? ''),
      summaryCtrl: TextEditingController(text: map['summary']?.toString() ?? ''),
      detailCtrl: TextEditingController(text: map['detail']?.toString() ?? ''),
      extraLinkCtrl: TextEditingController(text: map['extra_link']?.toString() ?? ''),
    );
  }

  factory _CardDraft.create() {
    return _CardDraft(
      cardKeyCtrl: TextEditingController(),
      titleCtrl: TextEditingController(text: '新卡片'),
      summaryCtrl: TextEditingController(text: '请填写卡片摘要'),
      detailCtrl: TextEditingController(text: '请填写卡片详情'),
      extraLinkCtrl: TextEditingController(),
    );
  }

  void bind(VoidCallback listener) {
    titleCtrl.addListener(listener);
    summaryCtrl.addListener(listener);
  }

  Map<String, dynamic> toPayload({required int sortOrder}) {
    final cardKey = cardKeyCtrl.text.trim();
    return {
      if (cardKey.isNotEmpty) 'card_key': cardKey,
      'title': titleCtrl.text.trim(),
      'summary': summaryCtrl.text.trim(),
      'detail': detailCtrl.text.trim(),
      'extra_link': extraLinkCtrl.text.trim().isEmpty ? null : extraLinkCtrl.text.trim(),
      'sort_order': sortOrder,
    };
  }

  void dispose() {
    cardKeyCtrl.dispose();
    titleCtrl.dispose();
    summaryCtrl.dispose();
    detailCtrl.dispose();
    extraLinkCtrl.dispose();
  }
}
