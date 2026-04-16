import { useEffect } from 'react';
import { Platform } from 'react-native';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Colors } from '../theme/colors';
import { marketWs } from '../services/websocket/marketWs';
import { useMarketStore } from '../services/store/marketStore';
import { useAuthStore } from '../services/store/authStore';
import { loadLanguagePreference } from '../services/storage/preferences';
import i18n from '../i18n';
import '../i18n';
import DialogHost from '../components/ui/DialogHost';
import { installDialogAlertBridge } from '../services/utils/dialog';

let livekitGlobalsReady = false;

export default function RootLayout() {
  const setWsConnected = useMarketStore((s) => s.setWsConnected);
  const initialize = useAuthStore((s) => s.initialize);

  useEffect(() => {
    if (Platform.OS === 'web' || livekitGlobalsReady) return;
    try {
      const { registerGlobals } = require('@livekit/react-native');
      registerGlobals();
      livekitGlobalsReady = true;
    } catch (e) {
      console.warn('[LiveKit] registerGlobals failed:', e);
    }
  }, []);

  useEffect(() => {
    let mounted = true;
    (async () => {
      const savedLanguage = await loadLanguagePreference();
      if (!mounted || !savedLanguage) return;
      if (i18n.language !== savedLanguage) {
        await i18n.changeLanguage(savedLanguage);
      }
    })();
    return () => {
      mounted = false;
    };
  }, []);

  useEffect(() => {
    installDialogAlertBridge();
  }, []);

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
      <DialogHost />
    </>
  );
}
