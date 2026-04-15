import { useMemo, useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import i18n from '../../i18n';
import { Colors, Sizes } from '../../theme/colors';
import { saveLanguagePreference } from '../../services/storage/preferences';
import AppIcon from '../../components/ui/AppIcon';

type LanguageOption = {
  value: 'zh' | 'en';
  label: string;
  description: string;
};

export default function LanguageSettingsScreen() {
  const router = useRouter();
  const { t } = useTranslation();
  const current = useMemo<'zh' | 'en'>(
    () => (i18n.language?.startsWith('en') ? 'en' : 'zh'),
    []
  );
  const [selected, setSelected] = useState<'zh' | 'en'>(current);
  const [saving, setSaving] = useState(false);
  const options: LanguageOption[] = useMemo(
    () => [
      {
        value: 'zh',
        label: t('language.zhLabel'),
        description: t('language.zhDescription'),
      },
      {
        value: 'en',
        label: t('language.enLabel'),
        description: t('language.enDescription'),
      },
    ],
    [t]
  );

  const handleSave = async () => {
    setSaving(true);
    try {
      await i18n.changeLanguage(selected);
      await saveLanguagePreference(selected);
      Alert.alert(
        t('language.updatedTitle'),
        selected === 'zh' ? t('language.updatedZh') : t('language.updatedEn')
      );
      router.back();
    } catch (e: any) {
      Alert.alert(t('language.failedTitle'), e?.message || t('language.failedBody'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
      <TouchableOpacity style={styles.backBtn} activeOpacity={0.8} onPress={() => router.back()}>
        <AppIcon name="back" size={16} color={Colors.primary} />
        <Text style={styles.backBtnText}>{t('common.back')}</Text>
      </TouchableOpacity>
      <Text style={styles.title}>{t('language.title')}</Text>
      <Text style={styles.subtitle}>{t('language.subtitle')}</Text>

      <View style={styles.card}>
        {options.map((option, index) => {
          const active = option.value === selected;
          return (
            <TouchableOpacity
              key={option.value}
              style={[styles.optionRow, index < options.length - 1 && styles.optionBorder, active && styles.optionRowActive]}
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
        <Text style={styles.saveBtnText}>{saving ? t('language.saving') : t('language.save')}</Text>
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
  backBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    alignSelf: 'flex-start',
    paddingVertical: 4,
  },
  backBtnText: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '700',
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
