/** 股票行数据 */
export interface StockRowData {
  id: string;
  code: string;
  name: string;
  changePercent: number;
  price: number;
  change: number;
  volume: number;
  amount: number;
  peTtm: number | null;
  pb: number | null;
  dividendYield: number | null;
}

/** 指数卡片数据 */
export interface IndexCardData {
  symbol: string;
  name: string;
  value: number;
  changePercent: number;
  sparkline: number[];
}

/** K 线单点 */
export interface KLinePoint {
  time: number;
  open: number;
  high: number;
  low: number;
  close: number;
}

/** 买卖盘口档位 */
export interface OrderBookLevel {
  price: number;
  quantity: number;
}
