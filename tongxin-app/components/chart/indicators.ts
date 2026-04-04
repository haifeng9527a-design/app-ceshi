/**
 * Indicator Registry for KLineChart
 * KLineChart has built-in indicator calculations, so we only define the registry/config here.
 */

export type IndicatorType =
  | 'MA' | 'EMA' | 'SMA' | 'BOLL' | 'SAR'
  | 'MACD' | 'RSI' | 'KDJ' | 'WR' | 'CCI' | 'MTM' | 'AO'
  | 'VOL' | 'OBV'
  | 'DMI' | 'BIAS' | 'TRIX' | 'CR' | 'EMV';

export interface IndicatorConfig {
  type: IndicatorType;
  name: string;
  description: string;
  category: 'trend' | 'momentum' | 'volume' | 'volatility';
  overlay: boolean; // true = main chart pane, false = sub pane
}

export const INDICATOR_REGISTRY: IndicatorConfig[] = [
  // ─── Trend ─────────────────────
  { type: 'MA',   name: 'MA 均线',    description: '移动平均线 (Moving Average)',       category: 'trend', overlay: true },
  { type: 'EMA',  name: 'EMA',        description: '指数移动平均线 (Exponential MA)',    category: 'trend', overlay: true },
  { type: 'SMA',  name: 'SMA',        description: '简单移动平均线 (Simple MA)',         category: 'trend', overlay: true },
  { type: 'BOLL', name: '布林带',      description: 'Bollinger Bands',                  category: 'trend', overlay: true },
  { type: 'SAR',  name: 'SAR',        description: '抛物线止损 (Parabolic SAR)',         category: 'trend', overlay: true },

  // ─── Momentum ──────────────────
  { type: 'MACD', name: 'MACD',       description: '指数平滑异同移动平均线',               category: 'momentum', overlay: false },
  { type: 'RSI',  name: 'RSI',        description: '相对强弱指标 (Relative Strength)',    category: 'momentum', overlay: false },
  { type: 'KDJ',  name: 'KDJ',        description: '随机指标 (Stochastic)',              category: 'momentum', overlay: false },
  { type: 'WR',   name: 'WR',         description: '威廉指标 (Williams %R)',             category: 'momentum', overlay: false },
  { type: 'CCI',  name: 'CCI',        description: '顺势指标 (Commodity Channel)',       category: 'momentum', overlay: false },
  { type: 'MTM',  name: 'MTM',        description: '动量指标 (Momentum)',                category: 'momentum', overlay: false },
  { type: 'AO',   name: 'AO',         description: 'Awesome Oscillator',                category: 'momentum', overlay: false },

  // ─── Volume ────────────────────
  { type: 'VOL',  name: '成交量',      description: 'Volume',                           category: 'volume',  overlay: false },
  { type: 'OBV',  name: 'OBV',        description: '能量潮指标 (On Balance Volume)',      category: 'volume',  overlay: false },

  // ─── Volatility ────────────────
  { type: 'DMI',  name: 'DMI',        description: '趋向指标 (Directional Movement)',    category: 'volatility', overlay: false },
  { type: 'BIAS', name: 'BIAS',       description: '乖离率',                             category: 'volatility', overlay: false },
  { type: 'TRIX', name: 'TRIX',       description: '三重指数平滑移动平均',                  category: 'volatility', overlay: false },
  { type: 'CR',   name: 'CR',         description: '价格动量指标',                         category: 'volatility', overlay: false },
  { type: 'EMV',  name: 'EMV',        description: '简易波动指标 (Ease of Movement)',      category: 'volatility', overlay: false },
];
