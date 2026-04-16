import { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  useWindowDimensions,
  RefreshControl,
  ActivityIndicator,
  Image,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors, Shadows } from '../../theme/colors';
import { Config } from '../../services/config';
import { getTraderRankings, TraderRankingItem } from '../../services/api/traderApi';
import TraderDetailPanel from '../../components/trader/TraderDetailPanel';
import { FollowingWorkbench } from './following';

type SortBy = 'pnl' | 'win_rate' | 'followers' | 'trades';
type RankingsTab = 'leaderboard' | 'following';

// ─── Avatar Component ────────────────────────────────
function AvatarCircle({ name, size = 40, borderColor, certified, imageUrl }: { name: string; size?: number; borderColor?: string; certified?: boolean; imageUrl?: string | null }) {
  const letter = (name || '?').charAt(0).toUpperCase();
  const colors = ['#D4AF37', '#66e4b9', '#f2ca50', '#ffb4ab', '#627EEA', '#9945FF'];
  const idx = (name || '').charCodeAt(0) % colors.length;
  const bg = colors[idx];
  const resolvedUrl = imageUrl && imageUrl.startsWith('/') ? `${Config.API_BASE_URL}${imageUrl}` : imageUrl;

  return (
    <View style={{ position: 'relative' }}>
      {resolvedUrl ? (
        <Image
          source={{ uri: resolvedUrl }}
          style={{
            width: size,
            height: size,
            borderRadius: size / 2,
            borderWidth: 2,
            borderColor: borderColor || bg + '40',
            backgroundColor: bg + '20',
          }}
        />
      ) : (
      <View
        style={[
          avatarStyles.circle,
          {
            width: size,
            height: size,
            borderRadius: size / 2,
            backgroundColor: bg + '20',
            borderColor: borderColor || bg + '40',
          },
        ]}
      >
        <Text style={[avatarStyles.letter, { fontSize: size * 0.4, color: bg }]}>{letter}</Text>
      </View>
      )}
      {certified && (
        <View style={[avatarStyles.badge, { right: -2, bottom: -2 }]}>
          <Text style={avatarStyles.badgeText}>✓</Text>
        </View>
      )}
    </View>
  );
}

const avatarStyles = StyleSheet.create({
  circle: {
    borderWidth: 2,
    justifyContent: 'center',
    alignItems: 'center',
  },
  letter: {
    fontWeight: '800',
  },
  badge: {
    position: 'absolute',
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: Colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1.5,
    borderColor: Colors.background,
  },
  badgeText: {
    color: Colors.textOnPrimary,
    fontSize: 9,
    fontWeight: '800',
  },
});

// ─── Top 3 Spotlight Card ────────────────────────────
function SpotlightCard({ trader, rank, isChampion, onPress }: { trader: TraderRankingItem; rank: number; isChampion: boolean; onPress: () => void }) {
  const cardHeight = isChampion ? 420 : 360;
  const avatarSize = isChampion ? 88 : 64;

  return (
    <TouchableOpacity
      style={[spotStyles.card, { height: cardHeight }, isChampion && spotStyles.cardChampion]}
      activeOpacity={0.8}
      onPress={onPress}
    >
      <Text style={[spotStyles.rankWatermark, isChampion && spotStyles.rankWatermarkChampion]}>
        {String(rank).padStart(2, '0')}
      </Text>
      {isChampion && <View style={spotStyles.glowOrb} />}

      <View style={{ marginBottom: isChampion ? 14 : 10 }}>
        <AvatarCircle
          name={trader.display_name}
          size={avatarSize}
          borderColor={isChampion ? Colors.primary : undefined}
          certified
          imageUrl={trader.avatar_url}
        />
      </View>

      <Text style={[spotStyles.name, isChampion && spotStyles.nameChampion]}>
        {trader.display_name}
      </Text>
      <Text style={spotStyles.subtitle}>
        {trader.followers_count} FOLLOWERS
      </Text>

      <View style={[spotStyles.statsArea, { marginBottom: isChampion ? 16 : 12 }]}>
        <View style={[spotStyles.statRow, isChampion && spotStyles.statRowChampion]}>
          <Text style={spotStyles.statLabel}>PnL</Text>
          <Text style={[spotStyles.statValue, { color: trader.total_pnl >= 0 ? Colors.up : Colors.down }, isChampion && spotStyles.statValueBig]}>
            {trader.total_pnl >= 0 ? '+' : ''}${trader.total_pnl.toFixed(2)}
          </Text>
        </View>
        <View style={spotStyles.statRow}>
          <Text style={spotStyles.statLabel}>Win Rate</Text>
          <Text style={spotStyles.statValue}>{trader.win_rate.toFixed(1)}%</Text>
        </View>
      </View>

      <TouchableOpacity
        style={isChampion ? spotStyles.ctaPrimary : spotStyles.ctaOutline}
        activeOpacity={0.7}
        onPress={onPress}
      >
        <Text style={isChampion ? spotStyles.ctaPrimaryText : spotStyles.ctaOutlineText}>
          {trader.allow_copy_trading ? 'COPY PORTFOLIO' : 'VIEW PROFILE'}
        </Text>
      </TouchableOpacity>
    </TouchableOpacity>
  );
}

const spotStyles = StyleSheet.create({
  card: {
    flex: 1,
    backgroundColor: 'rgba(53,53,52,0.4)',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.2)',
    borderTopWidth: 2,
    borderTopColor: 'rgba(77,70,53,0.4)',
    padding: 24,
    alignItems: 'center',
    overflow: 'hidden',
    position: 'relative',
  },
  cardChampion: {
    borderTopColor: 'rgba(242,202,80,0.5)',
    shadowColor: '#f2ca50',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.1,
    shadowRadius: 50,
    elevation: 10,
    padding: 28,
  },
  glowOrb: {
    position: 'absolute',
    top: -40,
    right: -40,
    width: 140,
    height: 140,
    borderRadius: 70,
    backgroundColor: 'rgba(242,202,80,0.08)',
  },
  rankWatermark: {
    position: 'absolute',
    top: 12,
    left: 20,
    fontSize: 48,
    fontWeight: '800',
    color: Colors.textSecondary,
    opacity: 0.1,
  },
  rankWatermarkChampion: {
    fontSize: 56,
    color: Colors.primaryLight,
    opacity: 0.2,
  },
  name: { fontSize: 17, fontWeight: '700', color: Colors.textActive, marginBottom: 4 },
  nameChampion: { fontSize: 22, fontWeight: '800' },
  subtitle: { fontSize: 10, color: Colors.textSecondary, letterSpacing: 2, marginBottom: 20 },
  statsArea: { width: '100%', gap: 10 },
  statRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: 'rgba(14,14,14,0.5)',
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.1)',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  statRowChampion: {
    borderColor: 'rgba(242,202,80,0.2)',
    paddingVertical: 14,
    paddingHorizontal: 20,
  },
  statLabel: { fontSize: 12, color: Colors.textSecondary },
  statValue: { fontSize: 15, fontWeight: '700', color: Colors.textActive },
  statValueBig: { fontSize: 22 },
  ctaPrimary: {
    width: '100%',
    backgroundColor: Colors.primaryLight,
    paddingVertical: 14,
    borderRadius: 10,
    alignItems: 'center',
    ...Shadows.glow,
  },
  ctaPrimaryText: { color: Colors.background, fontSize: 12, fontWeight: '800', letterSpacing: 2 },
  ctaOutline: {
    width: '100%',
    borderWidth: 1,
    borderColor: 'rgba(242,202,80,0.4)',
    paddingVertical: 12,
    borderRadius: 10,
    alignItems: 'center',
  },
  ctaOutlineText: { color: Colors.primaryLight, fontSize: 11, fontWeight: '700', letterSpacing: 2 },
});

// ─── Table Row (Desktop) ───────────────────────────────
function RankingRow({ trader, rank, onPress }: { trader: TraderRankingItem; rank: number; onPress: () => void }) {
  const { t } = useTranslation();
  return (
    <TouchableOpacity style={rowStyles.container} onPress={onPress} activeOpacity={0.7}>
      <Text style={rowStyles.rank}>{String(rank).padStart(2, '0')}</Text>
      <View style={rowStyles.traderInfo}>
        <AvatarCircle name={trader.display_name} size={36} certified imageUrl={trader.avatar_url} />
        <View>
          <Text style={rowStyles.traderName}>{trader.display_name}</Text>
          <Text style={rowStyles.traderSub}>{trader.followers_count} followers</Text>
        </View>
      </View>
      <View style={rowStyles.pnlCol}>
        <Text style={[rowStyles.pnlText, { color: trader.total_pnl >= 0 ? Colors.up : Colors.down }]}>
          {trader.total_pnl >= 0 ? '+' : ''}${trader.total_pnl.toFixed(2)}
        </Text>
      </View>
      <Text style={rowStyles.winRate}>{trader.win_rate.toFixed(1)}%</Text>
      <Text style={rowStyles.trades}>{trader.total_trades.toLocaleString()}</Text>
      <TouchableOpacity style={rowStyles.followBtn} activeOpacity={0.7}>
        <Text style={rowStyles.followText}>{t('rankings.follow')}</Text>
      </TouchableOpacity>
    </TouchableOpacity>
  );
}

const rowStyles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 16,
    paddingHorizontal: 24,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.1)',
  },
  rank: { width: 40, fontSize: 16, fontWeight: '700', color: Colors.textSecondary, opacity: 0.4 },
  traderInfo: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12 },
  traderName: { fontSize: 14, fontWeight: '700', color: Colors.textActive },
  traderSub: { fontSize: 10, color: Colors.textSecondary, marginTop: 1 },
  pnlCol: { width: 110, alignItems: 'flex-end' },
  pnlText: { fontSize: 14, fontWeight: '700' },
  winRate: { width: 70, textAlign: 'right', fontSize: 14, fontWeight: '600', color: Colors.textActive },
  trades: { width: 80, textAlign: 'right', fontSize: 14, color: Colors.textSecondary, opacity: 0.6 },
  followBtn: {
    marginLeft: 20,
    backgroundColor: '#2a2a2a',
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.3)',
    borderRadius: 6,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  followText: { fontSize: 12, fontWeight: '700', color: Colors.textActive },
});

// ─── Mobile Row ────────────────────────────────────────
function MobileRankingRow({ trader, rank, onPress }: { trader: TraderRankingItem; rank: number; onPress: () => void }) {
  return (
    <TouchableOpacity style={mobileRowStyles.container} onPress={onPress} activeOpacity={0.7}>
      <Text style={mobileRowStyles.rank}>#{rank}</Text>
      <AvatarCircle name={trader.display_name} size={36} certified imageUrl={trader.avatar_url} />
      <View style={mobileRowStyles.info}>
        <Text style={mobileRowStyles.name}>{trader.display_name}</Text>
        <Text style={mobileRowStyles.sub}>{trader.followers_count} followers</Text>
      </View>
      <View style={mobileRowStyles.statsCol}>
        <Text style={[mobileRowStyles.pnl, { color: trader.total_pnl >= 0 ? Colors.up : Colors.down }]}>
          {trader.total_pnl >= 0 ? '+' : ''}${trader.total_pnl.toFixed(2)}
        </Text>
        <Text style={mobileRowStyles.wr}>{trader.win_rate.toFixed(1)}% WR</Text>
      </View>
    </TouchableOpacity>
  );
}

const mobileRowStyles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    gap: 10,
  },
  rank: { width: 28, fontSize: 13, fontWeight: '700', color: Colors.textMuted },
  info: { flex: 1 },
  name: { fontSize: 14, fontWeight: '600', color: Colors.textActive },
  sub: { fontSize: 10, color: Colors.textMuted, marginTop: 1 },
  statsCol: { alignItems: 'flex-end' },
  pnl: { fontSize: 14, fontWeight: '700' },
  wr: { fontSize: 11, color: Colors.textSecondary, marginTop: 2 },
});

// ─── Main Screen ─────────────────────────────────────
export default function RankingsScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const params = useLocalSearchParams<{ tab?: string; trader?: string }>();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;
  const resolvedTab: RankingsTab = params.tab === 'following' ? 'following' : 'leaderboard';
  const [activeTab, setActiveTab] = useState<RankingsTab>(resolvedTab);
  const [sortBy, setSortBy] = useState<SortBy>('pnl');
  const [traders, setTraders] = useState<TraderRankingItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [selectedTrader, setSelectedTrader] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    if (activeTab !== 'leaderboard') {
      setLoading(false);
      return;
    }
    try {
      const res = await getTraderRankings(sortBy, 50, 0);
      setTraders(res.traders || []);
    } catch {
      // keep existing data
    } finally {
      setLoading(false);
    }
  }, [activeTab, sortBy]);

  useEffect(() => {
    setActiveTab(resolvedTab);
  }, [resolvedTab]);

  useEffect(() => {
    setSelectedTrader(typeof params.trader === 'string' ? params.trader : null);
  }, [params.trader]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const onRefresh = async () => {
    if (activeTab !== 'leaderboard') return;
    setRefreshing(true);
    await fetchData();
    setRefreshing(false);
  };

  const baseRoute = activeTab === 'following' ? '/(tabs)/rankings?tab=following' : '/(tabs)/rankings';

  const handleTabChange = (tab: RankingsTab) => {
    if (tab === activeTab) return;
    setActiveTab(tab);
    setSelectedTrader(null);
    router.replace((tab === 'following' ? '/(tabs)/rankings?tab=following' : '/(tabs)/rankings') as any);
  };

  const navigateToTrader = (uid: string) => {
    setSelectedTrader(uid);
    router.push(
      (activeTab === 'following'
        ? `/(tabs)/rankings?tab=following&trader=${uid}`
        : `/(tabs)/rankings?trader=${uid}`) as any,
    );
  };

  const SORT_OPTIONS: { key: SortBy; label: string }[] = [
    { key: 'pnl', label: t('rankings.pnl') },
    { key: 'win_rate', label: t('rankings.winRate') },
    { key: 'followers', label: t('rankings.follow') },
    { key: 'trades', label: t('rankings.totalTrades') },
  ];

  const top3 = traders.slice(0, 3);
  const rest = traders.slice(3);

  const renderHeader = () => (
    <View style={[styles.header, isDesktop && styles.headerDesktop]}>
      <View style={styles.headerIntro}>
        {activeTab === 'leaderboard' ? (
          <>
            <Text style={styles.title}>{t('rankings.title')}</Text>
            <Text style={styles.subtitle}>{t('rankings.subtitle')}</Text>
          </>
        ) : (
          <Text style={styles.titleCompact}>{t('following.title')}</Text>
        )}
      </View>

      <View style={styles.headerControls}>
        <View style={styles.modeRail}>
          <TouchableOpacity
            style={[styles.modeBtn, activeTab === 'leaderboard' && styles.modeBtnActive]}
            activeOpacity={0.75}
            onPress={() => handleTabChange('leaderboard')}
          >
            <Text style={[styles.modeText, activeTab === 'leaderboard' && styles.modeTextActive]}>
              {t('rankings.title')}
            </Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.modeBtn, activeTab === 'following' && styles.modeBtnActive]}
            activeOpacity={0.75}
            onPress={() => handleTabChange('following')}
          >
            <Text style={[styles.modeText, activeTab === 'following' && styles.modeTextActive]}>
              {t('following.title')}
            </Text>
          </TouchableOpacity>
        </View>

        {activeTab === 'leaderboard' ? (
          <View style={styles.filterBar}>
            {SORT_OPTIONS.map((f) => (
              <TouchableOpacity
                key={f.key}
                style={[styles.filterBtn, sortBy === f.key && styles.filterBtnActive]}
                onPress={() => setSortBy(f.key)}
              >
                <Text style={[styles.filterText, sortBy === f.key && styles.filterTextActive]}>
                  {f.label}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        ) : (
          <View style={styles.followingHint}>
            <Text style={styles.followingHintText}>{t('following.emptyTitle')}</Text>
          </View>
        )}
      </View>
    </View>
  );

  if (selectedTrader) {
    return (
      <View style={styles.container}>
        <TraderDetailPanel
          key={selectedTrader}
          uid={selectedTrader}
          embedded
          onClose={() => {
            setSelectedTrader(null);
            router.replace(baseRoute as any);
          }}
        />
      </View>
    );
  }

  if (activeTab === 'following') {
    return (
      <View style={styles.container}>
        <ScrollView style={styles.scrollView} contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
          {renderHeader()}
          <FollowingWorkbench embedded />
        </ScrollView>
      </View>
    );
  }

  if (loading) {
    return (
      <View style={[styles.container, { justifyContent: 'center', alignItems: 'center' }]}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={Colors.primary} />
        }
      >
        {renderHeader()}

        {/* Top 3 Spotlight */}
        {top3.length >= 3 ? (
          isDesktop ? (
            <View style={styles.spotlightGrid}>
              <SpotlightCard trader={top3[1]} rank={2} isChampion={false} onPress={() => navigateToTrader(top3[1].uid)} />
              <SpotlightCard trader={top3[0]} rank={1} isChampion onPress={() => navigateToTrader(top3[0].uid)} />
              <SpotlightCard trader={top3[2]} rank={3} isChampion={false} onPress={() => navigateToTrader(top3[2].uid)} />
            </View>
          ) : (
            <View style={styles.spotlightMobile}>
              <SpotlightCard trader={top3[0]} rank={1} isChampion onPress={() => navigateToTrader(top3[0].uid)} />
              <View style={styles.spotlightMobileRow}>
                <SpotlightCard trader={top3[1]} rank={2} isChampion={false} onPress={() => navigateToTrader(top3[1].uid)} />
                <SpotlightCard trader={top3[2]} rank={3} isChampion={false} onPress={() => navigateToTrader(top3[2].uid)} />
              </View>
            </View>
          )
        ) : top3.length > 0 ? (
          <View style={styles.spotlightMobile}>
            {top3.map((tr, i) => (
              <SpotlightCard key={tr.uid} trader={tr} rank={i + 1} isChampion={i === 0} onPress={() => navigateToTrader(tr.uid)} />
            ))}
          </View>
        ) : null}

        {/* Table */}
        {(rest.length > 0 || traders.length === 0) && (
          <View style={styles.tableCard}>
            <View style={styles.tableHeader}>
              <Text style={styles.tableTitle}>{t('rankings.topManagers')}</Text>
            </View>

            {isDesktop && (
              <View style={styles.colHeaders}>
                <Text style={[styles.colText, { width: 40 }]}>RANK</Text>
                <Text style={[styles.colText, { flex: 1 }]}>TRADER</Text>
                <Text style={[styles.colText, { width: 110, textAlign: 'right' }]}>PNL</Text>
                <Text style={[styles.colText, { width: 70, textAlign: 'right' }]}>WIN RATE</Text>
                <Text style={[styles.colText, { width: 80, textAlign: 'right' }]}>TRADES</Text>
                <Text style={[styles.colText, { width: 76, textAlign: 'center', marginLeft: 20 }]}>ACTION</Text>
              </View>
            )}

            {traders.length === 0 && (
              <View style={{ padding: 40, alignItems: 'center' }}>
                <Text style={{ color: Colors.textMuted, fontSize: 14 }}>{t('common.noData')}</Text>
              </View>
            )}

            {rest.map((trader, i) =>
              isDesktop ? (
                <RankingRow key={trader.uid} trader={trader} rank={i + 4} onPress={() => navigateToTrader(trader.uid)} />
              ) : (
                <MobileRankingRow key={trader.uid} trader={trader} rank={i + 4} onPress={() => navigateToTrader(trader.uid)} />
              )
            )}
          </View>
        )}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: Colors.background },
  scrollView: { flex: 1 },
  scrollContent: { padding: 20, paddingBottom: 40 },
  header: { marginBottom: 24 },
  headerDesktop: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    marginBottom: 32,
    gap: 24,
  },
  headerIntro: { flex: 1, maxWidth: 520 },
  headerControls: {
    alignItems: 'flex-end',
    gap: 14,
  },
  title: { fontSize: 32, fontWeight: '800', color: Colors.textActive, letterSpacing: -0.5, marginBottom: 6 },
  titleCompact: { fontSize: 24, fontWeight: '800', color: Colors.textActive, letterSpacing: -0.3 },
  subtitle: { fontSize: 14, color: Colors.textSecondary, maxWidth: 400, lineHeight: 20 },
  modeRail: {
    flexDirection: 'row',
    backgroundColor: '#171717',
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.24)',
    padding: 6,
    minWidth: 340,
  },
  modeBtn: {
    flex: 1,
    minHeight: 52,
    borderRadius: 999,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 20,
    borderWidth: 1,
    borderColor: 'transparent',
  },
  modeBtnActive: {
    backgroundColor: 'rgba(242,202,80,0.14)',
    borderColor: 'rgba(242,202,80,0.38)',
  },
  modeText: {
    fontSize: 15,
    fontWeight: '700',
    color: Colors.textSecondary,
  },
  modeTextActive: {
    color: Colors.primaryLight,
  },
  filterBar: {
    flexDirection: 'row',
    backgroundColor: '#1c1b1b',
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.2)',
    padding: 5,
    minHeight: 54,
  },
  filterBtn: { paddingHorizontal: 18, paddingVertical: 8, borderRadius: 8 },
  filterBtnActive: {
    backgroundColor: '#3a3939',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 6,
    elevation: 4,
  },
  filterText: { fontSize: 12, fontWeight: '600', color: Colors.textSecondary },
  filterTextActive: { color: Colors.primaryLight, fontWeight: '700' },
  followingHint: {
    minHeight: 54,
    minWidth: 340,
    paddingHorizontal: 18,
    justifyContent: 'center',
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.2)',
    backgroundColor: '#171717',
  },
  followingHintText: {
    fontSize: 13,
    fontWeight: '600',
    color: Colors.textMuted,
  },
  spotlightGrid: { flexDirection: 'row', gap: 16, marginBottom: 32, alignItems: 'flex-end' },
  spotlightMobile: { gap: 12, marginBottom: 24 },
  spotlightMobileRow: { flexDirection: 'row', gap: 12 },
  tableCard: {
    backgroundColor: '#201f1f',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.2)',
    overflow: 'hidden',
    ...Shadows.card,
  },
  tableHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingVertical: 18,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(77,70,53,0.2)',
    backgroundColor: Colors.background,
  },
  tableTitle: { fontSize: 16, fontWeight: '700', color: Colors.textActive },
  colHeaders: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 24,
    backgroundColor: '#1c1b1b',
  },
  colText: { fontSize: 9, fontWeight: '600', color: Colors.textSecondary, letterSpacing: 1.5 },

  // ── Split Layout ──
  splitLayout: {
    flexDirection: 'row',
  },
  detailPanel: {
    width: 420,
    flexShrink: 0,
    borderLeftWidth: 1,
    borderLeftColor: Colors.border,
    backgroundColor: Colors.background,
  },
});
