/**
 * 根据 channelId、可选 uid 生成 Agora RTC Token（v1），供主叫/被叫加入频道时使用。
 * 需在 Supabase 项目 Secrets 中配置：AGORA_APP_ID、AGORA_APP_CERTIFICATE。
 * 使用纯 TypeScript 实现，不依赖 npm 包，避免 Deno 环境 import 失败。
 */
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const appId = Deno.env.get("AGORA_APP_ID") ?? "";
const appCert = Deno.env.get("AGORA_APP_CERTIFICATE") ?? "";
const VERSION = "006";
const APP_ID_LENGTH = 32;

// CRC32 表（标准多项式）
const crcTable = (() => {
  const t: number[] = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    }
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32Str(s: string): number {
  let crc = 0 ^ -1;
  for (let i = 0; i < s.length; i++) {
    crc = (crc >>> 8) ^ crcTable[(crc ^ s.charCodeAt(i)) & 0xff];
  }
  return (crc ^ -1) >>> 0;
}

function utf8(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

// 小端序写入
function putUint16(buf: Uint8Array, offset: number, v: number): void {
  buf[offset] = v & 0xff;
  buf[offset + 1] = (v >>> 8) & 0xff;
}
function putUint32(buf: Uint8Array, offset: number, v: number): void {
  buf[offset] = v & 0xff;
  buf[offset + 1] = (v >>> 8) & 0xff;
  buf[offset + 2] = (v >>> 16) & 0xff;
  buf[offset + 3] = (v >>> 24) & 0xff;
}

// 打包 privileges map: [count:2][key:2, value:4]...
function packMessages(salt: number, ts: number, messages: Record<number, number>): Uint8Array {
  const keys = Object.keys(messages).map(Number);
  let size = 4 + 4 + 2 + keys.length * (2 + 4);
  const buf = new Uint8Array(size);
  let off = 0;
  putUint32(buf, off, salt); off += 4;
  putUint32(buf, off, ts); off += 4;
  putUint16(buf, off, keys.length); off += 2;
  for (const k of keys) {
    putUint16(buf, off, k); off += 2;
    putUint32(buf, off, messages[k] >>> 0); off += 4;
  }
  return buf;
}

// 带长度前缀的 bytes
function packWithLength(data: Uint8Array): Uint8Array {
  const out = new Uint8Array(2 + data.length);
  putUint16(out, 0, data.length);
  out.set(data, 2);
  return out;
}

async function hmacSha256(key: string, message: Uint8Array): Promise<Uint8Array> {
  const keyData = utf8(key);
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, message);
  return new Uint8Array(sig);
}

/**
 * Agora RTC Token v1（与官方 Node RtcTokenBuilder 兼容）
 */
async function buildRtcTokenV1(
  appID: string,
  appCertificate: string,
  channelName: string,
  uid: number,
  privilegeExpiredTs: number
): Promise<string> {
  const uidStr = uid === 0 ? "" : String(uid);
  const salt = Math.floor(Math.random() * 0xffffffff) >>> 0;
  const ts = Math.floor(Date.now() / 1000) + 24 * 3600;
  const messages: Record<number, number> = {
    1: privilegeExpiredTs, // kJoinChannel
    2: privilegeExpiredTs, // kPublishAudioStream
    3: privilegeExpiredTs, // kPublishVideoStream
    4: privilegeExpiredTs, // kPublishDataStream
  };
  const m = packMessages(salt, ts, messages);
  const appIDBuf = utf8(appID);
  const channelBuf = utf8(channelName);
  const uidBuf = utf8(uidStr);
  const toSign = new Uint8Array(appIDBuf.length + channelBuf.length + uidBuf.length + m.length);
  let pos = 0;
  toSign.set(appIDBuf, pos); pos += appIDBuf.length;
  toSign.set(channelBuf, pos); pos += channelBuf.length;
  toSign.set(uidBuf, pos); pos += uidBuf.length;
  toSign.set(m, pos);
  const signature = await hmacSha256(appCertificate, toSign);
  const crcChannel = crc32Str(channelName) >>> 0;
  const crcUid = crc32Str(uidStr) >>> 0;
  const contentSig = packWithLength(signature);
  const contentM = packWithLength(m);
  const contentLen = contentSig.length + 4 + 4 + contentM.length;
  const content = new Uint8Array(contentLen);
  pos = 0;
  content.set(contentSig, pos); pos += contentSig.length;
  putUint32(content, pos, crcChannel); pos += 4;
  putUint32(content, pos, crcUid); pos += 4;
  content.set(contentM, pos);
  const appIDPadded = appID.slice(0, APP_ID_LENGTH).padEnd(APP_ID_LENGTH, "\0");
  const b64 = btoa(String.fromCharCode(...content));
  return VERSION + appIDPadded + b64;
}

async function buildRtcToken(
  channelId: string,
  uid: number,
  expireSeconds: number
): Promise<string> {
  if (!appId || !appCert) return "";
  const privilegeExpiredTs = Math.floor(Date.now() / 1000) + expireSeconds;
  try {
    return await buildRtcTokenV1(appId, appCert, channelId, uid, privilegeExpiredTs);
  } catch (e) {
    console.error("get_agora_token build error:", e);
    return "";
  }
}

serve(async (req) => {
  if (req.method !== "POST" && req.method !== "GET") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  let channelId = "";
  let uid = 0;

  if (req.method === "POST") {
    try {
      const body = await req.json();
      channelId = String(body?.channel_id ?? body?.channelId ?? "").trim();
      const u = body?.uid ?? body?.user_id;
      uid = typeof u === "number" ? u : parseInt(String(u || "0"), 10) || 0;
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON or missing channel_id" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }
  } else {
    const url = new URL(req.url);
    channelId = url.searchParams.get("channel_id") ?? url.searchParams.get("channelId") ?? "";
    uid = parseInt(url.searchParams.get("uid") ?? "0", 10) || 0;
  }

  if (!channelId) {
    return new Response(
      JSON.stringify({ error: "Missing channel_id" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const expireSeconds = 3600;
  const token = await buildRtcToken(channelId, uid, expireSeconds);

  return new Response(
    JSON.stringify({ token: token || "", expireSeconds }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
