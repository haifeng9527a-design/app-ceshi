import { useState, useEffect, useCallback, useMemo } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Switch,
  RefreshControl,
  TextInput,
  Alert,
  useWindowDimensions,
  Image,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { Colors, Shadows } from '../../theme/colors';
import EquityCurve from '../../components/chart/EquityCurve';
import { useAuthStore } from '../../services/store/authStore';
import { useMarketStore } from '../../services/store/marketStore';
import { marketWs } from '../../services/websocket/marketWs';
import { Config } from '../../services/config';
import ApplicationForm from '../../components/trader/ApplicationForm';
import AppIcon from '../../components/ui/AppIcon';
import {
  getMyApplication,
  getMyStats,
  getMyFollowers,
  getTraderPositions,
  getTraderTrades,
  toggleCopyTrading,
  TraderApplication,
  TraderStats,
  TraderPosition,
  CopyTrading,
} from '../../services/api/traderApi';
import {
  getMyStrategies,
  TraderStrategy,
} from '../../services/api/traderStrategyApi';

type PageState = 'loading' | 'not-logged-in' | 'no-application' | 'applying' | 'pending' | 'rejected' | 'dashboard';

export default function TraderCenterScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { user, syncProfile } = useAuthStore();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;

  const [pageState, setPageState] = useState<PageState>('loading');
  const [application, setApplication] = useState<TraderApplication | null>(null);
  const [stats, setStats] = useState<TraderStats | null>(null);
  const [followers, setFollowers] = useState<CopyTrading[]>([]);
  const [positions, setPositions] = useState<TraderPosition[]>([]);
  const [trades, setTrades] = useState<TraderPosition[]>([]);
  const [strategies, setStrategies] = useState<TraderStrategy[]>([]);
  const [copyEnabled, setCopyEnabled] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const loadData = useCallback(async () => {
    if (!user) {
      setPageState('not-logged-in');
      return;
    }

    if (user.isTrader) {
      try {
        const [statsRes, followersRes, posRes, trdRes, stratRes] = await Promise.all([
          getMyStats(),
          getMyFollowers(),
          getTraderPositions(user.uid).catch(() => []),
          getTraderTrades(user.uid).catch(() => []),
          getMyStrategies(undefined, 10).catch(() => ({ strategies: [], total: 0 })),
        ]);
        setStats(statsRes);
        setFollowers(followersRes || []);
        setPositions(posRes);
        setTrades(trdRes);
        setStrategies(stratRes.strategies || []);
        setCopyEnabled(user.allowCopyTrading || false);
        setPageState('dashboard');
      } catch {
        setPageState('dashboard');
      }
      return;
    }

    try {
      const res = await getMyApplication();
      if (res.application) {
        setApplication(res.application);
        if (res.application.status === 'pending') {
          setPageState('pending');
        } else if (res.application.status === 'rejected') {
          setPageState('rejected');
        } else {
          setPageState('no-application');
        }
      } else {
        setPageState('no-application');
      }
    } catch {
      setPageState('no-application');
    }
  }, [user]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  // Real-time price updates for open positions
  const quotes = useMarketStore((s) => s.quotes);
  const updateQuote = useMarketStore((s) => s.updateQuote);

  useEffect(() => {
    if (positions.length === 0) return;
    const symbols = [...new Set(positions.map((p) => p.symbol))];
    marketWs.connect();
    const handler = (msg: any) => {
      if (msg.symbol && msg.price != null) {
        updateQuote(msg.symbol, msg);
      }
    };
    marketWs.subscribeMany(symbols, handler);
    return () => {
      symbols.forEach((sym) => marketWs.unsubscribe(sym, handler));
    };
  }, [positions]);

  // Merge live prices into positions
  const livePositions = useMemo(() => {
    return positions.map((pos) => {
      const q = quotes[pos.symbol];
      if (!q?.price) return pos;
      const livePrice = q.price;
      const pnl = pos.side === 'long'
        ? (livePrice - pos.entry_price) * pos.qty
        : (pos.entry_price - livePrice) * pos.qty;
      return { ...pos, current_price: livePrice, unrealized_pnl: pnl };
    });
  }, [positions, quotes]);

  const onRefresh = async () => {
    setRefreshing(true);
    await syncProfile();
    await loadData();
    setRefreshing(false);
  };

  const handleToggleCopy = async (value: boolean) => {
    setCopyEnabled(value);
    try {
      await toggleCopyTrading(value);
      await syncProfile();
    } catch {
      setCopyEnabled(!value);
    }
  };

  const handleApplicationSuccess = () => {
    setPageState('pending');
  };

  if (pageState === 'loading') {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

  if (pageState === 'not-logged-in') {
    return (
      <View style={styles.centered}>
        <Text style={styles.title}>{t('traderCenter.title')}</Text>
        <Text style={styles.subtitle}>{t('auth.notLoggedIn')}</Text>
      </View>
    );
  }

  if (pageState === 'applying') {
    return (
      <View style={styles.container}>
        <View style={styles.header}>
          <TouchableOpacity onPress={() => setPageState('no-application')}>
            <Text style={styles.backBtn}>← {t('common.cancel')}</Text>
          </TouchableOpacity>
          <Text style={styles.headerTitle}>{t('traderCenter.applyTitle')}</Text>
        </View>
        <ApplicationForm onSuccess={handleApplicationSuccess} />
      </View>
    );
  }

  if (pageState === 'no-application') {
    return (
      <ScrollView
        style={styles.container}
        contentContainerStyle={styles.centeredContent}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={Colors.primary} />}
      >
        <View style={styles.heroCard}>
          <Text style={styles.heroIcon}>🏅</Text>
          <Text style={styles.heroTitle}>{t('traderCenter.applyTitle')}</Text>
          <Text style={styles.heroDesc}>{t('traderCenter.applyDesc')}</Text>
          <TouchableOpacity style={styles.applyBtn} onPress={() => setPageState('applying')}>
            <Text style={styles.applyBtnText}>{t('traderCenter.applyButton')}</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    );
  }

  if (pageState === 'pending') {
    return (
      <ScrollView
        style={styles.container}
        contentContainerStyle={styles.centeredContent}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={Colors.primary} />}
      >
        <View style={styles.heroCard}>
          <Text style={styles.heroIcon}>⏳</Text>
          <Text style={styles.heroTitle}>{t('traderCenter.pendingTitle')}</Text>
          <Text style={styles.heroDesc}>{t('traderCenter.pendingDesc')}</Text>
        </View>
      </ScrollView>
    );
  }

  if (pageState === 'rejected') {
    return (
      <ScrollView
        style={styles.container}
        contentContainerStyle={styles.centeredContent}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={Colors.primary} />}
      >
        <View style={[styles.heroCard, styles.rejectedCard]}>
          <Text style={styles.heroIcon}>❌</Text>
          <Text style={styles.heroTitle}>{t('traderCenter.rejectedTitle')}</Text>
          {application?.rejection_reason ? (
            <Text style={styles.rejectedReason}>
              {t('traderCenter.rejectedReason')}: {application.rejection_reason}
            </Text>
          ) : null}
          <TouchableOpacity style={styles.applyBtn} onPress={() => setPageState('applying')}>
            <Text style={styles.applyBtnText}>{t('traderCenter.reapplyButton')}</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    );
  }

  // ── Dashboard with same style as trader detail page ──
  const pnl = stats?.total_pnl || 0;
  const winRate = stats?.win_rate || 0;
  const maxDD = stats?.max_drawdown || 0;
  const totalTrades = stats?.total_trades || 0;
  const followersCount = stats?.followers_count || 0;
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

  // Market Sentiment — composite score from multiple factors
  // Score range: -100 (极度看跌) to +100 (极度看涨)
  const sentimentScore = (() => {
    let score = 0;
    // 1. Recent PnL trend (weight: 30%)
    if (pnl > 0) score += Math.min(30, (pnl / 1000) * 5);
    else score -= Math.min(30, (Math.abs(pnl) / 1000) * 5);
    // 2. Win rate contribution (weight: 25%) — 50% is neutral
    score += (winRate - 50) * 0.5;
    // 3. Sharpe ratio (weight: 20%)
    score += parseFloat(sharpeRatio) * 7;
    // 4. Recent trade momentum — positive avg pnl = bullish (weight: 15%)
    if (avgPnl > 0) score += Math.min(15, avgPnl / 100);
    else score -= Math.min(15, Math.abs(avgPnl) / 100);
    // 5. Low drawdown = more confidence (weight: 10%)
    score += Math.max(-10, (20 - maxDD) * 0.5);
    return Math.max(-100, Math.min(100, Math.round(score)));
  })();
  const sentimentText = sentimentScore >= 60 ? '强力看涨 Strong Bullish'
    : sentimentScore >= 25 ? '偏多看涨 Bullish'
    : sentimentScore >= -25 ? '谨慎观望 Neutral'
    : sentimentScore >= -60 ? '偏空看跌 Bearish'
    : '强力看跌 Strong Bearish';
  const sentimentIcon = sentimentScore >= 25 ? 'trend-up' : sentimentScore >= -25 ? 'market' : 'trend-down';

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={[styles.scrollContent, isDesktop && { maxWidth: 960, alignSelf: 'center', width: '100%' }]}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={Colors.primary} />}
    >
      {/* Profile Header */}
      <View style={styles.headerCard}>
        <View style={[styles.headerContent, isDesktop && styles.headerContentDesktop]}>
          <View style={[styles.headerLeft, isDesktop && styles.headerLeftDesktop]}>
            <View style={styles.avatarContainer}>
              <View style={styles.avatar}>
                {user?.photoURL ? (
                  <Image
                    source={{ uri: user.photoURL.startsWith('/') ? `${Config.API_BASE_URL}${user.photoURL}` : user.photoURL }}
                    style={{ width: 68, height: 68, borderRadius: 12 }}
                  />
                ) : (
                  <Text style={styles.avatarText}>
                    {(user?.displayName || '?')[0].toUpperCase()}
                  </Text>
                )}
              </View>
              <View style={styles.eliteBadge}>
                <Text style={styles.eliteBadgeText}>ELITE</Text>
              </View>
            </View>
            <View style={styles.headerInfo}>
              <View style={styles.nameRow}>
                <Text style={styles.profileName}>{user?.displayName}</Text>
                <Text style={styles.verifiedIcon}>✓</Text>
              </View>
              <Text style={styles.selfLabel}>我的交易员主页</Text>
              <View style={styles.tagsRow}>
                {user?.allowCopyTrading && (
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

          {/* Settings badge */}
          <View style={styles.headerActions}>
            <View style={styles.certBadge}>
              <Text style={styles.certBadgeText}>✓ Certified</Text>
            </View>
          </View>
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
          value={formatNumber(followersCount)}
        />
      </View>

      {/* Equity Curve + Risk Matrix */}
      <View style={[styles.rowGrid, isDesktop && styles.rowGridDesktop, isDesktop && { alignItems: 'stretch' }]}>
        <View style={[isDesktop ? { flex: 1, minWidth: 0 } : {}]}>
          <EquityCurve traderUid={user!.uid} />
        </View>

        <View style={[{ gap: 12 }, isDesktop && { width: 340, flexShrink: 0 }]}>
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
              <AppIcon name="shield" size={22} color={Colors.primary} />
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

          <View style={[styles.glassCard, styles.sentimentCardWrapper, { marginBottom: 0 }]}>
            <View style={styles.sentimentRow}>
              <View style={styles.sentimentIcon}>
                <AppIcon name={sentimentIcon} size={22} color={sentimentScore >= -25 && sentimentScore < 25 ? Colors.primary : sentimentScore >= 25 ? Colors.up : Colors.down} />
              </View>
              <View style={{ flex: 1 }}>
                <Text style={styles.sentimentLabel}>当前情绪 MARKET SENTIMENT ({sentimentScore > 0 ? '+' : ''}{sentimentScore})</Text>
                <Text style={styles.sentimentValue}>
                  {sentimentText}
                </Text>
              </View>
            </View>
          </View>
        </View>
      </View>

      {/* My Strategies Section */}
      <View style={[styles.glassCard, { marginBottom: 16 }]}>
        <View style={styles.sectionHeader}>
          <View style={styles.sectionTitleRow}>
            <AppIcon name="paper" size={16} color={Colors.primary} />
            <Text style={[styles.sectionTitle, { marginBottom: 0 }]}>我的策略 My Strategies</Text>
          </View>
          <TouchableOpacity
            style={styles.writeBtn}
            onPress={() => router.push('/strategy/editor' as any)}
          >
            <View style={styles.writeBtnInner}>
              <AppIcon name="paper" size={15} color={Colors.background} />
              <Text style={styles.writeBtnText}>发布策略</Text>
            </View>
          </TouchableOpacity>
        </View>

        {strategies.length === 0 ? (
          <View style={styles.emptyStrategy}>
            <AppIcon name="paper" size={26} color={Colors.textMuted} />
            <Text style={styles.emptyText}>还没有发布策略</Text>
            <Text style={[styles.emptyText, { fontSize: 12, marginTop: 4 }]}>
              分享你的交易见解，建立影响力
            </Text>
          </View>
        ) : (
          strategies.map((s) => {
            const date = new Date(s.created_at).toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' });
            return (
              <TouchableOpacity
                key={s.id}
                style={styles.strategyItem}
                onPress={() => router.push(`/strategy/${s.id}` as any)}
              >
                <View style={{ flex: 1 }}>
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                    <Text style={styles.strategyTitle} numberOfLines={1}>{s.title}</Text>
                    {s.status === 'draft' && (
                      <View style={styles.draftBadge}>
                        <Text style={styles.draftBadgeText}>草稿</Text>
                      </View>
                    )}
                  </View>
                  <Text style={styles.strategySummary} numberOfLines={2}>{s.summary}</Text>
                  <View style={styles.strategyMeta}>
                    <Text style={styles.strategyMetaText}>{date}</Text>
                    <View style={styles.strategyMetaInline}>
                      <AppIcon name="eye" size={12} color={Colors.textMuted} />
                      <Text style={styles.strategyMetaText}>{s.views} 阅读</Text>
                    </View>
                    <View style={styles.strategyMetaInline}>
                      <AppIcon name="heart" size={12} color={Colors.textMuted} />
                      <Text style={styles.strategyMetaText}>{s.likes} 赞</Text>
                    </View>
                  </View>
                </View>
                {s.cover_image ? (
                  <Image source={{ uri: s.cover_image }} style={styles.strategyThumb} />
                ) : null}
              </TouchableOpacity>
            );
          })
        )}
      </View>

      {/* Open Positions + Recent Trades */}
      <View style={[styles.rowGrid, isDesktop && styles.rowGridDesktop]}>
        {/* Open Positions */}
        <View style={[styles.glassCard, { marginBottom: isDesktop ? 0 : 16 }, isDesktop && { flex: 1, minWidth: 0 }]}>
          <View style={styles.sectionHeader}>
            <View style={styles.sectionTitleRow}>
              <AppIcon name="chart" size={16} color={Colors.primary} />
              <Text style={[styles.sectionTitle, { marginBottom: 0 }]}>当前持仓 Open Positions</Text>
            </View>
            {livePositions.length > 0 && (
              <View style={styles.activeBadge}>
                <Text style={styles.activeBadgeText}>{livePositions.length} ACTIVE</Text>
              </View>
            )}
          </View>
          {livePositions.length === 0 ? (
            <Text style={styles.emptyText}>暂无持仓</Text>
          ) : (
            <>
              <View style={styles.tableHeader}>
                <Text style={[styles.tableHeaderText, { flex: 2 }]}>交易对 PAIR</Text>
                <Text style={[styles.tableHeaderText, { flex: 1.5 }]}>入场 ENTRY</Text>
                <Text style={[styles.tableHeaderText, { flex: 1.5 }]}>当前 CURRENT</Text>
                <Text style={[styles.tableHeaderText, { flex: 1, textAlign: 'right' }]}>盈亏 PNL</Text>
              </View>
              {livePositions.map((pos) => {
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
              <AppIcon name="clock" size={16} color={Colors.primary} />
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
                      {rpnl >= 0 ? '+' : '-'}${formatMoney(Math.abs(rpnl))}
                    </Text>
                  </View>
                );
              })}
            </>
          )}
        </View>
      </View>

      {/* Management Section: Copy Trading Toggle + Followers */}
      <View style={[styles.rowGrid, isDesktop && styles.rowGridDesktop]}>
        {/* Copy Trading Toggle */}
        <View style={[styles.glassCard, { marginBottom: isDesktop ? 0 : 16 }, isDesktop && { flex: 1, minWidth: 0 }]}>
          <View style={styles.sectionHeader}>
            <View style={styles.sectionTitleRow}>
              <AppIcon name="settings" size={16} color={Colors.primary} />
              <Text style={[styles.sectionTitle, { marginBottom: 0 }]}>跟单管理 Copy Trading</Text>
            </View>
          </View>
          <View style={styles.settingRow}>
            <View>
              <Text style={styles.settingLabel}>开放跟单</Text>
              <Text style={styles.settingHint}>
                {copyEnabled ? '已开启 — 其他用户可以跟随你的交易' : '已关闭'}
              </Text>
            </View>
            <Switch
              value={copyEnabled}
              onValueChange={handleToggleCopy}
              trackColor={{ false: Colors.surfaceAlt, true: Colors.primaryDim }}
              thumbColor={copyEnabled ? Colors.primary : Colors.textMuted}
            />
          </View>
        </View>

        {/* Followers */}
        <View style={[styles.glassCard, { marginBottom: 0 }, isDesktop && { flex: 1, minWidth: 0 }]}>
          <View style={styles.sectionHeader}>
            <View style={styles.sectionTitleRow}>
              <AppIcon name="users" size={16} color={Colors.primary} />
              <Text style={[styles.sectionTitle, { marginBottom: 0 }]}>我的跟单者 Followers</Text>
            </View>
            <View style={styles.activeBadge}>
              <Text style={styles.activeBadgeText}>{followers.length}</Text>
            </View>
          </View>
          {followers.length === 0 ? (
            <Text style={styles.emptyText}>暂无跟单者</Text>
          ) : (
            followers.map((f) => (
              <View key={f.id} style={styles.followerRow}>
                <View style={styles.followerAvatar}>
                  <Text style={styles.followerAvatarText}>
                    {(f.trader_name || '?')[0].toUpperCase()}
                  </Text>
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={styles.followerName}>{f.trader_name || f.follower_id}</Text>
                  <Text style={styles.followerMeta}>
                    Ratio: {f.copy_ratio}x
                    {f.max_position ? ` · Max: $${f.max_position}` : ''}
                  </Text>
                </View>
                <Text style={[styles.followerStatus, { color: f.status === 'active' ? Colors.up : Colors.textMuted }]}>
                  {f.status.toUpperCase()}
                </Text>
              </View>
            ))
          )}
        </View>
      </View>

      <View style={{ height: 40 }} />
    </ScrollView>
  );
}

/* ── Sub Components ── */

function MetricCard({ label, value, color, glow }: { label: string; value: string; color?: string; glow?: boolean }) {
  const fontSize = value.length > 10 ? 16 : value.length > 7 ? 18 : 22;
  return (
    <View style={[styles.metricCard, glow && styles.metricCardGlow]}>
      <Text style={styles.metricLabel} numberOfLines={1}>{label}</Text>
      <Text
        style={[styles.metricValue, { fontSize }, color ? { color } : undefined]}
        numberOfLines={1}
        adjustsFontSizeToFit
        minimumFontScale={0.6}
      >
        {value}
      </Text>
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
  if (n >= 1000) return `${(n / 1000).toFixed(1)}K`;
  return String(n);
}

function formatMoney(n: number): string {
  const abs = Math.abs(n);
  if (abs >= 1_000_000) return `${(n / 1_000_000).toFixed(2)}M`;
  if (abs >= 10_000) return `${(n / 1_000).toFixed(1)}K`;
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
    padding: 20,
  },
  centeredContent: {
    flexGrow: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  title: { color: Colors.textActive, fontSize: 20, fontWeight: '700' },
  subtitle: { color: Colors.textMuted, fontSize: 14, marginTop: 8 },
  scrollContent: { padding: 16, paddingBottom: 60 },

  header: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    gap: 12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  backBtn: { color: Colors.primary, fontSize: 15, fontWeight: '600' },
  headerTitle: { color: Colors.textActive, fontSize: 17, fontWeight: '700', flex: 1 },

  // Hero card
  heroCard: {
    backgroundColor: Colors.surface,
    borderRadius: 16,
    padding: 32,
    alignItems: 'center',
    maxWidth: 420,
    width: '100%',
    borderWidth: 1,
    borderColor: Colors.border,
  },
  rejectedCard: { borderColor: Colors.down },
  heroIcon: { fontSize: 48, marginBottom: 16 },
  heroTitle: {
    color: Colors.textActive,
    fontSize: 20,
    fontWeight: '700',
    textAlign: 'center',
    marginBottom: 12,
  },
  heroDesc: {
    color: Colors.textSecondary,
    fontSize: 14,
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: 24,
  },
  rejectedReason: {
    color: Colors.down,
    fontSize: 14,
    textAlign: 'center',
    marginBottom: 20,
  },
  applyBtn: {
    backgroundColor: Colors.primary,
    paddingHorizontal: 32,
    paddingVertical: 14,
    borderRadius: 8,
  },
  applyBtnText: { color: Colors.textOnPrimary, fontSize: 16, fontWeight: '700' },

  // ── Profile Header ──
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
  selfLabel: { color: Colors.textMuted, fontSize: 12, marginBottom: 8 },
  tagsRow: { flexDirection: 'row', gap: 6, flexWrap: 'wrap' },
  tag: {
    backgroundColor: Colors.surfaceAlt,
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  tagText: { color: Colors.textSecondary, fontSize: 9, fontWeight: '700', letterSpacing: 1.5 },
  headerActions: { flexDirection: 'row', gap: 10 },
  certBadge: {
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.primary,
  },
  certBadgeText: { color: Colors.primary, fontSize: 13, fontWeight: '700' },

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
    paddingVertical: 14,
    paddingHorizontal: 14,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    flexGrow: 1,
    flexShrink: 1,
    flexBasis: '30%',
    minWidth: 120,
    overflow: 'hidden',
  },
  metricCardGlow: { ...Shadows.glow },
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
  sectionTitleRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
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
  riskScore: { color: Colors.primary, fontSize: 36, fontWeight: '800', letterSpacing: -1 },
  riskScoreUnit: { color: Colors.textMuted, fontSize: 14, fontWeight: '400' },
  riskLabel: { color: Colors.textMuted, fontSize: 9, fontWeight: '600', letterSpacing: 1.5, textTransform: 'uppercase' },
  shieldIcon: { fontSize: 32, opacity: 0.4 },
  riskMetrics: { gap: 16 },
  riskBarContainer: {},
  riskBarHeader: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 6 },
  riskBarLabel: { color: Colors.textSecondary, fontSize: 12 },
  riskBarValue: { color: Colors.textActive, fontSize: 12, fontWeight: '700' },
  riskBarTrack: { height: 5, backgroundColor: Colors.background, borderRadius: 3, overflow: 'hidden' },
  riskBarFill: { height: '100%', backgroundColor: Colors.primary, borderRadius: 3 },
  riskNote: { marginTop: 16, paddingTop: 12, borderTopWidth: 1, borderTopColor: Colors.border },
  riskNoteText: { color: Colors.textMuted, fontSize: 11, lineHeight: 18 },

  // ── Sentiment ──
  sentimentCardWrapper: { backgroundColor: Colors.surfaceAlt },
  sentimentRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  sentimentIcon: {
    width: 44,
    height: 44,
    borderRadius: 10,
    backgroundColor: Colors.upDim,
    justifyContent: 'center',
    alignItems: 'center',
  },
  sentimentLabel: { color: Colors.textMuted, fontSize: 10, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 2 },
  sentimentValue: { color: Colors.textActive, fontSize: 14, fontWeight: '700' },

  // ── Table ──
  activeBadge: { backgroundColor: Colors.upDim, paddingHorizontal: 10, paddingVertical: 4, borderRadius: 6 },
  activeBadgeText: { color: Colors.up, fontSize: 10, fontWeight: '700', letterSpacing: 1 },
  viewAllText: { color: Colors.primary, fontSize: 11, fontWeight: '700', letterSpacing: 1 },
  emptyText: { color: Colors.textMuted, fontSize: 13, textAlign: 'center', paddingVertical: 20 },
  tableHeader: {
    flexDirection: 'row',
    paddingBottom: 10,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    marginBottom: 4,
  },
  tableHeaderText: { color: Colors.textMuted, fontSize: 9, fontWeight: '600', letterSpacing: 1, textTransform: 'uppercase' },
  tableRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  tableCell: { color: Colors.textSecondary, fontSize: 13 },
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
  tradeDot: { width: 6, height: 6, borderRadius: 3 },
  tradeAction: { color: Colors.textActive, fontSize: 13, fontWeight: '600' },
  tradeType: { color: Colors.textMuted, fontSize: 10, letterSpacing: 0.5, marginTop: 2, marginLeft: 12 },

  // ── Settings ──
  settingRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  settingLabel: { color: Colors.textActive, fontSize: 15, fontWeight: '600' },
  settingHint: { color: Colors.textMuted, fontSize: 12, marginTop: 2 },

  // ── Followers ──
  followerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    gap: 12,
  },
  followerAvatar: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.primaryDim,
    justifyContent: 'center',
    alignItems: 'center',
  },
  followerAvatarText: { color: Colors.primary, fontSize: 14, fontWeight: '700' },
  followerName: { color: Colors.textActive, fontSize: 14, fontWeight: '600' },
  followerMeta: { color: Colors.textMuted, fontSize: 12, marginTop: 2 },
  followerStatus: { fontSize: 10, fontWeight: '700', letterSpacing: 1 },

  // ── Strategy Section ──
  writeBtn: {
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: Colors.primary,
  },
  writeBtnInner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  writeBtnText: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '700',
  },
  emptyStrategy: {
    alignItems: 'center',
    paddingVertical: 32,
  },
  strategyItem: {
    flexDirection: 'row',
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    gap: 12,
  },
  strategyTitle: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '700',
    flex: 1,
  },
  draftBadge: {
    backgroundColor: 'rgba(255, 204, 0, 0.15)',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 4,
  },
  draftBadgeText: {
    color: '#FFCC00',
    fontSize: 10,
    fontWeight: '700',
  },
  strategySummary: {
    color: Colors.textMuted,
    fontSize: 13,
    lineHeight: 20,
    marginTop: 4,
  },
  strategyMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginTop: 8,
  },
  strategyMetaInline: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  strategyMetaText: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  strategyThumb: {
    width: 72,
    height: 72,
    borderRadius: 8,
    backgroundColor: Colors.surfaceAlt,
  },
});
