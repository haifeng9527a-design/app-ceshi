import { ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors } from '../theme/colors';
import AppIcon from '../components/ui/AppIcon';

export default function HelpScreen() {
  const router = useRouter();
  const { t } = useTranslation();
  const faqs = [
    {
      q: t('help.faqMessageQuestion'),
      a: t('help.faqMessageAnswer'),
    },
    {
      q: t('help.faqCallQuestion'),
      a: t('help.faqCallAnswer'),
    },
    {
      q: t('help.faqCopyQuestion'),
      a: t('help.faqCopyAnswer'),
    },
    {
      q: t('help.faqGroupQuestion'),
      a: t('help.faqGroupAnswer'),
    },
  ];

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
      <TouchableOpacity style={styles.backBtn} activeOpacity={0.8} onPress={() => router.back()}>
        <AppIcon name="back" size={16} color={Colors.primary} />
        <Text style={styles.backBtnText}>{t('common.back')}</Text>
      </TouchableOpacity>
      <Text style={styles.title}>{t('help.title')}</Text>
      <Text style={styles.subtitle}>{t('help.subtitle')}</Text>

      {faqs.map((item) => (
        <View key={item.q} style={styles.card}>
          <Text style={styles.question}>{item.q}</Text>
          <Text style={styles.answer}>{item.a}</Text>
        </View>
      ))}
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
    gap: 16,
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
    marginTop: 12,
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
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
    padding: 18,
    gap: 8,
  },
  question: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
  },
  answer: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 20,
  },
});
