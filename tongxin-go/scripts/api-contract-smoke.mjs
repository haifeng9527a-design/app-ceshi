#!/usr/bin/env node
//
// api-contract-smoke.mjs — 前后端 API 路由契约静态 smoke
//
// 动机：
//   agent-web 是独立 git repo，tongxin-go 是主仓子目录，两端由不同 agent 并行开发。
//   Sprint 2/3/4 连续出现前后端路径不一致 → 404（time-series / thresholds / touch）。
//   人工看 PRD 对齐不可靠，加一道静态 smoke 挡住同类 bug 再进来。
//
// 做法：
//   1. 解析 `tongxin-agent-web/src/lib/api.ts` 里所有 `api.<method>(<path>)` 调用
//   2. 解析 `tongxin-go/**/*.go` 里所有 `mux.Handle(Func)?("METHOD /path", ...)` 注册
//   3. 归一化（去 query、路径参数 -> {param}），逐条比对
//   4. 任何前端契约在后端缺失 → 非零退出
//
// 特性：
//   - 纯静态，不启动服务、不连 DB、不需要网络 → pre-push 秒跑
//   - 从任意 CWD 可跑：用脚本位置推断 repo root，或传 --root <path>
//   - 对 /api/agent/*、/api/auth/*、/api/referral/* 全部校验
//   - 输出里每条缺失路径给出可操作的修法建议

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// ── args ───────────────────────────────────────────────────────────
const args = process.argv.slice(2);
let rootArg = null;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--root') rootArg = args[i + 1];
}

// 脚本在 <repo-root>/tongxin-go/scripts/，默认 root = ../..
const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(rootArg ?? path.join(here, '..', '..'));

const FRONTEND_FILE = path.join(ROOT, 'tongxin-agent-web/src/lib/api.ts');
const BACKEND_DIR = path.join(ROOT, 'tongxin-go');

// ── helpers ────────────────────────────────────────────────────────
function normalizePath(p) {
  return p
    .replace(/\$\{[^}]*\}/g, '{param}')   // ES 模板字符串 ${id}
    .replace(/\{[^}]*\}/g, '{param}')     // Go net/http 1.22 {id}
    .replace(/:[A-Za-z_][\w]*/g, '{param}') // :id 风格（fallback）
    .replace(/\?.*$/, '')                 // 丢 query string
    .replace(/\/+$/, '');                 // 丢末尾斜杠
}

function walkGoFiles(dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'node_modules' || entry.name === 'vendor' || entry.name.startsWith('.')) continue;
      walkGoFiles(full, acc);
    } else if (entry.name.endsWith('.go')) {
      acc.push(full);
    }
  }
  return acc;
}

// ── parse frontend ─────────────────────────────────────────────────
// 匹配: api.METHOD<...?>(  ['"`]<path>
// 跨行 OK — `[^)]` 允许换行（api.ts 有多行调用，例如
//   api.get<...>(\n      `/path`,\n    )
// ）
function parseFrontendCalls(src) {
  const re = /\bapi\.(get|post|put|delete|patch)\b[^(]*\(\s*[`'"]([^`'")]+)/gs;
  const out = [];
  let m;
  while ((m = re.exec(src)) !== null) {
    const method = m[1].toUpperCase();
    const rawPath = m[2];
    if (!rawPath.startsWith('/api/')) continue;  // 外部 URL / 相对 URL 忽略
    out.push({ method, path: normalizePath(rawPath), rawPath });
  }
  return out;
}

// ── parse backend ──────────────────────────────────────────────────
// 匹配: mux.Handle(Func)?(  "METHOD /path"
function parseBackendRoutes(files) {
  const re = /mux\.Handle(?:Func)?\s*\(\s*"(GET|POST|PUT|DELETE|PATCH)\s+([^"]+)"/g;
  const set = new Set();
  const origin = new Map(); // key -> file for debug
  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    let m;
    while ((m = re.exec(src)) !== null) {
      const key = m[1] + ' ' + normalizePath(m[2]);
      set.add(key);
      if (!origin.has(key)) origin.set(key, f);
    }
  }
  return { set, origin };
}

// ── run ────────────────────────────────────────────────────────────
if (!fs.existsSync(FRONTEND_FILE)) {
  console.log(`[contract] skipping — no frontend file at ${FRONTEND_FILE}`);
  process.exit(0);
}
if (!fs.existsSync(BACKEND_DIR)) {
  console.log(`[contract] skipping — no backend dir at ${BACKEND_DIR}`);
  process.exit(0);
}

const feSrc = fs.readFileSync(FRONTEND_FILE, 'utf8');
const feCalls = parseFrontendCalls(feSrc);

const goFiles = walkGoFiles(BACKEND_DIR);
const { set: beRoutes } = parseBackendRoutes(goFiles);

console.log(`[contract] frontend calls (api.ts): ${feCalls.length}`);
console.log(`[contract] backend routes (tongxin-go/**): ${beRoutes.size}`);

const missing = [];
for (const c of feCalls) {
  const key = c.method + ' ' + c.path;
  if (!beRoutes.has(key)) missing.push(c);
}

if (missing.length === 0) {
  console.log(`[contract] ✅ all ${feCalls.length} frontend calls have matching backend routes`);
  process.exit(0);
}

console.error('[contract] ❌ frontend calls missing in backend routes:');
for (const c of missing) {
  console.error(`  ${c.method.padEnd(6)} ${c.path.padEnd(50)}  (api.ts raw: ${c.rawPath})`);
}
console.error('');
console.error('[contract] how to fix:');
console.error('  - 后端漏注册：在 tongxin-go/cmd/api/main.go 加 mux.Handle("METHOD /path", handler)');
console.error('  - 两边命名不一致：推荐后端加 alias 路由，前端不动（参考 time-series / touch / thresholds 的修法）');
console.error('  - 前端写错：修 tongxin-agent-web/src/lib/api.ts');
process.exit(1);
