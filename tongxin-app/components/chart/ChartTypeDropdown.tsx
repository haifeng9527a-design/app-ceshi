import { TouchableOpacity, View, Text, StyleSheet, Platform } from 'react-native';
import { Colors } from '../../theme/colors';
import type { ChartType } from './TradingViewChart';

interface ChartTypeDropdownProps {
  visible: boolean;
  currentType: ChartType;
  onSelect: (type: ChartType) => void;
  onClose: () => void;
}

const CHART_TYPE_OPTIONS: { key: ChartType; label: string; icon: string; desc: string }[] = [
  { key: 'candle',      label: '蜡烛图',     icon: '▐▌', desc: 'Candlestick' },
  { key: 'hollowCandle', label: '空心蜡烛',   icon: '▯▯', desc: 'Hollow Candlestick' },
  { key: 'ohlc',        label: 'OHLC 柱',    icon: '┤├', desc: 'Bar Chart' },
  { key: 'line',        label: '折线图',      icon: '╱╲', desc: 'Line Chart' },
  { key: 'area',        label: '面积图',      icon: '▓░', desc: 'Area Chart' },
];

export default function ChartTypeDropdown({ visible, currentType, onSelect, onClose }: ChartTypeDropdownProps) {
  if (!visible) return null;

  return (
    <View style={ct.overlay}>
      <TouchableOpacity style={ct.backdrop} onPress={onClose} activeOpacity={1} />
      <View style={ct.dropdown}>
        <Text style={ct.title}>图表类型</Text>
        {CHART_TYPE_OPTIONS.map((opt) => {
          const isActive = currentType === opt.key;
          return (
            <TouchableOpacity
              key={opt.key}
              style={[ct.item, isActive && ct.itemActive]}
              onPress={() => { onSelect(opt.key); onClose(); }}
              activeOpacity={0.6}
            >
              <Text style={[ct.icon, isActive && ct.iconActive]}>{opt.icon}</Text>
              <View style={ct.itemInfo}>
                <Text style={[ct.itemLabel, isActive && ct.itemLabelActive]}>{opt.label}</Text>
                <Text style={ct.itemDesc}>{opt.desc}</Text>
              </View>
              {isActive && <Text style={ct.check}>✓</Text>}
            </TouchableOpacity>
          );
        })}
      </View>
    </View>
  );
}

// Get the icon for a given chart type (for the toolbar button)
export function getChartTypeIcon(type: ChartType): string {
  return CHART_TYPE_OPTIONS.find((o) => o.key === type)?.icon ?? '▐▌';
}

const ct = StyleSheet.create({
  overlay: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    zIndex: 150,
  },
  backdrop: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
  },
  dropdown: {
    position: 'absolute',
    top: 90,
    right: 20,
    width: 220,
    backgroundColor: '#1a1a1a',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.3)',
    padding: 8,
    ...(Platform.OS === 'web' ? { boxShadow: '0 4px 20px rgba(0,0,0,0.6)' } : {}),
  },
  title: {
    fontSize: 10,
    color: Colors.textMuted,
    fontWeight: '600',
    letterSpacing: 1,
    textTransform: 'uppercase',
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
  item: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 10,
    borderRadius: 6,
    gap: 10,
  },
  itemActive: {
    backgroundColor: 'rgba(242,202,80,0.08)',
  },
  icon: {
    width: 24,
    fontSize: 13,
    fontFamily: 'monospace',
    fontWeight: '700',
    color: Colors.textMuted,
    textAlign: 'center',
  },
  iconActive: {
    color: Colors.primary,
  },
  itemInfo: {
    flex: 1,
    gap: 1,
  },
  itemLabel: {
    color: Colors.textActive,
    fontSize: 12,
    fontWeight: '600',
  },
  itemLabelActive: {
    color: Colors.primary,
  },
  itemDesc: {
    color: Colors.textMuted,
    fontSize: 9,
  },
  check: {
    color: Colors.primary,
    fontSize: 14,
    fontWeight: '700',
  },
});
