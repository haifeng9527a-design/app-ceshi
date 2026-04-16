#!/usr/bin/env node
/* eslint-disable no-console */

/**
 * Web bundle smoke test — 防白屏。
 *
 * 原理：tongxin-app 的 web 版本把整个 bundle 作为 <script> 加载（非 ES module），
 * 所以 bundle 里只要混进 `import.meta.xxx` / 顶层 `export` / 顶层 `await`
 * 这类 ESM-only 语法，整个 bundle 就会 SyntaxError 挂掉 → 白屏。
 * 典型根因：依赖某个 .mjs（例如 zustand/middleware 的 devtools 路径）。
 *
 * 这个脚本：
 *   1. 如果 :8081 没 Metro，启一个（CI 场景）；否则复用（开发机）。
 *   2. fetch 默认 web bundle（和浏览器打开 / 看到白屏时是同一个 URL）。
 *   3. strip 注释 + 字符串字面量 后，grep 已知会触发白屏的危险字符串。
 *   4. 任一命中 → exit 1，打印上下文便于定位根因。
 *
 * 用法：
 *     cd tongxin-app && node scripts/smoke-web.mjs
 *   或：
 *     pnpm smoke:web
 */

import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const APP_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const METRO_PORT = 8081;
// 跟浏览器首次请求时一致的 URL（lazy=false 是为了拿到完整 bundle 而不是分片）。
const BUNDLE_URL =
  `http://localhost:${METRO_PORT}/node_modules/expo-router/entry.bundle` +
  `?platform=web&dev=true&hot=false&lazy=false` +
  `&transform.engine=hermes&transform.routerRoot=app` +
  `&unstable_transformProfile=hermes-stable`;

const START_TIMEOUT_SEC = 120;

// 已知会让 Metro web bundle（作为 <script> 加载）直接 SyntaxError 的语法。
// 往后遇到新 case 就在这里加一条。
const DANGER = [
  {
    name: 'import.meta.<field>',
    re: /\bimport\.meta\.[A-Za-z_$]/,
    hint:
      '某个依赖把 ESM-only 的 import.meta 流到了 web bundle，浏览器会 SyntaxError。' +
      '常见根因：引入了 zustand/middleware 等 .mjs 文件。',
  },
  {
    name: 'top-level export',
    re: /^\s*export\s+(const|function|default|class|let|var|async|\{)/m,
    hint:
      '某个 .mjs 被当脚本直接嵌入 bundle。检查最近加的依赖是否走了 ESM entry。',
  },
];

async function metroAlive() {
  try {
    const r = await fetch(`http://localhost:${METRO_PORT}/`, {
      signal: AbortSignal.timeout(1500),
    });
    return r.ok;
  } catch {
    return false;
  }
}

async function waitForMetro(startedAt) {
  for (;;) {
    if (await metroAlive()) return;
    if ((Date.now() - startedAt) / 1000 > START_TIMEOUT_SEC) {
      throw new Error(`Metro did not become ready in ${START_TIMEOUT_SEC}s`);
    }
    await sleep(2000);
  }
}

/**
 * 单行 sanitize：只处理该行内部的注释和字符串字面量，不跨行。
 * 跨行场景（块注释、模板字符串跨行）无法在单行内处理，但这些场景里几乎不可能
 * 藏着真正触发白屏的代码——触发白屏的都是正常的同行表达式。
 */
function sanitizeLine(line) {
  return line
    .replace(/\/\*.*?\*\//g, '') // 同行块注释
    .replace(/\/\/.*$/, '') // 行注释（直到行末）
    .replace(/"(?:\\.|[^"\\])*"/g, '""')
    .replace(/'(?:\\.|[^'\\])*'/g, "''");
}

/**
 * 逐行扫描 bundle，找所有命中的规则和行号。
 * 用 split('\n') 一次性切，再 map；27 万行 bundle 总耗时 < 1 秒。
 */
function scanBundle(bundle) {
  const lines = bundle.split('\n');
  const hits = []; // [{ rule, line, raw, clean }]
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    // 小小的优化：行里根本没出现 'import.meta' / 'export ' 就跳过 sanitize
    if (!raw.includes('import.meta') && !/\bexport\b/.test(raw)) continue;
    const clean = sanitizeLine(raw);
    for (const rule of DANGER) {
      if (rule.re.test(clean)) {
        hits.push({ rule, line: i + 1, raw, clean });
      }
    }
  }
  return hits;
}

async function main() {
  const weStartedMetro = !(await metroAlive());
  let proc = null;

  if (weStartedMetro) {
    console.log('[smoke] Metro not running — starting expo start --web...');
    proc = spawn('npx', ['expo', 'start', '--web', '--port', String(METRO_PORT)], {
      cwd: APP_ROOT,
      stdio: ['ignore', 'pipe', 'pipe'],
      detached: false,
    });
    // drain output 防 pipe 塞满
    proc.stdout.on('data', () => {});
    proc.stderr.on('data', () => {});
    proc.on('exit', (code) => {
      if (code !== 0 && code !== null) {
        console.error(`[smoke] metro exited early with code ${code}`);
      }
    });

    const startedAt = Date.now();
    await waitForMetro(startedAt);
    console.log(`[smoke] Metro ready in ${Math.round((Date.now() - startedAt) / 1000)}s`);
  } else {
    console.log(`[smoke] reusing existing Metro on :${METRO_PORT}`);
  }

  try {
    console.log('[smoke] fetching bundle...');
    const r = await fetch(BUNDLE_URL);
    if (!r.ok) {
      console.error(`❌ bundle fetch HTTP ${r.status}`);
      const body = await r.text();
      console.error(`   first 500 chars: ${body.slice(0, 500)}`);
      process.exit(1);
    }
    const bundle = await r.text();
    const ctype = r.headers.get('content-type') || '';
    if (!ctype.includes('javascript')) {
      console.error(`❌ bundle content-type looks wrong: ${ctype}`);
      console.error(`   first 500 chars: ${bundle.slice(0, 500)}`);
      process.exit(1);
    }
    console.log(`[smoke] bundle size: ${(bundle.length / 1024 / 1024).toFixed(2)} MB`);

    const hits = scanBundle(bundle);
    if (hits.length === 0) {
      console.log('\n✅ [smoke] bundle is script-safe — no known white-screen triggers.');
      process.exit(0);
    }

    // 按 rule 分组展示，最多每类 3 条避免刷屏
    const byRule = new Map();
    for (const hit of hits) {
      const arr = byRule.get(hit.rule.name) || [];
      arr.push(hit);
      byRule.set(hit.rule.name, arr);
    }
    for (const [name, arr] of byRule) {
      const rule = arr[0].rule;
      console.error(`\n❌ SMOKE FAILED: ${name} detected in web bundle (${arr.length} occurrence${arr.length > 1 ? 's' : ''})`);
      console.error(`   hint: ${rule.hint}`);
      for (const hit of arr.slice(0, 3)) {
        console.error(`   → line ${hit.line}: ${hit.raw.trim().slice(0, 160)}`);
      }
      if (arr.length > 3) {
        console.error(`   ... and ${arr.length - 3} more`);
      }
    }
    console.error(
      '\n→ 修复思路：在 bundle 里搜命中行上方最近的 `// /path/to/source.ts`（Metro' +
        '会在每个 module 前标源文件路径），回到源码改成不经 ESM path 的等价写法。\n',
    );
    process.exit(1);
  } finally {
    if (proc) {
      try {
        proc.kill('SIGTERM');
      } catch {
        /* ignore */
      }
    }
  }
}

main().catch((e) => {
  console.error('❌ [smoke] error:', e);
  process.exit(1);
});
