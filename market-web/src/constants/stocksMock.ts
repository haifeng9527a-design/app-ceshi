import type { StockRowData, IndexCardData, KLinePoint, OrderBookLevel } from '../types/stocks';

/** 股票列表 mock */
export const stocksMock: StockRowData[] = [
  { id: '1', code: 'AUR', name: 'Allurion Technologies', changePercent: 60.55, price: 1.75, change: 0.66, volume: 377490000, amount: 661615500, peTtm: 12.5, pb: 2.1, dividendYield: 0 },
  { id: '2', code: 'VIR', name: 'Vir Biotechnology', changePercent: 63.93, price: 12.18, change: 4.75, volume: 12500000, amount: 152250000, peTtm: null, pb: 1.8, dividendYield: null },
  { id: '3', code: 'ELPW', name: 'Electra Power', changePercent: 36.26, price: 0.5314, change: 0.14, volume: 8900000, amount: 4729460, peTtm: 8.2, pb: 0.9, dividendYield: 0 },
  { id: '4', code: 'SILO', name: 'Silo Pharma', changePercent: 29.98, price: 0.3655, change: 0.08, volume: 5200000, amount: 1900600, peTtm: null, pb: 1.2, dividendYield: null },
  { id: '5', code: 'BHAT', name: 'Blue Hat', changePercent: 27.36, price: 0.0838, change: 0.02, volume: 31000000, amount: 2597800, peTtm: 15.0, pb: 2.0, dividendYield: 0 },
  { id: '6', code: 'MYGN', name: 'Myriad Genetics', changePercent: 25.34, price: 5.49, change: 1.11, volume: 4200000, amount: 23058000, peTtm: -8.5, pb: 1.5, dividendYield: null },
  { id: '7', code: 'SPR', name: 'Singina Inc', changePercent: -5.2, price: 11.19, change: -0.61, volume: 2800000, amount: 31332000, peTtm: 22.0, pb: 3.1, dividendYield: 1.2 },
  { id: '8', code: 'NVDA', name: 'NVIDIA Corp', changePercent: 2.31, price: 927.51, change: 20.9, volume: 52000000, amount: 48230520000, peTtm: 68.0, pb: 28.5, dividendYield: 0.03 },
  { id: '9', code: 'AAPL', name: 'Apple Inc', changePercent: 1.05, price: 168.92, change: 1.76, volume: 48000000, amount: 8108160000, peTtm: 28.5, pb: 45.2, dividendYield: 0.55 },
  { id: '10', code: 'TSLA', name: 'Tesla Inc', changePercent: 3.74, price: 168.46, change: 6.08, volume: 95000000, amount: 16003700000, peTtm: 72.0, pb: 12.8, dividendYield: 0 },
];

/** 指数 mock */
export const indexMock: IndexCardData[] = [
  { symbol: 'DJI', name: '道琼斯', value: 39220.25, changePercent: 1.34, sparkline: [38800, 38920, 39050, 39100, 39180, 39220.25] },
  { symbol: 'SPX', name: '标普500', value: 5120.59, changePercent: 0.52, sparkline: [5090, 5100, 5105, 5110, 5118, 5120.59] },
  { symbol: 'NASDAQ', name: '纳斯达克', value: 16500.34, changePercent: 0.8, sparkline: [16350, 16400, 16450, 16480, 16495, 16500.34] },
  { symbol: 'VIX', name: 'VIX', value: 13.24, changePercent: -0.3, sparkline: [13.6, 13.5, 13.4, 13.35, 13.28, 13.24] },
];

/** 生成 K 线 mock（按时间戳） */
export function klineMock(symbol: string, count = 60): KLinePoint[] {
  const base = symbol === 'AUR' ? 1.1 : symbol === 'NVDA' ? 900 : 12;
  const points: KLinePoint[] = [];
  let t = Math.floor(Date.now() / 1000) - count * 3600;
  let o = base;
  for (let i = 0; i < count; i++) {
    const change = (Math.random() - 0.48) * 0.02 * base;
    const c = o + change;
    const h = Math.max(o, c) + Math.random() * 0.005 * base;
    const l = Math.min(o, c) - Math.random() * 0.005 * base;
    points.push({ time: t, open: o, high: h, low: l, close: c });
    o = c;
    t += 3600;
  }
  return points;
}

/** 买卖盘口 mock */
export function orderBookMock(price: number): { bids: OrderBookLevel[]; asks: OrderBookLevel[] } {
  const bids: OrderBookLevel[] = [];
  const asks: OrderBookLevel[] = [];
  for (let i = 0; i < 5; i++) {
    bids.push({ price: price - (i + 1) * 0.01, quantity: Math.floor(1000 + Math.random() * 5000) });
    asks.push({ price: price + (i + 1) * 0.01, quantity: Math.floor(1000 + Math.random() * 5000) });
  }
  return { bids, asks };
}
