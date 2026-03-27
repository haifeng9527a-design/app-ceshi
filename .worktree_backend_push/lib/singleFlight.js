/**
 * SingleFlight：同一 key 并发只执行一次，其他等待同结果，防羊群
 */
const inflight = new Map();

async function getOrInflight(key, fn) {
  const existing = inflight.get(key);
  if (existing) return existing;
  const p = Promise.resolve().then(() => fn()).finally(() => {
    inflight.delete(key);
  });
  inflight.set(key, p);
  return p;
}

module.exports = { getOrInflight };
