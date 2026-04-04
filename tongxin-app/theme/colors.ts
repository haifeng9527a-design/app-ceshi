/**
 * Sovereign Exchange Design System
 * Material Design 3 dark theme with gold accent
 * Derived from Stitch design specification
 */
export const Colors = {
  // ── Core backgrounds ──
  background: '#0a0a0f',        // Deep dark
  surface: '#121218',           // Card/panel surface
  surfaceAlt: '#1a1a24',        // Elevated surface
  topBarBg: '#0f0f16',          // Top bar & sidebar
  border: '#1e1e2e',            // Subtle borders
  borderLight: '#2a2a3a',       // Slightly more visible borders

  // ── Glass / Overlay ──
  glass: 'rgba(18, 18, 24, 0.65)',
  glassBorder: 'rgba(212, 175, 55, 0.08)',
  overlayBg: 'rgba(10, 10, 15, 0.85)',

  // ── Primary (Gold) ──
  primary: '#D4AF37',           // Sovereign Gold
  primaryLight: '#f2ca50',      // Light gold
  primaryDim: 'rgba(212, 175, 55, 0.15)',
  primaryBorder: 'rgba(212, 175, 55, 0.2)',

  // ── Text ──
  textActive: '#e8e8f0',        // Primary text
  textSecondary: '#9a9ab0',     // Secondary text
  textMuted: '#6b6b80',         // Muted/placeholder
  textOnPrimary: '#0a0a0f',     // Text on gold buttons

  // ── Semantic ──
  up: '#66e4b9',                // Tertiary green (gain)
  down: '#ffb4ab',              // Error red (loss)
  upDim: 'rgba(102, 228, 185, 0.12)',
  downDim: 'rgba(255, 180, 171, 0.12)',

  // ── Legacy aliases (backward compat) ──
  accentGold: '#D4AF37',
  tabUnderline: '#D4AF37',
  cardBg: '#121218',
  inputBg: '#0f0f16',

  // ── Status ──
  online: '#66e4b9',
  offline: '#ffb4ab',
  warning: '#f2ca50',
} as const;

/** Sizing constants */
export const Sizes = {
  navBarHeight: 40,
  timeframeBarHeight: 36,
  sidePanelWidth: 256,
  topBarHeight: 64,
  borderRadius: 12,
  borderRadiusSm: 8,
  fontMono: 'monospace',
} as const;

/** Shadow presets for elevated elements */
export const Shadows = {
  card: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 12,
    elevation: 6,
  },
  glow: {
    shadowColor: '#D4AF37',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.15,
    shadowRadius: 20,
    elevation: 4,
  },
} as const;
