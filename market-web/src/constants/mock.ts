/**
 * Mock 行情数据，结构贴近真实 API，便于后续替换
 */

export interface IndexQuote {
  name: string;
  ticker: string;
  price: number;
  changePercent: number;
  sparkline: number[];
}

export interface WatchlistRow {
  symbol: string;
  name: string;
  price: number;
  changePercent: number;
}

export interface MoverRow {
  symbol: string;
  name: string;
  price: number;
  change: number;
  changePercent: number;
  sparkline: number[];
}

export interface HeatmapItem {
  symbol: string;
  price: number;
  changePercent: number;
  /** 用于 treemap 视觉权重，如市值或成交量 */
  weight: number;
}

export interface TrendingRow {
  symbol: string;
  name: string;
  price: number;
  changePercent: number;
}

/** 四大指数 */
export const indexQuotes: IndexQuote[] = [
  {
    name: '道琼斯',
    ticker: 'DJI',
    price: 39220.25,
    changePercent: 1.24,
    sparkline: [38800, 38920, 39050, 39100, 39180, 39220.25],
  },
  {
    name: '标普500',
    ticker: 'SPX',
    price: 5120.59,
    changePercent: 0.52,
    sparkline: [5090, 5100, 5105, 5110, 5118, 5120.59],
  },
  {
    name: '纳斯达克',
    ticker: 'NASDAQ',
    price: 16500.34,
    changePercent: 0.8,
    sparkline: [16350, 16400, 16450, 16480, 16495, 16500.34],
  },
  {
    name: 'VIX',
    ticker: 'VIX',
    price: 13.24,
    changePercent: -0.3,
    sparkline: [13.6, 13.5, 13.4, 13.35, 13.28, 13.24],
  },
];

/** 自选列表 */
export const watchlistRows: WatchlistRow[] = [
  { symbol: 'TNXP', name: 'TNXP', price: 0.65, changePercent: 0.08 },
  { symbol: 'NVDA', name: 'NVDA', price: 927.51, changePercent: 2.31 },
  { symbol: 'TSLA', name: 'TSLA', price: 168.46, changePercent: 3.74 },
  { symbol: 'AAPL', name: 'AAPL', price: 168.92, changePercent: 1.05 },
];

/** 涨跌榜（涨幅榜按涨跌幅降序，跌幅榜升序） */
export const moversGainers: MoverRow[] = [
  { symbol: 'NVDA', name: 'NVDA', price: 927.51, change: 35.51, changePercent: 2.31, sparkline: [900, 910, 918, 922, 925, 927.51] },
  { symbol: 'TSLA', name: 'TSLA', price: 168.46, change: 6.08, changePercent: 3.74, sparkline: [162, 164, 165, 166, 167, 168.46] },
  { symbol: 'AAPL', name: 'AAPL', price: 168.92, change: 1.76, changePercent: 1.05, sparkline: [167, 167.5, 168, 168.2, 168.5, 168.92] },
  { symbol: 'TNXP', name: 'TNXP', price: 11.39, change: -0.08, changePercent: -0.7, sparkline: [11.5, 11.45, 11.42, 11.4, 11.39, 11.39] },
].sort((a, b) => b.changePercent - a.changePercent);

export const moversLosers: MoverRow[] = [...moversGainers]
  .map((r) => ({ ...r, change: -r.change, changePercent: -r.changePercent, sparkline: [...r.sparkline].reverse() }))
  .sort((a, b) => a.changePercent - b.changePercent);

/** 市场热度（紧凑表） */
export const marketHeatGainers: MoverRow[] = [
  { symbol: 'NVDA', name: 'NVDA', price: 927.51, change: 53.3, changePercent: 53.3, sparkline: [] },
  { symbol: 'SILO', name: 'SILO', price: 0.3811, change: 0.1, changePercent: 35.6, sparkline: [] },
  { symbol: 'TJGC', name: 'TJGC', price: 1.13, change: 0.28, changePercent: 32.78, sparkline: [] },
  { symbol: 'BHAT', name: 'BHAT', price: 0.0847, change: 0.019, changePercent: 28.72, sparkline: [] },
  { symbol: 'MYGN', name: 'MYGN', price: 5.3, change: 0.92, changePercent: 21.0, sparkline: [] },
].sort((a, b) => b.changePercent - a.changePercent);

export const marketHeatLosers: MoverRow[] = marketHeatGainers
  .map((r) => ({ ...r, change: -r.change, changePercent: -r.changePercent }))
  .sort((a, b) => a.changePercent - b.changePercent);

/** Heatmap 数据（至少 12 块，带 weight 做 treemap） */
export const heatmapItems: HeatmapItem[] = [
  { symbol: 'NVDA', price: 927.51, changePercent: 2.31, weight: 28 },
  { symbol: 'AAPL', price: 168.92, changePercent: 1.09, weight: 22 },
  { symbol: 'TSLA', price: 168.46, changePercent: 1.89, weight: 18 },
  { symbol: 'MSFT', price: 415.5, changePercent: 0.23, weight: 16 },
  { symbol: 'GOOGL', price: 172.3, changePercent: -0.31, weight: 14 },
  { symbol: 'AMZN', price: 185.2, changePercent: 1.51, weight: 12 },
  { symbol: 'META', price: 518.4, changePercent: 0.5, weight: 10 },
  { symbol: 'AMD', price: 153.54, changePercent: -0.76, weight: 9 },
  { symbol: 'NFLX', price: 612.1, changePercent: 0.8, weight: 7 },
  { symbol: 'INTC', price: 42.2, changePercent: -0.5, weight: 5 },
  { symbol: 'COIN', price: 228.5, changePercent: 3.2, weight: 4 },
  { symbol: 'SOFI', price: 8.92, changePercent: -1.2, weight: 3 },
];

/** 热门 Stocks */
export const trendingStocks: TrendingRow[] = [
  { symbol: 'NVDA', name: 'NVDA', price: 927.51, changePercent: 2.31 },
  { symbol: 'TSLA', name: 'TSLA', price: 168.46, changePercent: 3.74 },
  { symbol: 'AAPL', name: 'AAPL', price: 168.92, changePercent: 1.05 },
  { symbol: 'AMD', name: 'AMD', price: 153.54, changePercent: -0.76 },
];

/** 热门 Crypto */
export const trendingCrypto: TrendingRow[] = [
  { symbol: 'BTC', name: 'BTC', price: 97250, changePercent: 1.2 },
  { symbol: 'ETH', name: 'ETH', price: 3520, changePercent: 2.1 },
  { symbol: 'SOL', name: 'SOL', price: 228.5, changePercent: 5.3 },
];
