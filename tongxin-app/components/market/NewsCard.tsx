import { View, Text, TouchableOpacity, Image, StyleSheet, Linking } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Colors, Sizes, Shadows } from '../../theme/colors';
import AppIcon from '../ui/AppIcon';
import type { NewsItem } from '../../services/store/marketStore';

interface NewsCardProps {
  items: NewsItem[];
  loading?: boolean;
}

function timeAgo(dateStr?: string): string {
  if (!dateStr) return '';
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export default function NewsCard({ items, loading }: NewsCardProps) {
  const { t } = useTranslation();

  if (loading) {
    return (
      <View style={styles.card}>
        <View style={styles.badge}>
          <Text style={styles.badgeText}>{t('market.macroSpotlight')}</Text>
        </View>
        <Text style={styles.loadingText}>{t('marketCard.loadingNews')}</Text>
      </View>
    );
  }

  if (items.length === 0) {
    return (
      <View style={styles.card}>
        <View style={styles.badge}>
          <Text style={styles.badgeText}>{t('market.macroSpotlight')}</Text>
        </View>
        <Text style={styles.loadingText}>{t('marketCard.noNews')}</Text>
      </View>
    );
  }

  const featured = items[0];
  const rest = items.slice(1, 4);

  return (
    <View style={styles.card}>
      {/* Featured story with image */}
      <TouchableOpacity
        activeOpacity={0.7}
        onPress={() => featured.url && Linking.openURL(featured.url)}
        style={styles.featuredRow}
      >
        {/* Left: text */}
        <View style={styles.featuredText}>
          <View style={styles.badge}>
            <Text style={styles.badgeText}>{t('market.macroSpotlight')}</Text>
          </View>
          <Text style={styles.featuredTitle} numberOfLines={2}>
            {featured.headline}
          </Text>
          {featured.summary ? (
            <Text style={styles.featuredSub} numberOfLines={2}>
              {featured.summary}
            </Text>
          ) : null}
          <View style={styles.metaRow}>
            {featured.source ? (
              <Text style={styles.source}>{featured.source}</Text>
            ) : null}
            <Text style={styles.time}>{timeAgo(featured.publishedUtc)}</Text>
          </View>
          <Text style={styles.readMore}>{t('marketCard.readAnalysis')} →</Text>
        </View>

        {/* Right: image */}
        {featured.image_url ? (
          <Image
            source={{ uri: featured.image_url }}
            style={styles.featuredImage}
            resizeMode="cover"
          />
        ) : (
          <View style={styles.imagePlaceholder}>
            <AppIcon name="market" size={28} color={Colors.textMuted} />
          </View>
        )}
      </TouchableOpacity>

      {/* More news */}
      {rest.length > 0 && (
        <View style={styles.moreSection}>
          {rest.map((item, i) => (
            <TouchableOpacity
              key={i}
              style={styles.moreRow}
              activeOpacity={0.6}
              onPress={() => item.url && Linking.openURL(item.url)}
            >
              <Text style={styles.moreTitle} numberOfLines={1}>
                {item.headline}
              </Text>
              <Text style={styles.moreTime}>{timeAgo(item.publishedUtc)}</Text>
            </TouchableOpacity>
          ))}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    flex: 2,
    backgroundColor: Colors.surface,
    borderRadius: Sizes.borderRadius,
    borderWidth: 1,
    borderColor: Colors.border,
    padding: 20,
    justifyContent: 'center',
    ...Shadows.card,
  },
  loadingText: {
    color: Colors.textMuted,
    fontSize: 13,
    marginTop: 8,
  },
  // Badge
  badge: {
    alignSelf: 'flex-start',
    backgroundColor: Colors.primaryDim,
    borderRadius: 4,
    paddingHorizontal: 8,
    paddingVertical: 3,
    marginBottom: 10,
  },
  badgeText: {
    color: Colors.primary,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 1,
  },
  // Featured
  featuredRow: {
    flexDirection: 'row',
    gap: 16,
  },
  featuredText: {
    flex: 1,
  },
  featuredTitle: {
    color: Colors.textActive,
    fontSize: 16,
    fontWeight: '700',
    lineHeight: 22,
    marginBottom: 6,
  },
  featuredSub: {
    color: Colors.textSecondary,
    fontSize: 13,
    lineHeight: 18,
    marginBottom: 8,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 6,
  },
  source: {
    color: Colors.primary,
    fontSize: 11,
    fontWeight: '600',
  },
  time: {
    color: Colors.textMuted,
    fontSize: 11,
  },
  readMore: {
    color: Colors.primary,
    fontSize: 12,
    fontWeight: '600',
    marginTop: 2,
  },
  // Image
  featuredImage: {
    width: 100,
    height: 100,
    borderRadius: 8,
  },
  imagePlaceholder: {
    width: 100,
    height: 100,
    borderRadius: 8,
    backgroundColor: Colors.border,
    justifyContent: 'center',
    alignItems: 'center',
  },
  // More news
  moreSection: {
    marginTop: 12,
    borderTopWidth: 1,
    borderTopColor: Colors.border,
    paddingTop: 8,
  },
  moreRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 6,
  },
  moreTitle: {
    flex: 1,
    color: Colors.textSecondary,
    fontSize: 12,
  },
  moreTime: {
    color: Colors.textMuted,
    fontSize: 10,
    marginLeft: 8,
  },
});
