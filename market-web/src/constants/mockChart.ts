import type { IntradayPoint, CandlePoint, ChartStats } from '../types/chart';

const now = Math.floor(Date.now() / 1000);
const day = 86400;

/** 生成分时 mock：从 09:30 到 16:00，间隔 5 分钟 */
function genIntraday5m(prevClose: number, current: number): IntradayPoint[] {
  const points: IntradayPoint[] = [];
  const base = new Date();
  base.setHours(9, 30, 0, 0);
  const startT = Math.floor(base.getTime() / 1000);
  const end = new Date();
  end.setHours(16, 0, 0, 0);
  const endT = Math.floor(end.getTime() / 1000);
  const total = endT - startT;
  const interval = 5 * 60;
  let price = prevClose;
  for (let t = startT; t <= endT; t += interval) {
    const progress = (t - startT) / total;
    const target = prevClose + (current - prevClose) * Math.min(1, progress + (Math.random() - 0.5) * 0.05);
    price = price + (target - price) * 0.35 + (Math.random() - 0.5) * 0.015;
    price = Math.max(prevClose * 0.95, Math.min(prevClose * 1.2, price));
    points.push({
      time: t,
      price: Math.round(price * 100) / 100,
      volume: Math.floor(10000 + Math.random() * 50000),
    });
  }
  if (points.length > 0) points[points.length - 1].price = current;
  return points;
}

/** 生成 1m 分时（点数更多） */
function genIntraday1m(prevClose: number, current: number): IntradayPoint[] {
  const pts = genIntraday5m(prevClose, current);
  const out: IntradayPoint[] = [];
  for (let i = 0; i < pts.length; i++) {
    out.push(pts[i]);
    if (i < pts.length - 1) {
      const t = pts[i].time;
      const next = pts[i + 1];
      for (let j = 1; j < 5; j++) {
        const tt = t + j * 60;
        const p = pts[i].price + (next.price - pts[i].price) * (j / 5) + (Math.random() - 0.5) * 0.01;
        out.push({ time: tt, price: Math.round(p * 100) / 100, volume: Math.floor(2000 + Math.random() * 8000) });
      }
    }
  }
  return out;
}

/** 按周期生成分时 */
export function getIntradayMock(symbol: string, timeframe: string): IntradayPoint[] {
  const prevClose = 7.43;
  const current = 11.89;
  if (timeframe === '1m') return genIntraday1m(prevClose, current);
  return genIntraday5m(prevClose, current);
}

/** 生成 K 线 mock */
function genCandles(basePrice: number, count: number, intervalSec: number): CandlePoint[] {
  const points: CandlePoint[] = [];
  let t = now - count * intervalSec;
  let o = basePrice;
  for (let i = 0; i < count; i++) {
    const change = (Math.random() - 0.48) * 0.02 * basePrice;
    const c = o + change;
    const h = Math.max(o, c) + Math.random() * 0.008 * basePrice;
    const l = Math.min(o, c) - Math.random() * 0.008 * basePrice;
    const vol = Math.floor(50000 + Math.random() * 150000);
    points.push({ time: t, open: o, high: h, low: l, close: c, volume: vol });
    o = c;
    t += intervalSec;
  }
  return points;
}

const TIMEFRAME_INTERVAL: Record<string, number> = {
  '1m': 60,
  '5m': 5 * 60,
  '15m': 15 * 60,
  '1h': 3600,
  '1D': day,
};

/** 按周期获取 K 线 mock */
export function getCandlesMock(symbol: string, timeframe: string): CandlePoint[] {
  const base = symbol === 'VIR' ? 11.89 : 12;
  const interval = TIMEFRAME_INTERVAL[timeframe] ?? 3600;
  const count = timeframe === '1D' ? 120 : timeframe === '1h' ? 90 : 80;
  return genCandles(base, count, interval);
}

/** 图表统计 mock（与 VIR 11.89 对应） */
export function getChartStatsMock(symbol: string): ChartStats {
  return {
    open: 7.5,
    high: 13.46,
    low: 7.26,
    close: 11.89,
    prevClose: 7.43,
    change: 4.46,
    changePercent: 60.57,
    amplitude: 10.87,
    avgPrice: 10.2,
    volume: 88500,
    turnover: 104300,
    turnoverRate: 83.45,
    peTtm: null,
  };
}
