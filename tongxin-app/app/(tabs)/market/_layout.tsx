import { Stack } from 'expo-router';
import { Colors } from '../../../theme/colors';

export default function MarketLayout() {
  return (
    <Stack
      screenOptions={{
        headerShown: false,
        contentStyle: { backgroundColor: Colors.background },
      }}
    />
  );
}
