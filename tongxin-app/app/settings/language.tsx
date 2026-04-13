import { useMemo, useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useRouter } from 'expo-router';
import i18n from '../../i18n';
import { Colors, Sizes } from '../../theme/colors';
import { saveLanguagePreference } from '../../services/storage/preferences';

type LanguageOption = {
  value: 'zh' | 'en';
  label: string;
  description: string;
};

const OPTIONS: LanguageOption[] = [
  { value: 'zh', label: '简体中文', description: '适合中文用户，界面文案更自然。' },
  { value: 'en', label: 'English', description: 'Useful for international users and English-first workflows.' },
];

export default function LanguageSettingsScreen() {
  const router = useRouter();
  const current = useMemo<'zh' | 'en'>(
    () => (i18n.language?.startsWith('en') ? 'en' : 'zh'),
    []
  );
  const [selected, setSelected] = useState<'zh' | 'en'>(current);
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    setSaving(true);
    try {
      await i18n.changeLanguage(selected);
      await saveLanguagePreference(selected);
      Alert.alert('已更新', selected === 'zh' ? '语言已切换为简体中文。' : 'Language switched to English.');
      router.back();
    } catch (e: any) {
      Alert.alert('切换失败', e?.message || '语言切换失败，请稍后重试。');
    } finally {
      setSaving(false);
    }
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
      <Text style={styles.title}>语言设置</Text>
      <Text style={styles.subtitle}>选择你更习惯的界面语言，切换后会立即作用于全局页面。</Text>

      <View style={styles.card}>
        {OPTIONS.map((option, index) => {
          const active = option.value === selected;
          return (
            <TouchableOpacity
              key={option.value}
              style={[styles.optionRow, index < OPTIONS.length - 1 && styles.optionBorder, active && styles.optionRowActive]}
              activeOpacity={0.8}
              onPress={() => setSelected(option.value)}
            >
              <View style={styles.optionMain}>
                <Text style={styles.optionLabel}>{option.label}</Text>
                <Text style={styles.optionDescription}>{option.description}</Text>
              </View>
              <View style={[styles.optionRadio, active && styles.optionRadioActive]}>
                {active ? <View style={styles.optionRadioDot} /> : null}
              </View>
            </TouchableOpacity>
          );
        })}
      </View>

      <TouchableOpacity
        style={[styles.saveBtn, saving && styles.saveBtnDisabled]}
        activeOpacity={0.85}
        onPress={() => void handleSave()}
        disabled={saving}
      >
        <Text style={styles.saveBtnText}>{saving ? '保存中…' : '保存语言设置'}</Text>
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  content: {
    padding: 20,
    gap: 18,
  },
  title: {
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
    marginTop: 12,
  },
  subtitle: {
    color: Colors.textMuted,
    fontSize: 13,
    lineHeight: 20,
  },
  card: {
    backgroundColor: Colors.surface,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    overflow: 'hidden',
  },
  optionRow: {
    paddingHorizontal: 18,
    paddingVertical: 18,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
  },
  optionRowActive: {
    backgroundColor: Colors.primaryDim,
  },
  optionBorder: {
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  optionMain: {
    flex: 1,
    gap: 6,
  },
  optionLabel: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '700',
  },
  optionDescription: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
  },
  optionRadio: {
    width: 22,
    height: 22,
    borderRadius: 11,
    borderWidth: 1.5,
    borderColor: Colors.borderLight,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.surfaceAlt,
  },
  optionRadioActive: {
    borderColor: Colors.primary,
    backgroundColor: 'rgba(212, 178, 75, 0.18)',
  },
  optionRadioDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: Colors.primary,
  },
  saveBtn: {
    backgroundColor: Colors.primary,
    borderRadius: Sizes.borderRadiusSm,
    paddingVertical: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  saveBtnDisabled: {
    opacity: 0.6,
  },
  saveBtnText: {
    color: Colors.background,
    fontSize: 14,
    fontWeight: '800',
  },
});
