import { useEffect, useMemo, useState } from 'react';
import { Image, StyleSheet, Text, View, type ImageStyle, type StyleProp, type ViewStyle } from 'react-native';

import { Config } from '../../services/config';
import { useAssetIconStore } from '../../services/store/assetIconStore';
import { Colors } from '../../theme/colors';
import AppIcon from './AppIcon';
import type { AssetIconCategory } from '../../services/api/assetIconApi';

const FOREX_BASES = new Set([
  'EUR', 'GBP', 'USD', 'JPY', 'AUD', 'CAD', 'CHF', 'NZD', 'SGD', 'HKD', 'MXN', 'ZAR', 'TRY', 'SEK', 'NOK', 'DKK', 'PLN', 'CZK', 'HUF',
]);

type AssetSymbolIconProps = {
  symbol?: string;
  assetCode?: string;
  category?: AssetIconCategory;
  size?: number;
  style?: StyleProp<ViewStyle>;
  imageStyle?: StyleProp<ImageStyle>;
};

function resolveIconUrl(url?: string | null) {
  const value = (url || '').trim();
  if (!value) return null;
  if (/^https?:\/\//i.test(value)) return value;
  return `${Config.API_BASE_URL}${value.startsWith('/') ? value : `/${value}`}`;
}

function inferTarget(symbol?: string, assetCode?: string, category?: AssetIconCategory) {
  const normalizedCode = (assetCode || '').trim().toUpperCase();
  if (normalizedCode && category) {
    return { category, assetCode: normalizedCode };
  }

  const normalizedSymbol = (symbol || '').trim().toUpperCase();
  if (!normalizedSymbol) return null;

  if (normalizedCode) {
    return { category: category || 'crypto', assetCode: normalizedCode };
  }

  if (normalizedSymbol.includes('/')) {
    const [base = '', quote = ''] = normalizedSymbol.split('/');
    if (!base) return null;
    if (FOREX_BASES.has(base) && FOREX_BASES.has(quote)) {
      return null;
    }
    return { category: category || 'crypto', assetCode: base };
  }

  return { category: category || 'stock', assetCode: normalizedSymbol };
}

export default function AssetSymbolIcon({
  symbol,
  assetCode,
  category,
  size = 22,
  style,
  imageStyle,
}: AssetSymbolIconProps) {
  const target = useMemo(() => inferTarget(symbol, assetCode, category), [symbol, assetCode, category]);
  const ensureIcons = useAssetIconStore((s) => s.ensureIcons);
  const iconUrl = useAssetIconStore((s) =>
    target ? s.getIcon(target.category, target.assetCode) : undefined,
  );
  const [imageFailed, setImageFailed] = useState(false);

  useEffect(() => {
    if (!target) return;
    ensureIcons(target.category, [target.assetCode]);
  }, [ensureIcons, target]);

  useEffect(() => {
    setImageFailed(false);
  }, [iconUrl, target?.assetCode, target?.category]);

  const resolvedIconUrl = resolveIconUrl(iconUrl || null);
  const fallbackName =
    target?.category === 'stock' ? 'chart' : target?.category === 'crypto' ? 'bitcoin' : 'globe';
  const label = (target?.assetCode || symbol || '?').charAt(0).toUpperCase();

  return (
    <View style={[styles.wrap, { width: size, height: size, borderRadius: size / 2 }, style]}>
      {resolvedIconUrl && !imageFailed ? (
        <Image
          source={{ uri: resolvedIconUrl }}
          style={[
            styles.image,
            { width: size, height: size, borderRadius: size / 2 },
            imageStyle,
          ]}
          resizeMode="cover"
          onError={() => setImageFailed(true)}
        />
      ) : target ? (
        <AppIcon name={fallbackName} size={Math.max(14, Math.floor(size * 0.66))} color={Colors.primary} />
      ) : (
        <Text style={[styles.fallbackText, { fontSize: Math.max(11, Math.floor(size * 0.48)) }]}>{label}</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    backgroundColor: Colors.surfaceAlt,
    borderWidth: 1,
    borderColor: Colors.border,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
  },
  image: {
    backgroundColor: Colors.surface,
  },
  fallbackText: {
    color: Colors.primary,
    fontWeight: '800',
  },
});
