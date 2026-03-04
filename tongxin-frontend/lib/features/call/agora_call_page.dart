import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:proximity_sensor/proximity_sensor.dart';

import '../../l10n/app_localizations.dart';
import 'agora_config.dart';
import 'call_invitation_repository.dart';

/// 主叫方在通话页内创建邀请时传入的参数（用于点击后立即弹窗，邀请在页内异步创建）
class CallerCreateInvitationParams {
  const CallerCreateInvitationParams({
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.callType,
  });
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String callType;
}

/// 语音/视频通话页：参照微信/Telegram，支持通话时长、静音、扬声器、视频画面与切换摄像头
/// 日志统一前缀 [TH_CALL]，便于 adb logcat 过滤：adb logcat | findstr TH_CALL
class AgoraCallPage extends StatefulWidget {
  const AgoraCallPage({
    super.key,
    required this.channelId,
    required this.remoteUserName,
    required this.isVideo,
    this.token,
    this.invitationId,
    this.isCallee = false,
    this.callerCreateInvitation,
  });

  final String channelId;
  final String remoteUserName;
  final bool isVideo;
  final String? token;
  final String? invitationId;
  final bool isCallee;
  /// 主叫且 invitationId 为空时，用此参数在页内创建邀请，实现点击即弹窗
  final CallerCreateInvitationParams? callerCreateInvitation;

  @override
  State<AgoraCallPage> createState() => _AgoraCallPageState();
}

class _AgoraCallPageState extends State<AgoraCallPage> {
  RtcEngine? _engine;
  int? _remoteUid;
  bool _muted = false;
  bool _speakerOn = true;
  bool _cameraFront = true;
  int _callDurationSeconds = 0;
  Timer? _durationTimer;
  Timer? _statusPollTimer;
  StreamSubscription<String?>? _statusSubscription;
  bool _joined = false;
  bool _signalingConnected = false;
  String? _invitationId;
  StreamSubscription<dynamic>? _proximitySubscription;

  @override
  void initState() {
    super.initState();
    _invitationId = widget.invitationId;
    final role = widget.isCallee ? '被叫' : '主叫';
    final tokenLen = (widget.token?.length ?? 0);
    print('[TH_CALL] $role 进入通话页 channelId=${widget.channelId} invitationId=${_invitationId} tokenLen=$tokenLen');
    if (widget.isCallee) {
      _signalingConnected = true;
      _startDurationTimer();
    }
    _initAndJoin();
    if (!widget.isCallee) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_signalingConnected) _startRingbackIfCaller();
      });
    }
    final id = _invitationId;
    if (id != null && id.isNotEmpty) {
      _applyAcceptedIfNeeded(id);
      _startInvitationListeners(id);
    } else if (!widget.isCallee && widget.callerCreateInvitation != null) {
      _createInvitationThenListen();
    }
    // 语音通话：靠近耳朵听筒、离开耳朵扬声器（多数设备 0=近 非0=远）
    if (!widget.isVideo) {
      _proximitySubscription = ProximitySensor.events.listen((dynamic event) {
        final num value = event is num ? event : (event is int ? event : 0);
        final isNear = value == 0;
        if (!mounted || _engine == null) return;
        final useSpeaker = !isNear;
        setState(() => _speakerOn = useSpeaker);
        _engine!.setDefaultAudioRouteToSpeakerphone(useSpeaker);
      });
    }
  }

  void _startInvitationListeners(String id) {
    _applyAcceptedIfNeeded(id);
    _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollInvitationStatus(id));
    _statusSubscription = CallInvitationRepository()
        .watchInvitationStatus(id)
        .listen((status) {
      if (!mounted) return;
      print('[TH_CALL] 主叫 Realtime 收到 status=$status');
      _applyInvitationStatus(status);
    });
  }

  Future<void> _createInvitationThenListen() async {
    final p = widget.callerCreateInvitation!;
    try {
      final id = await CallInvitationRepository().createInvitation(
        fromUserId: p.fromUserId,
        fromUserName: p.fromUserName,
        toUserId: p.toUserId,
        channelId: widget.channelId,
        callType: p.callType,
      );
      if (!mounted) return;
      setState(() => _invitationId = id);
      print('[TH_CALL] 主叫 页内创建邀请成功 id=$id');
      _startInvitationListeners(id);
    } catch (e) {
      print('[TH_CALL] 主叫 页内创建邀请失败: $e');
      if (mounted) _showErrorAndPop('发起通话失败');
    }
  }

  void _applyInvitationStatus(String? status) {
    print('[TH_CALL] 主叫 _applyInvitationStatus status=$status _signalingConnected=$_signalingConnected');
    if (status == null) return;
    if (status == 'rejected') {
      print('[TH_CALL] 主叫 执行：对方已拒绝，退出');
      _showRejectedAndLeave();
      return;
    }
    if (status == 'cancelled') {
      print('[TH_CALL] 主叫 执行：对方已取消，退出');
      _showCancelledAndLeave();
      return;
    }
    if (status == 'accepted' && !_signalingConnected) {
      print('[TH_CALL] 主叫 执行：收到 accepted，开始计时');
      _stopRingback();
      _signalingConnected = true;
      _startDurationTimer();
      setState(() {});
    }
  }

  /// 主叫等待对方接听时播放回铃音，接通/挂断/拒绝/取消时停止
  void _stopRingback() {
    FlutterRingtonePlayer().stop();
  }

  void _startRingbackIfCaller() {
    if (widget.isCallee) return;
    FlutterRingtonePlayer().playRingtone(looping: true);
  }

  Future<void> _pollInvitationStatus(String invitationId) async {
    if (!mounted || _signalingConnected) return; // 已接通则不再轮询
    try {
      final status = await CallInvitationRepository().getStatus(invitationId);
      print('[TH_CALL] 主叫 轮询 getStatus invitationId=$invitationId => status=$status');
      if (!mounted) return;
      _applyInvitationStatus(status);
    } catch (e) {
      print('[TH_CALL] 主叫 轮询 getStatus 异常: $e');
    }
  }

  /// 主叫进入页面时立即查一次邀请状态，避免 stream 只推送“变化”导致已 accepted 时收不到
  Future<void> _applyAcceptedIfNeeded(String invitationId) async {
    try {
      final status = await CallInvitationRepository().getStatus(invitationId);
      print('[TH_CALL] 主叫 首次 getStatus invitationId=$invitationId => status=$status');
      if (!mounted) return;
      if (status == 'accepted' && !_signalingConnected) {
        print('[TH_CALL] 主叫 首次已为 accepted，开始计时');
        _stopRingback();
        _signalingConnected = true;
        _startDurationTimer();
        setState(() {});
      }
    } catch (e) {
      print('[TH_CALL] 主叫 首次 getStatus 异常: $e');
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _callDurationSeconds++);
    });
  }

  Future<void> _initAndJoin() async {
    if (!AgoraConfig.isAvailable) {
      print('[TH_CALL] Agora 未配置 appId');
      if (mounted) _showErrorAndPop('未配置 Agora App ID');
      return;
    }
    // 进入通话前先请求麦克风（语音/视频都要）和相机（仅视频），避免加入后无音/无画面
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      print('[TH_CALL] 麦克风权限未授予');
      if (mounted) _showErrorAndPop('需要麦克风权限才能进行通话');
      return;
    }
    if (widget.isVideo) {
      final camera = await Permission.camera.request();
      if (!camera.isGranted) {
        print('[TH_CALL] 相机权限未授予');
        if (mounted) _showErrorAndPop('需要相机权限才能进行视频通话');
        return;
      }
    }
    try {
      print('[TH_CALL] 开始初始化引擎并加入频道 channelId=${widget.channelId}');
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: AgoraConfig.appId!,
      ));
      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          print('[TH_CALL] onJoinChannelSuccess localUid=${connection.localUid} channelId=${connection.channelId} elapsed=${elapsed}ms');
          if (!mounted) return;
          setState(() {});
        },
        onError: (ErrorCodeType err, String msg) {
          print('[TH_CALL] onError err=$err msg=$msg');
          if (!mounted) return;
          // 加入失败或通话异常（尚未有远端用户时多为加入/Token/网络问题）
          if (_remoteUid == null && _engine != null) {
            _showErrorAndPop('无法加入语音频道 ($err)');
          }
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          print('[TH_CALL] onUserJoined remoteUid=$remoteUid channelId=${connection.channelId} 已建立语音通道');
          if (!mounted) return;
          setState(() {
            _remoteUid = remoteUid;
            if (!_joined) {
              _joined = true;
              _startDurationTimer();
            }
          });
        },
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          print('[TH_CALL] onUserOffline remoteUid=$remoteUid reason=$reason');
          if (!mounted) return;
          // 对方离开频道即关闭：已接通时匹配 uid；未接通时（_remoteUid 仍为 null）任一用户离线也视为对方挂断
          if (_remoteUid == remoteUid || _remoteUid == null) {
            _showRemoteLeftAndLeave();
          }
        },
      ));
      await _engine!.enableAudio();
      if (widget.isVideo) {
        await _engine!.enableVideo();
      } else {
        // 语音通话：语音场景 + 会议场景，利于 1:1 通话连通与音质
        await _engine!.setAudioProfile(
          profile: AudioProfileType.audioProfileSpeechStandard,
          scenario: AudioScenarioType.audioScenarioMeeting,
        );
      }
      await _engine!.setDefaultAudioRouteToSpeakerphone(_speakerOn);

      // 双方必须使用不同 uid，否则可能收不到 onUserJoined / 无声音；用当前用户 ID 生成非 0 uid
      final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
      final agoraUid = (currentUserId.isNotEmpty)
          ? (currentUserId.hashCode.abs() % 0x7FFFFFFE) + 1
          : 0;
      // 无 token 时在页内请求，避免主叫在 chat 页等待网络导致通话窗不弹出
      String? token = widget.token;
      if (token == null || token.isEmpty) {
        token = await CallInvitationRepository().fetchAgoraToken(widget.channelId, uid: agoraUid);
      }
      if (!mounted) return;
      final tokenLen = (token?.length ?? 0);
      print('[TH_CALL] 正在加入频道 channelId=${widget.channelId} uid=$agoraUid tokenLen=$tokenLen');
      // 声网已开 Token 鉴权时，未拿到 Token 会报 errInvalidToken；提前提示便于区分是「没拿到」还是「格式错」
      if (token == null || token.isEmpty) {
        if (mounted) {
          _showErrorAndPop(
            '未获取到 Token。请：1) 在 Supabase 部署 get_agora_token 并配置 AGORA_APP_ID、AGORA_APP_CERTIFICATE；或 2) 在声网控制台暂时关闭 Token 鉴权',
          );
        }
        return;
      }
      await _engine!.joinChannel(
        token: token ?? '',
        channelId: widget.channelId,
        uid: agoraUid,
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          publishCameraTrack: widget.isVideo,
          autoSubscribeAudio: true,
          autoSubscribeVideo: widget.isVideo,
        ),
      );
      await _engine!.muteLocalAudioStream(false);
      print('[TH_CALL] joinChannel 成功 channelId=${widget.channelId} uid=$agoraUid');
      if (mounted) {
        setState(() => _joined = true);
        _startDurationTimer();
      }
    } catch (e, st) {
      print('[TH_CALL] Agora 初始化/加入失败: $e\n$st');
      if (mounted) _showErrorAndPop(AppLocalizations.of(context)!.callJoinFailed);
    }
  }

  void _showRejectedAndLeave() {
    _stopRingback();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.callOtherRejected)));
    _leaveAndPop();
  }

  void _showCancelledAndLeave() {
    _stopRingback();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.callOtherCancelled)));
    _leaveAndPop();
  }

  /// 对方已挂断（onUserOffline）：提示并关闭页面
  void _showRemoteLeftAndLeave() {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.callOtherHangup)));
    _leaveAndPop();
  }

  void _showErrorAndPop(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    Navigator.of(context).pop();
  }

  Future<void> _leaveAndPop() async {
    _stopRingback();
    _durationTimer?.cancel();
    if (_engine != null) {
      try {
        await _engine!.leaveChannel();
      } catch (_) {}
      _engine!.release();
      _engine = null;
    }
    final id = _invitationId ?? widget.invitationId;
    if (id != null && id.isNotEmpty) {
      try {
        await CallInvitationRepository().updateStatus(id, 'cancelled');
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleSpeaker() async {
    if (_engine == null) return;
    setState(() => _speakerOn = !_speakerOn);
    await _engine!.setDefaultAudioRouteToSpeakerphone(_speakerOn);
  }

  Future<void> _switchCamera() async {
    if (_engine == null) return;
    await _engine!.switchCamera();
    setState(() => _cameraFront = !_cameraFront);
  }

  @override
  void dispose() {
    _stopRingback();
    _durationTimer?.cancel();
    _statusPollTimer?.cancel();
    _statusSubscription?.cancel();
    _proximitySubscription?.cancel();
    if (_engine != null) {
      _engine!.leaveChannel();
      _engine!.release();
      _engine = null;
    }
    super.dispose();
  }

  String get _durationText {
    final m = _callDurationSeconds ~/ 60;
    final s = _callDurationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.remoteUserName.isNotEmpty ? widget.remoteUserName[0].toUpperCase() : '?';
    final isMediaConnected = _remoteUid != null;
    final subtitle = isMediaConnected || _signalingConnected
        ? _durationText
        : AppLocalizations.of(context)!.callWaiting;
    final showNetworkHint = _signalingConnected && !isMediaConnected;

    final content = widget.isVideo && _engine != null
        ? _buildVideoCallUI(initial, subtitle, showNetworkHint)
        : _buildVoiceCallUI(initial, subtitle, showNetworkHint);
    // 仅挂断按钮可结束通话：返回键/切后台不关闭页面
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.callPleaseHangup)),
          );
        }
      },
      child: content,
    );
  }

  Widget _buildVoiceCallUI(String initial, String subtitle, bool showNetworkHint) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.isVideo ? AppLocalizations.of(context)!.callVideoCall : AppLocalizations.of(context)!.callVoiceCall,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 56,
              backgroundColor: const Color(0xFF2A2B33),
              child: Text(
                initial,
                style: const TextStyle(fontSize: 36, color: Color(0xFFD4AF37)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.remoteUserName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
            if (showNetworkHint) ...[
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context)!.callCheckNetwork,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '频道: ${widget.channelId}',
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            _buildControlBar(showSwitchCamera: false),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCallUI(String initial, String subtitle, bool showNetworkHint) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 远端画面（全屏）
            if (_remoteUid != null && _engine != null)
              AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _engine!,
                  canvas: VideoCanvas(uid: _remoteUid!),
                  connection: RtcConnection(channelId: widget.channelId),
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: const Color(0xFF2A2B33),
                      child: Text(
                        initial,
                        style: const TextStyle(
                            fontSize: 32, color: Color(0xFFD4AF37)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.remoteUserName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    if (showNetworkHint)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          AppLocalizations.of(context)!.callCheckNetwork,
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            // 顶部状态栏：时长
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _durationText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            // 本地画面（小窗）
            if (_engine != null)
              Positioned(
                top: 48,
                right: 16,
                width: 100,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AgoraVideoView(
                    controller: VideoViewController(
                      rtcEngine: _engine!,
                      canvas: const VideoCanvas(uid: 0),
                    ),
                  ),
                ),
              ),
            // 底部控制栏
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: _buildControlBar(showSwitchCamera: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlBar({required bool showSwitchCamera}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _controlButton(
          icon: _muted ? Icons.mic_off : Icons.mic,
          label: _muted ? AppLocalizations.of(context)!.callUnmute : AppLocalizations.of(context)!.callMute,
          onPressed: () async {
            if (_engine == null) return;
            setState(() => _muted = !_muted);
            await _engine!.muteLocalAudioStream(_muted);
          },
        ),
        if (showSwitchCamera)
          _controlButton(
            icon: Icons.cameraswitch,
            label: AppLocalizations.of(context)!.callFlipCamera,
            onPressed: _switchCamera,
          ),
        _controlButton(
          icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
          label: _speakerOn ? AppLocalizations.of(context)!.callSpeaker : AppLocalizations.of(context)!.callEarpiece,
          onPressed: _toggleSpeaker,
        ),
        _controlButton(
          icon: Icons.call_end,
          label: AppLocalizations.of(context)!.callHangup,
          color: Colors.red,
          onPressed: () => _leaveAndPop(),
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    VoidCallback? onPressed,
    Color? color,
  }) {
    final c = color ?? Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: c.withValues(alpha: 0.2),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, size: 28, color: c),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(color: c, fontSize: 12),
        ),
      ],
    );
  }
}
