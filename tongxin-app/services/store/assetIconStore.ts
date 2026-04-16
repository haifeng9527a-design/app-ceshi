import { create } from 'zustand';
import { fetchAssetIconMap, type AssetIconCategory } from '../api/assetIconApi';

type IconState = {
  icons: Record<string, string>;
  inflight: Record<string, boolean>;
  getIcon: (category: AssetIconCategory, code: string) => string | undefined;
  ensureIcons: (category: AssetIconCategory, codes: string[]) => Promise<void>;
};

const toKey = (category: AssetIconCategory, code: string) =>
  `${category}:${code.trim().toUpperCase()}`;

export const useAssetIconStore = create<IconState>((set, get) => ({
  icons: {},
  inflight: {},

  getIcon: (category, code) => get().icons[toKey(category, code)],

  ensureIcons: async (category, codes) => {
    const normalized = Array.from(
      new Set(
        codes
          .map((code) => code.trim().toUpperCase())
          .filter(Boolean),
      ),
    );
    if (!category || normalized.length === 0) {
      return;
    }

    const { icons, inflight } = get();
    const missing = normalized.filter((code) => !icons[toKey(category, code)] && !inflight[toKey(category, code)]);
    if (missing.length === 0) {
      return;
    }

    set((state) => {
      const next = { ...state.inflight };
      for (const code of missing) next[toKey(category, code)] = true;
      return { inflight: next };
    });

    try {
      const data = await fetchAssetIconMap(category, missing);
      set((state) => {
        const nextIcons = { ...state.icons };
        const nextInflight = { ...state.inflight };
        for (const code of missing) {
          delete nextInflight[toKey(category, code)];
          if (data?.[code]) {
            nextIcons[toKey(category, code)] = data[code];
          }
        }
        return { icons: nextIcons, inflight: nextInflight };
      });
    } catch {
      set((state) => {
        const nextInflight = { ...state.inflight };
        for (const code of missing) delete nextInflight[toKey(category, code)];
        return { inflight: nextInflight };
      });
    }
  },
}));
