import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Alert,
  useWindowDimensions,
  Image,
} from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Colors } from '../../theme/colors';
import { HtmlContent } from '../../components/editor/RichTextEditor';
import { useAuthStore } from '../../services/store/authStore';
import {
  getStrategy,
  likeStrategy,
  deleteStrategy,
  TraderStrategy,
} from '../../services/api/traderStrategyApi';

const CATEGORY_LABELS: Record<string, string> = {
  technical: '技术分析',
  fundamental: '基本面',
  macro: '宏观经济',
  news: '市场资讯',
  education: '交易教学',
  other: '其他',
};

export default function StrategyDetailScreen() {
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuthStore();
  const { width } = useWindowDimensions();
  const isDesktop = width >= 768;

  const [strategy, setStrategy] = useState<TraderStrategy | null>(null);
  const [liked, setLiked] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    getStrategy(id)
      .then((res) => {
        setStrategy(res.strategy);
        setLiked(res.liked);
      })
      .catch(() => Alert.alert('Error', 'Failed to load strategy'))
      .finally(() => setLoading(false));
  }, [id]);

  const handleLike = async () => {
    if (!id) return;
    try {
      const res = await likeStrategy(id);
      setLiked(res.liked);
      if (strategy) {
        setStrategy({
          ...strategy,
          likes: strategy.likes + (res.liked ? 1 : -1),
        });
      }
    } catch {}
  };

  const handleDelete = () => {
    Alert.alert('确认删除', '删除后无法恢复，确定要删除这篇策略吗？', [
      { text: '取消', style: 'cancel' },
      {
        text: '删除',
        style: 'destructive',
        onPress: async () => {
          try {
            await deleteStrategy(id!);
            goBack();
          } catch {}
        },
      },
    ]);
  };

  const handleEdit = () => {
    router.push(`/strategy/editor?id=${id}` as any);
  };

  const goBack = () => {
    router.back();
  };

  const goToAuthor = () => {
    if (!strategy) return;
    router.push(`/trader/${strategy.author_id}` as any);
  };

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" color={Colors.primary} />
      </View>
    );
  }

  if (!strategy) {
    return (
      <View style={styles.centered}>
        <Text style={styles.errorText}>策略不存在</Text>
        <TouchableOpacity onPress={goBack} style={styles.backButton}>
          <Text style={styles.backButtonText}>返回</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const isOwner = user?.uid === strategy.author_id;
  const publishDate = new Date(strategy.created_at).toLocaleDateString('zh-CN', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });

  return (
    <View style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={goBack}>
          <Text style={styles.backBtn}>← 返回</Text>
        </TouchableOpacity>
        <View style={{ flex: 1 }} />
        {isOwner && (
          <View style={styles.ownerActions}>
            <TouchableOpacity style={styles.editBtn} onPress={handleEdit}>
              <Text style={styles.editBtnText}>编辑</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.deleteBtn} onPress={handleDelete}>
              <Text style={styles.deleteBtnText}>删除</Text>
            </TouchableOpacity>
          </View>
        )}
      </View>

      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={[
          styles.scrollContent,
          isDesktop && { maxWidth: 800, alignSelf: 'center', width: '100%' },
        ]}
      >
        {/* Cover Image */}
        {strategy.cover_image ? (
          <Image
            source={{ uri: strategy.cover_image }}
            style={styles.coverImage}
            resizeMode="cover"
          />
        ) : null}

        {/* Category + Meta */}
        <View style={styles.metaRow}>
          {strategy.category ? (
            <View style={styles.categoryBadge}>
              <Text style={styles.categoryBadgeText}>
                {CATEGORY_LABELS[strategy.category] || strategy.category}
              </Text>
            </View>
          ) : null}
          <Text style={styles.metaText}>{publishDate}</Text>
          <Text style={styles.metaText}>· {strategy.views} 阅读</Text>
          <Text style={styles.metaText}>· {strategy.likes} 赞</Text>
        </View>

        {/* Title */}
        <Text style={styles.title}>{strategy.title}</Text>

        {/* Author Card */}
        <TouchableOpacity style={styles.authorCard} onPress={goToAuthor}>
          <View style={styles.authorAvatar}>
            {strategy.author_avatar ? (
              <Image
                source={{ uri: strategy.author_avatar }}
                style={styles.avatarImage}
              />
            ) : (
              <Text style={styles.avatarFallback}>
                {(strategy.author_name || '?')[0].toUpperCase()}
              </Text>
            )}
            {strategy.is_trader && (
              <View style={styles.traderBadge}>
                <Text style={styles.traderBadgeText}>V</Text>
              </View>
            )}
          </View>
          <View>
            <Text style={styles.authorName}>{strategy.author_name || 'Unknown'}</Text>
            <Text style={styles.authorRole}>
              {strategy.is_trader ? '认证交易员' : '用户'}
            </Text>
          </View>
        </TouchableOpacity>

        {/* Content */}
        <View style={styles.contentSection}>
          <HtmlContent html={strategy.content_html} />
        </View>

        {/* Like + Share */}
        <View style={styles.actionsRow}>
          <TouchableOpacity
            style={[styles.likeBtn, liked && styles.likeBtnActive]}
            onPress={handleLike}
          >
            <Text style={[styles.likeBtnText, liked && styles.likeBtnTextActive]}>
              {liked ? '❤️' : '🤍'} {strategy.likes}
            </Text>
          </TouchableOpacity>
        </View>

        {/* Status badge for drafts */}
        {strategy.status !== 'published' && (
          <View style={styles.draftBanner}>
            <Text style={styles.draftBannerText}>
              {strategy.status === 'draft' ? '📝 草稿 — 仅自己可见' : '📦 已归档'}
            </Text>
          </View>
        )}

        <View style={{ height: 60 }} />
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.background,
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: Colors.background,
  },
  errorText: {
    color: Colors.textMuted,
    fontSize: 16,
    marginBottom: 16,
  },
  backButton: {
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 8,
    backgroundColor: Colors.surface,
  },
  backButtonText: {
    color: Colors.primary,
    fontWeight: '600',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
    backgroundColor: Colors.surface,
    gap: 12,
  },
  backBtn: {
    color: Colors.primary,
    fontSize: 15,
    fontWeight: '600',
  },
  ownerActions: {
    flexDirection: 'row',
    gap: 8,
  },
  editBtn: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: Colors.primary,
  },
  editBtnText: {
    color: Colors.primary,
    fontSize: 13,
    fontWeight: '600',
  },
  deleteBtn: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: Colors.down,
  },
  deleteBtnText: {
    color: Colors.down,
    fontSize: 13,
    fontWeight: '600',
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: 24,
  },
  coverImage: {
    width: '100%',
    height: 300,
    borderRadius: 16,
    marginBottom: 24,
    backgroundColor: Colors.surface,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 12,
    flexWrap: 'wrap',
  },
  categoryBadge: {
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 10,
    paddingVertical: 3,
    borderRadius: 12,
  },
  categoryBadgeText: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '600',
  },
  metaText: {
    color: Colors.textMuted,
    fontSize: 13,
  },
  title: {
    fontSize: 32,
    fontWeight: '800',
    color: Colors.textActive,
    marginBottom: 20,
    lineHeight: 42,
  },
  authorCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 16,
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: Colors.border,
    marginBottom: 24,
  },
  authorAvatar: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: Colors.primaryDim,
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  avatarImage: {
    width: 44,
    height: 44,
    borderRadius: 22,
  },
  avatarFallback: {
    color: Colors.primary,
    fontSize: 18,
    fontWeight: '700',
  },
  traderBadge: {
    position: 'absolute',
    bottom: -2,
    right: -2,
    width: 18,
    height: 18,
    borderRadius: 9,
    backgroundColor: Colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: Colors.background,
  },
  traderBadgeText: {
    color: '#fff',
    fontSize: 9,
    fontWeight: '800',
  },
  authorName: {
    color: Colors.textActive,
    fontSize: 15,
    fontWeight: '600',
  },
  authorRole: {
    color: Colors.textMuted,
    fontSize: 12,
    marginTop: 2,
  },
  contentSection: {
    marginBottom: 32,
  },
  actionsRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    paddingVertical: 24,
    borderTopWidth: 1,
    borderColor: Colors.border,
    gap: 16,
  },
  likeBtn: {
    paddingHorizontal: 28,
    paddingVertical: 12,
    borderRadius: 24,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.border,
  },
  likeBtnActive: {
    backgroundColor: 'rgba(255, 59, 48, 0.1)',
    borderColor: 'rgba(255, 59, 48, 0.3)',
  },
  likeBtnText: {
    fontSize: 16,
    fontWeight: '600',
    color: Colors.textMuted,
  },
  likeBtnTextActive: {
    color: '#FF3B30',
  },
  draftBanner: {
    backgroundColor: 'rgba(255, 204, 0, 0.1)',
    borderRadius: 8,
    padding: 12,
    alignItems: 'center',
    marginTop: 16,
  },
  draftBannerText: {
    color: '#FFCC00',
    fontSize: 14,
    fontWeight: '600',
  },
});
