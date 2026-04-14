import { useState, useMemo } from 'react';
import {
  View, Text, TextInput, TouchableOpacity, ScrollView, StyleSheet,
} from 'react-native';
import { Colors } from '../../theme/colors';
import { INDICATOR_REGISTRY, type IndicatorType, type IndicatorConfig } from './indicators';
import type { ActiveIndicator } from './TradingViewChart';
import AppIcon from '../ui/AppIcon';

interface IndicatorsPanelProps {
  visible: boolean;
  activeIndicators: ActiveIndicator[];
  onToggleIndicator: (type: IndicatorType, params: Record<string, number>) => void;
  onRemoveIndicator: (type: IndicatorType) => void;
  onClose: () => void;
}

const CATEGORY_LABELS: Record<string, string> = {
  trend: '趋势',
  momentum: '动量',
  volatility: '波动率',
  volume: '成交量',
};

const CATEGORY_ORDER = ['trend', 'momentum', 'volatility', 'volume'];

export default function IndicatorsPanel({
  visible, activeIndicators, onToggleIndicator, onRemoveIndicator, onClose,
}: IndicatorsPanelProps) {
  const [searchText, setSearchText] = useState('');

  const activeTypes = useMemo(() => new Set(activeIndicators.map((i) => i.type)), [activeIndicators]);

  const filtered = useMemo(() => {
    if (!searchText) return INDICATOR_REGISTRY;
    const q = searchText.toLowerCase();
    return INDICATOR_REGISTRY.filter(
      (ind) =>
        ind.name.toLowerCase().includes(q) ||
        ind.description.toLowerCase().includes(q) ||
        ind.type.toLowerCase().includes(q),
    );
  }, [searchText]);

  const grouped = useMemo(() => {
    const map: Record<string, IndicatorConfig[]> = {};
    for (const ind of filtered) {
      if (!map[ind.category]) map[ind.category] = [];
      map[ind.category].push(ind);
    }
    return map;
  }, [filtered]);

  if (!visible) return null;

  return (
    <View style={ip.overlay}>
      <TouchableOpacity style={ip.backdrop} onPress={onClose} activeOpacity={1} />
      <View style={ip.panel}>
        {/* Header */}
        <View style={ip.header}>
          <Text style={ip.title}>技术指标</Text>
          <TouchableOpacity onPress={onClose} hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}>
            <AppIcon name="close" size={16} color={Colors.textMuted} />
          </TouchableOpacity>
        </View>

        {/* Search */}
        <View style={ip.searchRow}>
          <AppIcon name="search" size={15} color={Colors.textMuted} />
          <TextInput
            style={ip.searchInput}
            placeholder="搜索指标..."
            placeholderTextColor={Colors.textMuted}
            value={searchText}
            onChangeText={setSearchText}
          />
        </View>

        {/* Active indicators */}
        {activeIndicators.length > 0 && (
          <View style={ip.activeSection}>
            <Text style={ip.sectionLabel}>已添加</Text>
            <View style={ip.activeList}>
              {activeIndicators.map((ind) => {
                const config = INDICATOR_REGISTRY.find((r) => r.type === ind.type);
                return (
                  <View key={ind.type} style={ip.activeChip}>
                    <Text style={ip.activeChipText}>{config?.name ?? ind.type}</Text>
                    <TouchableOpacity onPress={() => onRemoveIndicator(ind.type)}>
                      <AppIcon name="close" size={12} color={Colors.textMuted} />
                    </TouchableOpacity>
                  </View>
                );
              })}
            </View>
          </View>
        )}

        {/* Indicator list */}
        <ScrollView style={ip.list} showsVerticalScrollIndicator={false}>
          {CATEGORY_ORDER.filter((cat) => grouped[cat]).map((cat) => (
            <View key={cat}>
              <Text style={ip.categoryLabel}>{CATEGORY_LABELS[cat]}</Text>
              {grouped[cat].map((ind) => {
                const isActive = activeTypes.has(ind.type);
                return (
                  <TouchableOpacity
                    key={ind.type}
                    style={[ip.indicatorRow, isActive && ip.indicatorRowActive]}
                    onPress={() => {
                      if (isActive) {
                        onRemoveIndicator(ind.type);
                      } else {
                        onToggleIndicator(ind.type, {});
                      }
                    }}
                    activeOpacity={0.6}
                  >
                    <View style={ip.indicatorInfo}>
                      <Text style={[ip.indicatorName, isActive && ip.indicatorNameActive]}>
                        {ind.name}
                      </Text>
                      <Text style={ip.indicatorDesc}>{ind.description}</Text>
                    </View>
                    <View style={ip.indicatorMeta}>
                      <Text style={ip.indicatorTag}>
                        {ind.overlay ? '主图' : '副图'}
                      </Text>
                      <View style={[ip.toggleDot, isActive && ip.toggleDotActive]} />
                    </View>
                  </TouchableOpacity>
                );
              })}
            </View>
          ))}
          <View style={{ height: 40 }} />
        </ScrollView>
      </View>
    </View>
  );
}

const ip = StyleSheet.create({
  overlay: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    zIndex: 200,
  },
  backdrop: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  panel: {
    position: 'absolute',
    top: 0, right: 0, bottom: 0,
    width: 340,
    backgroundColor: '#131313',
    borderLeftWidth: 1,
    borderLeftColor: Colors.border,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  title: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
  },
  closeBtn: {
    color: Colors.textMuted,
    fontSize: 16,
    padding: 4,
  },
  searchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.15)',
    gap: 8,
  },
  searchIcon: { fontSize: 13, opacity: 0.5 },
  searchInput: {
    flex: 1,
    color: Colors.textActive,
    fontSize: 13,
    paddingVertical: 4,
  },
  activeSection: {
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.15)',
  },
  sectionLabel: {
    fontSize: 10,
    color: Colors.textMuted,
    fontWeight: '600',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: 8,
  },
  activeList: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  activeChip: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(242,202,80,0.12)',
    borderWidth: 1,
    borderColor: 'rgba(242,202,80,0.3)',
    borderRadius: 4,
    paddingHorizontal: 10,
    paddingVertical: 5,
    gap: 6,
  },
  activeChipText: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '700',
  },
  activeChipRemove: {
    color: Colors.primary,
    fontSize: 12,
    opacity: 0.7,
  },
  list: {
    flex: 1,
  },
  categoryLabel: {
    fontSize: 11,
    color: Colors.textMuted,
    fontWeight: '600',
    letterSpacing: 0.5,
    paddingHorizontal: 14,
    paddingTop: 14,
    paddingBottom: 6,
  },
  indicatorRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(42,42,42,0.3)',
  },
  indicatorRowActive: {
    backgroundColor: 'rgba(242,202,80,0.05)',
  },
  indicatorInfo: {
    flex: 1,
    gap: 2,
  },
  indicatorName: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '600',
  },
  indicatorNameActive: {
    color: Colors.primary,
  },
  indicatorDesc: {
    color: Colors.textMuted,
    fontSize: 10,
  },
  indicatorMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  indicatorTag: {
    fontSize: 9,
    color: Colors.textMuted,
    backgroundColor: 'rgba(42,42,42,0.5)',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 3,
    overflow: 'hidden',
  },
  toggleDot: {
    width: 16,
    height: 16,
    borderRadius: 8,
    borderWidth: 2,
    borderColor: Colors.textMuted,
  },
  toggleDotActive: {
    borderColor: Colors.primary,
    backgroundColor: Colors.primary,
  },
});
