import { View, useWindowDimensions, StyleSheet } from 'react-native';
import { Tabs } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors } from '../../theme/colors';
import Sidebar from '../../components/layout/Sidebar';

export default function TabLayout() {
  const { t } = useTranslation();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 1024;

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
            name="rankings"
            options={{
              title: t('nav.rankings'),
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
