/**
 * 数字与价格格式化
 */

export function formatPrice(value: number): string {
  if (value >= 10000) return value.toLocaleString('en-US', { maximumFractionDigits: 0 });
  if (value >= 1) return value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return value.toFixed(4);
}

export function formatPercent(value: number): string {
  const sign = value >= 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}%`;
}

export function formatChange(value: number): string {
  const sign = value >= 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}`;
}

/** 图表时间显示 09:30 / 02/23 */
export function formatTimeChart(ts: number, mode: 'time' | 'date' = 'time'): string {
  const d = new Date(ts * 1000);
  if (mode === 'date') return `${String(d.getMonth() + 1).padStart(2, '0')}/${d.getDate()}`;
  const h = String(d.getHours()).padStart(2, '0');
  const m = String(d.getMinutes()).padStart(2, '0');
  return `${h}:${m}`;
}

/** 成交量/成交额简写：万、亿 */
export function formatVol(value: number): string {
  if (value >= 1e8) return (value / 1e8).toFixed(2) + '亿';
  if (value >= 1e4) return (value / 1e4).toFixed(2) + '万';
  return value.toLocaleString();
}

/** 换手率、振幅等百分比 */
export function formatPct(value: number): string {
  return value.toFixed(2) + '%';
}
