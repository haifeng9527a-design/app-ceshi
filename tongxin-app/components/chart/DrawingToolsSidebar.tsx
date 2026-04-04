import { useState, useMemo } from 'react';
import {
  View, Text, TouchableOpacity, ScrollView, StyleSheet, Platform,
} from 'react-native';
import { Colors } from '../../theme/colors';

/* ═══════════════════════════════════════════
   Drawing Tool Types & Registry
   ═══════════════════════════════════════════ */

/**
 * DrawingTool — KLineChart overlay names + special values (cursor, crosshair, eraser).
 */
export type DrawingTool =
  | 'cursor'
  | 'crosshair'
  // Lines
  | 'segment'
  | 'straightLine'
  | 'rayLine'
  // Horizontal
  | 'horizontalStraightLine'
  | 'horizontalRayLine'
  | 'horizontalSegment'
  // Vertical
  | 'verticalStraightLine'
  | 'verticalRayLine'
  | 'verticalSegment'
  // Fibonacci
  | 'fibonacciLine'
  // Channels
  | 'parallelStraightLine'
  | 'priceChannelLine'
  // Annotations
  | 'priceLine'
  | 'simpleAnnotation'
  | 'simpleTag'
  // Actions
  | 'eraser';

export type ToolCategory =
  | 'cursor'
  | 'lines'
  | 'horizontal'
  | 'vertical'
  | 'fibonacci'
  | 'channels'
  | 'annotations'
  | 'actions';

export interface DrawingToolConfig {
  key: DrawingTool;
  label: string;
  icon: string;
  category: ToolCategory;
  categoryLabel: string;
  description: string;
}

/**
 * Complete registry of ALL available drawing tools.
 * Users can choose which to show in the sidebar.
 */
export const ALL_DRAWING_TOOLS: DrawingToolConfig[] = [
  // ─── Cursor ───────────────────
  { key: 'cursor',                  label: '选择',        icon: '↖',  category: 'cursor',     categoryLabel: '光标',   description: '普通选择模式' },
  { key: 'crosshair',              label: '十字准线',    icon: '＋',  category: 'cursor',     categoryLabel: '光标',   description: '十字准线模式' },
  // ─── Lines ────────────────────
  { key: 'segment',                label: '趋势线',      icon: '╱',  category: 'lines',      categoryLabel: '线段',   description: '两点之间的线段' },
  { key: 'straightLine',           label: '直线',        icon: '⟋',  category: 'lines',      categoryLabel: '线段',   description: '穿过两点的无限延伸直线' },
  { key: 'rayLine',                label: '射线',        icon: '→',  category: 'lines',      categoryLabel: '线段',   description: '从一点出发的半无限线' },
  // ─── Horizontal ───────────────
  { key: 'horizontalStraightLine', label: '水平线',      icon: '━',  category: 'horizontal', categoryLabel: '水平线', description: '水平方向的无限延伸直线' },
  { key: 'horizontalRayLine',      label: '水平射线',    icon: '⟶', category: 'horizontal', categoryLabel: '水平线', description: '水平方向的半无限线' },
  { key: 'horizontalSegment',      label: '水平线段',    icon: '──', category: 'horizontal', categoryLabel: '水平线', description: '水平方向的线段' },
  // ─── Vertical ─────────────────
  { key: 'verticalStraightLine',   label: '垂直线',      icon: '│',  category: 'vertical',   categoryLabel: '垂直线', description: '垂直方向的无限延伸直线' },
  { key: 'verticalRayLine',        label: '垂直射线',    icon: '↓',  category: 'vertical',   categoryLabel: '垂直线', description: '垂直方向的半无限线' },
  { key: 'verticalSegment',        label: '垂直线段',    icon: '┃',  category: 'vertical',   categoryLabel: '垂直线', description: '垂直方向的线段' },
  // ─── Fibonacci ────────────────
  { key: 'fibonacciLine',          label: '斐波那契回撤', icon: '⊞',  category: 'fibonacci',  categoryLabel: '斐波那契', description: '斐波那契回撤线 (0%, 23.6%, 38.2%, 50%, 61.8%, 78.6%, 100%)' },
  // ─── Channels ─────────────────
  { key: 'parallelStraightLine',   label: '平行通道',    icon: '⋕',  category: 'channels',   categoryLabel: '通道',   description: '两条平行线构成的通道' },
  { key: 'priceChannelLine',       label: '价格通道',    icon: '⧈',  category: 'channels',   categoryLabel: '通道',   description: '基于趋势的价格通道' },
  // ─── Annotations ──────────────
  { key: 'priceLine',              label: '价格线',      icon: '﹉',  category: 'annotations', categoryLabel: '标注',  description: '带价格标签的水平线' },
  { key: 'simpleAnnotation',       label: '标注',        icon: 'A',  category: 'annotations', categoryLabel: '标注',  description: '在图表上添加文字标注' },
  { key: 'simpleTag',              label: '标签',        icon: '⚑',  category: 'annotations', categoryLabel: '标注',  description: '在图表上添加标签' },
  // ─── Actions ──────────────────
  { key: 'eraser',                 label: '清除全部',    icon: '🗑', category: 'actions',    categoryLabel: '操作',   description: '清除所有画线' },
];

/** Default enabled tools (a reasonable starter set) */
export const DEFAULT_ENABLED_TOOLS: DrawingTool[] = [
  'cursor', 'crosshair',
  'segment', 'rayLine',
  'horizontalStraightLine',
  'verticalStraightLine',
  'fibonacciLine',
  'parallelStraightLine',
  'priceLine', 'simpleAnnotation',
  'eraser',
];

const CATEGORY_ORDER: ToolCategory[] = [
  'cursor', 'lines', 'horizontal', 'vertical', 'fibonacci', 'channels', 'annotations', 'actions',
];

/* ═══════════════════════════════════════════
   Sidebar Component
   ═══════════════════════════════════════════ */

interface DrawingToolsSidebarProps {
  visible: boolean;
  activeTool: DrawingTool;
  onToolSelect: (tool: DrawingTool) => void;
  enabledTools: DrawingTool[];
  onOpenSettings: () => void;
}

export default function DrawingToolsSidebar({
  visible, activeTool, onToolSelect, enabledTools, onOpenSettings,
}: DrawingToolsSidebarProps) {
  const [hoveredTool, setHoveredTool] = useState<DrawingTool | null>(null);

  const visibleTools = useMemo(() => {
    const enabledSet = new Set(enabledTools);
    return ALL_DRAWING_TOOLS.filter((t) => enabledSet.has(t.key));
  }, [enabledTools]);

  const groupedTools = useMemo(() => {
    const map: Record<string, DrawingToolConfig[]> = {};
    for (const tool of visibleTools) {
      if (!map[tool.category]) map[tool.category] = [];
      map[tool.category].push(tool);
    }
    return map;
  }, [visibleTools]);

  if (!visible) return null;

  return (
    <View style={ds.sidebar}>
      <ScrollView
        style={ds.scrollArea}
        contentContainerStyle={ds.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {CATEGORY_ORDER.map((cat) => {
          const tools = groupedTools[cat];
          if (!tools || tools.length === 0) return null;
          return (
            <View key={cat} style={ds.group}>
              {tools.map((tool) => {
                const isActive = activeTool === tool.key;
                return (
                  <View key={tool.key} style={{ position: 'relative' as any }}>
                    <TouchableOpacity
                      style={[ds.toolBtn, isActive && ds.toolBtnActive]}
                      onPress={() => onToolSelect(tool.key)}
                      activeOpacity={0.7}
                      {...(Platform.OS === 'web' ? {
                        onMouseEnter: () => setHoveredTool(tool.key),
                        onMouseLeave: () => setHoveredTool(null),
                      } as any : {})}
                    >
                      <Text style={[
                        ds.toolIcon,
                        isActive && ds.toolIconActive,
                        tool.key === 'eraser' && ds.toolIconDanger,
                      ]}>
                        {tool.icon}
                      </Text>
                    </TouchableOpacity>
                    {hoveredTool === tool.key && (
                      <View style={ds.tooltip}>
                        <Text style={ds.tooltipText}>{tool.label}</Text>
                      </View>
                    )}
                  </View>
                );
              })}
              {cat !== 'actions' && <View style={ds.divider} />}
            </View>
          );
        })}
      </ScrollView>

      {/* Settings button at bottom */}
      <View style={ds.settingsArea}>
        <View style={ds.divider} />
        <TouchableOpacity
          style={ds.settingsBtn}
          onPress={onOpenSettings}
          activeOpacity={0.7}
          {...(Platform.OS === 'web' ? {
            onMouseEnter: () => setHoveredTool('cursor'), // reuse hover state
            onMouseLeave: () => setHoveredTool(null),
          } as any : {})}
        >
          <Text style={ds.settingsIcon}>⚙</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

/* ═══════════════════════════════════════════
   Settings Panel Component
   ═══════════════════════════════════════════ */

interface DrawingToolsSettingsProps {
  visible: boolean;
  enabledTools: DrawingTool[];
  onToggleTool: (tool: DrawingTool) => void;
  onResetDefaults: () => void;
  onClose: () => void;
}

export function DrawingToolsSettings({
  visible, enabledTools, onToggleTool, onResetDefaults, onClose,
}: DrawingToolsSettingsProps) {
  if (!visible) return null;

  const enabledSet = new Set(enabledTools);

  // Group all tools by category
  const grouped: Record<string, DrawingToolConfig[]> = {};
  for (const tool of ALL_DRAWING_TOOLS) {
    if (tool.key === 'cursor' || tool.key === 'crosshair' || tool.key === 'eraser') continue; // always shown
    if (!grouped[tool.category]) grouped[tool.category] = [];
    grouped[tool.category].push(tool);
  }

  const categories = CATEGORY_ORDER.filter((c) => grouped[c]);

  return (
    <View style={sp.overlay}>
      <TouchableOpacity style={sp.backdrop} onPress={onClose} activeOpacity={1} />
      <View style={sp.panel}>
        {/* Header */}
        <View style={sp.header}>
          <Text style={sp.title}>画线工具设置</Text>
          <TouchableOpacity onPress={onClose} hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}>
            <Text style={sp.closeBtn}>✕</Text>
          </TouchableOpacity>
        </View>

        {/* Description */}
        <View style={sp.descRow}>
          <Text style={sp.descText}>选择需要显示在工具栏中的画线工具</Text>
          <TouchableOpacity onPress={onResetDefaults} activeOpacity={0.7}>
            <Text style={sp.resetBtn}>恢复默认</Text>
          </TouchableOpacity>
        </View>

        {/* Always-on tools notice */}
        <View style={sp.alwaysOnRow}>
          <Text style={sp.alwaysOnText}>↖ 选择、＋ 十字准线、🗑 清除 始终显示</Text>
        </View>

        {/* Tool list */}
        <ScrollView style={sp.list} showsVerticalScrollIndicator={false}>
          {categories.map((cat) => {
            const tools = grouped[cat];
            if (!tools) return null;
            const catLabel = tools[0].categoryLabel;
            return (
              <View key={cat}>
                <Text style={sp.categoryLabel}>{catLabel}</Text>
                {tools.map((tool) => {
                  const isEnabled = enabledSet.has(tool.key);
                  return (
                    <TouchableOpacity
                      key={tool.key}
                      style={sp.toolRow}
                      onPress={() => onToggleTool(tool.key)}
                      activeOpacity={0.6}
                    >
                      <Text style={sp.toolIcon}>{tool.icon}</Text>
                      <View style={sp.toolInfo}>
                        <Text style={[sp.toolName, isEnabled && sp.toolNameEnabled]}>
                          {tool.label}
                        </Text>
                        <Text style={sp.toolDesc}>{tool.description}</Text>
                      </View>
                      <View style={[sp.toggle, isEnabled && sp.toggleEnabled]}>
                        <View style={[sp.toggleDot, isEnabled && sp.toggleDotEnabled]} />
                      </View>
                    </TouchableOpacity>
                  );
                })}
              </View>
            );
          })}
          <View style={{ height: 40 }} />
        </ScrollView>
      </View>
    </View>
  );
}

/* ═══════════════════════════════════════════
   Styles
   ═══════════════════════════════════════════ */

const ds = StyleSheet.create({
  sidebar: {
    width: 42,
    backgroundColor: '#111',
    borderRightWidth: 1,
    borderRightColor: 'rgba(77,70,53,0.2)',
    justifyContent: 'space-between',
  },
  scrollArea: {
    flex: 1,
  },
  scrollContent: {
    paddingVertical: 6,
    alignItems: 'center',
  },
  group: {
    alignItems: 'center',
    gap: 1,
  },
  divider: {
    width: 26,
    height: 1,
    backgroundColor: 'rgba(77,70,53,0.25)',
    marginVertical: 5,
    alignSelf: 'center',
  },
  toolBtn: {
    width: 34,
    height: 34,
    borderRadius: 6,
    justifyContent: 'center',
    alignItems: 'center',
  },
  toolBtnActive: {
    backgroundColor: 'rgba(242,202,80,0.18)',
  },
  toolIcon: {
    fontSize: 15,
    color: Colors.textMuted,
    fontWeight: '700',
  },
  toolIconActive: {
    color: Colors.primary,
  },
  toolIconDanger: {
    color: '#EF5350',
  },
  tooltip: {
    position: 'absolute',
    left: 40,
    top: 4,
    backgroundColor: 'rgba(30,30,30,0.95)',
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 4,
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.3)',
    zIndex: 999,
  } as any,
  tooltipText: {
    color: Colors.textActive,
    fontSize: 11,
    fontWeight: '500',
    whiteSpace: 'nowrap',
  } as any,
  settingsArea: {
    alignItems: 'center',
    paddingBottom: 6,
  },
  settingsBtn: {
    width: 34,
    height: 34,
    borderRadius: 6,
    justifyContent: 'center',
    alignItems: 'center',
  },
  settingsIcon: {
    fontSize: 16,
    color: Colors.textMuted,
  },
});

const sp = StyleSheet.create({
  overlay: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    zIndex: 250,
  },
  backdrop: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  panel: {
    position: 'absolute',
    top: 0, left: 0, bottom: 0,
    width: 380,
    backgroundColor: '#131313',
    borderRightWidth: 1,
    borderRightColor: Colors.border,
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
  descRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.15)',
  },
  descText: {
    color: Colors.textMuted,
    fontSize: 11,
    flex: 1,
  },
  resetBtn: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '600',
    paddingLeft: 12,
  },
  alwaysOnRow: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: 'rgba(242,202,80,0.05)',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.15)',
  },
  alwaysOnText: {
    color: Colors.textMuted,
    fontSize: 10,
    fontStyle: 'italic',
  },
  list: {
    flex: 1,
  },
  categoryLabel: {
    fontSize: 11,
    color: Colors.primary,
    fontWeight: '600',
    letterSpacing: 0.5,
    paddingHorizontal: 16,
    paddingTop: 14,
    paddingBottom: 6,
  },
  toolRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 11,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(42,42,42,0.3)',
    gap: 12,
  },
  toolIcon: {
    width: 24,
    fontSize: 16,
    textAlign: 'center',
    color: Colors.textMuted,
  },
  toolInfo: {
    flex: 1,
    gap: 2,
  },
  toolName: {
    color: Colors.textActive,
    fontSize: 13,
    fontWeight: '600',
  },
  toolNameEnabled: {
    color: Colors.primary,
  },
  toolDesc: {
    color: Colors.textMuted,
    fontSize: 10,
  },
  toggle: {
    width: 36,
    height: 20,
    borderRadius: 10,
    backgroundColor: 'rgba(60,60,60,0.8)',
    justifyContent: 'center',
    paddingHorizontal: 2,
  },
  toggleEnabled: {
    backgroundColor: 'rgba(242,202,80,0.3)',
  },
  toggleDot: {
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: '#666',
    alignSelf: 'flex-start',
  },
  toggleDotEnabled: {
    backgroundColor: Colors.primary,
    alignSelf: 'flex-end',
  },
});
