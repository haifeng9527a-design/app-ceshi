/**
 * SpotFillReceiptModal
 *
 * 现货「市价单」成交后的回执弹窗。
 *
 * 设计意图
 * ─────────────────────────────────────────────────────────────────────────
 *   市价单会立刻成交，用户常常来不及看底部订单列表的新增行就离开了。
 *   弹窗把成交的关键数据（成交对、价格、数量、总额、手续费）集中展示一次，
 *   作为交易确认单。限价单不走这里 —— 限价是挂单，还没成交。
 *
 * 复弹控制
 * ─────────────────────────────────────────────────────────────────────────
 *   底部「下次不再提示」checkbox 勾选后，用户态通过 AsyncStorage 持久化
 *   （key: tongxin_spot_fill_receipt_muted），后续市价成交不再弹。
 *   用户可以在「设置 → 通知偏好」再打开（未来项，此处仅埋 mute flag）。
 *
 * 仅依赖：
 *   - props 传入 SpotOrder 快照（成交后的完整对象，含 filled_qty / filled_price）
 *   - Colors / Shadows：视觉和 TransferModal 对齐
 */
import React, { memo, useCallback, useEffect, useState } from 'react';
import {
  Modal,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useTranslation } from 'react-i18next';

import AppIcon from '../ui/AppIcon';
import type { SpotOrder, SpotSide } from '../../services/api/spotApi';
import { Colors, Shadows } from '../../theme/colors';

export interface SpotFillReceiptModalProps {
  visible: boolean;
  order: SpotOrder | null;
  /** 用户当前的 mute 偏好（initial）。父组件从 AsyncStorage 加载。 */
  muted: boolean;
  /** 用户勾选/取消「下次不再提示」。父组件负责持久化。 */
  onMutedChange: (muted: boolean) => void;
  onClose: () => void;
}

function formatNumber(value: number | undefined | null, precision: number): string {
  if (value == null || !Number.isFinite(value)) return '--';
  return value.toLocaleString(undefined, {
    minimumFractionDigits: precision,
    maximumFractionDigits: precision,
  });
}

/** 智能精度：大数字少位，小数字多位 —— 和 spot.tsx formatPrice 行为一致。 */
function smartPricePrecision(value: number | undefined | null): number {
  if (value == null || !Number.isFinite(value) || value <= 0) return 2;
  if (value >= 1000) return 2;
  if (value >= 1) return 4;
  if (value >= 0.01) return 6;
  return 8;
}

/**
 * 提取展示用的成交数据。成交成功的市价单后端保证有 filled_qty + filled_price，
 * 但防守式兜底：若字段缺失，从 qty / price 回退。
 */
function extractReceipt(order: SpotOrder) {
  const side: SpotSide = order.side;
  const qty = order.filled_qty > 0 ? order.filled_qty : order.qty;
  const price = order.filled_price && order.filled_price > 0 ? order.filled_price : order.price || 0;
  const quoteAmount = order.quote_qty > 0 ? order.quote_qty : qty * price;
  const fee = order.fee;
  const feeAsset = order.fee_asset || (side === 'buy' ? order.base_asset : order.quote_asset);
  return {
    side,
    baseAsset: order.base_asset,
    quoteAsset: order.quote_asset,
    qty,
    price,
    quoteAmount,
    fee,
    feeAsset,
  };
}

function SpotFillReceiptModalImpl({
  visible,
  order,
  muted,
  onMutedChange,
  onClose,
}: SpotFillReceiptModalProps) {
  const { t } = useTranslation();
  // 本地 ticked 镜像，避免父组件异步持久化带来的短暂闪烁。
  const [ticked, setTicked] = useState(muted);
  useEffect(() => {
    setTicked(muted);
  }, [muted, visible]);

  const toggleTicked = useCallback(() => {
    const next = !ticked;
    setTicked(next);
    onMutedChange(next);
  }, [ticked, onMutedChange]);

  if (!order) return null;
  const r = extractReceipt(order);
  const isBuy = r.side === 'buy';
  const qtyPrecision = 8; // filled_qty 显示到 8 位；尾部 0 用户也能看出差异
  const pricePrecision = smartPricePrecision(r.price);
  const accentColor = isBuy ? Colors.up : Colors.down;
  const accentDim = isBuy ? Colors.upDim : Colors.downDim;

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <View style={styles.overlay}>
        <View style={[styles.card, Shadows.card]}>
          {/* ── 标题栏 ── */}
          <View style={styles.header}>
            <View style={[styles.iconWrap, { backgroundColor: accentDim, borderColor: accentColor }]}>
              <AppIcon name="check" size={24} color={accentColor} />
            </View>
            <Text style={styles.title}>
              {isBuy
                ? t('spot.fillReceiptBuyTitle') || '买入成功'
                : t('spot.fillReceiptSellTitle') || '卖出成功'}
            </Text>
            <Text style={styles.subtitle}>
              {t('spot.fillReceiptSubtitle') || '市价单已成交'}
            </Text>
          </View>

          {/* ── 顶部大字：成交数量 + 币种 ── */}
          <View style={[styles.hero, { backgroundColor: accentDim, borderColor: accentColor }]}>
            <Text style={styles.heroLabel}>
              {isBuy
                ? t('spot.fillReceiptReceivedLabel') || '到账'
                : t('spot.fillReceiptReleasedLabel') || '卖出'}
            </Text>
            <Text style={[styles.heroValue, { color: accentColor }]}>
              {isBuy ? '+' : '-'}
              {formatNumber(r.qty, qtyPrecision)}{' '}
              <Text style={styles.heroUnit}>{r.baseAsset}</Text>
            </Text>
          </View>

          {/* ── 明细行 ── */}
          <View style={styles.detailBlock}>
            <DetailRow
              label={t('spot.fillReceiptSymbol') || '交易对'}
              value={`${r.baseAsset}/${r.quoteAsset}`}
            />
            <DetailRow
              label={t('spot.fillReceiptPrice') || '成交价格'}
              value={`${formatNumber(r.price, pricePrecision)} ${r.quoteAsset}`}
            />
            <DetailRow
              label={t('spot.fillReceiptQty') || '成交数量'}
              value={`${formatNumber(r.qty, qtyPrecision)} ${r.baseAsset}`}
            />
            <DetailRow
              label={t('spot.fillReceiptAmount') || '成交金额'}
              value={`${formatNumber(r.quoteAmount, 2)} ${r.quoteAsset}`}
              emphasize
            />
            <DetailRow
              label={t('spot.fillReceiptFee') || '手续费'}
              value={`${formatNumber(r.fee, 8).replace(/\.?0+$/, '')} ${r.feeAsset}`}
              subtle
            />
          </View>

          {/* ── 不再提示勾选 ── */}
          <TouchableOpacity
            style={styles.muteRow}
            activeOpacity={0.7}
            onPress={toggleTicked}
          >
            <View style={[styles.checkbox, ticked && styles.checkboxChecked]}>
              {ticked ? <AppIcon name="check" size={12} color={Colors.textOnPrimary} /> : null}
            </View>
            <Text style={styles.muteLabel}>
              {t('spot.fillReceiptMuteHint') || '下次不再提示（可在设置中恢复）'}
            </Text>
          </TouchableOpacity>

          {/* ── 主按钮 ── */}
          <TouchableOpacity style={styles.primaryBtn} onPress={onClose} activeOpacity={0.85}>
            <Text style={styles.primaryBtnText}>
              {t('common.ok') || '知道了'}
            </Text>
          </TouchableOpacity>
        </View>
      </View>
    </Modal>
  );
}

const DetailRow = memo(function DetailRow({
  label,
  value,
  emphasize,
  subtle,
}: {
  label: string;
  value: string;
  emphasize?: boolean;
  subtle?: boolean;
}) {
  return (
    <View style={styles.detailRow}>
      <Text style={styles.detailLabel}>{label}</Text>
      <Text
        style={[
          styles.detailValue,
          emphasize && styles.detailValueEmphasize,
          subtle && styles.detailValueSubtle,
        ]}
        numberOfLines={1}
      >
        {value}
      </Text>
    </View>
  );
});

const SpotFillReceiptModal = memo(SpotFillReceiptModalImpl);
export default SpotFillReceiptModal;

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: Colors.overlayBg,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  card: {
    width: '100%',
    maxWidth: 420,
    backgroundColor: Colors.surface,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 22,
    paddingTop: 26,
    paddingBottom: 20,
  },

  /* Header */
  header: {
    alignItems: 'center',
    marginBottom: 18,
  },
  iconWrap: {
    width: 48,
    height: 48,
    borderRadius: 24,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 12,
  },
  title: {
    color: Colors.textActive,
    fontSize: 19,
    fontWeight: '800',
    letterSpacing: 0.3,
  },
  subtitle: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 4,
    letterSpacing: 0.4,
  },

  /* Hero */
  hero: {
    borderWidth: 1,
    borderRadius: 14,
    paddingVertical: 16,
    paddingHorizontal: 18,
    alignItems: 'center',
    marginBottom: 16,
  },
  heroLabel: {
    color: Colors.textSecondary,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
    marginBottom: 6,
  },
  heroValue: {
    fontSize: 26,
    fontWeight: '800',
    fontFamily: 'monospace',
    letterSpacing: 0.3,
  },
  heroUnit: {
    fontSize: 15,
    fontWeight: '700',
    color: Colors.textSecondary,
  },

  /* Details */
  detailBlock: {
    backgroundColor: Colors.surfaceAlt,
    borderRadius: 12,
    paddingVertical: 4,
    paddingHorizontal: 14,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  detailRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Colors.border,
  },
  detailLabel: {
    color: Colors.textMuted,
    fontSize: 13,
    fontWeight: '500',
  },
  detailValue: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '700',
    fontFamily: 'monospace',
    flexShrink: 1,
    textAlign: 'right',
    marginLeft: 12,
  },
  detailValueEmphasize: {
    color: Colors.primary,
    fontSize: 14,
  },
  detailValueSubtle: {
    color: Colors.textSecondary,
    fontWeight: '500',
  },

  /* Mute row */
  muteRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 6,
    marginBottom: 10,
  },
  checkbox: {
    width: 18,
    height: 18,
    borderRadius: 5,
    borderWidth: 1.5,
    borderColor: Colors.borderLight,
    backgroundColor: Colors.inputBg,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 10,
  },
  checkboxChecked: {
    backgroundColor: Colors.primary,
    borderColor: Colors.primary,
  },
  muteLabel: {
    color: Colors.textSecondary,
    fontSize: 12,
    flexShrink: 1,
  },

  /* Button */
  primaryBtn: {
    backgroundColor: Colors.primary,
    borderRadius: 12,
    paddingVertical: 13,
    alignItems: 'center',
    justifyContent: 'center',
  },
  primaryBtnText: {
    color: Colors.textOnPrimary,
    fontSize: 15,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
});
