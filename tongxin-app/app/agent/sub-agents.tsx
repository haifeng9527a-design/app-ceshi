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

import { Colors, Shadows } from '../../theme/colors';
import AppIcon from '../../components/ui/AppIcon';
import { SubAgentRow, agentApi } from '../../services/api/referralApi';

function fmtUsdt(n: number, digits = 2): string {
  if (!Number.isFinite(n)) return '0.00';
  return n.toLocaleString('en-US', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}

export default function SubAgentsScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { width } = useWindowDimensions();
  const isDesktop = width > 900;

  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [agents, setAgents] = useState<SubAgentRow[]>([]);

  // Rate modal
  const [selectedAgent, setSelectedAgent] = useState<SubAgentRow | null>(null);
  const [rateInput, setRateInput] = useState('');
  const [saving, setSaving] = useState(false);

  const loadAgents = useCallback(async () => {
    setLoading(true);
    try {
      const data = await agentApi.listSubAgents();
      setAgents(Array.isArray(data) ? data : []);
    } catch {
      // silent
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadAgents();
  }, [loadAgents]);

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    await loadAgents();
    setRefreshing(false);
  }, [loadAgents]);

  const openRateModal = useCallback((agent: SubAgentRow) => {
    setSelectedAgent(agent);
    setRateInput(((agent.my_rebate_rate ?? 0) * 100).toFixed(1));
  }, []);

  const handleSaveRate = useCallback(async () => {
    if (!selectedAgent) return;
    const pct = parseFloat(rateInput);
    if (!Number.isFinite(pct) || pct < 0 || pct > 100) {
      Alert.alert(t('agent.rateInvalidTitle'), t('agent.rateInvalidBody'));
      return;
    }
    setSaving(true);
    try {
      const rate = pct / 100;
      await agentApi.setSubAgentRate(selectedAgent.uid, rate);
      setAgents((prev) =>
        prev.map((a) => (a.uid === selectedAgent.uid ? { ...a, my_rebate_rate: rate } : a)),
      );
      setSelectedAgent(null);
      Alert.alert(t('agent.rateSavedTitle'), t('agent.rateSavedBody'));
    } catch (e: any) {
      Alert.alert(t('agent.rateFailedTitle'), e?.message || t('agent.rateFailedBody'));
    } finally {
      setSaving(false);
    }
  }, [selectedAgent, rateInput, t]);

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
          <Text style={[styles.pageTitle, { flex: 1 }]}>{t('agent.subAgentsTitle')}</Text>
        </View>

        {loading && agents.length === 0 ? (
          <View style={styles.centerBlock}>
            <ActivityIndicator size="large" color={Colors.primary} />
          </View>
        ) : agents.length === 0 ? (
          <View style={styles.centerBlock}>
            <AppIcon name="users" size={28} color={Colors.textMuted} />
            <Text style={styles.emptyTitle}>{t('agent.noSubAgents')}</Text>
            <Text style={styles.emptyDesc}>{t('agent.noSubAgentsDesc')}</Text>
          </View>
        ) : (
          agents.map((agent) => {
            const initial = (agent.display_name || agent.uid || '?').charAt(0).toUpperCase();
            const ratePct = ((agent.my_rebate_rate ?? 0) * 100).toFixed(1);
            return (
              <TouchableOpacity
                key={agent.uid}
                style={styles.agentCard}
                activeOpacity={0.7}
                onPress={() => openRateModal(agent)}
              >
                {/* Avatar placeholder */}
                <View style={styles.avatar}>
                  <Text style={styles.avatarText}>{initial}</Text>
                </View>

                <View style={{ flex: 1 }}>
                  <Text style={styles.agentName}>
                    {agent.display_name || agent.uid}
                  </Text>
                  <Text style={styles.agentMeta}>
                    {t('agent.subAgentRate')}: {ratePct}%
                  </Text>
                  <Text style={styles.agentMeta}>
                    {t('agent.subAgentVolume')}: {fmtUsdt(agent.this_month_volume)} USDT
                  </Text>
                  <Text style={styles.agentMeta}>
                    {t('agent.subAgentContrib')}: {fmtUsdt(agent.contrib_to_parent)} USDT
                  </Text>
                </View>

                <AppIcon name="settings" size={18} color={Colors.textMuted} />
              </TouchableOpacity>
            );
          })
        )}

        <View style={{ height: 32 }} />
      </ScrollView>

      {/* Rate adjustment modal */}
      <Modal visible={!!selectedAgent} transparent animationType="fade">
        <View style={styles.modalOverlay}>
          <View style={[styles.modalContent, isDesktop && { maxWidth: 400 }]}>
            <Text style={styles.modalTitle}>{t('agent.adjustRateTitle')}</Text>
            <Text style={styles.modalDesc}>
              {t('agent.adjustRateDesc', { name: selectedAgent?.display_name || selectedAgent?.uid })}
            </Text>

            <View style={styles.rateInputRow}>
              <TextInput
                style={styles.rateInputField}
                value={rateInput}
                onChangeText={setRateInput}
                keyboardType={Platform.OS === 'web' ? 'default' : 'decimal-pad'}
                placeholder="0"
                placeholderTextColor={Colors.textMuted}
              />
              <Text style={styles.ratePctSign}>%</Text>
            </View>

            <Text style={styles.rateHint}>{t('agent.adjustRateHint')}</Text>

            <View style={styles.modalBtnRow}>
              <TouchableOpacity
                style={styles.cancelBtn}
                activeOpacity={0.7}
                onPress={() => setSelectedAgent(null)}
              >
                <Text style={styles.cancelBtnText}>{t('common.cancel')}</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[styles.confirmBtn, saving && { opacity: 0.5 }]}
                activeOpacity={0.85}
                onPress={handleSaveRate}
                disabled={saving}
              >
                {saving ? (
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

  // Agent card
  agentCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    ...Shadows.card,
  },
  avatar: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: Colors.primaryDim,
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarText: {
    color: Colors.primary,
    fontSize: 18,
    fontWeight: '800',
  },
  agentName: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
  },
  agentMeta: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 2,
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
  modalDesc: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 20,
  },
  rateInputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.inputBg,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    borderRadius: 10,
    paddingHorizontal: 14,
    height: 44,
  },
  rateInputField: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 18,
    fontWeight: '700',
    paddingVertical: 0,
  },
  ratePctSign: {
    color: Colors.textMuted,
    fontSize: 16,
    fontWeight: '700',
    marginLeft: 4,
  },
  rateHint: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
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
