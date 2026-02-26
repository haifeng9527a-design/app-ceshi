/**
 * 全量轮询：每 N 秒拉取一批（如 500 只）美股报价写入 DB，轮完约 8000 只
 * 前端启动时从后端缓存即可拿到全部数据；可见区再实时拉取
 */
const polygon = require('./polygon');
const db = require('./db');
const quoteStore = require('./quoteStore');
const quoteFetcher = require('./quoteFetcher');
const singleFlight = require('./singleFlight');
const { resolve } = require('./symbolResolver');
const {
  ROTATION_BATCH_SIZE,
  ROTATION_INTERVAL_MS,
  ROTATION_RATE_PER_SEC,
} = require('./config');

let allSymbols = [];
let rotationIndex = 0;
let rotationTimer = null;
let rotationRateCount = 0;
let rotationRateLastSec = 0;

async function rotationRateAcquire() {
  const now = Date.now();
  const sec = Math.floor(now / 1000);
  if (sec > rotationRateLastSec) {
    rotationRateLastSec = sec;
    rotationRateCount = 0;
  }
  if (rotationRateCount >= ROTATION_RATE_PER_SEC) {
    const wait = (sec + 1) * 1000 - now;
    await new Promise((r) => setTimeout(r, wait));
    rotationRateLastSec = Math.floor(Date.now() / 1000);
    rotationRateCount = 0;
  }
  rotationRateCount++;
}

function runBatch(polygonKey) {
  if (allSymbols.length === 0) return;
  const start = rotationIndex;
  const batch = allSymbols.slice(start, start + ROTATION_BATCH_SIZE);
  rotationIndex = (start + ROTATION_BATCH_SIZE) % allSymbols.length;

  const concurrency = Math.min(ROTATION_RATE_PER_SEC, 50);
  const list = batch.filter((s) => resolve(s).usePolygon);
  if (list.length === 0) return;

  (async () => {
    const entries = [];
    const queue = [...list];
    await Promise.all(
      Array(concurrency)
        .fill(0)
        .map(async () => {
          while (queue.length > 0) {
            const sym = queue.shift();
            if (!sym) break;
            await rotationRateAcquire();
            try {
              const r = resolve(sym);
              const snap = await singleFlight.getOrInflight(`quote:${sym}`, () =>
                quoteFetcher.fetchOneQuote(polygonKey, sym, r.polygon)
              );
              entries.push({ symbol: sym, payload: snap, priority: 3 });
            } catch (_) {}
          }
        })
    );
    if (entries.length > 0) quoteStore.setQuotesBatch(entries);
  })().catch(() => {});
}

function startRotationScheduler(polygonKey) {
  if (!polygonKey || rotationTimer) return;
  (async () => {
    try {
      allSymbols = await polygon.getAllUsTickers(polygonKey);
      if (allSymbols.length === 0) return;
    } catch (e) {
      return;
    }
    rotationTimer = setInterval(() => runBatch(polygonKey), ROTATION_INTERVAL_MS);
    runBatch(polygonKey);
  })();
}

function stopRotationScheduler() {
  if (rotationTimer) {
    clearInterval(rotationTimer);
    rotationTimer = null;
  }
  allSymbols = [];
  rotationIndex = 0;
}

module.exports = { startRotationScheduler, stopRotationScheduler };