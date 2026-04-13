import { useState, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Alert,
  useWindowDimensions,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Shadows } from '../../theme/colors';
import EquityCurve from '../chart/EquityCurve';
import { useAuthStore } from '../../services/store/authStore';
import {
  getTraderProfile,
  getTraderPositions,
  getTraderTrades,
  followTrader,
  unfollowTrader,
  getMyFollowing,
  pauseCopyTrading,
  resumeCopyTrading,
  updateCopySettings,
  watchTrader,
  unwatchTrader,
  TraderProfile,
  TraderPosition,
  CopyTrading,
  FollowTraderRequest,
} from '../../services/api/traderApi';
import CopySettingsModal from './CopySettingsModal';
import {
  getTraderStrategies,
  TraderStrategy,
} from '../../services/api/traderStrategyApi';

interface Props {
  uid: string;
  onClose?: () => void;
  embedded?: boolean;
}

export default function TraderDetailPanel({ uid, onClose, embedded }: Props) {
  const { t } = useTranslation();
  const router = useRouter();
  const { user } = useAuthStore();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;

  const [profile, setProfile] = useState<TraderProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [following, setFollowing] = useState(false);
  const [copySettings, setCopySettings] = useState<CopyTrading | undefined>(undefined);
  const [showCopySettings, setShowCopySettings] = useState(false);
  const [editMode, setEditMode] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);
  const [positions, setPositions] = useState<TraderPosition[]>([]);
  const [trades, setTrades] = useState<TraderPosition[]>([]);
  const [strategies, setStrategies] = useState<TraderStrategy[]>([]);
  const [isWatched, setIsWatched] = useState(false);
  const [watchLoading, setWatchLoading] = useState(false);
  const isSelf = user?.uid === uid;

  useEffect(() => {
    if (!uid) return;
    setLoading(true);
    (async () => {
      try {
        const [p, myFollowing, pos, trd, strats] = await Promise.all([
          getTraderProfile(uid),
          user && !isSelf ? getMyFollowing().catch(() => []) : Promise.resolve([]),
          getTraderPositions(uid).catch(() => []),
          getTraderTrades(uid).catch(() => []),
          getTraderStrategies(uid, 10).catch(() => ({ strategies: [] })),
        ]);
        setProfile(p);
        setPositions(pos);
        setTrades(trd);
        setStrategies(strats.strategies || []);
        setIsWatched(!!p.is_followed);
        if (!isSelf) {
          const myCopy = myFollowing.find((f: CopyTrading) => f.trader_id === uid && (f.status === 'active' || f.status === 'paused'));
          setFollowing(!!myCopy);
          setCopySettings(myCopy || undefined);
        }
      } catch {
      } finally {
        setLoading(false);
      }
    })();
  }, [uid, user]);

  const handleCopySubmit = async (settings: FollowTraderRequest) => {
    if (!user) { Alert.alert('', t('auth.notLoggedIn')); return; }
    setActionLoading(true);
    try {
      if (editMode && copySettings) {
        const updated = await updateCopySettings(uid, settings);
        setCopySettings(updated);
      } else {
        const created = await followTrader(uid, settings);
        setCopySettings(created);
        setFollowing(true);
      }
      setShowCopySettings(false);
      setEditMode(false);
    } catch (e: any) {
      Alert.alert('Error', e.response?.data?.error || e.message);
    } finally { setActionLoading(false); }
  };

  const handleUnfollow = async () => {
    setActionLoading(true);
    try {
      await unfollowTrader(uid);
      setFollowing(false);
      setCopySettings(undefined);
    } catch (e: any) {
      Alert.alert('Error', e.response?.data?.error || e.message);
    } finally { setActionLoading(false); }
  };

  const handlePauseResume = async () => {
    if (!copySettings) return;
    setActionLoading(true);
    try {
      if (copySettings.status === 'active') {
        await pauseCopyTrading(uid);
        setCopySettings({ ...copySettings, status: 'paused' });
      } else {
        await resumeCopyTrading(uid);
        setCopySettings({ ...copySettings, status: 'active' });
      }
    } catch (e: any) {
      Alert.alert('Error', e.response?.data?.error || e.message);
    } finally { setActionLoading(false); }
  };

  const handleToggleWatch = async () => {
    if (!user) { Alert.alert('', t('auth.notLoggedIn')); return; }
    setWatchLoading(true);
    try {
      if (isWatched) {
        await unwatchTrader(uid);
        setIsWatched(false);
      } else {
        await watchTrader(uid);
        setIsWatched(true);
      }
    } catch (e: any) {
      Alert.alert('Error', e.response?.data?.error || e.message);
    } finally { setWatchLoading(false); }
  };

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

  if (!profile) {
    return (
      <View style={styles.centered}>
        <Text style={styles.errorText}>Trader not found</Text>
        {onClose && (
          <TouchableOpacity onPress={onClose} style={{ marginTop: 16 }}>
            <Text style={styles.backLinkText}>← 返回排行榜</Text>
          </TouchableOpacity>
        )}
      </View>
    );
  }

  const stats = profile.stats;
  const pnl = stats?.total_pnl || 0;
  const winRate = stats?.win_rate || 0;
  const maxDD = stats?.max_drawdown || 0;
  const followers = stats?.followers_count || 0;
  const totalTrades = stats?.total_trades || 0;
  const avgPnl = stats?.avg_pnl || 0;

  // Calculate risk score from multiple factors
  const riskScore = Math.min(100, Math.max(0,
    Math.round(maxDD * 2 + (100 - winRate) * 0.3 + (totalTrades < 10 ? 20 : 0))
  ));
  const riskLevel = riskScore <= 30 ? 'CONSERVATIVE' : riskScore <= 60 ? 'MODERATE' : 'AGGRESSIVE';

  // Sharpe Ratio: normalized to -3..3 range
  const sharpeRatio = totalTrades > 0
    ? Math.min(3.0, Math.max(-3.0, (avgPnl / (Math.abs(avgPnl) + Math.abs(maxDD) + 100)) * 3)).toFixed(1)
    : '0.0';
  const sharpePct = Math.min(100, Math.max(0, parseFloat(sharpeRatio) / 3 * 100));

  // Volatility from maxDD
  const volLevel = maxDD <= 5 ? 'Low' : maxDD <= 15 ? 'Medium' : maxDD <= 30 ? 'High' : 'Extreme';
  const volPct = Math.min(100, maxDD * 3);

  return (
    <View style={styles.container}>
      <ScrollView contentContainerStyle={[styles.scrollContent, isDesktop && { maxWidth: 960, alignSelf: 'center', width: '100%' }]}>
        {/* Back button */}
        {onClose && (
          <TouchableOpacity onPress={onClose} style={styles.backRow}>
            <Text style={styles.backLinkText}>← 返回排行榜</Text>
          </TouchableOpacity>
        )}

        {/* Profile Header */}
        <View style={styles.headerCard}>
          <View style={[styles.headerContent, isDesktop && styles.headerContentDesktop]}>
            <View style={[styles.headerLeft, isDesktop && styles.headerLeftDesktop]}>
              <View style={styles.avatarContainer}>
                <View style={styles.avatar}>
                  <Text style={styles.avatarText}>
                    {(profile.display_name || '?')[0].toUpperCase()}
                  </Text>
                </View>
                {profile.is_trader && (
                  <View style={styles.eliteBadge}>
                    <Text style={styles.eliteBadgeText}>ELITE</Text>
                  </View>
                )}
              </View>
              <View style={styles.headerInfo}>
                <View style={styles.nameRow}>
                  <Text style={styles.profileName}>{profile.display_name}</Text>
                  {profile.is_trader && (
                    <Text style={styles.verifiedIcon}>✓</Text>
                  )}
                </View>
                {isSelf && (
                  <Text style={styles.selfLabel}>我的交易员主页</Text>
                )}
                <View style={styles.tagsRow}>
                  {profile.allow_copy_trading && (
                    <View style={styles.tag}>
                      <Text style={styles.tagText}>COPY TRADING</Text>
                    </View>
                  )}
                  <View style={styles.tag}>
                    <Text style={styles.tagText}>SWING</Text>
                  </View>
                  <View style={styles.tag}>
                    <Text style={styles.tagText}>LOW RISK</Text>
                  </View>
                </View>
              </View>
            </View>

            {/* Action Buttons (not self) */}
            {!isSelf && (
              <View style={[styles.headerActions, isDesktop && styles.headerActionsDesktop]}>
                <TouchableOpacity
                  style={[styles.followBtnOutline, isWatched && styles.followBtnOutlineActive]}
                  onPress={handleToggleWatch}
                  disabled={watchLoading}
                >
                  {watchLoading ? (
                    <ActivityIndicator color={Colors.primary} size="small" />
                  ) : (
                    <Text style={[styles.followBtnOutlineText, isWatched && styles.followBtnOutlineTextActive]}>
                      {isWatched ? '已关注 Following' : '关注 Follow'}
                    </Text>
                  )}
                </TouchableOpacity>
                {profile.allow_copy_trading && user && (
                  following ? (
                    <View style={styles.copyActionGroup}>
                      <TouchableOpacity
                        style={styles.copyActionBtn}
                        onPress={() => { setEditMode(true); setShowCopySettings(true); }}
                      >
                        <Text style={styles.copyActionBtnText}>修改设置</Text>
                      </TouchableOpacity>
                      <TouchableOpacity
                        style={[styles.copyActionBtn, copySettings?.status === 'paused' && styles.copyActionBtnActive]}
                        onPress={handlePauseResume}
                        disabled={actionLoading}
                      >
                        {actionLoading ? (
                          <ActivityIndicator color={Colors.textSecondary} size="small" />
                        ) : (
                          <Text style={[styles.copyActionBtnText, copySettings?.status === 'paused' && styles.copyActionBtnTextActive]}>
                            {copySettings?.status === 'paused' ? '恢复跟单' : '暂停跟单'}
                          </Text>
                        )}
                      </TouchableOpacity>
                      <TouchableOpacity
                        style={styles.unfollowBtn}
                        onPress={handleUnfollow}
                        disabled={actionLoading}
                      >
                        <Text style={styles.unfollowBtnText}>取消跟单</Text>
                      </TouchableOpacity>
                    </View>
                  ) : (
                    <TouchableOpacity
                      style={styles.followBtn}
                      onPress={() => { setEditMode(false); setShowCopySettings(true); }}
                    >
                      <Text style={styles.followBtnText}>一键跟单 Copy Trading</Text>
                    </TouchableOpacity>
                  )
                )}
              </View>
            )}
          </View>
        </View>

        {/* Metrics Grid */}
        <View style={[styles.metricsGrid, isDesktop && styles.metricsGridDesktop]}>
          <MetricCard
            label="总盈亏 Total PnL"
            value={`${pnl >= 0 ? '+' : ''}$${formatMoney(pnl)}`}
            color={pnl >= 0 ? Colors.up : Colors.down}
            glow={pnl > 0}
          />
          <MetricCard
            label="平均盈亏 Avg PnL"
            value={`${avgPnl >= 0 ? '+' : ''}$${formatMoney(avgPnl)}`}
            color={avgPnl >= 0 ? Colors.up : Colors.down}
          />
          <MetricCard
            label="胜率 Win Rate"
            value={`${winRate.toFixed(1)}%`}
            color={winRate >= 50 ? Colors.textActive : Colors.down}
          />
          <MetricCard
            label="最大回撤 Max DD"
            value={`${maxDD.toFixed(1)}%`}
            color={Colors.down}
          />
          <MetricCard
            label="跟随人数 Followers"
            value={formatNumber(followers)}
          />
        </View>

        {/* Row 2: Equity Curve (left) + Risk Matrix & Sentiment (right) */}
        <View style={[styles.rowGrid, isDesktop && styles.rowGridDesktop, isDesktop && { alignItems: 'stretch' }]}>
          {/* Equity Curve */}
          <View style={[isDesktop ? { flex: 1, minWidth: 0 } : {}]}>
            <EquityCurve totalPnl={pnl} totalTrades={totalTrades} />
          </View>

          {/* Risk Matrix + Sentiment */}
          <View style={[{ gap: 12 }, isDesktop && { width: 340, flexShrink: 0 }]}>
            {/* Risk Matrix */}
            <View style={[styles.glassCard, { marginBottom: 0, flex: 1 }]}>
              <Text style={styles.sectionTitle}>风险指数 Risk Matrix</Text>
              <View style={styles.riskHeader}>
                <View>
                  <Text style={styles.riskScore}>
                    {riskScore}
                    <Text style={styles.riskScoreUnit}>/100</Text>
                  </Text>
                  <Text style={styles.riskLabel}>
                    {riskLevel} PROFILE
                  </Text>
                </View>
                <Text style={styles.shieldIcon}>🛡</Text>
              </View>
              <View style={styles.riskMetrics}>
                <RiskBar label="夏普比率 Sharpe Ratio" value={sharpeRatio} pct={sharpePct} />
                <RiskBar label="波动率 Volatility" value={volLevel} pct={volPct} />
              </View>
              <View style={[styles.riskNote, { flex: 1, justifyContent: 'flex-end' }]}>
                <Text style={styles.riskNoteText}>
                  {maxDD <= 15
                    ? '资金管理严格，近30日无大笔异常回撤。适合稳健型投资者。'
                    : '交易风格较为激进，适合风险承受能力较强的投资者。'}
                </Text>
              </View>
            </View>

            {/* Market Sentiment */}
            <View style={[styles.glassCard, styles.sentimentCardWrapper, { marginBottom: 0 }]}>
              <View style={styles.sentimentRow}>
                <View style={styles.sentimentIcon}>
                  <Text style={{ fontSize: 22 }}>📈</Text>
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={styles.sentimentLabel}>当前情绪 Market Sentiment</Text>
                  <Text style={styles.sentimentValue}>
                    {pnl > 0 ? '强力看涨 Strong Bullish' : '谨慎观望 Neutral'}
                  </Text>
                </View>
              </View>
            </View>
          </View>
        </View>

        {/* Published Strategies */}
        {strategies.length > 0 && (
          <View style={styles.glassCard}>
            <View style={styles.sectionHeader}>
              <View style={styles.sectionTitleRow}>
                <Text style={styles.sectionTitleIcon}>📝</Text>
                <Text style={[styles.sectionTitle, { marginBottom: 0 }]}>策略文章 Strategies</Text>
              </View>
              <View style={styles.activeBadge}>
                <Text style={styles.activeBadgeText}>{strategies.length} ARTICLES</Text>
              </View>
            </View>
            {strategies.map((s) => {
              const date = new Date(s.created_at).toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' });
              const categoryLabels: Record<string, string> = {
                technical: '技术分析', fundamental: '基本面', macro: '宏观经济',
                news: '市场资讯', education: '交易教学', other: '其他',
              };
              return (
                <TouchableOpacity
                  key={s.id}
                  style={styles.strategyItem}
                  onPress={() => router.push(`/strategy/${s.id}` as any)}
                >
                  <View style={{ flex: 1 }}>
                    <Text style={styles.strategyTitle} numberOfLines={1}>{s.title}</Text>
                    {s.summary ? (
                      <Text style={styles.strategySummary} numberOfLines={2}>{s.summary}</Text>
                    ) : null}
                    <View style={styles.strategyMeta}>
                      <View style={styles.strategyCategoryTag}>
                        <Text style={styles.strategyCategoryText}>{categoryLabels[s.category] || s.category}</Text>
                      </View>
                      <Text style={styles.strategyMetaText}>{date}</Text>
                      <Text style={styles.strategyMetaText}>👁 {s.views}</Text>
                      <Text style={styles.strategyMetaText}>❤️ {s.likes}</Text>
                    </View>
                  </View>
                  {s.cover_image ? (
                    <View style={styles.strategyCover}>
                      <Text style={{ fontSize: 20 }}>📄</Text>
                    </View>
                  ) : null}
                </TouchableOpacity>
              );
            })}
          </View>
        )}

        {/* Row 3: Open Positions (left) + Recent Trades (right) */}
        <View style={[styles.rowGrid, isDesktop && styles.rowGridDesktop]}>
          {/* Open Positions */}
          <View style={[styles.glassCard, { marginBottom: isDesktop ? 0 : 16 }, isDesktop && { flex: 1, minWidth: 0 }]}>
            <View style={styles.sectionHeader}>
              <View style={styles.sectionTitleRow}>
                <Text style={styles.sectionTitleIcon}>📊</Text>
                <Text style={[styles.sectionTitle, { marginBottom: 0 }]}>当前持仓 Open Positions</Text>
              </View>
              {positions.length > 0 && (
                <View style={styles.activeBadge}>
                  <Text style={styles.activeBadgeText}>{positions.length} ACTIVE</Text>
                </View>
              )}
            </View>

            {positions.length === 0 ? (
              <Text style={styles.emptyText}>暂无持仓</Text>
            ) : (
              <>
                <View style={styles.tableHeader}>
                  <Text style={[styles.tableHeaderText, { flex: 2 }]}>交易对 PAIR</Text>
                  <Text style={[styles.tableHeaderText, { flex: 1.5 }]}>入场 ENTRY</Text>
                  <Text style={[styles.tableHeaderText, { flex: 1.5 }]}>当前 CURRENT</Text>
                  <Text style={[styles.tableHeaderText, { flex: 1, textAlign: 'right' }]}>盈亏 PNL</Text>
                </View>
                {positions.map((pos) => {
                  const upnl = pos.unrealized_pnl || 0;
                  return (
                    <View key={pos.id} style={styles.tableRow}>
                      <View style={{ flex: 2, flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                        <View style={styles.pairIcon}>
                          <Text style={styles.pairIconText}>{pos.symbol[0]}</Text>
                        </View>
                        <View>
                          <Text style={styles.pairName}>{pos.symbol}</Text>
                          <Text style={[styles.pairSide, { color: pos.side === 'long' ? Colors.up : Colors.down }]}>
                            {pos.side.toUpperCase()} {pos.leverage}x
                          </Text>
                        </View>
                      </View>
                      <Text style={[styles.tableCell, { flex: 1.5 }]}>${formatMoney(pos.entry_price)}</Text>
                      <Text style={[styles.tableCell, { flex: 1.5 }]}>${formatMoney(pos.current_price)}</Text>
                      <Text style={[styles.tableCell, { flex: 1, textAlign: 'right', color: upnl >= 0 ? Colors.up : Colors.down, fontWeight: '700' }]}>
                        {upnl >= 0 ? '+' : ''}${formatMoney(upnl)}
                      </Text>
                    </View>
                  );
                })}
              </>
            )}
          </View>

          {/* Recent Trades */}
          <View style={[styles.glassCard, { marginBottom: 0 }, isDesktop && { flex: 1, minWidth: 0 }]}>
            <View style={styles.sectionHeader}>
              <View style={styles.sectionTitleRow}>
                <Text style={styles.sectionTitleIcon}>🕐</Text>
                <Text style={[styles.sectionTitle, { marginBottom: 0 }]}>最近成交 Recent Trades</Text>
              </View>
              <TouchableOpacity>
                <Text style={styles.viewAllText}>VIEW ALL</Text>
              </TouchableOpacity>
            </View>

            {trades.length === 0 ? (
              <Text style={styles.emptyText}>暂无成交记录</Text>
            ) : (
              <>
                <View style={styles.tableHeader}>
                  <Text style={[styles.tableHeaderText, { flex: 2 }]}>操作 ACTION</Text>
                  <Text style={[styles.tableHeaderText, { flex: 2 }]}>时间 TIME</Text>
                  <Text style={[styles.tableHeaderText, { flex: 1, textAlign: 'right' }]}>已实现 PNL</Text>
                </View>
                {trades.map((trade) => {
                  const rpnl = trade.realized_pnl || 0;
                  const closeType = rpnl > 0 ? 'TAKE PROFIT' : rpnl < 0 ? 'STOP LOSS' : 'CLOSE';
                  const closedTime = trade.closed_at ? new Date(trade.closed_at).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }) : '';
                  return (
                    <View key={trade.id} style={styles.tableRow}>
                      <View style={{ flex: 2 }}>
                        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                          <View style={[styles.tradeDot, { backgroundColor: rpnl >= 0 ? Colors.up : Colors.down }]} />
                          <Text style={styles.tradeAction}>{trade.side === 'long' ? 'SELL' : 'BUY'} {trade.symbol}</Text>
                        </View>
                        <Text style={styles.tradeType}>{closeType}</Text>
                      </View>
                      <Text style={[styles.tableCell, { flex: 2 }]}>{closedTime}</Text>
                      <Text style={[styles.tableCell, { flex: 1, textAlign: 'right', color: rpnl >= 0 ? Colors.up : Colors.down, fontWeight: '700' }]}>
                        {rpnl >= 0 ? '+' : ''}${formatMoney(Math.abs(rpnl))}
                      </Text>
                    </View>
                  );
                })}
              </>
            )}
          </View>
        </View>

        {/* Copy Settings Modal */}
        <CopySettingsModal
          visible={showCopySettings}
          onClose={() => { setShowCopySettings(false); setEditMode(false); }}
          onSubmit={handleCopySubmit}
          initialSettings={editMode ? copySettings : undefined}
          traderName={profile.display_name}
        />
      </ScrollView>
    </View>
  );
}

/* ── Sub Components ── */

function MetricCard({ label, value, color, glow }: { label: string; value: string; color?: string; glow?: boolean }) {
  return (
    <View style={[styles.metricCard, glow && styles.metricCardGlow]}>
      <Text style={styles.metricLabel}>{label}</Text>
      <Text style={[styles.metricValue, color ? { color } : undefined]}>{value}</Text>
    </View>
  );
}

function RiskBar({ label, value, pct }: { label: string; value: string; pct: number }) {
  return (
    <View style={styles.riskBarContainer}>
      <View style={styles.riskBarHeader}>
        <Text style={styles.riskBarLabel}>{label}</Text>
        <Text style={styles.riskBarValue}>{value}</Text>
      </View>
      <View style={styles.riskBarTrack}>
        <View style={[styles.riskBarFill, { width: `${pct}%` }]} />
      </View>
    </View>
  );
}

function formatNumber(n: number): string {
  if (n >= 10000) return `${(n / 1000).toFixed(1)}K`;
  if (n >= 1000) return `${(n / 1000).toFixed(1)}K`;
  return String(n);
}

function formatMoney(n: number): string {
  return n.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/* ── Styles ── */

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: Colors.background },
  centered: {
    flex: 1,
    backgroundColor: Colors.background,
    justifyContent: 'center',
    alignItems: 'center',
  },
  errorText: { color: Colors.textMuted, fontSize: 16 },
  scrollContent: { padding: 16, paddingBottom: 60 },

  backRow: { paddingVertical: 8, marginBottom: 8 },
  backLinkText: { color: Colors.primary, fontSize: 14, fontWeight: '600' },

  // ── Header Card ──
  headerCard: {
    backgroundColor: Colors.surface,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: 20,
    marginBottom: 16,
    ...Shadows.card,
  },
  headerContent: {},
  headerContentDesktop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
    marginBottom: 16,
  },
  headerLeftDesktop: { marginBottom: 0 },
  avatarContainer: { position: 'relative' },
  avatar: {
    width: 72,
    height: 72,
    borderRadius: 14,
    backgroundColor: Colors.surfaceAlt,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: Colors.primaryBorder,
  },
  avatarText: { color: Colors.primary, fontSize: 28, fontWeight: '800' },
  eliteBadge: {
    position: 'absolute',
    bottom: -6,
    right: -6,
    backgroundColor: Colors.primary,
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 8,
    ...Shadows.glow,
  },
  eliteBadgeText: { color: Colors.textOnPrimary, fontSize: 8, fontWeight: '800', letterSpacing: 1 },
  headerInfo: { flex: 1 },
  nameRow: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 4 },
  profileName: { color: Colors.textActive, fontSize: 24, fontWeight: '800', letterSpacing: -0.5 },
  verifiedIcon: {
    color: Colors.primary,
    fontSize: 14,
    fontWeight: '800',
    backgroundColor: Colors.primaryDim,
    width: 20,
    height: 20,
    borderRadius: 10,
    textAlign: 'center',
    lineHeight: 20,
    overflow: 'hidden',
  },
  selfLabel: {
    color: Colors.textMuted,
    fontSize: 12,
    marginBottom: 8,
  },
  tagsRow: { flexDirection: 'row', gap: 6, flexWrap: 'wrap' },
  tag: {
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  tagText: {
    color: Colors.textSecondary,
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 1.5,
  },

  headerActions: { flexDirection: 'row', gap: 10 },
  headerActionsDesktop: {},
  followBtnOutline: {
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 10,
  },
  followBtnOutlineActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  followBtnOutlineText: { color: Colors.textSecondary, fontSize: 14, fontWeight: '600' },
  followBtnOutlineTextActive: { color: Colors.primary },
  followBtn: {
    backgroundColor: Colors.primary,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 10,
    ...Shadows.glow,
  },
  followBtnText: { color: Colors.textOnPrimary, fontSize: 14, fontWeight: '700' },
  unfollowBtn: {
    borderWidth: 1,
    borderColor: Colors.borderLight,
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 10,
  },
  unfollowBtnText: { color: Colors.textSecondary, fontSize: 14, fontWeight: '600' },

  // ── Metrics Grid ──
  metricsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
    marginBottom: 16,
  },
  metricsGridDesktop: { flexWrap: 'nowrap' },
  metricCard: {
    backgroundColor: Colors.surface,
    borderRadius: 14,
    padding: 16,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    flex: 1,
    minWidth: 140,
  },
  metricCardGlow: {
    ...Shadows.glow,
  },
  metricLabel: {
    color: Colors.textMuted,
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
    marginBottom: 8,
  },
  metricValue: {
    color: Colors.textActive,
    fontSize: 22,
    fontWeight: '800',
    letterSpacing: -0.5,
  },

  // ── Row Grid ──
  rowGrid: { gap: 16, marginBottom: 16 },
  rowGridDesktop: { flexDirection: 'row' },

  // ── Glass Card ──
  glassCard: {
    backgroundColor: Colors.surface,
    borderRadius: 14,
    padding: 20,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    marginBottom: 16,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  sectionTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  sectionTitleIcon: { fontSize: 16 },
  sectionTitle: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '700',
    marginBottom: 16,
  },

  // ── Risk Matrix ──
  riskHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
    marginBottom: 20,
  },
  riskScore: {
    color: Colors.primary,
    fontSize: 36,
    fontWeight: '800',
    letterSpacing: -1,
  },
  riskScoreUnit: {
    color: Colors.textMuted,
    fontSize: 14,
    fontWeight: '400',
  },
  riskLabel: {
    color: Colors.textMuted,
    fontSize: 9,
    fontWeight: '600',
    letterSpacing: 1.5,
    textTransform: 'uppercase',
  },
  shieldIcon: { fontSize: 32, opacity: 0.4 },
  riskMetrics: { gap: 16 },
  riskBarContainer: {},
  riskBarHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 6,
  },
  riskBarLabel: { color: Colors.textSecondary, fontSize: 12 },
  riskBarValue: { color: Colors.textActive, fontSize: 12, fontWeight: '700' },
  riskBarTrack: {
    height: 5,
    backgroundColor: Colors.background,
    borderRadius: 3,
    overflow: 'hidden',
  },
  riskBarFill: {
    height: '100%',
    backgroundColor: Colors.primary,
    borderRadius: 3,
  },
  riskNote: {
    marginTop: 16,
    paddingTop: 12,
    borderTopWidth: 1,
    borderTopColor: Colors.border,
  },
  riskNoteText: {
    color: Colors.textMuted,
    fontSize: 11,
    lineHeight: 18,
  },

  // ── Sentiment ──
  sentimentCardWrapper: {
    backgroundColor: Colors.surfaceAlt,
  },
  sentimentRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  sentimentIcon: {
    width: 44,
    height: 44,
    borderRadius: 10,
    backgroundColor: Colors.upDim,
    justifyContent: 'center',
    alignItems: 'center',
  },
  sentimentLabel: {
    color: Colors.textMuted,
    fontSize: 10,
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: 2,
  },
  sentimentValue: { color: Colors.textActive, fontSize: 14, fontWeight: '700' },

  // ── Active Badge ──
  activeBadge: {
    backgroundColor: Colors.upDim,
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 6,
  },
  activeBadgeText: {
    color: Colors.up,
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: 1,
  },
  emptyText: {
    color: Colors.textMuted,
    fontSize: 13,
    textAlign: 'center',
    paddingVertical: 20,
  },
  viewAllText: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1,
  },

  // ── Table ──
  tableHeader: {
    flexDirection: 'row',
    paddingBottom: 10,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    marginBottom: 4,
  },
  tableHeaderText: {
    color: Colors.textMuted,
    fontSize: 9,
    fontWeight: '600',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  tableRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  tableCell: {
    color: Colors.textSecondary,
    fontSize: 13,
  },
  pairIcon: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: Colors.surfaceAlt,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: Colors.border,
  },
  pairIconText: { color: Colors.primary, fontSize: 13, fontWeight: '700' },
  pairName: { color: Colors.textActive, fontSize: 13, fontWeight: '700' },
  pairSide: { fontSize: 10, fontWeight: '600', letterSpacing: 0.5 },
  tradeDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
  },
  tradeAction: { color: Colors.textActive, fontSize: 13, fontWeight: '600' },
  tradeType: { color: Colors.textMuted, fontSize: 10, letterSpacing: 0.5, marginTop: 2, marginLeft: 12 },

  // ── Strategies ──
  strategyItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  strategyTitle: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '700',
    marginBottom: 4,
  },
  strategySummary: {
    color: Colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
    marginBottom: 6,
  },
  strategyMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  strategyCategoryTag: {
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 4,
  },
  strategyCategoryText: {
    color: Colors.primary,
    fontSize: 10,
    fontWeight: '600',
  },
  strategyMetaText: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  strategyCover: {
    width: 48,
    height: 48,
    borderRadius: 8,
    backgroundColor: Colors.surfaceAlt,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: Colors.border,
  },

  // ── Copy Action Buttons ──
  copyActionGroup: {
    flexDirection: 'row',
    gap: 8,
    flexWrap: 'wrap',
  },
  copyActionBtn: {
    borderWidth: 1,
    borderColor: Colors.border,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 10,
  },
  copyActionBtnActive: {
    borderColor: Colors.primaryBorder,
    backgroundColor: Colors.primaryDim,
  },
  copyActionBtnText: {
    color: Colors.textSecondary,
    fontSize: 13,
    fontWeight: '600',
  },
  copyActionBtnTextActive: {
    color: Colors.primary,
  },
});
