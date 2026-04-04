import { Redirect } from 'expo-router';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { useAuthStore } from '../services/store/authStore';
import { Colors } from '../theme/colors';

export default function Index() {
  const { user, initializing } = useAuthStore();

  // Show loading while Firebase checks auth state
  if (initializing) {
    return (
      <View style={styles.splash}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

  // Not logged in → show login screen
  if (!user) {
    return <Redirect href="/(auth)/login" />;
  }

  // Logged in → go to main app
  return <Redirect href="/(tabs)/market" />;
}

const styles = StyleSheet.create({
  splash: {
    flex: 1,
    backgroundColor: Colors.background,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
