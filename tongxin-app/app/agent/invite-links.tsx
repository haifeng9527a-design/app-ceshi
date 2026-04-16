import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Modal,
  Platform,
  RefreshControl,
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
import * as Clipboard from 'expo-clipboard';

import { Colors, Shadows } from '../../theme/colors';
import AppIcon from '../../components/ui/AppIcon';
import { InviteLink, agentApi } from '../../services/api/referralApi';

export default function InviteLinksScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { width } = useWindowDimensions();
  const isDesktop = width > 900;

  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [links, setLinks] = useState<InviteLink[]>([]);

  // Create modal
  const [showCreate, setShowCreate] = useState(false);
  const [newCode, setNewCode] = useState('');
  const [newName, setNewName] = useState('');
  const [creating, setCreating] = useState(false);

  const loadLinks = useCallback(async () => {
    setLoading(true);
    try {
      const data = await agentApi.listInviteLinks();
      setLinks(Array.isArray(data) ? data : []);
    } catch {
      // silent
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadLinks();
  }, [loadLinks]);

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadLinks();
    setRefreshing(false);
  }, [loadLinks]);

  const handleCopy = useCallback(
    async (link: InviteLink) => {
      const url = link.landing_page || link.code;
      try {
        await Clipboard.setStringAsync(url);
        Alert.alert(t('common.copied'), url);
      } catch {
        Alert.alert(t('common.copy'), url);
      }
    },
    [t],
  );

  const handleDisable = useCallback(
    async (link: InviteLink) => {
      Alert.alert(t('agent.disableLinkTitle'), t('agent.disableLinkBody', { code: link.code }), [
        { text: t('common.cancel'), style: 'cancel' },
        {
          text: t('common.confirm'),
          style: 'destructive',
          onPress: async () => {
            try {
              await agentApi.disableInviteLink(link.id);
              setLinks((prev) => prev.map((l) => (l.id === link.id ? { ...l, is_active: false } : l)));
            } catch (e: any) {
              Alert.alert(t('agent.disableFailedTitle'), e?.message || t('agent.disableFailedBody'));
            }
          },
        },
      ]);
    },
    [t],
  );

  const handleCreate = useCallback(async () => {
    if (!newCode.trim()) {
      Alert.alert(t('agent.createLinkHintTitle'), t('agent.createLinkCodeRequired'));
      return;
    }
    setCreating(true);
    try {
      const created = await agentApi.createInviteLink({ code: newCode.trim(), name: newName.trim() });
      setLinks((prev) => [created, ...prev]);
      setShowCreate(false);
      setNewCode('');
      setNewName('');
    } catch (e: any) {
      Alert.alert(t('agent.createLinkFailedTitle'), e?.message || t('agent.createLinkFailedBody'));
    } finally {
      setCreating(false);
    }
  }, [newCode, newName, t]);

  return (
    <View style={styles.container}>
      <ScrollView
        contentContainerStyle={[
          styles.scrollContent,
          isDesktop && { maxWidth: 700, alignSelf: 'center' as const, width: '100%' },
        ]}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={handleRefresh} tintColor={Colors.primary} />
        }
      >
        {/* Header */}
        <View style={styles.headerRow}>
          <TouchableOpacity style={styles.backBtn} onPress={() => router.back()} activeOpacity={0.7}>
            <AppIcon name="back" size={20} color={Colors.textActive} />
          </TouchableOpacity>
          <Text style={[styles.pageTitle, { flex: 1 }]}>{t('agent.inviteLinksTitle')}</Text>
          <TouchableOpacity
            style={styles.headerAction}
            activeOpacity={0.7}
            onPress={() => setShowCreate(true)}
          >
            <Text style={styles.headerActionText}>+ {t('agent.createLink')}</Text>
          </TouchableOpacity>
        </View>

        {loading && links.length === 0 ? (
          <View style={styles.centerBlock}>
            <ActivityIndicator size="large" color={Colors.primary} />
          </View>
        ) : links.length === 0 ? (
          <View style={styles.centerBlock}>
            <AppIcon name="send" size={28} color={Colors.textMuted} />
            <Text style={styles.emptyTitle}>{t('agent.noLinks')}</Text>
            <Text style={styles.emptyDesc}>{t('agent.noLinksDesc')}</Text>
          </View>
        ) : (
          links.map((link) => (
            <View key={link.id} style={styles.linkCard}>
              <View style={{ flex: 1 }}>
                <View style={styles.linkTopRow}>
                  <Text style={styles.linkCode}>{link.code}</Text>
                  <View
                    style={[
                      styles.statusBadge,
                      { backgroundColor: link.is_active ? Colors.upDim : Colors.downDim },
                    ]}
                  >
                    <Text
                      style={[
                        styles.statusBadgeText,
                        { color: link.is_active ? Colors.up : Colors.down },
                      ]}
                    >
                      {link.is_active ? t('agent.linkActive') : t('agent.linkDisabled')}
                    </Text>
                  </View>
                </View>
                {!!link.name && <Text style={styles.linkName}>{link.name}</Text>}
                <Text style={styles.linkMeta}>
                  {t('agent.linkRegistrations', { count: link.registration_count })}
                </Text>
              </View>

              <View style={styles.linkActions}>
                <TouchableOpacity style={styles.iconBtn} activeOpacity={0.7} onPress={() => handleCopy(link)}>
                  <AppIcon name="paper" size={16} color={Colors.primary} />
                </TouchableOpacity>
                {link.is_active && (
                  <TouchableOpacity
                    style={styles.iconBtn}
                    activeOpacity={0.7}
                    onPress={() => handleDisable(link)}
                  >
                    <AppIcon name="close" size={16} color={Colors.down} />
                  </TouchableOpacity>
                )}
              </View>
            </View>
          ))
        )}

        <View style={{ height: 32 }} />
      </ScrollView>

      {/* Create modal */}
      <Modal visible={showCreate} transparent animationType="fade">
        <View style={styles.modalOverlay}>
          <View style={[styles.modalContent, isDesktop && { maxWidth: 420 }]}>
            <Text style={styles.modalTitle}>{t('agent.createLinkTitle')}</Text>

            <Text style={styles.fieldLabel}>{t('agent.linkCodeLabel')}</Text>
            <TextInput
              style={styles.input}
              value={newCode}
              onChangeText={setNewCode}
              placeholder={t('agent.linkCodePlaceholder')}
              placeholderTextColor={Colors.textMuted}
              autoCapitalize="none"
            />

            <Text style={styles.fieldLabel}>{t('agent.linkNameLabel')}</Text>
            <TextInput
              style={styles.input}
              value={newName}
              onChangeText={setNewName}
              placeholder={t('agent.linkNamePlaceholder')}
              placeholderTextColor={Colors.textMuted}
            />

            <View style={styles.modalBtnRow}>
              <TouchableOpacity
                style={styles.cancelBtn}
                activeOpacity={0.7}
                onPress={() => {
                  setShowCreate(false);
                  setNewCode('');
                  setNewName('');
                }}
              >
                <Text style={styles.cancelBtnText}>{t('common.cancel')}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.confirmBtn, creating && { opacity: 0.5 }]}
                activeOpacity={0.85}
                onPress={handleCreate}
                disabled={creating}
              >
                {creating ? (
                  <ActivityIndicator size="small" color={Colors.textOnPrimary} />
                ) : (
                  <Text style={styles.confirmBtnText}>{t('common.confirm')}</Text>
                )}
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
    </View>
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
    gap: 12,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginBottom: 8,
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
  headerAction: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 10,
    backgroundColor: Colors.primary,
  },
  headerActionText: {
    color: Colors.textOnPrimary,
    fontSize: 13,
    fontWeight: '800',
  },
  centerBlock: {
    alignItems: 'center',
    justifyContent: 'center',
    padding: 40,
    gap: 8,
  },
  emptyTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
  },
  emptyDesc: {
    color: Colors.textMuted,
    fontSize: 12,
    textAlign: 'center',
    lineHeight: 18,
  },

  // Link card
  linkCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 12,
    ...Shadows.card,
  },
  linkTopRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  linkCode: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
    fontFamily: Platform.OS === 'web' ? 'monospace' : undefined,
  },
  statusBadge: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
  },
  statusBadgeText: {
    fontSize: 11,
    fontWeight: '700',
  },
  linkName: {
    color: Colors.textSecondary,
    fontSize: 13,
    marginTop: 4,
  },
  linkMeta: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 4,
  },
  linkActions: {
    flexDirection: 'row',
    gap: 8,
  },
  iconBtn: {
    width: 34,
    height: 34,
    borderRadius: 10,
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },

  // Modal
  modalOverlay: {
    flex: 1,
    backgroundColor: Colors.overlayBg,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  modalContent: {
    width: '100%',
    backgroundColor: Colors.surface,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 20,
    gap: 14,
    ...Shadows.card,
  },
  modalTitle: {
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '800',
  },
  fieldLabel: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '600',
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
  modalBtnRow: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    gap: 10,
    marginTop: 4,
  },
  cancelBtn: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  cancelBtnText: {
    color: Colors.textSecondary,
    fontSize: 14,
    fontWeight: '700',
  },
  confirmBtn: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 10,
    backgroundColor: Colors.primary,
  },
  confirmBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 14,
    fontWeight: '800',
  },
});
