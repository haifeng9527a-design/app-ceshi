/**
 * 简单速率限制：每秒最多 N 次，超过则等待到下一秒
 */
let currentSecond = 0;
let countThisSecond = 0;
let maxPerSecondLimit = 5;

function init(maxPerSecond) {
  maxPerSecondLimit = maxPerSecond;
}

async function acquire() {
  const now = Date.now();
  const sec = Math.floor(now / 1000);
  if (sec > currentSecond) {
    currentSecond = sec;
    countThisSecond = 0;
  }
  if (countThisSecond < maxPerSecondLimit) {
    countThisSecond++;
    return;
  }
  const waitMs = (sec + 1) * 1000 - now;
  await new Promise((r) => setTimeout(r, waitMs));
  currentSecond = Math.floor(Date.now() / 1000);
  countThisSecond = 1;
}

module.exports = { acquire, init };