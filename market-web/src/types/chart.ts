/** 分时点 */
export interface IntradayPoint {
  time: number;
  price: number;
  volume: number;
}

/** K 线点（含成交量） */
export interface CandlePoint {
  time: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

/** 图表底部统计 */
export interface ChartStats {
  open: number;
  high: number;
  low: number;
  close: number;
  prevClose: number;
  change: number;
  changePercent: number;
  amplitude: number;
  avgPrice: number;
  volume: number;
  turnover: number;
  turnoverRate: number;
  peTtm: number | null;
}
