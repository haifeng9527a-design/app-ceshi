import { useEffect, useCallback, useRef } from 'react';
import { View, useWindowDimensions, StyleSheet, Alert, Modal, Text, TouchableOpacity } from 'react-native';
import { Tabs, useRouter, useSegments } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors } from '../../theme/colors';
import Sidebar from '../../components/layout/Sidebar';
import { useAuthStore } from '../../services/store/authStore';
import { useMessagesStore } from '../../services/store/messagesStore';
import { useCallStore } from '../../services/store/callStore';
import { chatWs } from '../../services/websocket/chatWs';

export default function TabLayout() {
  const { t } = useTranslation();
  const router = useRouter();
  const segments = useSegments();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 1024;
  const user = useAuthStore((s) => s.user);
  const totalUnread = useMessagesStore((s) => s.totalUnread);
  const connectWs = useMessagesStore((s) => s.connectWs);
  const disconnectWs = useMessagesStore((s) => s.disconnectWs);
  const loadConversations = useMessagesStore((s) => s.loadConversations);
  const loadFriends = useMessagesStore((s) => s.loadFriends);
  const loadFriendRequests = useMessagesStore((s) => s.loadFriendRequests);
  const incomingCall = useCallStore((s) => s.incomingCall);
  const pendingCall = useCallStore((s) => s.pending);
  const acceptIncomingCall = useCallStore((s) => s.acceptIncomingCall);
  const rejectIncomingCall = useCallStore((s) => s.rejectIncomingCall);
  const handleCallEvent = useCallStore((s) => s.handleCallEvent);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const currentLeaf = segments[segments.length - 1] ?? '';
  const showGlobalIncomingCall = !!incomingCall && currentLeaf !== 'messages';

  const onFriendRequest = useCallback(
    (payload: { from_display_name?: string }) => {
      loadFriends();
      void loadFriendRequests();
      const name = payload.from_display_name?.trim() || t('messages.friendUnknown');
      Alert.alert(t('messages.friendRequestTitle'), t('messages.friendRequestBody', { name }));
    },
    [loadFriends, loadFriendRequests, t],
  );

  const onFriendAccepted = useCallback(
    (payload: { accepter_display_name?: string }) => {
      loadFriends();
      void loadFriendRequests();
      const name = payload.accepter_display_name?.trim() || t('messages.friendUnknown');
      Alert.alert(t('messages.friendAcceptedTitle'), t('messages.friendAcceptedBody', { name }));
    },
    [loadFriends, loadFriendRequests, t],
  );

  useEffect(() => {
    if (!user?.uid) {
      disconnectWs();
      if (pollRef.current) {
        clearInterval(pollRef.current);
        pollRef.current = null;
      }
      return;
    }

    chatWs.onFriendRequest(onFriendRequest);
    chatWs.onFriendAccepted(onFriendAccepted);
    chatWs.onCallEvent(handleCallEvent);
    void connectWs();

    void loadConversations();
    void loadFriendRequests();
    if (pollRef.current) clearInterval(pollRef.current);
    pollRef.current = setInterval(() => {
      void loadFriendRequests();
    }, 20000);

    return () => {
      chatWs.offFriendRequest(onFriendRequest);
      chatWs.offFriendAccepted(onFriendAccepted);
      chatWs.offCallEvent(handleCallEvent);
      disconnectWs();
      if (pollRef.current) {
        clearInterval(pollRef.current);
        pollRef.current = null;
      }
    };
  }, [user?.uid, connectWs, disconnectWs, onFriendRequest, onFriendAccepted, handleCallEvent, loadConversations, loadFriendRequests]);

  return (
    <View style={styles.container}>
      <Modal visible={showGlobalIncomingCall} transparent animationType="fade" onRequestClose={() => void rejectIncomingCall()}>
        <View style={styles.callOverlay}>
          <View style={styles.callCard}>
            <Text style={styles.callCardEyebrow}>{t('messages.incomingCall')}</Text>
            <Text style={styles.callCardTitle}>{t('messages.incomingCallInvite')}</Text>
            <Text style={styles.callCardSub}>{t('messages.callConversationId', { id: incomingCall?.conversation_id || '--' })}</Text>
            <View style={styles.callActionRow}>
              <TouchableOpacity
                style={[styles.callBtn, styles.callRejectBtn, pendingCall && styles.callBtnDisabled]}
                activeOpacity={0.85}
                disabled={pendingCall}
                onPress={() => void rejectIncomingCall()}
              >
                <Text style={styles.callRejectText}>{t('messages.rejectCall')}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.callBtn, styles.callAcceptBtn, pendingCall && styles.callBtnDisabled]}
                activeOpacity={0.85}
                disabled={pendingCall}
                onPress={async () => {
                  try {
                    await acceptIncomingCall();
                    const latestCallId = useCallStore.getState().currentCall?.id;
                    if (latestCallId) {
                      router.push(`/call/${latestCallId}` as any);
                    }
                  } catch (e: any) {
                    Alert.alert(t('messages.acceptCallFailedTitle'), e?.response?.data?.error || e?.message || t('messages.acceptVoiceCallFailed'));
                  }
                }}
              >
                <Text style={styles.callAcceptText}>{t('messages.acceptCall')}</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      {/* Sidebar (desktop only) */}
      {isDesktop && <Sidebar />}

      {/* Main Content */}
      <View style={styles.content}>
        <Tabs
          screenOptions={{
            headerShown: false,
            tabBarStyle: isDesktop
              ? { display: 'none' }
              : {
                  backgroundColor: Colors.topBarBg,
                  borderTopColor: Colors.border,
                  borderTopWidth: 1,
                  height: 56,
                  paddingBottom: 4,
                },
            tabBarActiveTintColor: Colors.primary,
            tabBarInactiveTintColor: Colors.textMuted,
            tabBarLabelStyle: {
              fontSize: 11,
              fontWeight: '600',
            },
          }}
        >
          <Tabs.Screen
            name="market"
            options={{
              title: t('nav.market'),
              tabBarIcon: ({ color }) => null,
            }}
          />
          <Tabs.Screen
            name="watchlist"
            options={{
              title: t('nav.watchlist'),
              tabBarIcon: ({ color }) => null,
            }}
          />
          <Tabs.Screen
            name="following"
            options={{
              title: t('following.title'),
              href: null,
              tabBarIcon: ({ color }) => null,
            }}
          />
          <Tabs.Screen
            name="rankings"
            options={{
              title: t('nav.rankings'),
              tabBarIcon: ({ color }) => null,
            }}
          />
          <Tabs.Screen
            name="trader-center"
            options={{
              title: t('nav.traderCenter'),
              tabBarIcon: ({ color }) => null,
            }}
          />
          <Tabs.Screen
            name="trading"
            options={{
              title: t('nav.trading'),
              tabBarIcon: ({ color }) => null,
            }}
          />
          <Tabs.Screen
            name="portfolio"
            options={{
              title: t('assets.title'),
              href: null,
              tabBarIcon: ({ color }) => null,
            }}
          />
          <Tabs.Screen
            name="spot"
            options={{
              title: t('nav.spot'),
              href: null,
              tabBarIcon: ({ color }) => null,
            }}
          />
          <Tabs.Screen
            name="messages"
            options={{
              title: t('messages.title'),
              tabBarIcon: ({ color }) => null,
              tabBarBadge: totalUnread > 0 ? (totalUnread > 99 ? '99+' : totalUnread) : undefined,
              tabBarBadgeStyle: { backgroundColor: '#F6465D', fontSize: 10, fontWeight: '700' },
            }}
          />
          <Tabs.Screen
            name="profile"
            options={{
              title: t('nav.profile'),
              tabBarIcon: ({ color }) => null,
            }}
          />
        </Tabs>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    flexDirection: 'row',
    backgroundColor: Colors.background,
  },
  content: {
    flex: 1,
  },
  callOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.55)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  callCard: {
    width: '100%',
    maxWidth: 420,
    backgroundColor: Colors.surface,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 22,
  },
  callCardEyebrow: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
  },
  callCardTitle: {
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
    marginTop: 8,
  },
  callCardSub: {
    color: Colors.textMuted,
    fontSize: 13,
    marginTop: 8,
  },
  callActionRow: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 20,
  },
  callBtn: {
    flex: 1,
    borderRadius: 14,
    paddingVertical: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  callBtnDisabled: {
    opacity: 0.5,
  },
  callRejectBtn: {
    backgroundColor: 'rgba(198, 40, 40, 0.12)',
    borderWidth: 1,
    borderColor: 'rgba(198, 40, 40, 0.24)',
  },
  callAcceptBtn: {
    backgroundColor: Colors.primary,
  },
  callRejectText: {
    color: Colors.down,
    fontSize: 15,
    fontWeight: '800',
  },
  callAcceptText: {
    color: Colors.background,
    fontSize: 15,
    fontWeight: '800',
  },
});
