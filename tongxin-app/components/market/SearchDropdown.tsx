import { View, Text, TouchableOpacity, StyleSheet, ActivityIndicator } from 'react-native';
import { useRouter } from 'expo-router';
import { Colors, Sizes } from '../../theme/colors';
import { useMarketStore } from '../../services/store/marketStore';
import type { SearchResult } from '../../services/api/client';

interface SearchDropdownProps {
  onSelect?: () => void;
}

export default function SearchDropdown({ onSelect }: SearchDropdownProps) {
  const router = useRouter();
  const { searchResults, searchLoading } = useMarketStore();

  if (!searchLoading && searchResults.length === 0) return null;

  return (
    <View style={styles.container}>
      {searchLoading ? (
        <View style={styles.loadingRow}>
          <ActivityIndicator size="small" color={Colors.primary} />
          <Text style={styles.loadingText}>Searching...</Text>
        </View>
      ) : (
        searchResults.slice(0, 8).map((item: SearchResult) => (
          <TouchableOpacity
            key={item.symbol}
            style={styles.row}
            activeOpacity={0.6}
            onPress={() => {
              router.push({
                pathname: '/chart/[symbol]',
                params: { symbol: item.symbol },
              });
              onSelect?.();
            }}
          >
            <View style={styles.left}>
              <Text style={styles.symbol}>{item.symbol}</Text>
              {item.name ? (
                <Text style={styles.name} numberOfLines={1}>{item.name}</Text>
              ) : null}
            </View>
            {item.market ? (
              <View style={styles.typeBadge}>
                <Text style={styles.typeText}>{item.market}</Text>
              </View>
            ) : null}
          </TouchableOpacity>
        ))
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: Sizes.topBarHeight,
    left: 20,
    width: 360,
    maxHeight: 400,
    backgroundColor: Colors.surface,
    borderRadius: Sizes.borderRadiusSm,
    borderWidth: 1,
    borderColor: Colors.borderLight,
    zIndex: 100,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.4,
    shadowRadius: 16,
    elevation: 10,
  },
  loadingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    gap: 8,
  },
  loadingText: {
    color: Colors.textMuted,
    fontSize: 13,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 14,
    borderBottomWidth: 1,
    borderBottomColor: Colors.border,
  },
  left: {
    flex: 1,
  },
  symbol: {
    color: Colors.textActive,
    fontSize: 14,
    fontWeight: '600',
    fontFamily: 'monospace',
  },
  name: {
    color: Colors.textMuted,
    fontSize: 11,
    marginTop: 2,
  },
  typeBadge: {
    backgroundColor: Colors.primaryDim,
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 4,
  },
  typeText: {
    color: Colors.primary,
    fontSize: 10,
    fontWeight: '600',
  },
});
