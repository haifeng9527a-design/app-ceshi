import { useEffect, useMemo, useRef, useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, Alert, Platform, Image } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Colors, Sizes } from '../../theme/colors';
import { endCall, getCall, getLiveKitToken, type CallRecord, type LiveKitTokenPayload } from '../../services/api/callsApi';
import { fetchConversation, fetchUserProfilesBatch, type ApiConversation, type PeerProfile } from '../../services/api/messagesApi';
import { Room, RoomEvent, Track } from 'livekit-client';
import { useAuthStore } from '../../services/store/authStore';
import { useCallStore } from '../../services/store/callStore';

const livekitNative = Platform.OS === 'web' ? null : require('@livekit/react-native');
const LiveKitRoom = livekitNative?.LiveKitRoom as any;
const AudioSession = livekitNative?.AudioSession as any;

function formatDuration(totalSeconds: number): string {
  const mins = Math.floor(totalSeconds / 60);
  const secs = totalSeconds % 60;
  return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

export default function CallScreen() {
  const router = useRouter();
  const currentUser = useAuthStore((s) => s.user);
  const currentCall = useCallStore((s) => s.currentCall);
  const params = useLocalSearchParams<{ id?: string | string[] }>();
  const callId = Array.isArray(params.id) ? params.id[0] : params.id;
  const room = useMemo(
    () =>
      new Room({
        adaptiveStream: true,
        dynacast: true,
      }),
    [],
  );
  const attachedElementsRef = useRef<Map<string, HTMLMediaElement>>(new Map());

  const [call, setCall] = useState<CallRecord | null>(null);
  const [tokenData, setTokenData] = useState<LiveKitTokenPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [ending, setEnding] = useState(false);
  const [configError, setConfigError] = useState<string | null>(null);
  const [lkConnected, setLkConnected] = useState(false);
  const [lkError, setLkError] = useState<string | null>(null);
  const [micEnabled, setMicEnabled] = useState(true);
  const [remoteParticipantCount, setRemoteParticipantCount] = useState(0);
  const [needsAudioStart, setNeedsAudioStart] = useState(false);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [conversation, setConversation] = useState<ApiConversation | null>(null);
  const [peerProfile, setPeerProfile] = useState<PeerProfile | null>(null);
  const hasBeenLiveRef = useRef(false);
  const hasExitedRef = useRef(false);

  useEffect(() => {
    if (!callId) return;
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const [callRes, tokenRes] = await Promise.all([
          getCall(callId),
          getLiveKitToken(callId).catch((e: any) => {
            const msg = e?.response?.data?.error || e?.message || 'livekit is not configured';
            setConfigError(msg);
            return null;
          }),
        ]);
        if (cancelled) return;
        setCall(callRes);
        setTokenData(tokenRes);

        const conversationRes = await fetchConversation(callRes.conversation_id).catch(() => null);
        if (cancelled) return;
        setConversation(conversationRes);

        if (conversationRes?.peer_id) {
          const profiles = (await fetchUserProfilesBatch([conversationRes.peer_id]).catch(
            () => ({} as Record<string, PeerProfile>),
          )) as Record<string, PeerProfile>;
          if (cancelled) return;
          setPeerProfile(profiles[conversationRes.peer_id] ?? null);
        } else {
          setPeerProfile(null);
        }
      } catch (e: any) {
        if (!cancelled) {
          Alert.alert('加载失败', e?.response?.data?.error || e?.message || '无法加载通话信息');
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [callId]);

  useEffect(() => {
    if (Platform.OS === 'web' || !AudioSession) return;
    let mounted = true;
    (async () => {
      try {
        await AudioSession.startAudioSession();
      } catch (e) {
        if (mounted) {
          console.warn('[Call] startAudioSession failed:', e);
        }
      }
    })();
    return () => {
      mounted = false;
      try {
        AudioSession.stopAudioSession();
      } catch {
        // ignore
      }
    };
  }, []);

  useEffect(() => {
    if (!call) return;
    const startedAt = call.answered_at || call.started_at;
    if (!startedAt) return;

    const tick = () => {
      const startedMs = new Date(startedAt).getTime();
      const diff = Math.max(0, Math.floor((Date.now() - startedMs) / 1000));
      setElapsedSeconds(diff);
    };

    tick();
    const timer = setInterval(tick, 1000);
    return () => clearInterval(timer);
  }, [call?.id, call?.answered_at, call?.started_at]);

  useEffect(() => {
    if (!callId || loading) return;

    if (currentCall?.id === callId) {
      hasBeenLiveRef.current = currentCall.status === 'ringing' || currentCall.status === 'active';
      setCall((prev) => {
        if (!prev || prev.id !== currentCall.id) return currentCall;
        if (
          prev.status === currentCall.status &&
          prev.answered_at === currentCall.answered_at &&
          prev.ended_at === currentCall.ended_at &&
          prev.updated_at === currentCall.updated_at
        ) {
          return prev;
        }
        return { ...prev, ...currentCall };
      });
      return;
    }

    if (!call || call.id !== callId || hasExitedRef.current) return;

    const localEnded = call.status === 'ended' || call.status === 'rejected';
    if (localEnded || hasBeenLiveRef.current) {
      hasExitedRef.current = true;
      router.replace('/(tabs)/messages');
    }
  }, [callId, loading, currentCall, call, router]);

  useEffect(() => {
    if (!callId || loading || hasExitedRef.current) return;
    let cancelled = false;

    const pollCallState = async () => {
      try {
        const latest = await getCall(callId);
        if (cancelled || hasExitedRef.current) return;

        setCall((prev) => {
          if (!prev || prev.id !== latest.id) return latest;
          if (
            prev.status === latest.status &&
            prev.answered_at === latest.answered_at &&
            prev.ended_at === latest.ended_at &&
            prev.updated_at === latest.updated_at
          ) {
            return prev;
          }
          return { ...prev, ...latest };
        });

        if (latest.status === 'ringing' || latest.status === 'active') {
          hasBeenLiveRef.current = true;
        }

        if (latest.status === 'ended' || latest.status === 'rejected') {
          hasExitedRef.current = true;
          router.replace('/(tabs)/messages');
        }
      } catch {
        // Keep the current call screen if polling fails transiently.
      }
    };

    const timer = setInterval(() => {
      void pollCallState();
    }, 3000);

    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [callId, loading, router]);

  useEffect(() => {
    if (Platform.OS !== 'web' || !tokenData) return;
    let cancelled = false;

    const removeAttachedElements = () => {
      attachedElementsRef.current.forEach((element) => {
        try {
          element.pause?.();
          element.remove();
        } catch {
          // ignore
        }
      });
      attachedElementsRef.current.clear();
    };

    const syncRemoteParticipantCount = () => {
      setRemoteParticipantCount(room.remoteParticipants.size);
    };

    const handleTrackSubscribed = (track: any, publication: any, participant: any) => {
      if (track.kind !== Track.Kind.Audio) return;
      const element = track.attach();
      element.setAttribute('data-lk-participant', participant.identity || participant.sid || '');
      element.style.display = 'none';
      document.body.appendChild(element);
      attachedElementsRef.current.set(publication.trackSid, element);
      syncRemoteParticipantCount();
    };

    const handleTrackUnsubscribed = (track: any, publication: any) => {
      const existing = attachedElementsRef.current.get(publication.trackSid);
      if (existing) {
        existing.remove();
        attachedElementsRef.current.delete(publication.trackSid);
      }
      track.detach();
      syncRemoteParticipantCount();
    };

    const handleDisconnected = () => {
      setLkConnected(false);
    };

    const handleAudioPlaybackStatus = () => {
      setNeedsAudioStart(!room.canPlaybackAudio);
    };

    const connectWebRoom = async () => {
      try {
        room
          .on(RoomEvent.TrackSubscribed, handleTrackSubscribed)
          .on(RoomEvent.TrackUnsubscribed, handleTrackUnsubscribed)
          .on(RoomEvent.ParticipantConnected, syncRemoteParticipantCount)
          .on(RoomEvent.ParticipantDisconnected, syncRemoteParticipantCount)
          .on(RoomEvent.Disconnected, handleDisconnected)
          .on(RoomEvent.AudioPlaybackStatusChanged, handleAudioPlaybackStatus);

        room.prepareConnection(tokenData.server_url, tokenData.token);
        await room.connect(tokenData.server_url, tokenData.token);
        if (cancelled) return;

        setLkConnected(true);
        setLkError(null);
        syncRemoteParticipantCount();
        setNeedsAudioStart(!room.canPlaybackAudio);

        await room.localParticipant.setMicrophoneEnabled(true);
        if (!cancelled) setMicEnabled(true);
      } catch (e: any) {
        if (!cancelled) {
          setLkConnected(false);
          setLkError(e?.message || '网页端连接 LiveKit 失败');
        }
      }
    };

    void connectWebRoom();

    return () => {
      cancelled = true;
      room.off(RoomEvent.TrackSubscribed, handleTrackSubscribed);
      room.off(RoomEvent.TrackUnsubscribed, handleTrackUnsubscribed);
      room.off(RoomEvent.ParticipantConnected, syncRemoteParticipantCount);
      room.off(RoomEvent.ParticipantDisconnected, syncRemoteParticipantCount);
      room.off(RoomEvent.Disconnected, handleDisconnected);
      room.off(RoomEvent.AudioPlaybackStatusChanged, handleAudioPlaybackStatus);
      removeAttachedElements();
      room.disconnect(true);
      setLkConnected(false);
      setNeedsAudioStart(false);
      setRemoteParticipantCount(0);
    };
  }, [room, tokenData]);

  const handleHangup = async () => {
    if (!callId) return;
    setEnding(true);
    try {
      await endCall(callId, 'hangup');
      router.back();
    } catch (e: any) {
      Alert.alert('挂断失败', e?.response?.data?.error || e?.message || '挂断失败');
    } finally {
      setEnding(false);
    }
  };

  const handleToggleMic = async () => {
    try {
      const next = !micEnabled;
      await room.localParticipant.setMicrophoneEnabled(next);
      setMicEnabled(next);
    } catch (e: any) {
      Alert.alert('麦克风切换失败', e?.message || '无法切换麦克风');
    }
  };

  const handleStartWebAudio = async () => {
    try {
      await room.startAudio();
      setNeedsAudioStart(false);
      setLkError(null);
    } catch (e: any) {
      Alert.alert('音频播放失败', e?.message || '浏览器未允许播放远端音频');
    }
  };

  const statusTone =
    call?.status === 'active'
      ? 'active'
      : call?.status === 'ringing'
        ? 'ringing'
        : call?.status === 'ended' || call?.status === 'rejected'
          ? 'ended'
          : 'idle';

  const statusLabel =
    call?.status === 'active'
      ? '通话中'
      : call?.status === 'ringing'
        ? '等待对方接听'
        : call?.status === 'ended'
          ? '已结束'
          : call?.status === 'rejected'
            ? '已拒绝'
            : '准备连接';

  const statusHint =
    Platform.OS === 'web'
      ? needsAudioStart
        ? '浏览器已连房，点击“开启声音”后才能听见对方。'
        : lkConnected
          ? '网页端已经连上语音房间，可以直接开始通话。'
          : '正在连接语音房间，请稍候。'
      : lkConnected
        ? '原生语音链路已经连通，当前可直接静音或挂断。'
        : '正在初始化原生音频会话。';

  const stageItems =
    Platform.OS === 'web'
      ? [
          { label: '房间票据', value: tokenData ? '已就绪' : '等待中' },
          { label: '麦克风', value: micEnabled ? '已打开' : '已静音' },
          { label: '远端音频', value: needsAudioStart ? '待手动开启' : '可播放' },
        ]
      : [
          { label: '房间票据', value: tokenData ? '已就绪' : '等待中' },
          { label: '音频会话', value: lkConnected ? '已连通' : '初始化中' },
          { label: '麦克风', value: micEnabled ? '已打开' : '已静音' },
        ];

  const participantLabel =
    remoteParticipantCount > 0
      ? `对方已加入`
      : call?.status === 'active'
        ? '通话已建立'
        : call?.status === 'ringing'
          ? '等待对方接听'
      : '准备中';

  const displayName =
    (conversation?.type === 'group'
      ? conversation?.title
      : peerProfile?.display_name || conversation?.title) ||
    '通话中';

  const displayAvatarUrl =
    (conversation?.type === 'group' ? conversation?.avatar_url : peerProfile?.avatar_url || conversation?.avatar_url) || '';

  const avatarFallback = (displayName || currentUser?.displayName || '?').trim().slice(0, 1).toUpperCase();

  const subtleStatus =
    Platform.OS === 'web'
      ? needsAudioStart
        ? '点一下开启声音'
        : lkConnected
          ? participantLabel
          : '连接语音中'
      : lkConnected
        ? participantLabel
        : '连接语音中';

  const headerCard = (
    <View style={styles.heroCard}>
      <View style={styles.heroCenter}>
        {displayAvatarUrl ? (
          <Image source={{ uri: displayAvatarUrl }} style={styles.heroAvatarImage} />
        ) : (
          <View style={styles.heroAvatar}>
            <Text style={styles.heroAvatarText}>{avatarFallback}</Text>
          </View>
        )}
        <Text style={styles.heroName}>{displayName}</Text>
        <Text style={styles.heroTitle}>{statusLabel}</Text>
        <Text style={styles.heroSub}>{subtleStatus}</Text>
      </View>

      <View style={styles.heroStatsRow}>
        <View style={styles.heroStat}>
          <Text style={styles.heroStatLabel}>通话时长</Text>
          <Text style={styles.heroStatValue}>{formatDuration(elapsedSeconds)}</Text>
        </View>
        <View style={styles.heroStat}>
          <Text style={styles.heroStatLabel}>麦克风</Text>
          <Text style={styles.heroStatValue}>{micEnabled ? '已开启' : '已静音'}</Text>
        </View>
        <View style={styles.heroStat}>
          <Text style={styles.heroStatLabel}>通话状态</Text>
          <Text style={styles.heroStatValue}>{lkConnected ? '已连接' : '连接中'}</Text>
        </View>
      </View>
    </View>
  );

  const detailCard = (
    <View style={styles.detailCard}>
      <View style={styles.checklistCard}>
        <Text style={styles.checklistTitle}>{Platform.OS === 'web' ? '通话提示' : '通话状态'}</Text>
        {stageItems.map((item) => (
          <View key={item.label} style={styles.checklistRow}>
            <Text style={styles.checklistDot}>•</Text>
            <Text style={styles.checklistLabel}>{item.label}</Text>
            <Text style={styles.checklistValue}>{item.value}</Text>
          </View>
        ))}
      </View>

      {needsAudioStart ? (
        <View style={styles.warnBox}>
          <Text style={styles.warnTitle}>还差一步</Text>
          <Text style={styles.warnText}>
            浏览器为了防止网页自动出声，要求你先点一次“开启声音”。这一步做完后，远端语音就能正常播放。
          </Text>
        </View>
      ) : null}

      {lkError ? (
        <View style={styles.warnBox}>
          <Text style={styles.warnTitle}>连接异常</Text>
          <Text style={styles.warnText}>{lkError}</Text>
        </View>
      ) : null}
    </View>
  );

  const actionRow = (
    <View style={styles.actionDock}>
      <TouchableOpacity
        style={[styles.secondaryActionBtn, !lkConnected && styles.nativeActionBtnDisabled]}
        activeOpacity={0.85}
        disabled={!lkConnected}
        onPress={handleToggleMic}
      >
        <Text style={styles.secondaryActionText}>{micEnabled ? '静音麦克风' : '恢复麦克风'}</Text>
      </TouchableOpacity>

      {Platform.OS === 'web' && needsAudioStart ? (
        <TouchableOpacity style={styles.primaryActionBtn} activeOpacity={0.85} onPress={handleStartWebAudio}>
          <Text style={styles.primaryActionText}>开启声音</Text>
        </TouchableOpacity>
      ) : null}

      <TouchableOpacity
        style={[
          styles.hangupBtn,
          ending && styles.hangupBtnDisabled,
          Platform.OS === 'web' && !needsAudioStart ? { marginTop: 0, flex: 1 } : null,
        ]}
        activeOpacity={0.85}
        disabled={ending}
        onPress={handleHangup}
      >
        <Text style={styles.hangupText}>{ending ? '挂断中...' : '挂断通话'}</Text>
      </TouchableOpacity>
    </View>
  );

  const nativeCard = (
    <View style={styles.screenWrap}>
      {headerCard}
      {detailCard}
      {actionRow}
    </View>
  );

  return (
    <View style={styles.container}>
      <TouchableOpacity style={styles.backBtn} activeOpacity={0.8} onPress={() => router.back()}>
        <Text style={styles.backText}>← 返回消息</Text>
      </TouchableOpacity>

      {loading ? (
        <ActivityIndicator color={Colors.primary} size="large" />
      ) : Platform.OS === 'web' ? (
        <View style={styles.screenWrap}>
          {headerCard}
          {detailCard}
          {actionRow}
          <Text style={styles.webHint}>
            网页端现在已支持真实语音。若你能看到连接正常但听不到声音，通常是浏览器还在等一次用户手势来开启音频。
          </Text>
        </View>
      ) : tokenData && LiveKitRoom ? (
        <LiveKitRoom
          room={room ?? undefined}
          serverUrl={tokenData.server_url}
          token={tokenData.token}
          connect={true}
          audio={true}
          video={false}
          onConnected={() => {
            setLkConnected(true);
            setLkError(null);
          }}
          onDisconnected={() => {
            setLkConnected(false);
          }}
          onError={(error: Error) => {
            setLkError(error.message);
          }}
        >
          {nativeCard}
        </LiveKitRoom>
      ) : (
        <View style={styles.screenWrap}>
          {headerCard}
          <View style={styles.detailCard}>
            {tokenData ? (
              <View style={styles.readyBox}>
                <Text style={styles.readyTitle}>Ready For LiveKit</Text>
                <Text style={styles.readyText}>
                  房间票据已经就绪，原生端会在进入页面后自动完成 LiveKit 连房和音频初始化。
                </Text>
              </View>
            ) : (
              <View style={styles.warnBox}>
                <Text style={styles.warnTitle}>暂时无法开始通话</Text>
                <Text style={styles.warnText}>
                  语音服务还没准备好，请稍后再试。
                </Text>
              </View>
            )}
          </View>
          {actionRow}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
    padding: 24,
    justifyContent: 'center',
  },
  screenWrap: {
    alignSelf: 'center',
    width: '100%',
    maxWidth: 820,
    gap: 18,
  },
  backBtn: {
    position: 'absolute',
    top: 24,
    left: 24,
  },
  backText: {
    color: Colors.textSecondary,
    fontSize: 14,
    fontWeight: '600',
  },
  card: {
    alignSelf: 'center',
    width: '100%',
    maxWidth: 720,
    backgroundColor: Colors.surface,
    borderRadius: 24,
    padding: 28,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  heroCard: {
    width: '100%',
    backgroundColor: Colors.surface,
    borderRadius: 28,
    padding: 28,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  heroCenter: {
    alignItems: 'center',
  },
  heroAvatar: {
    width: 96,
    height: 96,
    borderRadius: 48,
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    alignItems: 'center',
    justifyContent: 'center',
  },
  heroAvatarImage: {
    width: 96,
    height: 96,
    borderRadius: 48,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  heroAvatarText: {
    fontSize: 34,
    color: Colors.textActive,
    fontWeight: '800',
  },
  heroName: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '700',
    marginTop: 14,
    textAlign: 'center',
  },
  heroTitle: {
    color: Colors.textActive,
    fontSize: 30,
    fontWeight: '800',
    marginTop: 10,
    textAlign: 'center',
  },
  heroSub: {
    color: Colors.textMuted,
    fontSize: 14,
    lineHeight: 22,
    marginTop: 8,
    maxWidth: 460,
    textAlign: 'center',
  },
  heroStatsRow: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 22,
  },
  heroStat: {
    flex: 1,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
  },
  heroStatLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
  },
  heroStatValue: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '800',
    marginTop: 10,
  },
  eyebrow: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1.4,
    textTransform: 'uppercase',
  },
  title: {
    color: Colors.textActive,
    fontSize: 30,
    fontWeight: '800',
    marginTop: 8,
  },
  sub: {
    color: Colors.textMuted,
    fontSize: 14,
    lineHeight: 22,
    marginTop: 10,
    marginBottom: 24,
  },
  metaBlock: {
    marginBottom: 14,
  },
  detailCard: {
    width: '100%',
    backgroundColor: Colors.surface,
    borderRadius: 24,
    padding: 24,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  label: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  value: {
    color: Colors.textActive,
    fontSize: 14,
    marginTop: 6,
  },
  checklistCard: {
    marginTop: 18,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.02)',
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
  },
  checklistTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '800',
    marginBottom: 8,
  },
  checklistRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 7,
  },
  checklistDot: {
    color: Colors.primary,
    width: 18,
    fontSize: 18,
    lineHeight: 18,
  },
  checklistLabel: {
    flex: 1,
    color: Colors.textSecondary,
    fontSize: 13,
  },
  checklistValue: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
  },
  readyBox: {
    marginTop: 18,
    padding: 16,
    borderRadius: 16,
    backgroundColor: Colors.primaryDim,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
  },
  readyTitle: {
    color: Colors.primary,
    fontSize: 14,
    fontWeight: '800',
  },
  readyText: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 8,
  },
  warnBox: {
    marginTop: 18,
    padding: 16,
    borderRadius: 16,
    backgroundColor: 'rgba(198, 40, 40, 0.08)',
    borderWidth: 1,
    borderColor: 'rgba(198, 40, 40, 0.22)',
  },
  warnTitle: {
    color: Colors.down,
    fontSize: 14,
    fontWeight: '800',
  },
  warnText: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 8,
  },
  nativeActions: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 22,
  },
  actionDock: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'stretch',
  },
  nativeActionBtn: {
    flex: 1,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: Sizes.borderRadiusSm,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingVertical: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  nativeActionBtnDisabled: {
    opacity: 0.5,
  },
  secondaryActionBtn: {
    flex: 1,
    minHeight: 56,
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 16,
  },
  secondaryActionText: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '800',
  },
  primaryActionBtn: {
    flex: 1,
    minHeight: 56,
    backgroundColor: Colors.primary,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 16,
  },
  primaryActionText: {
    color: Colors.background,
    fontSize: 15,
    fontWeight: '800',
  },
  webAudioBtn: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  nativeActionText: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '800',
  },
  hangupBtn: {
    marginTop: 22,
    minHeight: 56,
    backgroundColor: 'rgba(198, 40, 40, 0.12)',
    borderRadius: Sizes.borderRadiusSm,
    borderWidth: 1,
    borderColor: 'rgba(198, 40, 40, 0.24)',
    paddingVertical: 14,
    alignItems: 'center',
  },
  hangupBtnDisabled: {
    opacity: 0.5,
  },
  hangupText: {
    color: Colors.down,
    fontSize: 14,
    fontWeight: '800',
  },
  webHint: {
    alignSelf: 'center',
    maxWidth: 760,
    color: Colors.textMuted,
    fontSize: 13,
    lineHeight: 20,
    textAlign: 'center',
    marginTop: 4,
  },
});
