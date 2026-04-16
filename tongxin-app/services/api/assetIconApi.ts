import apiClient from './client';

export type AssetIconCategory = 'crypto' | 'stock';

export async function fetchAssetIconMap(
  category: AssetIconCategory,
  codes: string[],
): Promise<Record<string, string>> {
  const normalized = Array.from(
    new Set(
      codes
        .map((code) => code.trim().toUpperCase())
        .filter(Boolean),
    ),
  );
  if (!category || normalized.length === 0) {
    return {};
  }

  const { data } = await apiClient.get('/api/assets/icon-map', {
    params: {
      category,
      codes: normalized.join(','),
    },
  });

  return data || {};
}
