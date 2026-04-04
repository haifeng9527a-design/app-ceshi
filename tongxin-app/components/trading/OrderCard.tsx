import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import type { OrderResponse } from '../../services/api/tradingApi';

interface Props {
  order: OrderResponse;
  onCancel?: (id: string) => void;
}

const fmt = (v: number | undefined | null, d = 2) =>
  v != null && isFinite(v) ? v.toFixed(d) : '--';

export default function OrderCard({ order, onCancel }: Props) {
  const isLong = order.side === 'long';
  const sideColor = isLong ? '#0ECB81' : '#F6465D';
  const sideLabel = isLong ? '多' : '空';
  const isPending = order.status === 'pending';
  const isFilled = order.status === 'filled';

  const statusLabel: Record<string, string> = {
    pending: '待成交',
    filled: '已成交',
    cancelled: '已撤销',
    rejected: '已拒绝',
  };

  const statusColor: Record<string, string> = {
    pending: '#C9A84C',
    filled: '#0ECB81',
    cancelled: '#888',
    rejected: '#F6465D',
  };

  const priceDisplay = isFilled && order.filled_price
    ? fmt(order.filled_price)
    : order.price
      ? fmt(order.price)
      : '市价';

  const dateStr = (() => {
    try {
      return new Date(order.created_at).toLocaleString('zh-CN', {
        month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
      });
    } catch { return '--'; }
  })();

  return (
    <View style={st.card}>
      <View style={st.header}>
        <View style={st.headerLeft}>
          <View style={[st.sideBadge, { backgroundColor: sideColor }]}>
            <Text style={st.sideBadgeText}>{sideLabel}</Text>
          </View>
          <Text style={st.symbol}>{order.symbol}</Text>
          <View style={st.typeBadge}>
            <Text style={st.typeText}>{order.order_type === 'limit' ? '限价' : '市价'}</Text>
          </View>
          <Text style={st.leverageText}>{order.leverage ?? '--'}x</Text>
        </View>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          <Text style={[st.statusText, { color: statusColor[order.status] || '#888' }]}>
            {statusLabel[order.status] || order.status}
          </Text>
          {isPending && onCancel && (
            <TouchableOpacity style={st.cancelBtn} onPress={() => onCancel(order.id)} activeOpacity={0.7}>
              <Text style={st.cancelBtnText}>撤单</Text>
            </TouchableOpacity>
          )}
        </View>
      </View>

      <View style={st.detailRow}>
        <View style={st.detailCell}>
          <Text style={st.detailLabel}>价格</Text>
          <Text style={st.detailValue}>{priceDisplay}</Text>
        </View>
        <View style={st.detailCell}>
          <Text style={st.detailLabel}>数量</Text>
          <Text style={st.detailValue}>{order.qty ?? '--'}</Text>
        </View>
        <View style={st.detailCell}>
          <Text style={st.detailLabel}>保证金</Text>
          <Text style={st.detailValue}>{fmt(order.margin_amount)}</Text>
        </View>
        <View style={st.detailCell}>
          <Text style={st.detailLabel}>时间</Text>
          <Text style={st.detailValue}>{dateStr}</Text>
        </View>
      </View>
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
    marginBottom: 10,
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
    fontSize: 13,
    fontWeight: '700',
  },
  typeBadge: {
    backgroundColor: 'rgba(255,255,255,0.08)',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
  },
  typeText: {
    color: '#aaa',
    fontSize: 10,
  },
  leverageText: {
    color: '#C9A84C',
    fontSize: 11,
    fontWeight: '600',
  },
  statusText: {
    fontSize: 11,
    fontWeight: '600',
  },
  cancelBtn: {
    backgroundColor: 'rgba(246,70,93,0.12)',
    paddingHorizontal: 12,
    paddingVertical: 5,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: 'rgba(246,70,93,0.2)',
  },
  cancelBtnText: {
    color: '#F6465D',
    fontSize: 11,
    fontWeight: '600',
  },
  detailRow: {
    flexDirection: 'row',
  },
  detailCell: {
    flex: 1,
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
