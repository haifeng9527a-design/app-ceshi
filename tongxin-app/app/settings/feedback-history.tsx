import { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Image,
  RefreshControl,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Colors } from '../../theme/colors';
import AppIcon, { type AppIconName } from '../../components/ui/AppIcon';
import { Config } from '../../services/config';
import { useFeedbackStore } from '../../services/store/feedbackStore';
import type { Feedback } from '../../services/api/feedbackApi';

type StatusKey = 'pending' | 'processing' | 'resolved' | 'rejected';

const STATUS_STYLE: Record<StatusKey, { bg: string; fg: string }> = {
  pending: { bg: 'rgba(255,184,0,0.14)', fg: '#f4b400' },
  processing: { bg: 'rgba(85,145,255,0.14)', fg: '#5a95ff' },
  resolved: { bg: 'rgba(102,228,185,0.14)', fg: '#66e4b9' },
  rejected: { bg: 'rgba(255,90,90,0.12)', fg: '#ff6b6b' },
};

const CATEGORY_ICON: Record<string, AppIconName> = {
  complaint: 'shield',
  suggestion: 'bulb',
  bug: 'settings',
  other: 'paper',
};

function resolveImageUrl(url: string): string {
  if (!url) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  // 后端 /uploads/xxx 是相对路径，拼上 API_BASE 才能加载
  return `${Config.API_BASE_URL}${url.startsWith('/') ? '' : '/'}${url}`;
}

export default function FeedbackHistoryScreen() {
  const router = useRouter();
  const { t } = useTranslation();
  const items = useFeedbackStore((s) => s.items);
  const loading = useFeedbackStore((s) => s.loading);
  const fetchList = useFeedbackStore((s) => s.fetchList);
  const markRead = useFeedbackStore((s) => s.markRead);
  const [expanded, setExpanded] = useState<string | null>(null);

  // 用 useFocusEffect：每次页面获得焦点（首次进入、从其他页 replace 回来、tab 切回）都重新拉一次，
  // 避免 zustand store 里的旧列表盖住刚提交的新记录。
  useFocusEffect(
    useCallback(() => {
      fetchList();
    }, [fetchList])
  );

  const onToggle = (fb: Feedback) => {
    const willOpen = expanded !== fb.id;
    setExpanded(willOpen ? fb.id : null);
    if (willOpen && fb.user_unread) {
      markRead(fb.id);
    }
  };

  const statusKey = (s: string): StatusKey => {
    if (s === 'processing' || s === 'resolved' || s === 'rejected') return s;
    return 'pending';
  };

  const renderItem = ({ item }: { item: Feedback }) => {
    const key = statusKey(item.status);
    const sty = STATUS_STYLE[key];
    const icon = CATEGORY_ICON[item.category] || 'paper';
    const open = expanded === item.id;
    const hasReply = !!item.admin_reply?.trim();

    return (
      <TouchableOpacity
        style={styles.card}
        activeOpacity={0.85}
        onPress={() => onToggle(item)}
      >
        <View style={styles.cardHeader}>
          <View style={styles.iconBox}>
            <AppIcon name={icon} size={16} color={Colors.primary} />
          </View>
          <View style={[styles.statusPill, { backgroundColor: sty.bg }]}>
            <Text style={[styles.statusText, { color: sty.fg }]}>
              {t(`feedback.status${key.charAt(0).toUpperCase() + key.slice(1)}`)}
            </Text>
          </View>
          {item.user_unread && (
            <View style={styles.unreadPill}>
              <Text style={styles.unreadText}>{t('feedback.unreadTag')}</Text>
            </View>
          )}
          <View style={{ flex: 1 }} />
          <Text style={styles.timeText}>
            {new Date(item.created_at).toLocaleString()}
          </Text>
        </View>

        <Text style={styles.contentText} numberOfLines={open ? undefined : 3}>
          {item.content}
        </Text>

        {item.image_urls && item.image_urls.length > 0 && (
          <View style={styles.imageRow}>
            {item.image_urls.slice(0, open ? undefined : 3).map((url, i) => (
              <Image
                key={`${item.id}-${i}`}
                source={{ uri: resolveImageUrl(url) }}
                style={styles.thumb}
              />
            ))}
          </View>
        )}

        {open && (
          <View style={styles.replyBox}>
            <Text style={styles.replyTitle}>
              {hasReply ? t('feedback.adminReplyTitle') : t('feedback.awaitingReply')}
            </Text>
            {hasReply && (
              <>
                <Text style={styles.replyText}>{item.admin_reply}</Text>
                {item.replied_at && (
                  <Text style={styles.replyMeta}>
                    {new Date(item.replied_at).toLocaleString()}
                  </Text>
                )}
              </>
            )}
          </View>
        )}
      </TouchableOpacity>
    );
  };

  const empty = (
    <View style={styles.emptyWrap}>
      <Text style={styles.emptyText}>{t('feedback.noHistory')}</Text>
      <TouchableOpacity
        style={styles.emptyBtn}
        activeOpacity={0.85}
        onPress={() => router.replace('/settings/feedback')}
      >
        <Text style={styles.emptyBtnText}>{t('feedback.goSubmit')}</Text>
      </TouchableOpacity>
    </View>
  );

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity
          onPress={() => {
            // 提交页走的是 router.replace 进来，有可能堆栈为空（直接访问/replace 后），
            // router.back() 会静默失败。canGoBack 判一下，不行就兜到 Profile。
            if (router.canGoBack()) {
              router.back();
            } else {
              router.replace('/(tabs)/profile');
            }
          }}
          style={styles.backBtn}
          activeOpacity={0.7}
        >
          <AppIcon name="back" size={18} color={Colors.textSecondary} />
        </TouchableOpacity>
        <View style={{ flex: 1 }}>
          <Text style={styles.title}>{t('feedback.historyTitle')}</Text>
          <Text style={styles.subtitle}>{t('feedback.historySubtitle')}</Text>
        </View>
        <TouchableOpacity
          onPress={() => router.push('/settings/feedback')}
          style={styles.newBtn}
          activeOpacity={0.85}
        >
          <Text style={styles.newBtnText}>+</Text>
        </TouchableOpacity>
      </View>

      {loading && items.length === 0 ? (
        <View style={styles.loadingWrap}>
          <ActivityIndicator color={Colors.primary} />
        </View>
      ) : (
        <FlatList
          data={items}
          keyExtractor={(it) => it.id}
          contentContainerStyle={styles.listContent}
          renderItem={renderItem}
          ListEmptyComponent={empty}
          refreshControl={
            <RefreshControl refreshing={loading} onRefresh={fetchList} tintColor={Colors.primary} />
          }
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: Colors.background },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 12,
    gap: 12,
  },
  backBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: { color: Colors.textActive, fontSize: 20, fontWeight: '800' },
  subtitle: { color: Colors.textMuted, fontSize: 12, marginTop: 2 },
  newBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: Colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  newBtnText: { color: Colors.textOnPrimary, fontSize: 20, fontWeight: '700', lineHeight: 22 },
  loadingWrap: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  listContent: { padding: 20, gap: 12, paddingBottom: 40 },
  card: {
    backgroundColor: Colors.surface,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 16,
    gap: 10,
  },
  cardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  iconBox: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: Colors.primaryDim,
    alignItems: 'center',
    justifyContent: 'center',
  },
  statusPill: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 999,
  },
  statusText: { fontSize: 11, fontWeight: '700' },
  unreadPill: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 999,
    backgroundColor: '#ff3b30',
  },
  unreadText: { color: '#fff', fontSize: 10, fontWeight: '700' },
  timeText: { color: Colors.textMuted, fontSize: 11 },
  contentText: { color: Colors.textActive, fontSize: 14, lineHeight: 20 },
  imageRow: { flexDirection: 'row', gap: 8, flexWrap: 'wrap' },
  thumb: {
    width: 70,
    height: 70,
    borderRadius: 10,
    backgroundColor: Colors.surfaceAlt,
  },
  replyBox: {
    marginTop: 4,
    padding: 12,
    borderRadius: 10,
    backgroundColor: Colors.surfaceAlt,
    borderLeftWidth: 3,
    borderLeftColor: Colors.primary,
    gap: 6,
  },
  replyTitle: { color: Colors.primary, fontSize: 12, fontWeight: '700' },
  replyText: { color: Colors.textActive, fontSize: 13, lineHeight: 20 },
  replyMeta: { color: Colors.textMuted, fontSize: 11 },
  emptyWrap: {
    alignItems: 'center',
    paddingVertical: 80,
    gap: 16,
  },
  emptyText: { color: Colors.textMuted, fontSize: 14 },
  emptyBtn: {
    paddingHorizontal: 24,
    paddingVertical: 10,
    borderRadius: 999,
    backgroundColor: Colors.primary,
  },
  emptyBtnText: { color: Colors.textOnPrimary, fontWeight: '700' },
});
