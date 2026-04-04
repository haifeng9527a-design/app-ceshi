import { useEffect, useCallback, useRef } from 'react';
import { View, useWindowDimensions, StyleSheet, Alert } from 'react-native';
import { Tabs } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors } from '../../theme/colors';
import Sidebar from '../../components/layout/Sidebar';
import { useAuthStore } from '../../services/store/authStore';
import { useMessagesStore } from '../../services/store/messagesStore';
import { chatWs } from '../../services/websocket/chatWs';

export default function TabLayout() {
  const { t } = useTranslation();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 1024;
  const user = useAuthStore((s) => s.user);
  const connectWs = useMessagesStore((s) => s.connectWs);
  const disconnectWs = useMessagesStore((s) => s.disconnectWs);
  const loadConversations = useMessagesStore((s) => s.loadConversations);
  const loadFriends = useMessagesStore((s) => s.loadFriends);
  const loadFriendRequests = useMessagesStore((s) => s.loadFriendRequests);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

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
      disconnectWs();
      if (pollRef.current) {
        clearInterval(pollRef.current);
        pollRef.current = null;
      }
    };
  }, [user?.uid, connectWs, disconnectWs, onFriendRequest, onFriendAccepted, loadConversations, loadFriendRequests]);

  return (
    <View style={styles.container}>
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
            name="messages"
            options={{
              title: t('messages.title'),
              tabBarIcon: ({ color }) => null,
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
});
