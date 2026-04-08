import { useEffect, useMemo, useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, Alert, Platform } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Colors, Sizes } from '../../theme/colors';
import { endCall, getCall, getLiveKitToken, type CallRecord, type LiveKitTokenPayload } from '../../services/api/callsApi';
import { Room } from 'livekit-client';

const livekitNative = Platform.OS === 'web' ? null : require('@livekit/react-native');
const LiveKitRoom = livekitNative?.LiveKitRoom as any;
const AudioSession = livekitNative?.AudioSession as any;

export default function CallScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{ id?: string | string[] }>();
  const callId = Array.isArray(params.id) ? params.id[0] : params.id;
  const room = useMemo(() => (Platform.OS === 'web' ? null : new Room()), []);

  const [call, setCall] = useState<CallRecord | null>(null);
  const [tokenData, setTokenData] = useState<LiveKitTokenPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [ending, setEnding] = useState(false);
  const [configError, setConfigError] = useState<string | null>(null);
  const [lkConnected, setLkConnected] = useState(false);
  const [lkError, setLkError] = useState<string | null>(null);
  const [micEnabled, setMicEnabled] = useState(true);

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
    if (!room) return;
    try {
      const next = !micEnabled;
      await room.localParticipant.setMicrophoneEnabled(next);
      setMicEnabled(next);
    } catch (e: any) {
      Alert.alert('麦克风切换失败', e?.message || '无法切换麦克风');
    }
  };

  const nativeCard = (
    <View style={styles.card}>
      <Text style={styles.eyebrow}>Voice Call</Text>
      <Text style={styles.title}>LiveKit 通话中枢</Text>
      <Text style={styles.sub}>
        现在已经会真正尝试连到 LiveKit 房间。当前页面负责连房、开麦、静音和挂断。
      </Text>

      <View style={styles.metaBlock}>
        <Text style={styles.label}>Call ID</Text>
        <Text style={styles.value}>{call?.id || '--'}</Text>
      </View>
      <View style={styles.metaBlock}>
        <Text style={styles.label}>状态</Text>
        <Text style={styles.value}>{call?.status || '--'}</Text>
      </View>
      <View style={styles.metaBlock}>
        <Text style={styles.label}>Room</Text>
        <Text style={styles.value}>{tokenData?.room_name || call?.room_name || '--'}</Text>
      </View>
      <View style={styles.metaBlock}>
        <Text style={styles.label}>LiveKit URL</Text>
        <Text style={styles.value}>{tokenData?.server_url || configError || '未配置'}</Text>
      </View>
      <View style={styles.metaBlock}>
        <Text style={styles.label}>连接状态</Text>
        <Text style={styles.value}>{lkConnected ? '已连接' : '连接中 / 未连接'}</Text>
      </View>

      {lkError ? (
        <View style={styles.warnBox}>
          <Text style={styles.warnTitle}>连接错误</Text>
          <Text style={styles.warnText}>{lkError}</Text>
        </View>
      ) : null}

      <View style={styles.nativeActions}>
        <TouchableOpacity
          style={[styles.nativeActionBtn, !lkConnected && styles.nativeActionBtnDisabled]}
          activeOpacity={0.85}
          disabled={!lkConnected}
          onPress={handleToggleMic}
        >
          <Text style={styles.nativeActionText}>{micEnabled ? '静音' : '取消静音'}</Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.hangupBtn, ending && styles.hangupBtnDisabled, { marginTop: 0, flex: 1 }]}
          activeOpacity={0.85}
          disabled={ending}
          onPress={handleHangup}
        >
          <Text style={styles.hangupText}>{ending ? '挂断中...' : '挂断'}</Text>
        </TouchableOpacity>
      </View>
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
        <View style={styles.card}>
          <Text style={styles.eyebrow}>Voice Call</Text>
          <Text style={styles.title}>网页端预览页</Text>
          <Text style={styles.sub}>
            当前网页端只保留信令和调试视图。真正语音媒体流需要 Expo development build。
          </Text>

          <View style={styles.metaBlock}>
            <Text style={styles.label}>Call ID</Text>
            <Text style={styles.value}>{call?.id || '--'}</Text>
          </View>
          <View style={styles.metaBlock}>
            <Text style={styles.label}>状态</Text>
            <Text style={styles.value}>{call?.status || '--'}</Text>
          </View>
          <View style={styles.metaBlock}>
            <Text style={styles.label}>LiveKit URL</Text>
            <Text style={styles.value}>{tokenData?.server_url || configError || '未配置'}</Text>
          </View>

          <View style={styles.warnBox}>
            <Text style={styles.warnTitle}>需要 Development Build</Text>
            <Text style={styles.warnText}>
              你已经装好了 LiveKit Expo plugin，下一步在原生 dev build 里就可以真正通话。
            </Text>
          </View>

          <TouchableOpacity
            style={[styles.hangupBtn, ending && styles.hangupBtnDisabled]}
            activeOpacity={0.85}
            disabled={ending}
            onPress={handleHangup}
          >
            <Text style={styles.hangupText}>{ending ? '挂断中...' : '挂断'}</Text>
          </TouchableOpacity>
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
        <View style={styles.card}>
          <Text style={styles.eyebrow}>Voice Call</Text>
          <Text style={styles.title}>通话连接页</Text>
          <Text style={styles.sub}>这一步已经把信令和 LiveKit token 获取链路接好了。</Text>

          <View style={styles.metaBlock}>
            <Text style={styles.label}>Call ID</Text>
            <Text style={styles.value}>{call?.id || '--'}</Text>
          </View>
          <View style={styles.metaBlock}>
            <Text style={styles.label}>状态</Text>
            <Text style={styles.value}>{call?.status || '--'}</Text>
          </View>
          <View style={styles.metaBlock}>
            <Text style={styles.label}>Room</Text>
            <Text style={styles.value}>{tokenData?.room_name || call?.room_name || '--'}</Text>
          </View>
          <View style={styles.metaBlock}>
            <Text style={styles.label}>LiveKit URL</Text>
            <Text style={styles.value}>{tokenData?.server_url || configError || '未配置'}</Text>
          </View>

          {tokenData ? (
            <View style={styles.readyBox}>
              <Text style={styles.readyTitle}>Ready For LiveKit</Text>
              <Text style={styles.readyText}>
                下一步只需要在原生 development build 中进入这个页面，就会真正连到 LiveKit 房间。
              </Text>
            </View>
          ) : (
            <View style={styles.warnBox}>
              <Text style={styles.warnTitle}>LiveKit 未配置</Text>
              <Text style={styles.warnText}>
                需要在消息服务环境变量里补 `LIVEKIT_URL`、`LIVEKIT_API_KEY`、`LIVEKIT_API_SECRET`。
              </Text>
            </View>
          )}

          <TouchableOpacity
            style={[styles.hangupBtn, ending && styles.hangupBtnDisabled]}
            activeOpacity={0.85}
            disabled={ending}
            onPress={handleHangup}
          >
            <Text style={styles.hangupText}>{ending ? '挂断中...' : '挂断'}</Text>
          </TouchableOpacity>
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
  nativeActionText: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '800',
  },
  hangupBtn: {
    marginTop: 22,
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
});
