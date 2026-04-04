import { useState, useCallback } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  useWindowDimensions,
  Image,
  RefreshControl,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';

// ─── Types ───────────────────────────────────────────
interface TraderProfile {
  rank: number;
  name: string;
  subtitle: string;
  avatar?: string;
  pnl: number;
  winRate: number;
  totalTrades: number;
}

type TimeFilter = 'all' | 'weekly' | 'monthly';

// ─── Mock Data ───────────────────────────────────────
const TOP3: TraderProfile[] = [
  {
    rank: 1,
    name: 'VaultMaster_X',
    subtitle: 'Strategic Lead',
    pnl: 452,
    winRate: 92,
    totalTrades: 3241,
  },
  {
    rank: 2,
    name: 'Aurelius_Capital',
    subtitle: 'Institutional Grade',
    pnl: 380,
    winRate: 88,
    totalTrades: 2108,
  },
  {
    rank: 3,
    name: 'Quant_Oracle',
    subtitle: 'Algorithm Driven',
    pnl: 310,
    winRate: 85,
    totalTrades: 1876,
  },
];

const TABLE_DATA: TraderProfile[] = [
  { rank: 4, name: 'Zenith_Protocol', subtitle: 'Joined Oct 2023', pnl: 284.1, winRate: 82.4, totalTrades: 1402 },
  { rank: 5, name: 'IronBank_Lead', subtitle: 'Institutional Partner', pnl: 210.5, winRate: 79.1, totalTrades: 894 },
  { rank: 6, name: 'Crypto_Nomad', subtitle: 'Independent', pnl: 192.3, winRate: 74.8, totalTrades: 2119 },
  { rank: 7, name: 'Alpha_Stream', subtitle: 'Quant Fund', pnl: 156.8, winRate: 81.0, totalTrades: 452 },
];

// ─── Avatar Component ────────────────────────────────
function AvatarCircle({ name, size = 40, borderColor }: { name: string; size?: number; borderColor?: string }) {
  const letter = name.charAt(0).toUpperCase();
  const colors = ['#D4AF37', '#66e4b9', '#f2ca50', '#ffb4ab', '#627EEA', '#9945FF'];
  const idx = name.charCodeAt(0) % colors.length;
  const bg = colors[idx];

  return (
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
});

// ─── Top 3 Spotlight Card ────────────────────────────
function SpotlightCard({ trader, isChampion }: { trader: TraderProfile; isChampion: boolean }) {
  const cardHeight = isChampion ? 440 : 380;
  const avatarSize = isChampion ? 96 : 72;

  return (
    <View
      style={[
        spotStyles.card,
        { height: cardHeight },
        isChampion && spotStyles.cardChampion,
      ]}
    >
      {/* Rank watermark */}
      <Text style={[spotStyles.rankWatermark, isChampion && spotStyles.rankWatermarkChampion]}>
        {String(trader.rank).padStart(2, '0')}
      </Text>

      {/* Champion glow */}
      {isChampion && <View style={spotStyles.glowOrb} />}

      {/* Avatar */}
      <View style={{ marginBottom: isChampion ? 16 : 12 }}>
        <AvatarCircle
          name={trader.name}
          size={avatarSize}
          borderColor={isChampion ? Colors.primary : undefined}
        />
        {isChampion && (
          <View style={spotStyles.starBadge}>
            <Text style={spotStyles.starIcon}>★</Text>
          </View>
        )}
      </View>

      {/* Name */}
      <Text style={[spotStyles.name, isChampion && spotStyles.nameChampion]}>
        {trader.name}
      </Text>
      <Text style={[spotStyles.subtitle, isChampion && spotStyles.subtitleChampion]}>
        {trader.subtitle.toUpperCase()}
      </Text>

      {/* Stats */}
      <View style={[spotStyles.statsArea, { marginBottom: isChampion ? 20 : 16 }]}>
        <View style={[spotStyles.statRow, isChampion && spotStyles.statRowChampion]}>
          <Text style={spotStyles.statLabel}>{isChampion ? 'Total PnL' : 'PnL'}</Text>
          <Text style={[spotStyles.statValue, spotStyles.statPnl, isChampion && spotStyles.statValueBig]}>
            +{trader.pnl}%
          </Text>
        </View>
        <View style={spotStyles.statRow}>
          <Text style={spotStyles.statLabel}>Win Rate</Text>
          <Text style={[spotStyles.statValue, isChampion && { fontSize: 18 }]}>
            {trader.winRate}%
          </Text>
        </View>
      </View>

      {/* CTA Button */}
      {isChampion ? (
        <TouchableOpacity style={spotStyles.ctaPrimary} activeOpacity={0.85}>
          <Text style={spotStyles.ctaPrimaryText}>CONNECT & FOLLOW</Text>
        </TouchableOpacity>
      ) : (
        <TouchableOpacity style={spotStyles.ctaOutline} activeOpacity={0.7}>
          <Text style={spotStyles.ctaOutlineText}>COPY PORTFOLIO</Text>
        </TouchableOpacity>
      )}
    </View>
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
  starBadge: {
    position: 'absolute',
    bottom: -4,
    right: -4,
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: Colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: Colors.background,
    ...Shadows.card,
  },
  starIcon: {
    color: Colors.background,
    fontSize: 16,
    fontWeight: '800',
  },
  name: {
    fontSize: 17,
    fontWeight: '700',
    color: Colors.textActive,
    marginBottom: 4,
  },
  nameChampion: {
    fontSize: 22,
    fontWeight: '800',
  },
  subtitle: {
    fontSize: 10,
    color: Colors.textSecondary,
    letterSpacing: 2,
    marginBottom: 20,
  },
  subtitleChampion: {
    color: Colors.primaryLight,
    letterSpacing: 3,
    marginBottom: 24,
  },
  statsArea: {
    width: '100%',
    gap: 10,
  },
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
  statLabel: {
    fontSize: 12,
    color: Colors.textSecondary,
  },
  statValue: {
    fontSize: 15,
    fontWeight: '700',
    color: Colors.textActive,
  },
  statValueBig: {
    fontSize: 22,
  },
  statPnl: {
    color: Colors.up,
  },
  ctaPrimary: {
    width: '100%',
    backgroundColor: Colors.primaryLight,
    paddingVertical: 14,
    borderRadius: 10,
    alignItems: 'center',
    ...Shadows.glow,
  },
  ctaPrimaryText: {
    color: Colors.background,
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 2,
  },
  ctaOutline: {
    width: '100%',
    borderWidth: 1,
    borderColor: 'rgba(242,202,80,0.4)',
    paddingVertical: 12,
    borderRadius: 10,
    alignItems: 'center',
  },
  ctaOutlineText: {
    color: Colors.primaryLight,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 2,
  },
});

// ─── Table Row ───────────────────────────────────────
function RankingRow({ trader }: { trader: TraderProfile }) {
  const barWidth = Math.min(trader.pnl / 300 * 100, 100);

  return (
    <View style={rowStyles.container}>
      {/* Rank */}
      <Text style={rowStyles.rank}>{String(trader.rank).padStart(2, '0')}</Text>

      {/* Avatar + Name */}
      <View style={rowStyles.traderInfo}>
        <AvatarCircle name={trader.name} size={36} />
        <View>
          <Text style={rowStyles.traderName}>{trader.name}</Text>
          <Text style={rowStyles.traderSub}>{trader.subtitle}</Text>
        </View>
      </View>

      {/* PnL */}
      <View style={rowStyles.pnlCol}>
        <Text style={rowStyles.pnlText}>+{trader.pnl}%</Text>
        <View style={rowStyles.pnlBarTrack}>
          <View style={[rowStyles.pnlBarFill, { width: `${barWidth}%` }]} />
        </View>
      </View>

      {/* Win Rate */}
      <Text style={rowStyles.winRate}>{trader.winRate}%</Text>

      {/* Total Trades */}
      <Text style={rowStyles.trades}>{trader.totalTrades.toLocaleString()}</Text>

      {/* Follow */}
      <TouchableOpacity style={rowStyles.followBtn} activeOpacity={0.7}>
        <Text style={rowStyles.followText}>Follow</Text>
      </TouchableOpacity>
    </View>
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
  rank: {
    width: 40,
    fontSize: 16,
    fontWeight: '700',
    color: Colors.textSecondary,
    opacity: 0.4,
  },
  traderInfo: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  traderName: {
    fontSize: 14,
    fontWeight: '700',
    color: Colors.textActive,
  },
  traderSub: {
    fontSize: 10,
    color: Colors.textSecondary,
    marginTop: 1,
  },
  pnlCol: {
    width: 110,
    alignItems: 'flex-end',
  },
  pnlText: {
    fontSize: 14,
    fontWeight: '700',
    color: Colors.up,
  },
  pnlBarTrack: {
    width: 80,
    height: 3,
    backgroundColor: Colors.border,
    borderRadius: 2,
    overflow: 'hidden',
    marginTop: 4,
  },
  pnlBarFill: {
    height: '100%',
    backgroundColor: Colors.up,
    borderRadius: 2,
  },
  winRate: {
    width: 70,
    textAlign: 'right',
    fontSize: 14,
    fontWeight: '600',
    color: Colors.textActive,
  },
  trades: {
    width: 80,
    textAlign: 'right',
    fontSize: 14,
    color: Colors.textSecondary,
    opacity: 0.6,
  },
  followBtn: {
    marginLeft: 20,
    backgroundColor: '#2a2a2a',
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.3)',
    borderRadius: 6,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  followText: {
    fontSize: 12,
    fontWeight: '700',
    color: Colors.textActive,
  },
});

// ─── Mobile Row (compact) ────────────────────────────
function MobileRankingRow({ trader }: { trader: TraderProfile }) {
  return (
    <View style={mobileRowStyles.container}>
      <Text style={mobileRowStyles.rank}>#{trader.rank}</Text>
      <AvatarCircle name={trader.name} size={36} />
      <View style={mobileRowStyles.info}>
        <Text style={mobileRowStyles.name}>{trader.name}</Text>
        <Text style={mobileRowStyles.sub}>{trader.subtitle}</Text>
      </View>
      <View style={mobileRowStyles.statsCol}>
        <Text style={mobileRowStyles.pnl}>+{trader.pnl}%</Text>
        <Text style={mobileRowStyles.wr}>{trader.winRate}% WR</Text>
      </View>
    </View>
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
  rank: {
    width: 28,
    fontSize: 13,
    fontWeight: '700',
    color: Colors.textMuted,
  },
  info: { flex: 1 },
  name: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.textActive,
  },
  sub: {
    fontSize: 10,
    color: Colors.textMuted,
    marginTop: 1,
  },
  statsCol: { alignItems: 'flex-end' },
  pnl: {
    fontSize: 14,
    fontWeight: '700',
    color: Colors.up,
  },
  wr: {
    fontSize: 11,
    color: Colors.textSecondary,
    marginTop: 2,
  },
});

// ─── Main Screen ─────────────────────────────────────
export default function RankingsScreen() {
  const { t } = useTranslation();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;
  const [timeFilter, setTimeFilter] = useState<TimeFilter>('weekly');
  const [refreshing, setRefreshing] = useState(false);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    // TODO: fetch real data
    await new Promise((r) => setTimeout(r, 800));
    setRefreshing(false);
  }, []);

  const champion = TOP3[0];
  const second = TOP3[1];
  const third = TOP3[2];

  const TIME_FILTERS: { key: TimeFilter; label: string }[] = [
    { key: 'all', label: t('rankings.allTime') },
    { key: 'weekly', label: t('rankings.weekly') },
    { key: 'monthly', label: t('rankings.monthly') },
  ];

  return (
    <View style={styles.container}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={Colors.primary}
            colors={[Colors.primary]}
          />
        }
      >
        {/* ── Header & Filters ── */}
        <View style={[styles.header, isDesktop && styles.headerDesktop]}>
          <View style={{ flex: 1 }}>
            <Text style={styles.title}>{t('rankings.title')}</Text>
            <Text style={styles.subtitle}>{t('rankings.subtitle')}</Text>
          </View>
          <View style={styles.filterBar}>
            {TIME_FILTERS.map((f) => (
              <TouchableOpacity
                key={f.key}
                style={[styles.filterBtn, timeFilter === f.key && styles.filterBtnActive]}
                onPress={() => setTimeFilter(f.key)}
              >
                <Text style={[styles.filterText, timeFilter === f.key && styles.filterTextActive]}>
                  {f.label}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>

        {/* ── Top 3 Spotlight (desktop: side by side, mobile: stacked) ── */}
        {isDesktop ? (
          <View style={styles.spotlightGrid}>
            <SpotlightCard trader={second} isChampion={false} />
            <SpotlightCard trader={champion} isChampion />
            <SpotlightCard trader={third} isChampion={false} />
          </View>
        ) : (
          <View style={styles.spotlightMobile}>
            <SpotlightCard trader={champion} isChampion />
            <View style={styles.spotlightMobileRow}>
              <SpotlightCard trader={second} isChampion={false} />
              <SpotlightCard trader={third} isChampion={false} />
            </View>
          </View>
        )}

        {/* ── Rankings Table ── */}
        <View style={styles.tableCard}>
          {/* Table Header */}
          <View style={styles.tableHeader}>
            <Text style={styles.tableTitle}>{t('rankings.topManagers')}</Text>
            <View style={styles.legendRow}>
              <View style={styles.legendItem}>
                <View style={[styles.legendDot, { backgroundColor: Colors.up }]} />
                <Text style={styles.legendText}>Net Positive</Text>
              </View>
              <View style={styles.legendItem}>
                <View style={[styles.legendDot, { backgroundColor: Colors.down }]} />
                <Text style={styles.legendText}>Net Negative</Text>
              </View>
            </View>
          </View>

          {/* Column Headers (desktop) */}
          {isDesktop && (
            <View style={styles.colHeaders}>
              <Text style={[styles.colText, { width: 40 }]}>RANK</Text>
              <Text style={[styles.colText, { flex: 1 }]}>TRADER ENTITY</Text>
              <Text style={[styles.colText, { width: 110, textAlign: 'right' }]}>PNL (WEEKLY)</Text>
              <Text style={[styles.colText, { width: 70, textAlign: 'right' }]}>WIN RATE</Text>
              <Text style={[styles.colText, { width: 80, textAlign: 'right' }]}>TOTAL TRADES</Text>
              <Text style={[styles.colText, { width: 76, textAlign: 'center', marginLeft: 20 }]}>PROTOCOL ACTION</Text>
            </View>
          )}

          {/* Rows */}
          {TABLE_DATA.map((trader) =>
            isDesktop ? (
              <RankingRow key={trader.rank} trader={trader} />
            ) : (
              <MobileRankingRow key={trader.rank} trader={trader} />
            )
          )}

          {/* Load More */}
          <TouchableOpacity style={styles.loadMore} activeOpacity={0.7}>
            <Text style={styles.loadMoreText}>{t('rankings.loadFull')} ↓</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  scrollView: { flex: 1 },
  scrollContent: { padding: 20, paddingBottom: 40 },

  // Header
  header: {
    marginBottom: 24,
  },
  headerDesktop: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    marginBottom: 32,
  },
  title: {
    fontSize: 32,
    fontWeight: '800',
    color: Colors.textActive,
    letterSpacing: -0.5,
    marginBottom: 6,
  },
  subtitle: {
    fontSize: 14,
    color: Colors.textSecondary,
    maxWidth: 400,
    lineHeight: 20,
  },

  // Time Filter
  filterBar: {
    flexDirection: 'row',
    backgroundColor: '#1c1b1b',
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(77,70,53,0.2)',
    padding: 5,
    marginTop: 12,
  },
  filterBtn: {
    paddingHorizontal: 18,
    paddingVertical: 8,
    borderRadius: 8,
  },
  filterBtnActive: {
    backgroundColor: '#3a3939',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 6,
    elevation: 4,
  },
  filterText: {
    fontSize: 12,
    fontWeight: '600',
    color: Colors.textSecondary,
  },
  filterTextActive: {
    color: Colors.primaryLight,
    fontWeight: '700',
  },

  // Spotlight
  spotlightGrid: {
    flexDirection: 'row',
    gap: 16,
    marginBottom: 32,
    alignItems: 'flex-end',
  },
  spotlightMobile: {
    gap: 12,
    marginBottom: 24,
  },
  spotlightMobileRow: {
    flexDirection: 'row',
    gap: 12,
  },

  // Table
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
  tableTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: Colors.textActive,
  },
  legendRow: {
    flexDirection: 'row',
    gap: 16,
  },
  legendItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  legendDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
  },
  legendText: {
    fontSize: 11,
    color: Colors.textSecondary,
  },

  // Column Headers
  colHeaders: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 24,
    backgroundColor: '#1c1b1b',
  },
  colText: {
    fontSize: 9,
    fontWeight: '600',
    color: Colors.textSecondary,
    letterSpacing: 1.5,
  },

  // Load More
  loadMore: {
    paddingVertical: 20,
    alignItems: 'center',
    backgroundColor: '#1c1b1b',
  },
  loadMoreText: {
    fontSize: 11,
    fontWeight: '700',
    color: Colors.textSecondary,
    letterSpacing: 2,
  },
});
