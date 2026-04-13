import AsyncStorage from '@react-native-async-storage/async-storage';

const LANGUAGE_KEY = 'tongxin_language';

export async function saveLanguagePreference(language: 'zh' | 'en') {
  await AsyncStorage.setItem(LANGUAGE_KEY, language);
}

export async function loadLanguagePreference(): Promise<'zh' | 'en' | null> {
  try {
    const value = await AsyncStorage.getItem(LANGUAGE_KEY);
    if (value === 'zh' || value === 'en') {
      return value;
    }
    return null;
  } catch {
    return null;
  }
}
