/**
 * 全量轮询：服务启动后立即做一次全量批量 Snapshot；
 * 之后每小时全量刷新一次并写入缓存（SQLite + Supabase stock_quote_cache）。
 */
const polygon = require('./polygon');
const quoteStore = require('./quoteStore');
const {
  ROTATION_BATCH_SIZE,
  ROTATION_INTERVAL_MS,
  ROTATION_CHUNK_DELAY_MS,
} = require('./config');

let allSymbols = [];
let rotationTimer = null;
let running = false;

async function refreshAllSnapshotsOnce(polygonKey) {
  if (!polygonKey || running) return;
  if (!Array.isArray(allSymbols) || allSymbols.length === 0) return;
  running = true;
  const startedAt = Date.now();
  let totalWritten = 0;
  try {
    for (let i = 0; i < allSymbols.length; i += ROTATION_BATCH_SIZE) {
      const chunk = allSymbols.slice(i, i + ROTATION_BATCH_SIZE);
      let batchMap = await polygon.getBatchSnapshotsV2(polygonKey, chunk);
      if (batchMap.size === 0) {
        batchMap = await polygon.getBatchSnapshotsV3(polygonKey, chunk);
      }
      const entries = [];
      for (const sym of chunk) {
        const payload = batchMap.get(sym);
        if (!payload) continue;
        entries.push({ symbol: sym, payload, priority: 3 });
      }
      if (entries.length > 0) {
        quoteStore.setQuotesBatch(entries);
        totalWritten += entries.length;
      }
      if (i + ROTATION_BATCH_SIZE < allSymbols.length) {
        await new Promise((r) => setTimeout(r, ROTATION_CHUNK_DELAY_MS));
      }
    }
    const ms = Date.now() - startedAt;
    console.log(`[rotationScheduler] full refresh done: symbols=${allSymbols.length}, written=${totalWritten}, elapsedMs=${ms}`);
  } catch (e) {
    console.warn('[rotationScheduler] full refresh failed:', String(e.message || e));
  } finally {
    running = false;
  }
}

function startRotationScheduler(polygonKey) {
  if (!polygonKey || rotationTimer) return;
  (async () => {
    try {
      allSymbols = await polygon.getAllUsTickers(polygonKey);
      allSymbols = [...new Set((allSymbols || []).map((s) => String(s).trim().toUpperCase()).filter(Boolean))];
      if (allSymbols.length === 0) {
        console.warn('[rotationScheduler] empty ticker list, skip');
        return;
      }
      console.log(`[rotationScheduler] loaded symbols: ${allSymbols.length}`);
      await refreshAllSnapshotsOnce(polygonKey); // 启动即全量刷新一次
      rotationTimer = setInterval(() => {
        refreshAllSnapshotsOnce(polygonKey).catch(() => {});
      }, ROTATION_INTERVAL_MS); // 每小时刷新一次
    } catch (e) {
      console.warn('[rotationScheduler] init failed:', String(e.message || e));
    }
  })();
}

function stopRotationScheduler() {
  if (rotationTimer) {
    clearInterval(rotationTimer);
    rotationTimer = null;
  }
  allSymbols = [];
  running = false;
}

module.exports = { startRotationScheduler, stopRotationScheduler };