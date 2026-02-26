import type { CandlePoint } from '../types/chart';

/** 简单移动平均 */
export function ma(closes: number[], period: number): (number | null)[] {
  const result: (number | null)[] = [];
  for (let i = 0; i < closes.length; i++) {
    if (i < period - 1) {
      result.push(null);
      continue;
    }
    let sum = 0;
    for (let j = i - period + 1; j <= i; j++) sum += closes[j];
    result.push(sum / period);
  }
  return result;
}

/** 指数移动平均 */
export function ema(closes: number[], period: number): (number | null)[] {
  const k = 2 / (period + 1);
  const result: (number | null)[] = [];
  let prev: number | null = null;
  for (let i = 0; i < closes.length; i++) {
    if (i < period - 1) {
      result.push(null);
      continue;
    }
    if (i === period - 1) {
      let sum = 0;
      for (let j = 0; j < period; j++) sum += closes[j];
      prev = sum / period;
    } else if (prev != null) {
      prev = closes[i] * k + prev * (1 - k);
    }
    result.push(prev);
  }
  return result;
}

/** 从 K 线计算 MA 序列，返回 { time, ma5, ma10, ma20 } */
export function computeMA(candles: CandlePoint[]): { time: number; ma5: number; ma10: number; ma20: number }[] {
  const closes = candles.map((c) => c.close);
  const ma5 = ma(closes, 5);
  const ma10 = ma(closes, 10);
  const ma20 = ma(closes, 20);
  return candles.map((c, i) => ({
    time: c.time,
    ma5: ma5[i] ?? 0,
    ma10: ma10[i] ?? 0,
    ma20: ma20[i] ?? 0,
  }));
}

/** MACD(12,26,9)：返回 DIF, DEA, MACD柱 */
export function macd(closes: number[]): { dif: (number | null)[]; dea: (number | null)[]; bar: (number | null)[] } {
  const ema12 = ema(closes, 12);
  const ema26 = ema(closes, 26);
  const dif: (number | null)[] = [];
  for (let i = 0; i < closes.length; i++) {
    if (ema12[i] != null && ema26[i] != null) dif.push(ema12[i]! - ema26[i]!);
    else dif.push(null);
  }
  const dea: (number | null)[] = [];
  let prevDea: number | null = null;
  const k = 2 / 10;
  for (let i = 0; i < dif.length; i++) {
    if (dif[i] == null) {
      dea.push(null);
      continue;
    }
    if (prevDea == null) prevDea = dif[i]!;
    else prevDea = dif[i]! * k + prevDea * (1 - k);
    dea.push(prevDea);
  }
  const bar: (number | null)[] = [];
  for (let i = 0; i < closes.length; i++) {
    if (dif[i] != null && dea[i] != null) bar.push((dif[i]! - dea[i]!) * 2);
    else bar.push(null);
  }
  return { dif, dea, bar };
}

/** 成交量 MA5/MA10 */
export function volumeMA(volumes: number[]): { volMa5: (number | null)[]; volMa10: (number | null)[] } {
  return { volMa5: ma(volumes, 5), volMa10: ma(volumes, 10) };
}
