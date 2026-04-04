import { useEffect } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Colors } from '../theme/colors';
import { marketWs } from '../services/websocket/marketWs';
import { useMarketStore } from '../services/store/marketStore';
import { useAuthStore } from '../services/store/authStore';
import '../i18n';

export default function RootLayout() {
  const setWsConnected = useMarketStore((s) => s.setWsConnected);
  const initialize = useAuthStore((s) => s.initialize);

  // Initialize Firebase auth listener
  useEffect(() => {
    const unsubscribe = initialize();
    return () => unsubscribe();
  }, []);

  // Connect to market WebSocket (public, no auth needed)
  useEffect(() => {
    marketWs.connect();
    marketWs.onMessage((data) => {
      if (data.type === 'connected' || data.type === 'welcome') {
        setWsConnected(true);
      }
    });

    return () => {
      marketWs.disconnect();
    };
  }, []);

  return (
    <>
      <StatusBar style="light" />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: Colors.background },
        }}
      />
    </>
  );
}
