// Cross-platform alert / confirm helpers.
//
// React Native's `Alert.alert` is silent (or inconsistent) on `react-native-web`,
// which makes UI feedback flaky on web builds. These helpers fall back to the
// browser's native `window.alert` / `window.confirm` on web and use `Alert` on
// iOS / Android.
//
// Use these in any cross-platform component instead of `Alert.alert` directly.
import { Alert, Platform } from 'react-native';

export function showAlert(message: string, title?: string): void {
  if (Platform.OS === 'web') {
    // Browsers concatenate title + message in their default dialog.
    const text = title ? `${title}\n\n${message}` : message;
    if (typeof window !== 'undefined' && typeof window.alert === 'function') {
      window.alert(text);
    } else {
      // Last-resort: log so it isn't silently dropped.
      console.warn('[dialog] showAlert (no window):', text);
    }
    return;
  }
  Alert.alert(title ?? '', message);
}

export function showConfirm(message: string, title?: string): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    if (Platform.OS === 'web') {
      const text = title ? `${title}\n\n${message}` : message;
      if (typeof window !== 'undefined' && typeof window.confirm === 'function') {
        resolve(window.confirm(text));
      } else {
        console.warn('[dialog] showConfirm (no window):', text);
        resolve(false);
      }
      return;
    }
    Alert.alert(
      title ?? '',
      message,
      [
        { text: '取消', style: 'cancel', onPress: () => resolve(false) },
        { text: '确认', style: 'destructive', onPress: () => resolve(true) },
      ],
      { cancelable: true, onDismiss: () => resolve(false) },
    );
  });
}
