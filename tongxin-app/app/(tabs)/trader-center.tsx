import { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Switch,
  RefreshControl,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { Colors } from '../../theme/colors';
import { useAuthStore } from '../../services/store/authStore';
import ApplicationForm from '../../components/trader/ApplicationForm';
import {
  getMyApplication,
  getMyStats,
  getMyFollowers,
  toggleCopyTrading,
  TraderApplication,
  TraderStats,
  CopyTrading,
} from '../../services/api/traderApi';

type PageState = 'loading' | 'not-logged-in' | 'no-application' | 'applying' | 'pending' | 'rejected' | 'dashboard';

export default function TraderCenterScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { user, syncProfile } = useAuthStore();

  const [pageState, setPageState] = useState<PageState>('loading');
  const [application, setApplication] = useState<TraderApplication | null>(null);
  const [stats, setStats] = useState<TraderStats | null>(null);
  const [followers, setFollowers] = useState<CopyTrading[]>([]);
  const [copyEnabled, setCopyEnabled] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const loadData = useCallback(async () => {
    if (!user) {
      setPageState('not-logged-in');
      return;
    }

    // Already approved trader
    if (user.isTrader) {
      try {
        const [statsRes, followersRes] = await Promise.all([
          getMyStats(),
          getMyFollowers(),
        ]);
        setStats(statsRes);
        setFollowers(followersRes || []);
        setCopyEnabled(user.allowCopyTrading || false);
        setPageState('dashboard');
      } catch {
        setPageState('dashboard');
      }
      return;
    }

    // Check application status
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

  // Dashboard
  return (
    <ScrollView
      style={styles.container}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={Colors.primary} />}
    >
      <View style={styles.dashHeader}>
        <Text style={styles.dashTitle}>{t('traderCenter.dashboard')}</Text>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          <TouchableOpacity
            style={styles.viewProfileBtn}
            onPress={() => router.push(`/trader/${user?.uid}` as any)}
          >
            <Text style={styles.viewProfileBtnText}>查看主页</Text>
          </TouchableOpacity>
          <View style={styles.certBadge}>
            <Text style={styles.certBadgeText}>✓ Certified</Text>
          </View>
        </View>
      </View>

      {/* Stats Grid */}
      <View style={styles.statsGrid}>
        <StatCard label={t('traderCenter.totalTrades')} value={String(stats?.total_trades || 0)} />
        <StatCard
          label={t('traderCenter.winRate')}
          value={`${(stats?.win_rate || 0).toFixed(1)}%`}
          color={Colors.up}
        />
        <StatCard
          label={t('traderCenter.totalPnl')}
          value={`$${(stats?.total_pnl || 0).toFixed(2)}`}
          color={(stats?.total_pnl || 0) >= 0 ? Colors.up : Colors.down}
        />
        <StatCard
          label={t('traderCenter.avgPnl')}
          value={`$${(stats?.avg_pnl || 0).toFixed(2)}`}
          color={(stats?.avg_pnl || 0) >= 0 ? Colors.up : Colors.down}
        />
        <StatCard
          label={t('traderCenter.maxDrawdown')}
          value={`${(stats?.max_drawdown || 0).toFixed(1)}%`}
          color={Colors.down}
        />
        <StatCard
          label={t('traderCenter.followersCount')}
          value={String(stats?.followers_count || 0)}
        />
      </View>

      {/* Copy Trading Toggle */}
      <View style={styles.settingCard}>
        <View style={styles.settingRow}>
          <View>
            <Text style={styles.settingLabel}>{t('traderCenter.copyTradingToggle')}</Text>
            <Text style={styles.settingHint}>
              {copyEnabled ? t('traderCenter.copyTradingOn') : t('traderCenter.copyTradingOff')}
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

      {/* Followers List */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('traderCenter.myFollowers')}</Text>
        {followers.length === 0 ? (
          <Text style={styles.emptyText}>{t('traderCenter.noFollowers')}</Text>
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
              <Text style={styles.followerStatus}>{f.status}</Text>
            </View>
          ))
        )}
      </View>
    </ScrollView>
  );
}

function StatCard({
  label,
  value,
  color,
}: {
  label: string;
  value: string;
  color?: string;
}) {
  return (
    <View style={styles.statCard}>
      <Text style={styles.statLabel}>{label}</Text>
      <Text style={[styles.statValue, color ? { color } : undefined]}>{value}</Text>
    </View>
  );
}

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

  // Dashboard
  dashHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 20,
  },
  dashTitle: { color: Colors.textActive, fontSize: 22, fontWeight: '700' },
  certBadge: {
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.primary,
  },
  certBadgeText: { color: Colors.primary, fontSize: 13, fontWeight: '700' },
  viewProfileBtn: {
    backgroundColor: Colors.surface,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  viewProfileBtnText: { color: Colors.textSecondary, fontSize: 13, fontWeight: '600' },

  // Stats
  statsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: 16,
    gap: 12,
  },
  statCard: {
    backgroundColor: Colors.surface,
    borderRadius: 12,
    padding: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    minWidth: 140,
    flex: 1,
  },
  statLabel: { color: Colors.textMuted, fontSize: 12, marginBottom: 6 },
  statValue: { color: Colors.textActive, fontSize: 20, fontWeight: '700' },

  // Settings
  settingCard: {
    backgroundColor: Colors.surface,
    borderRadius: 12,
    margin: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  settingRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  settingLabel: { color: Colors.textActive, fontSize: 15, fontWeight: '600' },
  settingHint: { color: Colors.textMuted, fontSize: 12, marginTop: 2 },

  // Followers
  section: { padding: 16 },
  sectionTitle: {
    color: Colors.textActive,
    fontSize: 17,
    fontWeight: '700',
    marginBottom: 12,
  },
  emptyText: { color: Colors.textMuted, fontSize: 14 },
  followerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surface,
    borderRadius: 10,
    padding: 12,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: Colors.border,
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
  followerStatus: { color: Colors.up, fontSize: 12, fontWeight: '600' },
});
