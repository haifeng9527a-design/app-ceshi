/**
 * 可配置：TTL（按优先级/时段）、速率限制、批次大小
 * P0=当前页/自选 P1=榜单/首页 P2=最近请求过 P3=冷门
 */
const TTL_MS_BY_PRIORITY = {
  0: 2 * 1000,    // P0: 2s
  1: 8 * 1000,    // P1: 8s
  2: 30 * 1000,   // P2: 30s
  3: 120 * 1000,  // P3: 2min
};
const TTL_OFF_HOURS_MULTIPLIER = 6;  // 非交易时段 TTL 放大倍数

/** Polygon 每秒最多请求数（按套餐调整） */
const POLYGON_RATE_LIMIT_PER_SEC = 5;
/** 单次补拉最多等多久再返回已有数据（ms） */
const QUOTE_FETCH_TIMEOUT_MS = 600;
/** needFetch 占比超过此值则先快返，后台补拉 */
const PARTIAL_THRESHOLD = 0.2;
/** 每批 Polygon 请求的 symbol 数（并行内仍受 SingleFlight + RateLimiter） */
const POLYGON_BATCH_SIZE = 100;

/** 后台刷新：每 tick 最多拉取的 symbol 数（预算） */
const REFRESH_BUDGET_PER_TICK = 5;
/** 后台刷新：tick 间隔（ms） */
const REFRESH_TICK_MS = 1000;

/** 全量轮询：每批拉取的股票数（每 5 秒一批，约 8000/500≈16 批，约 80 秒一轮） */
const ROTATION_BATCH_SIZE = 500;
/** 全量轮询：批间隔（ms） */
const ROTATION_INTERVAL_MS = 5000;
/** 全量轮询：每批内每秒最多请求数（500 只约 5 秒内完成 = 100/sec，可按套餐调低） */
const ROTATION_RATE_PER_SEC = 100;

module.exports = {
  TTL_MS_BY_PRIORITY,
  TTL_OFF_HOURS_MULTIPLIER,
  POLYGON_RATE_LIMIT_PER_SEC,
  QUOTE_FETCH_TIMEOUT_MS,
  PARTIAL_THRESHOLD,
  POLYGON_BATCH_SIZE,
  REFRESH_BUDGET_PER_TICK,
  REFRESH_TICK_MS,
  ROTATION_BATCH_SIZE,
  ROTATION_INTERVAL_MS,
  ROTATION_RATE_PER_SEC,
};
