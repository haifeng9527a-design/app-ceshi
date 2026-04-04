import { useState, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Alert,
  TextInput,
  useWindowDimensions,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Shadows } from '../../theme/colors';
import EquityCurve from '../../components/chart/EquityCurve';
import { useAuthStore } from '../../services/store/authStore';
import {
  getTraderProfile,
  getTraderPositions,
  getTraderTrades,
  followTrader,
  unfollowTrader,
  getMyFollowing,
  TraderProfile,
  TraderPosition,
  CopyTrading,
} from '../../services/api/traderApi';

export default function TraderDetailScreen() {
  const { uid } = useLocalSearchParams<{ uid: string }>();
  const { t } = useTranslation();
  const router = useRouter();
  const { user } = useAuthStore();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;

  const [profile, setProfile] = useState<TraderProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [following, setFollowing] = useState(false);
  const [showFollowModal, setShowFollowModal] = useState(false);
  const [copyRatio, setCopyRatio] = useState('1.0');
  const [actionLoading, setActionLoading] = useState(false);
  const [positions, setPositions] = useState<TraderPosition[]>([]);
  const [trades, setTrades] = useState<TraderPosition[]>([]);
  const isSelf = user?.uid === uid;

  useEffect(() => {
    if (!uid) return;
    (async () => {
      try {
        const [p, myFollowing, pos, trd] = await Promise.all([
          getTraderProfile(uid),
          user && !isSelf ? getMyFollowing().catch(() => []) : Promise.resolve([]),
          getTraderPositions(uid).catch(() => []),
          getTraderTrades(uid).catch(() => []),
        ]);
        setProfile(p);
        setPositions(pos);
        setTrades(trd);
        if (!isSelf) {
          setFollowing(myFollowing.some((f: CopyTrading) => f.trader_id === uid && f.status === 'active'));
        }
      } catch {
        // profile not found
      } finally {
        setLoading(false);
      }
    })();
  }, [uid, user]);

  const handleFollow = async () => {
    if (!user) {
      Alert.alert('', t('auth.notLoggedIn'));
      return;
    }
    setActionLoading(true);
    try {
      await followTrader(uid!, { copy_ratio: parseFloat(copyRatio) || 1.0 });
      setFollowing(true);
      setShowFollowModal(false);
    } catch (e: any) {
      Alert.alert('Error', e.response?.data?.error || e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleUnfollow = async () => {
    setActionLoading(true);
    try {
      await unfollowTrader(uid!);
      setFollowing(false);
    } catch (e: any) {
      Alert.alert('Error', e.response?.data?.error || e.message);
    } finally {
      setActionLoading(false);
    }
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
        <TouchableOpacity onPress={() => router.back()} style={{ marginTop: 16 }}>
          <Text style={styles.backLinkText}>← {t('common.back') || 'Back'}</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const stats = profile.stats;
  const pnl = stats?.total_pnl || 0;
  const winRate = stats?.win_rate || 0;
  const maxDD = stats?.max_drawdown || 0;
  const followers = stats?.followers_count || 0;
  const totalTrades = stats?.total_trades || 0;

  return (
    <View style={styles.container}>
      <ScrollView contentContainerStyle={[styles.scrollContent, isDesktop && { maxWidth: 960, alignSelf: 'center', width: '100%' }]}>
        {/* Back button */}
        <TouchableOpacity onPress={() => router.back()} style={styles.backRow}>
          <Text style={styles.backLinkText}>← {t('common.back') || 'Back'}</Text>
        </TouchableOpacity>

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
                <TouchableOpacity style={styles.followBtnOutline}>
                  <Text style={styles.followBtnOutlineText}>关注 Follow</Text>
                </TouchableOpacity>
                {profile.allow_copy_trading && user && (
                  following ? (
                    <TouchableOpacity
                      style={styles.unfollowBtn}
                      onPress={handleUnfollow}
                      disabled={actionLoading}
                    >
                      {actionLoading ? (
                        <ActivityIndicator color={Colors.down} size="small" />
                      ) : (
                        <Text style={styles.unfollowBtnText}>取消跟单</Text>
                      )}
                    </TouchableOpacity>
                  ) : (
                    <TouchableOpacity
                      style={styles.followBtn}
                      onPress={() => setShowFollowModal(true)}
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
            label="回报率 ROI"
            value={`+${(pnl / 10000 * 100).toFixed(1)}%`}
            color={Colors.up}
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
        <View style={[styles.rowGrid, isDesktop && styles.rowGridDesktop]}>
          {/* Equity Curve */}
          <View style={[isDesktop ? { flex: 1, minWidth: 0 } : {}]}>
            <EquityCurve totalPnl={pnl} totalTrades={totalTrades} />
          </View>

          {/* Risk Matrix + Sentiment */}
          <View style={[{ gap: 16 }, isDesktop && { width: 300, flexShrink: 0 }]}>
            {/* Risk Matrix */}
            <View style={[styles.glassCard, { marginBottom: 0 }]}>
              <Text style={styles.sectionTitle}>风险指数 Risk Matrix</Text>
              <View style={styles.riskHeader}>
                <View>
                  <Text style={styles.riskScore}>
                    {maxDD <= 10 ? '15' : maxDD <= 20 ? '28' : '60'}
                    <Text style={styles.riskScoreUnit}>/100</Text>
                  </Text>
                  <Text style={styles.riskLabel}>
                    {maxDD <= 10 ? 'CONSERVATIVE PROFILE' : maxDD <= 20 ? 'MODERATE PROFILE' : 'AGGRESSIVE PROFILE'}
                  </Text>
                </View>
                <Text style={styles.shieldIcon}>🛡</Text>
              </View>
              <View style={styles.riskMetrics}>
                <RiskBar label="夏普比率 Sharpe Ratio" value={winRate > 60 ? '2.4' : winRate > 40 ? '1.2' : '0.6'} pct={winRate > 60 ? 75 : winRate > 40 ? 45 : 20} />
                <RiskBar label="波动率 Volatility" value={maxDD <= 10 ? 'Low' : maxDD <= 20 ? 'Med' : 'High'} pct={maxDD <= 10 ? 25 : maxDD <= 20 ? 55 : 80} />
              </View>
              <View style={styles.riskNote}>
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

        {/* Follow Modal */}
        {showFollowModal && (
          <View style={styles.followModalOverlay}>
            <View style={styles.followModal}>
              <Text style={styles.followModalTitle}>跟单设置 Copy Trading</Text>
              <Text style={styles.followModalSubtitle}>设定跟单比例</Text>
              <TextInput
                style={styles.ratioInput}
                value={copyRatio}
                onChangeText={setCopyRatio}
                keyboardType="numeric"
                placeholder="1.0"
                placeholderTextColor={Colors.textMuted}
              />
              <View style={styles.followModalBtns}>
                <TouchableOpacity
                  style={styles.cancelBtn}
                  onPress={() => setShowFollowModal(false)}
                >
                  <Text style={styles.cancelBtnText}>取消</Text>
                </TouchableOpacity>
                <TouchableOpacity
                  style={styles.confirmBtn}
                  onPress={handleFollow}
                  disabled={actionLoading}
                >
                  {actionLoading ? (
                    <ActivityIndicator color={Colors.textOnPrimary} size="small" />
                  ) : (
                    <Text style={styles.confirmBtnText}>确认跟单</Text>
                  )}
                </TouchableOpacity>
              </View>
            </View>
          </View>
        )}
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
  followBtnOutlineText: { color: Colors.textSecondary, fontSize: 14, fontWeight: '600' },
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

  // ── Follow Modal ──
  followModalOverlay: {
    backgroundColor: Colors.surface,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: Colors.primaryBorder,
    padding: 24,
    marginBottom: 16,
  },
  followModal: {},
  followModalTitle: { color: Colors.textActive, fontSize: 18, fontWeight: '700', marginBottom: 4 },
  followModalSubtitle: { color: Colors.textMuted, fontSize: 13, marginBottom: 16 },
  ratioInput: {
    backgroundColor: Colors.background,
    borderWidth: 1,
    borderColor: Colors.border,
    borderRadius: 10,
    padding: 14,
    color: Colors.textActive,
    fontSize: 16,
    marginBottom: 16,
  },
  followModalBtns: { flexDirection: 'row', gap: 12 },
  cancelBtn: {
    flex: 1,
    borderWidth: 1,
    borderColor: Colors.border,
    paddingVertical: 14,
    borderRadius: 10,
    alignItems: 'center',
  },
  cancelBtnText: { color: Colors.textSecondary, fontSize: 15, fontWeight: '600' },
  confirmBtn: {
    flex: 1,
    backgroundColor: Colors.primary,
    paddingVertical: 14,
    borderRadius: 10,
    alignItems: 'center',
    ...Shadows.glow,
  },
  confirmBtnText: { color: Colors.textOnPrimary, fontSize: 15, fontWeight: '700' },
});
