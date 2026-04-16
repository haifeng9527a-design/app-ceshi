/**
 * TransferModal
 *
 * Drop-in dialog for USDT transfers between the spot ("main") and futures
 * accounts. Extracted from app/(tabs)/portfolio.tsx so the spot trading page
 * can reuse the same UX without re-implementing balance fetch / direction
 * swap / percent quick-fill / summary & risk card.
 *
 * Data flow:
 *   - Mounts hidden; on visible → getAssetsOverview() fetches fresh balances.
 *   - transferAssets({ from, to, amount }) on confirm.
 *   - onSuccess(amount, direction) is called after a successful transfer so
 *     the parent can refresh its own state (e.g. spot.getAccount, portfolio
 *     overview).
 *   - Errors surface through the shared app dialog; callers can override by passing
 *     onError.
 */
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Modal,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { useTranslation } from 'react-i18next';

import AppIcon from '../ui/AppIcon';
import {
  type AssetOverviewAccount,
  type AssetsOverviewResponse,
  getAssetsOverview,
  transferAssets,
} from '../../services/api/assetsApi';
import { Colors, Shadows } from '../../theme/colors';
import { showAlert } from '../../services/utils/dialog';

export type TransferDirection = 'spot_to_futures' | 'futures_to_spot';

export interface TransferModalProps {
  visible: boolean;
  onClose: () => void;
  /** Fired after a successful transfer. Receives the confirmed amount and direction. */
  onSuccess?: (amount: number, direction: TransferDirection) => void | Promise<void>;
  /** Optional custom error surfacer. Defaults to the shared app dialog. */
  onError?: (title: string, message: string) => void;
  /** Initial direction when opening. Defaults to spot_to_futures. */
  defaultDirection?: TransferDirection;
}

function formatUsd(value?: number) {
  const amount = Number.isFinite(value) ? Number(value) : 0;
  return amount.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function accountDisplayLabel(
  accountType: string,
  fallback: string,
  t: (key: string) => string,
) {
  const keyMap: Record<string, string> = {
    main: 'assets.distributionMain',
    spot: 'assets.distributionMain',
    futures: 'assets.distributionFutures',
  };
  return keyMap[accountType] ? t(keyMap[accountType]) : fallback;
}

export function TransferModal({
  visible,
  onClose,
  onSuccess,
  onError,
  defaultDirection = 'spot_to_futures',
}: TransferModalProps) {
  const { t } = useTranslation();

  const [overview, setOverview] = useState<AssetsOverviewResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [direction, setDirection] = useState<TransferDirection>(defaultDirection);
  const [amount, setAmount] = useState('');
  const [transferring, setTransferring] = useState(false);

  const showError = useCallback(
    (title: string, message: string) => {
      if (onError) onError(title, message);
      else showAlert(message, title, 'danger');
    },
    [onError],
  );

  // Refresh balances on open; reset inputs on close.
  useEffect(() => {
    if (!visible) {
      setAmount('');
      setTransferring(false);
      return;
    }
    setDirection(defaultDirection);
    let cancelled = false;
    setLoading(true);
    (async () => {
      try {
        const data = await getAssetsOverview();
        if (!cancelled) setOverview(data);
      } catch (e) {
        if (!cancelled) {
          setOverview(null);
          showError(
            t('assets.transferFailedTitle'),
            t('assets.transferFailedBody'),
          );
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [visible, defaultDirection, showError, t]);

  const accounts: AssetOverviewAccount[] = overview?.accounts || [];
  const spotAccount = useMemo(
    () => accounts.find((a) => a.account_type === 'spot' || a.account_type === 'main'),
    [accounts],
  );
  const futuresAccount = useMemo(
    () => accounts.find((a) => a.account_type === 'futures'),
    [accounts],
  );

  const sourceAccount = direction === 'spot_to_futures' ? spotAccount : futuresAccount;
  const targetAccount = direction === 'spot_to_futures' ? futuresAccount : spotAccount;
  const sourceAvailable = sourceAccount?.available || 0;
  const targetAvailable = targetAccount?.available || 0;

  const parsedAmount = Number.parseFloat(amount || '0');
  const availableAfter = Math.max(
    sourceAvailable - (Number.isFinite(parsedAmount) ? parsedAmount : 0),
    0,
  );
  const canSubmit =
    Number.isFinite(parsedAmount) &&
    parsedAmount > 0 &&
    parsedAmount <= sourceAvailable &&
    !transferring &&
    !loading;

  const handleSwap = useCallback(() => {
    setDirection((d) => (d === 'spot_to_futures' ? 'futures_to_spot' : 'spot_to_futures'));
  }, []);

  const handleSubmit = useCallback(async () => {
    const amt = Number.parseFloat(amount || '0');
    if (!Number.isFinite(amt) || amt <= 0) {
      showError(t('assets.transferFailedTitle'), t('assets.transferInvalidAmount'));
      return;
    }
    if (amt > sourceAvailable) {
      showError(t('assets.transferFailedTitle'), t('assets.transferExceedsAvailable'));
      return;
    }
    setTransferring(true);
    try {
      await transferAssets({
        from_account: direction === 'spot_to_futures' ? 'spot' : 'futures',
        to_account: direction === 'spot_to_futures' ? 'futures' : 'spot',
        amount: amt,
      });
      setAmount('');
      await onSuccess?.(amt, direction);
      onClose();
    } catch (e: any) {
      showError(
        t('assets.transferFailedTitle'),
        e?.response?.data?.error || e?.message || t('assets.transferFailedBody'),
      );
    } finally {
      setTransferring(false);
    }
  }, [amount, direction, onClose, onSuccess, showError, sourceAvailable, t]);

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <View style={styles.modalBackdrop}>
        <View style={styles.modalCard}>
          <View style={styles.modalHeader}>
            <View style={{ flex: 1 }}>
              <Text style={styles.modalTitle}>{t('assets.transferModalTitle')}</Text>
              <Text style={styles.modalSubtitle}>{t('assets.transferModalSubtitle')}</Text>
            </View>
            <TouchableOpacity style={styles.modalClose} activeOpacity={0.8} onPress={onClose}>
              <AppIcon name="close" size={16} color={Colors.textSecondary} />
            </TouchableOpacity>
          </View>

          <View style={styles.transferHeroCard}>
            <View style={styles.transferHeroTop}>
              <Text style={styles.metricLabel}>{t('assets.transferAvailableTitle')}</Text>
              <View style={styles.withdrawAssetPill}>
                <Text style={styles.withdrawAssetPillText}>USDT</Text>
              </View>
            </View>
            {loading ? (
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                <ActivityIndicator size="small" color={Colors.primary} />
                <Text style={styles.transferHeroHint}>{t('common.loading')}</Text>
              </View>
            ) : (
              <Text style={styles.transferHeroValue}>{formatUsd(sourceAvailable)} USDT</Text>
            )}
            <Text style={styles.transferHeroHint}>
              {direction === 'spot_to_futures'
                ? t('assets.transferMainToFutures')
                : t('assets.transferFuturesToMain')}
            </Text>
          </View>

          <View style={styles.transferRouteSection}>
            <View style={[styles.transferRouteCard, styles.transferRouteCardActive]}>
              <View style={styles.transferRouteHead}>
                <Text style={styles.transferRouteLabel}>{t('assets.transferFromLabel')}</Text>
                <View style={[styles.transferRoutePill, styles.transferRoutePillActive]}>
                  <Text style={[styles.transferRoutePillText, styles.transferRoutePillTextActive]}>
                    {t('assets.transferFromLabel')}
                  </Text>
                </View>
              </View>
              <Text style={styles.transferRouteValue}>
                {accountDisplayLabel(
                  sourceAccount?.account_type || '',
                  sourceAccount?.display_name || '',
                  t,
                )}
              </Text>
              <Text style={styles.transferRouteMeta}>
                {t('assets.transferAvailableLabel')}: {formatUsd(sourceAvailable)} USDT
              </Text>
            </View>
            <TouchableOpacity
              style={styles.transferSwapButton}
              activeOpacity={0.85}
              onPress={handleSwap}
            >
              <Text style={styles.transferSwapButtonText}>⇅</Text>
            </TouchableOpacity>
            <View style={styles.transferRouteCard}>
              <View style={styles.transferRouteHead}>
                <Text style={styles.transferRouteLabel}>{t('assets.transferToLabel')}</Text>
                <View style={styles.transferRoutePill}>
                  <Text style={styles.transferRoutePillText}>{t('assets.transferToLabel')}</Text>
                </View>
              </View>
              <Text style={styles.transferRouteValue}>
                {accountDisplayLabel(
                  targetAccount?.account_type || '',
                  targetAccount?.display_name || '',
                  t,
                )}
              </Text>
              <Text style={styles.transferRouteMeta}>
                {t('assets.transferAvailableLabel')}: {formatUsd(targetAvailable)} USDT
              </Text>
            </View>
          </View>

          <View style={styles.transferAmountSection}>
            <View style={styles.withdrawAmountHead}>
              <Text style={styles.inputLabel}>{t('assets.transferAmountLabel')}</Text>
              <TouchableOpacity
                style={styles.withdrawMaxBtn}
                activeOpacity={0.85}
                onPress={() =>
                  setAmount(
                    sourceAvailable > 0 ? String(Number(sourceAvailable.toFixed(8))) : '',
                  )
                }
              >
                <Text style={styles.withdrawMaxBtnText}>{t('assets.transferMaxAction')}</Text>
              </TouchableOpacity>
            </View>
            <View style={styles.withdrawAmountCard}>
              <TextInput
                value={amount}
                onChangeText={setAmount}
                keyboardType="decimal-pad"
                placeholder={t('assets.transferAmountPlaceholder')}
                placeholderTextColor={Colors.textMuted}
                style={styles.withdrawAmountInput}
              />
              <Text style={styles.withdrawAmountSuffix}>USDT</Text>
            </View>
            <View style={styles.withdrawPercentRow}>
              {[0.25, 0.5, 1].map((ratio) => (
                <TouchableOpacity
                  key={ratio}
                  style={styles.withdrawPercentChip}
                  activeOpacity={0.85}
                  onPress={() =>
                    setAmount(
                      sourceAvailable > 0
                        ? String(Number((sourceAvailable * ratio).toFixed(8)))
                        : '',
                    )
                  }
                >
                  <Text style={styles.withdrawPercentChipText}>
                    {ratio === 1 ? '100%' : `${ratio * 100}%`}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>

          <View style={styles.withdrawSummaryCard}>
            <Text style={styles.withdrawSectionTitle}>{t('assets.transferSummaryTitle')}</Text>
            <View style={styles.withdrawSummaryRow}>
              <Text style={styles.withdrawSummaryLabel}>{t('assets.transferSummaryReceive')}</Text>
              <Text style={styles.withdrawSummaryValue}>
                {formatUsd(Math.max(Number.isFinite(parsedAmount) ? parsedAmount : 0, 0))} USDT
              </Text>
            </View>
            <View style={styles.withdrawSummaryRow}>
              <Text style={styles.withdrawSummaryLabel}>{t('assets.transferFromLabel')}</Text>
              <Text style={styles.withdrawSummaryValue}>
                {accountDisplayLabel(
                  sourceAccount?.account_type || '',
                  sourceAccount?.display_name || '',
                  t,
                )}
              </Text>
            </View>
            <View style={styles.withdrawSummaryRow}>
              <Text style={styles.withdrawSummaryLabel}>{t('assets.transferToLabel')}</Text>
              <Text style={styles.withdrawSummaryValue}>
                {accountDisplayLabel(
                  targetAccount?.account_type || '',
                  targetAccount?.display_name || '',
                  t,
                )}
              </Text>
            </View>
            <View style={styles.withdrawSummaryRow}>
              <Text style={styles.withdrawSummaryLabel}>
                {t('assets.transferSummaryAvailableAfter')}
              </Text>
              <Text style={styles.withdrawSummaryValue}>{formatUsd(availableAfter)} USDT</Text>
            </View>
            <View style={styles.withdrawSummaryRow}>
              <Text style={styles.withdrawSummaryLabel}>{t('assets.transferSummaryRoute')}</Text>
              <Text style={styles.withdrawSummaryValue}>
                {t('assets.transferSummaryInstant')}
              </Text>
            </View>
          </View>

          <View style={styles.withdrawRiskCard}>
            <View style={styles.withdrawRiskTitleRow}>
              <AppIcon name="shield" size={16} color={Colors.primary} />
              <Text style={styles.withdrawRiskTitle}>{t('assets.transferInfoTitle')}</Text>
            </View>
            <Text style={styles.withdrawRiskBody}>{t('assets.transferInfoBody')}</Text>
          </View>

          <View style={styles.modalActions}>
            <TouchableOpacity
              style={styles.modalSecondaryBtn}
              activeOpacity={0.85}
              onPress={onClose}
            >
              <Text style={styles.modalSecondaryBtnText}>{t('common.cancel')}</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.modalPrimaryBtn, !canSubmit && styles.modalPrimaryBtnDisabled]}
              activeOpacity={0.85}
              onPress={() => void handleSubmit()}
              disabled={!canSubmit}
            >
              <Text style={styles.modalPrimaryBtnText}>
                {transferring
                  ? t('assets.transferSubmitting')
                  : t('assets.transferConfirmAction')}
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

export default TransferModal;

const styles = StyleSheet.create({
  modalBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(5,6,13,0.7)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  modalCard: {
    width: '100%',
    maxWidth: 520,
    backgroundColor: Colors.surface,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 20,
    gap: 18,
    ...Shadows.card,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
    alignItems: 'flex-start',
  },
  modalTitle: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '800',
  },
  modalSubtitle: {
    marginTop: 6,
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 19,
  },
  modalClose: {
    width: 34,
    height: 34,
    borderRadius: 17,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.surfaceAlt,
  },

  metricLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },

  transferHeroCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 18,
    gap: 8,
  },
  transferHeroTop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 12,
  },
  transferHeroValue: {
    color: Colors.textActive,
    fontSize: 28,
    fontWeight: '900',
    letterSpacing: -0.8,
  },
  transferHeroHint: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },

  transferRouteSection: { gap: 10 },
  transferRouteCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 14,
    gap: 6,
  },
  transferRouteCardActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  transferRouteHead: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  transferRouteLabel: {
    color: Colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  transferRoutePill: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.background,
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  transferRoutePillActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primary + '18',
  },
  transferRoutePillText: {
    color: Colors.textSecondary,
    fontSize: 10,
    fontWeight: '800',
  },
  transferRoutePillTextActive: { color: Colors.primary },
  transferRouteValue: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '800',
  },
  transferRouteMeta: {
    color: Colors.textSecondary,
    fontSize: 12,
  },
  transferSwapButton: {
    alignSelf: 'center',
    width: 40,
    height: 40,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.background,
    alignItems: 'center',
    justifyContent: 'center',
  },
  transferSwapButtonText: {
    color: Colors.primary,
    fontSize: 18,
    fontWeight: '800',
  },

  transferAmountSection: { gap: 12 },
  inputLabel: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
  },
  withdrawAmountHead: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  withdrawMaxBtn: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 12,
    paddingVertical: 7,
  },
  withdrawMaxBtnText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '800',
  },
  withdrawAmountCard: {
    minHeight: 64,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 14,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  withdrawAmountInput: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 24,
    fontWeight: '800',
    paddingVertical: 0,
  },
  withdrawAmountSuffix: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '800',
  },
  withdrawAssetPill: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  withdrawAssetPillText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '800',
  },
  withdrawPercentRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  withdrawPercentChip: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  withdrawPercentChipText: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '800',
  },

  withdrawSummaryCard: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 12,
  },
  withdrawSummaryRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  withdrawSummaryLabel: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '700',
    flexShrink: 0,
  },
  withdrawSummaryValue: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '800',
    textAlign: 'right',
    flexShrink: 1,
  },
  withdrawSectionTitle: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '800',
  },

  withdrawRiskCard: {
    backgroundColor: Colors.warning + '12',
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.warning + '33',
    padding: 16,
    gap: 10,
  },
  withdrawRiskTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  withdrawRiskTitle: {
    color: Colors.primaryLight,
    fontSize: 13,
    fontWeight: '800',
  },
  withdrawRiskBody: {
    color: Colors.textSecondary,
    fontSize: 12,
    lineHeight: 18,
  },

  modalActions: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    gap: 10,
    flexWrap: 'wrap',
  },
  modalSecondaryBtn: {
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.border,
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 16,
    paddingVertical: 11,
  },
  modalSecondaryBtnText: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '800',
  },
  modalPrimaryBtn: {
    borderRadius: 14,
    backgroundColor: Colors.primary,
    borderWidth: 1,
    borderColor: Colors.primary,
    paddingHorizontal: 16,
    paddingVertical: 11,
  },
  modalPrimaryBtnDisabled: { opacity: 0.45 },
  modalPrimaryBtnText: {
    color: Colors.background,
    fontSize: 13,
    fontWeight: '800',
  },
});
