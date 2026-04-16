import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
  useWindowDimensions,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';

import { Colors, Shadows } from '../../theme/colors';
import AppIcon from '../../components/ui/AppIcon';
import { useAuthStore } from '../../services/store/authStore';
import { AgentApplication, agentApi } from '../../services/api/referralApi';

export default function AgentApplyScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { user } = useAuthStore();
  const { width } = useWindowDimensions();
  const isDesktop = width > 900;

  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [existingApp, setExistingApp] = useState<AgentApplication | null>(null);

  // Form fields
  const [channelDesc, setChannelDesc] = useState('');
  const [audienceSize, setAudienceSize] = useState('');
  const [contactInfo, setContactInfo] = useState('');

  const checkExisting = useCallback(async () => {
    setLoading(true);
    try {
      const app = await agentApi.getApplicationStatus();
      if (app?.id) {
        setExistingApp(app);
      }
    } catch {
      // No existing application — show the form
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    checkExisting();
  }, [checkExisting]);

  const handleSubmit = useCallback(async () => {
    if (!channelDesc.trim()) {
      Alert.alert(t('agent.applyHintTitle'), t('agent.applyChannelRequired'));
      return;
    }
    setSubmitting(true);
    try {
      await agentApi.apply({
        channel_description: channelDesc.trim(),
        audience_size: audienceSize.trim(),
        contact_info: { text: contactInfo.trim() },
      });
      Alert.alert(t('agent.applySuccessTitle'), t('agent.applySuccessBody'));
      router.back();
    } catch (e: any) {
      Alert.alert(t('agent.applyFailedTitle'), e?.message || t('agent.applyFailedBody'));
    } finally {
      setSubmitting(false);
    }
  }, [channelDesc, audienceSize, contactInfo, t, router]);

  if (!user) {
    return (
      <View style={styles.center}>
        <Text style={styles.emptyTitle}>{t('common.loginRequired') || 'Login required'}</Text>
        <TouchableOpacity style={styles.primaryBtn} onPress={() => router.push('/(auth)/login' as any)}>
          <Text style={styles.primaryBtnText}>{t('auth.loginOrRegister')}</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

  // ── Pending application status ──
  if (existingApp && existingApp.status === 'pending') {
    return (
      <ScrollView
        style={styles.container}
        contentContainerStyle={[
          styles.scrollContent,
          isDesktop && { maxWidth: 600, alignSelf: 'center' as const, width: '100%' },
        ]}
      >
        <View style={styles.headerRow}>
          <TouchableOpacity style={styles.backBtn} onPress={() => router.back()} activeOpacity={0.7}>
            <AppIcon name="back" size={20} color={Colors.textActive} />
          </TouchableOpacity>
          <Text style={styles.pageTitle}>{t('agent.applyTitle')}</Text>
        </View>

        <View style={styles.statusSection}>
          <AppIcon name="clock" size={32} color={Colors.warning} />
          <Text style={styles.statusTitle}>{t('agent.pendingTitle')}</Text>
          <Text style={styles.statusDesc}>{t('agent.pendingDesc')}</Text>
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('agent.applyChannelLabel')}</Text>
          <Text style={styles.statusDetail}>{existingApp.channel_description}</Text>
          <Text style={styles.sectionTitle}>{t('agent.applyAudienceLabel')}</Text>
          <Text style={styles.statusDetail}>{existingApp.audience_size || '-'}</Text>
        </View>
      </ScrollView>
    );
  }

  // ── Rejected application ──
  if (existingApp && existingApp.status === 'rejected') {
    return (
      <ScrollView
        style={styles.container}
        contentContainerStyle={[
          styles.scrollContent,
          isDesktop && { maxWidth: 600, alignSelf: 'center' as const, width: '100%' },
        ]}
      >
        <View style={styles.headerRow}>
          <TouchableOpacity style={styles.backBtn} onPress={() => router.back()} activeOpacity={0.7}>
            <AppIcon name="back" size={20} color={Colors.textActive} />
          </TouchableOpacity>
          <Text style={styles.pageTitle}>{t('agent.applyTitle')}</Text>
        </View>

        <View style={styles.statusSection}>
          <AppIcon name="close" size={32} color={Colors.down} />
          <Text style={styles.statusTitle}>{t('agent.rejectedTitle')}</Text>
          <Text style={styles.statusDesc}>{t('agent.rejectedDesc')}</Text>
        </View>

        <TouchableOpacity
          style={styles.primaryBtn}
          activeOpacity={0.85}
          onPress={() => setExistingApp(null)}
        >
          <Text style={styles.primaryBtnText}>{t('agent.reapplyAction')}</Text>
        </TouchableOpacity>
      </ScrollView>
    );
  }

  // ── Application form ──
  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={[
        styles.scrollContent,
        isDesktop && { maxWidth: 600, alignSelf: 'center' as const, width: '100%' },
      ]}
      keyboardShouldPersistTaps="handled"
    >
      {/* Header */}
      <View style={styles.headerRow}>
        <TouchableOpacity style={styles.backBtn} onPress={() => router.back()} activeOpacity={0.7}>
          <AppIcon name="back" size={20} color={Colors.textActive} />
        </TouchableOpacity>
        <View style={{ flex: 1 }}>
          <Text style={styles.pageTitle}>{t('agent.applyTitle')}</Text>
          <Text style={styles.pageSub}>{t('agent.applySubtitle')}</Text>
        </View>
      </View>

      {/* Channel description */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('agent.applyChannelLabel')}</Text>
        <TextInput
          style={[styles.input, styles.multilineInput]}
          value={channelDesc}
          onChangeText={setChannelDesc}
          placeholder={t('agent.applyChannelPlaceholder')}
          placeholderTextColor={Colors.textMuted}
          multiline
          numberOfLines={3}
          textAlignVertical="top"
        />
      </View>

      {/* Audience size */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('agent.applyAudienceLabel')}</Text>
        <TextInput
          style={styles.input}
          value={audienceSize}
          onChangeText={setAudienceSize}
          placeholder={t('agent.applyAudiencePlaceholder')}
          placeholderTextColor={Colors.textMuted}
        />
      </View>

      {/* Contact info */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('agent.applyContactLabel')}</Text>
        <TextInput
          style={styles.input}
          value={contactInfo}
          onChangeText={setContactInfo}
          placeholder="Telegram / WeChat / Email"
          placeholderTextColor={Colors.textMuted}
        />
      </View>

      {/* Submit */}
      <TouchableOpacity
        style={[styles.submitBtn, submitting && styles.submitBtnDisabled]}
        activeOpacity={0.85}
        onPress={handleSubmit}
        disabled={submitting}
      >
        {submitting ? (
          <ActivityIndicator size="small" color={Colors.textOnPrimary} />
        ) : (
          <Text style={styles.submitBtnText}>{t('agent.applySubmit')}</Text>
        )}
      </TouchableOpacity>

      <View style={{ height: 32 }} />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  scrollContent: {
    padding: 20,
    paddingTop: Platform.OS === 'ios' ? 60 : 24,
    paddingBottom: 40,
    gap: 20,
  },
  center: {
    flex: 1,
    backgroundColor: Colors.background,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    gap: 12,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginBottom: 4,
  },
  backBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pageTitle: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '800',
  },
  pageSub: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 4,
    lineHeight: 18,
  },
  section: {
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 10,
    ...Shadows.card,
  },
  sectionTitle: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
  },
  input: {
    backgroundColor: Colors.inputBg,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 10,
    color: Colors.textActive,
    fontSize: 14,
  },
  multilineInput: {
    minHeight: 80,
    textAlignVertical: 'top',
  },
  submitBtn: {
    backgroundColor: Colors.primary,
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  submitBtnDisabled: {
    opacity: 0.5,
  },
  submitBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 16,
    fontWeight: '800',
  },

  // Status
  statusSection: {
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 24,
    alignItems: 'center',
    gap: 10,
    ...Shadows.card,
  },
  statusTitle: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '800',
    marginTop: 4,
  },
  statusDesc: {
    color: Colors.textMuted,
    fontSize: 13,
    textAlign: 'center',
    lineHeight: 20,
  },
  statusDetail: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 20,
  },

  emptyTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
    marginTop: 4,
  },
  primaryBtn: {
    paddingHorizontal: 18,
    paddingVertical: 10,
    borderRadius: 10,
    backgroundColor: Colors.primary,
    marginTop: 6,
    alignSelf: 'center',
  },
  primaryBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 14,
    fontWeight: '800',
  },
});
