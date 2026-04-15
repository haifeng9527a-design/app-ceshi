import { useState, useEffect } from 'react';
import {
  View,
  Text,
  Modal,
  ScrollView,
  TouchableOpacity,
  TextInput,
  StyleSheet,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { Colors, Sizes } from '../../theme/colors';
import { adjustAllocatedCapital, type FollowTraderRequest, type CopyTrading } from '../../services/api/traderApi';
import { useTradingStore } from '../../services/store/tradingStore';

interface Props {
  visible: boolean;
  onClose: () => void;
  onSubmit: (settings: FollowTraderRequest) => void;
  initialSettings?: CopyTrading;
  traderName?: string;
  traderUid?: string;
  onBucketUpdated?: (ct: CopyTrading) => void;
}

export default function CopySettingsModal({
  visible,
  onClose,
  onSubmit,
  initialSettings,
  traderName,
  traderUid,
  onBucketUpdated,
}: Props) {
  const isEdit = !!initialSettings;
  const wallet = useTradingStore((s) => s.wallet);
  const fetchWallet = useTradingStore((s) => s.fetchWallet);

  // Allocated capital for new follow (required, min 100 USDT)
  const [allocatedCapital, setAllocatedCapital] = useState(
    String(initialSettings?.allocated_capital ?? 1000)
  );
  // Top up / withdraw inputs (only relevant in edit mode)
  const [adjustMode, setAdjustMode] = useState<null | 'topup' | 'withdraw'>(null);
  const [adjustAmount, setAdjustAmount] = useState('');
  const [adjusting, setAdjusting] = useState(false);
  // Local copy of the current bucket (refreshed after top-up / withdraw)
  const [bucket, setBucket] = useState<CopyTrading | undefined>(initialSettings);

  const [copyMode, setCopyMode] = useState<'fixed' | 'ratio'>(
    initialSettings?.copy_mode || 'fixed'
  );
  const [fixedAmount, setFixedAmount] = useState(
    String(initialSettings?.fixed_amount ?? 100)
  );
  const [copyRatio, setCopyRatio] = useState(
    String(initialSettings?.copy_ratio ?? 1.0)
  );
  const [maxPosition, setMaxPosition] = useState(
    String(initialSettings?.max_position ?? 1000)
  );
  const [maxSingleMargin, setMaxSingleMargin] = useState(
    String(initialSettings?.max_single_margin ?? 500)
  );
  const [leverageMode, setLeverageMode] = useState<'trader' | 'custom'>(
    initialSettings?.leverage_mode || 'trader'
  );
  const [customLeverage, setCustomLeverage] = useState(
    String(initialSettings?.custom_leverage ?? 10)
  );
  const [tpSlMode, setTpSlMode] = useState<'trader' | 'custom'>(
    initialSettings?.tp_sl_mode || 'trader'
  );
  const [customTpRatio, setCustomTpRatio] = useState(
    String(initialSettings?.custom_tp_ratio ?? 50)
  );
  const [customSlRatio, setCustomSlRatio] = useState(
    String(initialSettings?.custom_sl_ratio ?? 20)
  );
  const [followDirection, setFollowDirection] = useState<'both' | 'long' | 'short'>(
    initialSettings?.follow_direction || 'both'
  );
  const [submitting, setSubmitting] = useState(false);

  // Reset form when modal opens with new settings
  useEffect(() => {
    if (visible) {
      setAllocatedCapital(String(initialSettings?.allocated_capital ?? 1000));
      setBucket(initialSettings);
      setAdjustMode(null);
      setAdjustAmount('');
      setCopyMode(initialSettings?.copy_mode || 'fixed');
      setFixedAmount(String(initialSettings?.fixed_amount ?? 100));
      setCopyRatio(String(initialSettings?.copy_ratio ?? 1.0));
      setMaxPosition(String(initialSettings?.max_position ?? 1000));
      setMaxSingleMargin(String(initialSettings?.max_single_margin ?? 500));
      setLeverageMode(initialSettings?.leverage_mode || 'trader');
      setCustomLeverage(String(initialSettings?.custom_leverage ?? 10));
      setTpSlMode(initialSettings?.tp_sl_mode || 'trader');
      setCustomTpRatio(String(initialSettings?.custom_tp_ratio ?? 50));
      setCustomSlRatio(String(initialSettings?.custom_sl_ratio ?? 20));
      setFollowDirection(initialSettings?.follow_direction || 'both');
      // Refresh wallet so the user sees current available balance
      fetchWallet();
    }
  }, [visible, initialSettings, fetchWallet]);

  const formatUsd = (n?: number) =>
    typeof n === 'number'
      ? n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
      : '0.00';

  const walletAvailable = wallet ? wallet.balance : 0;

  const handleAdjustCapital = async () => {
    if (!traderUid) return;
    const amt = parseFloat(adjustAmount);
    if (!amt || amt <= 0) {
      Alert.alert('', '请输入有效金额');
      return;
    }
    const delta = adjustMode === 'topup' ? amt : -amt;
    if (adjustMode === 'topup' && amt > walletAvailable) {
      Alert.alert('', `钱包可用余额不足（${formatUsd(walletAvailable)} USDT）`);
      return;
    }
    if (adjustMode === 'withdraw' && bucket && amt > bucket.available_capital) {
      Alert.alert('', `池子可用不足（${formatUsd(bucket.available_capital)} USDT）`);
      return;
    }
    setAdjusting(true);
    try {
      const updated = await adjustAllocatedCapital(traderUid, delta);
      setBucket(updated);
      setAdjustAmount('');
      setAdjustMode(null);
      fetchWallet(); // wallet changed too
      onBucketUpdated?.(updated);
    } catch (e: any) {
      Alert.alert('Error', e.response?.data?.error || e.message);
    } finally {
      setAdjusting(false);
    }
  };

  const handleSubmit = () => {
    // For NEW follow: validate allocated capital
    if (!isEdit) {
      const alloc = parseFloat(allocatedCapital);
      if (!alloc || alloc < 100) {
        Alert.alert('', '分配本金最少 100 USDT');
        return;
      }
      if (alloc > walletAvailable) {
        Alert.alert('', `钱包可用余额不足（${formatUsd(walletAvailable)} USDT）`);
        return;
      }
    }

    setSubmitting(true);
    const settings: FollowTraderRequest = {
      // For new follow this is required; for edit the backend ignores it
      // (capital changes go via PATCH /follow/capital)
      allocated_capital: isEdit
        ? (initialSettings?.allocated_capital ?? 0)
        : parseFloat(allocatedCapital) || 0,
      copy_mode: copyMode,
      max_position: parseFloat(maxPosition) || 1000,
      max_single_margin: parseFloat(maxSingleMargin) || 500,
      leverage_mode: leverageMode,
      tp_sl_mode: tpSlMode,
      follow_direction: followDirection,
    };

    if (copyMode === 'fixed') {
      settings.fixed_amount = parseFloat(fixedAmount) || 100;
    } else {
      settings.copy_ratio = parseFloat(copyRatio) || 1.0;
    }

    if (leverageMode === 'custom') {
      settings.custom_leverage = parseFloat(customLeverage) || 10;
    }

    if (tpSlMode === 'custom') {
      settings.custom_tp_ratio = parseFloat(customTpRatio) || 50;
      settings.custom_sl_ratio = parseFloat(customSlRatio) || 20;
    }

    onSubmit(settings);
    setSubmitting(false);
  };

  const directionOptions: { key: 'both' | 'long' | 'short'; label: string }[] = [
    { key: 'both', label: '双向' },
    { key: 'long', label: '仅做多' },
    { key: 'short', label: '仅做空' },
  ];

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <View style={s.overlay}>
        <View style={s.container}>
          {/* Header */}
          <View style={s.header}>
            <Text style={s.title}>
              {isEdit ? '修改跟单设置' : '跟单设置'}
              {traderName ? ` - ${traderName}` : ''}
            </Text>
            <TouchableOpacity onPress={onClose} hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}>
              <Text style={s.closeBtn}>✕</Text>
            </TouchableOpacity>
          </View>

          <ScrollView
            style={s.scrollBody}
            contentContainerStyle={s.scrollContent}
            showsVerticalScrollIndicator={false}
          >
            {/* ── Allocated Capital ── */}
            {!isEdit ? (
              <>
                <Text style={[s.sectionLabel, { marginTop: 0 }]}>跟单分配本金 (USDT)</Text>
                <TextInput
                  style={s.input}
                  value={allocatedCapital}
                  onChangeText={setAllocatedCapital}
                  keyboardType="numeric"
                  placeholder="1000"
                  placeholderTextColor={Colors.textMuted}
                />
                <Text style={s.fieldHint}>钱包可用：{formatUsd(walletAvailable)} USDT</Text>
                <View style={s.bucketHintBox}>
                  <Text style={s.bucketHintText}>
                    ⓘ 这笔资金会划转到该交易员的"跟单池"。仓位按池子大小计算，盈亏直接进出池子，与主钱包独立。最少 100 USDT。
                  </Text>
                </View>
              </>
            ) : (
              <>
                <Text style={[s.sectionLabel, { marginTop: 0 }]}>跟单本金池</Text>
                <View style={s.bucketCard}>
                  <View style={s.bucketRow}>
                    <Text style={s.bucketLabel}>分配本金</Text>
                    <Text style={s.bucketValue}>{formatUsd(bucket?.allocated_capital)} USDT</Text>
                  </View>
                  <View style={s.bucketRow}>
                    <Text style={s.bucketLabel}>可用</Text>
                    <Text style={[s.bucketValue, { color: Colors.up }]}>
                      {formatUsd(bucket?.available_capital)} USDT
                    </Text>
                  </View>
                  <View style={s.bucketRow}>
                    <Text style={s.bucketLabel}>冻结</Text>
                    <Text style={s.bucketValue}>{formatUsd(bucket?.frozen_capital)} USDT</Text>
                  </View>
                  {bucket && (
                    <View style={[s.bucketRow, s.bucketRowDivider]}>
                      <Text style={s.bucketLabel}>累计盈亏</Text>
                      <Text
                        style={[
                          s.bucketValue,
                          {
                            color:
                              (bucket.available_capital + bucket.frozen_capital - bucket.allocated_capital) >= 0
                                ? Colors.up
                                : Colors.down,
                          },
                        ]}
                      >
                        {(() => {
                          const pnl =
                            bucket.available_capital + bucket.frozen_capital - bucket.allocated_capital;
                          return `${pnl >= 0 ? '+' : ''}${formatUsd(pnl)} USDT`;
                        })()}
                      </Text>
                    </View>
                  )}
                </View>

                {/* Top Up / Withdraw toggle */}
                <View style={s.adjustRow}>
                  <TouchableOpacity
                    style={[s.adjustToggle, adjustMode === 'topup' && s.adjustToggleActive]}
                    onPress={() => {
                      setAdjustMode(adjustMode === 'topup' ? null : 'topup');
                      setAdjustAmount('');
                    }}
                  >
                    <Text
                      style={[s.adjustToggleText, adjustMode === 'topup' && s.adjustToggleTextActive]}
                    >
                      ＋ 追加本金
                    </Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={[s.adjustToggle, adjustMode === 'withdraw' && s.adjustToggleActive]}
                    onPress={() => {
                      setAdjustMode(adjustMode === 'withdraw' ? null : 'withdraw');
                      setAdjustAmount('');
                    }}
                  >
                    <Text
                      style={[
                        s.adjustToggleText,
                        adjustMode === 'withdraw' && s.adjustToggleTextActive,
                      ]}
                    >
                      － 赎回本金
                    </Text>
                  </TouchableOpacity>
                </View>

                {adjustMode && (
                  <>
                    <Text style={s.fieldLabel}>
                      {adjustMode === 'topup' ? '追加金额 (USDT)' : '赎回金额 (USDT)'}
                    </Text>
                    <View style={s.adjustInputRow}>
                      <TextInput
                        style={[s.input, { flex: 1, marginBottom: 0 }]}
                        value={adjustAmount}
                        onChangeText={setAdjustAmount}
                        keyboardType="numeric"
                        placeholder="0"
                        placeholderTextColor={Colors.textMuted}
                      />
                      <TouchableOpacity
                        style={s.adjustConfirmBtn}
                        onPress={handleAdjustCapital}
                        disabled={adjusting}
                      >
                        {adjusting ? (
                          <ActivityIndicator color={Colors.textOnPrimary} size="small" />
                        ) : (
                          <Text style={s.adjustConfirmText}>确认</Text>
                        )}
                      </TouchableOpacity>
                    </View>
                    <Text style={s.fieldHint}>
                      {adjustMode === 'topup'
                        ? `钱包可用：${formatUsd(walletAvailable)} USDT`
                        : `池子可用：${formatUsd(bucket?.available_capital)} USDT`}
                    </Text>
                  </>
                )}
              </>
            )}

            {/* Copy Mode */}
            <Text style={s.sectionLabel}>跟单模式</Text>
            <View style={s.toggleRow}>
              <TouchableOpacity
                style={[s.toggleBtn, copyMode === 'fixed' && s.toggleBtnActive]}
                onPress={() => setCopyMode('fixed')}
              >
                <Text style={[s.toggleBtnText, copyMode === 'fixed' && s.toggleBtnTextActive]}>
                  固定金额
                </Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[s.toggleBtn, copyMode === 'ratio' && s.toggleBtnActive]}
                onPress={() => setCopyMode('ratio')}
              >
                <Text style={[s.toggleBtnText, copyMode === 'ratio' && s.toggleBtnTextActive]}>
                  按比例
                </Text>
              </TouchableOpacity>
            </View>

            {/* Fixed Amount */}
            {copyMode === 'fixed' && (
              <>
                <Text style={s.fieldLabel}>固定金额 (USDT)</Text>
                <TextInput
                  style={s.input}
                  value={fixedAmount}
                  onChangeText={setFixedAmount}
                  keyboardType="numeric"
                  placeholder="100"
                  placeholderTextColor={Colors.textMuted}
                />
              </>
            )}

            {/* Copy Ratio */}
            {copyMode === 'ratio' && (
              <>
                <Text style={s.fieldLabel}>跟单比例</Text>
                <View style={s.inputWithSuffix}>
                  <TextInput
                    style={[s.input, { flex: 1, marginBottom: 0 }]}
                    value={copyRatio}
                    onChangeText={setCopyRatio}
                    keyboardType="numeric"
                    placeholder="1.0"
                    placeholderTextColor={Colors.textMuted}
                  />
                  <Text style={s.inputSuffix}>x</Text>
                </View>
              </>
            )}

            {/* Max Position */}
            <Text style={s.fieldLabel}>最大总仓位 (USDT)</Text>
            <TextInput
              style={s.input}
              value={maxPosition}
              onChangeText={setMaxPosition}
              keyboardType="numeric"
              placeholder="1000"
              placeholderTextColor={Colors.textMuted}
            />

            {/* Max Single Margin */}
            <Text style={s.fieldLabel}>最大单笔 (USDT)</Text>
            <TextInput
              style={s.input}
              value={maxSingleMargin}
              onChangeText={setMaxSingleMargin}
              keyboardType="numeric"
              placeholder="500"
              placeholderTextColor={Colors.textMuted}
            />

            {/* Leverage Mode */}
            <Text style={s.sectionLabel}>杠杆模式</Text>
            <View style={s.toggleRow}>
              <TouchableOpacity
                style={[s.toggleBtn, leverageMode === 'trader' && s.toggleBtnActive]}
                onPress={() => setLeverageMode('trader')}
              >
                <Text style={[s.toggleBtnText, leverageMode === 'trader' && s.toggleBtnTextActive]}>
                  跟随交易员
                </Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[s.toggleBtn, leverageMode === 'custom' && s.toggleBtnActive]}
                onPress={() => setLeverageMode('custom')}
              >
                <Text style={[s.toggleBtnText, leverageMode === 'custom' && s.toggleBtnTextActive]}>
                  自定义
                </Text>
              </TouchableOpacity>
            </View>

            {leverageMode === 'custom' && (
              <>
                <Text style={s.fieldLabel}>自定义杠杆</Text>
                <View style={s.inputWithSuffix}>
                  <TextInput
                    style={[s.input, { flex: 1, marginBottom: 0 }]}
                    value={customLeverage}
                    onChangeText={setCustomLeverage}
                    keyboardType="numeric"
                    placeholder="10"
                    placeholderTextColor={Colors.textMuted}
                  />
                  <Text style={s.inputSuffix}>x</Text>
                </View>
              </>
            )}

            {/* TP/SL Mode */}
            <Text style={s.sectionLabel}>止盈止损</Text>
            <View style={s.toggleRow}>
              <TouchableOpacity
                style={[s.toggleBtn, tpSlMode === 'trader' && s.toggleBtnActive]}
                onPress={() => setTpSlMode('trader')}
              >
                <Text style={[s.toggleBtnText, tpSlMode === 'trader' && s.toggleBtnTextActive]}>
                  跟随交易员
                </Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={[s.toggleBtn, tpSlMode === 'custom' && s.toggleBtnActive]}
                onPress={() => setTpSlMode('custom')}
              >
                <Text style={[s.toggleBtnText, tpSlMode === 'custom' && s.toggleBtnTextActive]}>
                  自定义比例
                </Text>
              </TouchableOpacity>
            </View>

            {tpSlMode === 'custom' && (
              <View style={s.tpSlRow}>
                <View style={{ flex: 1 }}>
                  <Text style={s.fieldLabel}>自定义 TP%</Text>
                  <View style={s.inputWithSuffix}>
                    <TextInput
                      style={[s.input, { flex: 1, marginBottom: 0 }]}
                      value={customTpRatio}
                      onChangeText={setCustomTpRatio}
                      keyboardType="numeric"
                      placeholder="50"
                      placeholderTextColor={Colors.textMuted}
                    />
                    <Text style={s.inputSuffix}>%</Text>
                  </View>
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={s.fieldLabel}>自定义 SL%</Text>
                  <View style={s.inputWithSuffix}>
                    <TextInput
                      style={[s.input, { flex: 1, marginBottom: 0 }]}
                      value={customSlRatio}
                      onChangeText={setCustomSlRatio}
                      keyboardType="numeric"
                      placeholder="20"
                      placeholderTextColor={Colors.textMuted}
                    />
                    <Text style={s.inputSuffix}>%</Text>
                  </View>
                </View>
              </View>
            )}

            {/* Follow Direction */}
            <Text style={s.sectionLabel}>跟单方向</Text>
            <View style={s.directionRow}>
              {directionOptions.map((opt) => (
                <TouchableOpacity
                  key={opt.key}
                  style={[s.directionBtn, followDirection === opt.key && s.directionBtnActive]}
                  onPress={() => setFollowDirection(opt.key)}
                >
                  <Text
                    style={[
                      s.directionBtnText,
                      followDirection === opt.key && s.directionBtnTextActive,
                    ]}
                  >
                    {opt.label}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </ScrollView>

          {/* Submit */}
          <View style={s.footer}>
            <TouchableOpacity style={s.cancelBtn} onPress={onClose}>
              <Text style={s.cancelBtnText}>取消</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={s.submitBtn}
              onPress={handleSubmit}
              disabled={submitting}
            >
              {submitting ? (
                <ActivityIndicator color={Colors.textOnPrimary} size="small" />
              ) : (
                <Text style={s.submitBtnText}>
                  {isEdit ? '保存设置' : '确认跟单'}
                </Text>
              )}
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

const s = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.75)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  container: {
    backgroundColor: Colors.surface,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    width: '92%',
    maxWidth: 480,
    maxHeight: '85%',
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  title: {
    color: Colors.textActive,
    fontSize: 17,
    fontWeight: '700',
  },
  closeBtn: {
    color: Colors.textMuted,
    fontSize: 18,
    padding: 4,
  },
  scrollBody: {
    flexGrow: 0,
  },
  scrollContent: {
    paddingHorizontal: 20,
    paddingTop: 16,
    paddingBottom: 8,
  },

  // Section label (with top divider feel)
  sectionLabel: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
    marginTop: 18,
    marginBottom: 10,
  },

  // Field label
  fieldLabel: {
    color: Colors.textSecondary,
    fontSize: 12,
    marginBottom: 6,
    marginTop: 12,
  },
  fieldHint: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 4,
    marginBottom: 4,
  },

  // Allocated capital bucket display (edit mode)
  bucketCard: {
    backgroundColor: Colors.background,
    borderWidth: 1,
    borderColor: Colors.border,
    borderRadius: Sizes.borderRadiusSm,
    paddingHorizontal: 14,
    paddingVertical: 12,
    marginBottom: 8,
  },
  bucketRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 4,
  },
  bucketRowDivider: {
    marginTop: 6,
    paddingTop: 8,
    borderTopWidth: 1,
    borderTopColor: Colors.border,
  },
  bucketLabel: {
    color: Colors.textSecondary,
    fontSize: 12,
  },
  bucketValue: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '600',
    fontFamily: 'monospace',
  },
  bucketHintBox: {
    backgroundColor: 'rgba(201, 168, 76, 0.08)',
    borderRadius: Sizes.borderRadiusSm,
    paddingHorizontal: 12,
    paddingVertical: 10,
    marginTop: 6,
  },
  bucketHintText: {
    color: Colors.textSecondary,
    fontSize: 11,
    lineHeight: 16,
  },
  adjustRow: {
    flexDirection: 'row',
    gap: 10,
    marginTop: 8,
  },
  adjustToggle: {
    flex: 1,
    paddingVertical: 9,
    borderRadius: Sizes.borderRadiusSm,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    backgroundColor: Colors.background,
  },
  adjustToggleActive: {
    borderColor: '#C9A84C',
    backgroundColor: 'rgba(201, 168, 76, 0.12)',
  },
  adjustToggleText: {
    color: Colors.textSecondary,
    fontSize: 12,
    fontWeight: '600',
  },
  adjustToggleTextActive: {
    color: '#C9A84C',
  },
  adjustInputRow: {
    flexDirection: 'row',
    gap: 8,
    alignItems: 'center',
    marginBottom: 4,
  },
  adjustConfirmBtn: {
    backgroundColor: '#C9A84C',
    paddingHorizontal: 18,
    paddingVertical: 12,
    borderRadius: Sizes.borderRadiusSm,
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 70,
  },
  adjustConfirmText: {
    color: Colors.textOnPrimary,
    fontSize: 13,
    fontWeight: '700',
  },

  // Input
  input: {
    backgroundColor: Colors.background,
    borderWidth: 1,
    borderColor: Colors.border,
    borderRadius: Sizes.borderRadiusSm,
    paddingHorizontal: 14,
    paddingVertical: 12,
    color: Colors.textActive,
    fontSize: 14,
    fontFamily: 'monospace',
    marginBottom: 4,
  },
  inputWithSuffix: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 4,
  },
  inputSuffix: {
    color: Colors.textMuted,
    fontSize: 14,
    fontWeight: '600',
    minWidth: 20,
  },

  // Toggle buttons
  toggleRow: {
    flexDirection: 'row',
    gap: 10,
  },
  toggleBtn: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: Sizes.borderRadiusSm,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    backgroundColor: Colors.background,
  },
  toggleBtnActive: {
    borderColor: '#C9A84C',
    backgroundColor: 'rgba(201, 168, 76, 0.12)',
  },
  toggleBtnText: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '600',
  },
  toggleBtnTextActive: {
    color: '#C9A84C',
  },

  // TP/SL row
  tpSlRow: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 4,
  },

  // Direction selector (3 options)
  directionRow: {
    flexDirection: 'row',
    gap: 8,
  },
  directionBtn: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: Sizes.borderRadiusSm,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    backgroundColor: Colors.background,
  },
  directionBtnActive: {
    borderColor: '#C9A84C',
    backgroundColor: 'rgba(201, 168, 76, 0.12)',
  },
  directionBtnText: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '600',
  },
  directionBtnTextActive: {
    color: '#C9A84C',
  },

  // Footer buttons
  footer: {
    flexDirection: 'row',
    gap: 12,
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderTopWidth: 1,
    borderTopColor: Colors.border,
  },
  cancelBtn: {
    flex: 1,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingVertical: 14,
    borderRadius: 10,
    alignItems: 'center',
  },
  cancelBtnText: {
    color: Colors.textSecondary,
    fontSize: 15,
    fontWeight: '600',
  },
  submitBtn: {
    flex: 1,
    backgroundColor: '#C9A84C',
    paddingVertical: 14,
    borderRadius: 10,
    alignItems: 'center',
    shadowColor: '#C9A84C',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.2,
    shadowRadius: 16,
    elevation: 4,
  },
  submitBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 15,
    fontWeight: '700',
  },
});
