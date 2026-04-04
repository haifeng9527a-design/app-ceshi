import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import { getLocales } from 'expo-localization';

import zh from './zh.json';
import en from './en.json';

const deviceLocale = getLocales()[0]?.languageCode ?? 'zh';

i18n.use(initReactI18next).init({
  resources: {
    zh: { translation: zh },
    en: { translation: en },
  },
  lng: deviceLocale.startsWith('zh') ? 'zh' : 'en',
  fallbackLng: 'zh',
  interpolation: {
    escapeValue: false,
  },
});

export default i18n;
