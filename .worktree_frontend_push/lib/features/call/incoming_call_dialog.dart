import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import 'package:flutter/foundation.dart';
import 'dart:io';

import '../../core/notification_service.dart';
import '../../l10n/app_localizations.dart';
import 'agora_config.dart';
import 'agora_call_page.dart';
import 'call_invitation_repository.dart';

/// 来电全屏界面：参照微信/Telegram，全屏展示头像、姓名、接听/拒绝；接听前校验 status 仍为 ringing
final _showingInvitationIds = <String>{};

Future<void> showIncomingCallDialog({
  required BuildContext context,
  required String invitationId,
  required String fromUserName,
  required String channelId,
  required String callType,
  String? fromAvatarUrl,
}) async {
  if (_showingInvitationIds.contains(invitationId)) return;
  _showingInvitationIds.add(invitationId);
  print('[TH_CALL] 被叫弹出来电界面 invitationId=$invitationId channelId=$channelId from=$fromUserName');
  // 来电震动 + 系统来电铃声（asAlarm 以便静音模式下也能响）
  HapticFeedback.heavyImpact();
  FlutterRingtonePlayer().playRingtone(looping: true, asAlarm: true);
  final isVideo = callType == 'video';

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (ctx) => _IncomingCallScreen(
      invitationId: invitationId,
      fromUserName: fromUserName,
      fromAvatarUrl: fromAvatarUrl,
      channelId: channelId,
      isVideo: isVideo,
      onDismiss: () => _showingInvitationIds.remove(invitationId),
    ),
  ).then((_) {
    _showingInvitationIds.remove(invitationId);
    FlutterRingtonePlayer().stop();
  });
}

class _IncomingCallScreen extends StatefulWidget {
  const _IncomingCallScreen({
    required this.invitationId,
    required this.fromUserName,
    required this.channelId,
    required this.isVideo,
    required this.onDismiss,
    this.fromAvatarUrl,
  });

  final String invitationId;
  final String fromUserName;
  final String? fromAvatarUrl;
  final String channelId;
  final bool isVideo;
  final VoidCallback onDismiss;

  @override
  State<_IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<_IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ringController;
  Timer? _vibrateTimer;
  StreamSubscription<String?>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (mounted) HapticFeedback.heavyImpact();
    });
    // 主叫取消时关闭来电弹窗并提示
    _statusSubscription = CallInvitationRepository()
        .watchInvitationStatus(widget.invitationId)
        .listen((status) {
      if (!mounted) return;
      if (status == 'cancelled') {
        if (!kIsWeb && Platform.isAndroid) {
          NotificationService.dismissIncomingCallService();
        }
        Navigator.of(context).pop();
        widget.onDismiss();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.callOtherCancelled)),
        );
      }
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _vibrateTimer?.cancel();
    _ringController.dispose();
    FlutterRingtonePlayer().stop();
    super.dispose();
  }

  Future<void> _reject() async {
    FlutterRingtonePlayer().stop();
    if (!kIsWeb && Platform.isAndroid) {
      NotificationService.dismissIncomingCallService();
    }
    Navigator.of(context).pop();
    widget.onDismiss();
    await CallInvitationRepository().updateStatus(widget.invitationId, 'rejected');
  }

  Future<void> _accept() async {
    final repo = CallInvitationRepository();
    // 在 pop 前拿到 Navigator，避免 pop 后 context 失效导致 push 失败
    final navigator = Navigator.of(context);
    final status = await repo.getStatus(widget.invitationId);
    if (status != 'ringing') {
      print('[TH_CALL] 被叫接听时状态已非 ringing: $status，放弃接听');
      if (mounted) {
        navigator.pop();
        widget.onDismiss();
      }
      return;
    }
    FlutterRingtonePlayer().stop();
    if (!kIsWeb && Platform.isAndroid) {
      NotificationService.dismissIncomingCallService();
    }
    print('[TH_CALL] 被叫接听，更新状态为 accepted invitationId=${widget.invitationId} channelId=${widget.channelId}');
    await repo.updateStatus(widget.invitationId, 'accepted');
    if (!mounted) return;
    navigator.pop();
    widget.onDismiss();
    print('[TH_CALL] 被叫跳转 AgoraCallPage channelId=${widget.channelId}');
    // Token 在通话页内再请求，保证接听后立即进入通话页
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AgoraCallPage(
          channelId: widget.channelId,
          remoteUserName: widget.fromUserName,
          isVideo: widget.isVideo,
          token: AgoraConfig.token,
          isCallee: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.fromUserName.isNotEmpty
        ? widget.fromUserName[0].toUpperCase()
        : '?';
    final hasAvatar =
        widget.fromAvatarUrl != null && widget.fromAvatarUrl!.trim().isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1A1B22),
              const Color(0xFF0E0F14),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        widget.isVideo ? AppLocalizations.of(context)!.callVideoCall : AppLocalizations.of(context)!.callVoiceCall,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // 头像 + 来电动画环
                      AnimatedBuilder(
                        animation: _ringController,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // 扩散环
                              ...List.generate(3, (i) {
                                final t = (_ringController.value + i * 0.33) % 1.0;
                                final scale = 0.85 + t * 0.5;
                                final opacity = (1 - t) * 0.4;
                                return Transform.scale(
                                  scale: scale,
                                  child: Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.green.withValues(alpha: opacity),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              child!,
                            ],
                          );
                        },
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: hasAvatar
                                ? CachedNetworkImage(
                                    imageUrl: widget.fromAvatarUrl!.trim(),
                                    fit: BoxFit.cover,
                                    fadeInDuration: Duration.zero,
                                    fadeOutDuration: Duration.zero,
                                    placeholder: (_, __) => _avatarPlaceholder(initial),
                                    errorWidget: (_, __, ___) => _avatarPlaceholder(initial),
                                  )
                                : _avatarPlaceholder(initial),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        widget.fromUserName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.isVideo ? AppLocalizations.of(context)!.callInviteVideoCall : AppLocalizations.of(context)!.callInviteVoiceCall,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // 底部按钮：拒绝 / 接听
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _CallActionButton(
                              label: AppLocalizations.of(context)!.callDecline,
                              icon: Icons.call_end,
                              color: Colors.red,
                              onPressed: _reject,
                            ),
                            _CallActionButton(
                              label: AppLocalizations.of(context)!.callAnswer,
                              icon: Icons.call,
                              color: const Color(0xFF34C759),
                              onPressed: _accept,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _avatarPlaceholder(String initial) {
    return Container(
      color: const Color(0xFF2A2B33),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFFD4AF37),
          fontSize: 48,
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color.withValues(alpha: 0.2),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(icon, size: 36, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 14),
        ),
      ],
    );
  }
}
