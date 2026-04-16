import { memo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import type { PositionResponse } from '../../services/api/tradingApi';
import { toDisplaySymbol } from '../../services/utils/symbolFormat';

interface Props {
  position: PositionResponse;
}

const fmt = (v: number | undefined | null, d = 2) =>
  v != null && isFinite(v) ? v.toFixed(d) : '--';

function formatTime(iso?: string) {
  if (!iso) return '--';
  const d = new Date(iso);
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  const hh = String(d.getHours()).padStart(2, '0');
  const mi = String(d.getMinutes()).padStart(2, '0');
  return `${mm}-${dd} ${hh}:${mi}`;
}

function ClosedPositionCard({ position }: Props) {
  const { t } = useTranslation();
  const isLong = position.side === 'long';
  const grossPnl = position.realized_pnl ?? 0;
  const openFee = position.open_fee ?? 0;
  const closeFee = position.close_fee ?? 0;
  const totalFee = openFee + closeFee;
  const netPnl = grossPnl - totalFee;
  const pnlColor = netPnl >= 0 ? '#0ECB81' : '#F6465D';
  const sideColor = isLong ? '#0ECB81' : '#F6465D';
  const sideLabel = isLong ? t('trading.longSide') : t('trading.shortSide');
  const marginAmt = position.margin_amount || 1;
  const roe = marginAmt > 0 ? (netPnl / marginAmt) * 100 : 0;
  const roeStr = roe >= 0 ? `+${fmt(roe)}%` : `${fmt(roe)}%`;
  const pnlStr = netPnl >= 0 ? `+${fmt(netPnl)}` : fmt(netPnl);
  const isLiquidated = position.status === 'liquidated';

  return (
    <View style={st.card}>
      {/* Header */}
      <View style={st.header}>
        <View style={st.headerLeft}>
          <View style={[st.sideBadge, { backgroundColor: sideColor }]}>
            <Text style={st.sideBadgeText}>{sideLabel}</Text>
          </View>
          <Text style={st.symbol}>{toDisplaySymbol(position.symbol)}</Text>
          <View style={st.leverageBadge}>
            <Text style={st.leverageText}>{position.leverage ?? '--'}x</Text>
          </View>
        </View>
        <View style={[st.statusBadge, isLiquidated && st.statusLiquidated]}>
          <Text style={[st.statusText, isLiquidated && st.statusTextLiquidated]}>
            {isLiquidated ? t('trading.liquidated') : t('trading.closed')}
          </Text>
        </View>
      </View>

      {/* PnL */}
      <View style={st.pnlRow}>
        <View style={{ flex: 1 }}>
          <Text style={st.pnlLabel}>{t('trading.realizedPnl')}(USDT)</Text>
          <Text style={[st.pnlValue, { color: pnlColor }]}>{pnlStr}</Text>
        </View>
        <View style={{ alignItems: 'flex-end' }}>
          <Text style={st.pnlLabel}>{t('trading.returnRate')}</Text>
          <Text style={[st.roeValue, { color: pnlColor }]}>{roeStr}</Text>
        </View>
      </View>

      {/* Divider */}
      <View style={st.divider} />

      {/* Details */}
      <View style={st.detailGrid}>
        <DetailItem label={t('trading.quantity')} value={String(position.qty ?? '--')} />
        <DetailItem label={t('trading.margin')} value={fmt(position.margin_amount)} />
        <DetailItem label={t('trading.openAvgPrice')} value={fmt(position.entry_price)} />
        <DetailItem label={t('trading.closeAvgPrice')} value={position.close_price ? fmt(position.close_price) : '--'} />
        <DetailItem label={t('trading.openTime')} value={formatTime(position.created_at)} />
        <DetailItem label={t('trading.closeTime')} value={formatTime(position.closed_at)} />
        <DetailItem label={t('trading.openFee')} value={fmt(openFee)} />
        <DetailItem label={t('trading.closeFee')} value={fmt(closeFee)} />
        <DetailItem label={t('trading.netPnl')} value={pnlStr} color={pnlColor} />
      </View>
    </View>
  );
}

function DetailItem({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <View style={st.detailCell}>
      <Text style={st.detailLabel}>{label}</Text>
      <Text style={[st.detailValue, color ? { color } : undefined]}>{value}</Text>
    </View>
  );
}

const st = StyleSheet.create({
  card: {
    backgroundColor: '#1A1A1A',
    borderRadius: 10,
    padding: 14,
    marginBottom: 8,
    marginHorizontal: 4,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.04)',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 12,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    flexShrink: 1,
  },
  sideBadge: {
    paddingHorizontal: 7,
    paddingVertical: 2,
    borderRadius: 4,
  },
  sideBadgeText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '700',
  },
  symbol: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
  },
  leverageBadge: {
    backgroundColor: 'rgba(201,168,76,0.18)',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
  },
  leverageText: {
    color: '#C9A84C',
    fontSize: 11,
    fontWeight: '600',
  },
  statusBadge: {
    backgroundColor: 'rgba(136,136,136,0.12)',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 6,
  },
  statusLiquidated: {
    backgroundColor: 'rgba(246,70,93,0.12)',
  },
  statusText: {
    color: '#888',
    fontSize: 11,
    fontWeight: '600',
  },
  statusTextLiquidated: {
    color: '#F6465D',
  },
  pnlRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
    marginBottom: 12,
  },
  pnlLabel: {
    color: '#666',
    fontSize: 11,
    marginBottom: 4,
  },
  pnlValue: {
    fontSize: 18,
    fontWeight: '700',
    fontFamily: 'monospace',
  },
  roeValue: {
    fontSize: 14,
    fontWeight: '700',
    fontFamily: 'monospace',
  },
  divider: {
    height: 1,
    backgroundColor: 'rgba(255,255,255,0.05)',
    marginBottom: 12,
  },
  detailGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  detailCell: {
    width: '33.33%',
    marginBottom: 10,
  },
  detailLabel: {
    color: '#555',
    fontSize: 11,
    marginBottom: 3,
  },
  detailValue: {
    color: '#bbb',
    fontSize: 12,
    fontFamily: 'monospace',
  },
});

export default memo(ClosedPositionCard);
