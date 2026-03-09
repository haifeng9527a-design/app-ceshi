import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.1";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v5.9.3/index.ts";

type Payload = {
  receiverId: string;
  senderId?: string;
  title?: string;
  body?: string;
  conversationId?: string;
  messageType?: string;
  /** 来电推送：邀请 id、频道、类型、主叫名，点击后弹出来电对话框 */
  invitationId?: string;
  channelId?: string;
  callType?: string;
  fromUserName?: string;
};

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type DeviceTokenRow = {
  token: string;
  platform: string;
  device_id?: string | null;
  manufacturer?: string | null;
  brand?: string | null;
  model?: string | null;
  os_name?: string | null;
  os_version?: string | null;
  app_version?: string | null;
  app_build?: string | null;
  preferred_push_provider?: string | null;
  supports_fcm?: boolean | null;
  supports_getui?: boolean | null;
  updated_at?: string | null;
};

const supabaseUrl = Deno.env.get("SB_URL") ?? "";
const supabaseKey = Deno.env.get("SB_SERVICE_ROLE_KEY") ?? "";
const serviceAccountBase64 =
  Deno.env.get("FIREBASE_SERVICE_ACCOUNT_BASE64") ?? "";
const getuiAppId = Deno.env.get("GETUI_APPID") ?? "";
const getuiAppKey = Deno.env.get("GETUI_APPKEY") ?? "";
const getuiMasterSecret = Deno.env.get("GETUI_MASTERSECRET") ?? "";

const supabase = createClient(supabaseUrl, supabaseKey);

async function getAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const pkcs8 = await importPKCS8(serviceAccount.private_key, "RS256");
  const jwt = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .sign(pkcs8);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    throw new Error(`token exchange failed: ${await response.text()}`);
  }
  const json = await response.json();
  return json.access_token as string;
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function getGetuiToken(): Promise<string> {
  if (!getuiAppId || !getuiAppKey || !getuiMasterSecret) {
    throw new Error("Missing GETUI credentials");
  }
  const timestamp = Date.now().toString();
  const sign = await sha256Hex(`${getuiAppKey}${timestamp}${getuiMasterSecret}`);
  const response = await fetch(`https://restapi.getui.com/v2/${getuiAppId}/auth`, {
    method: "POST",
    headers: { "Content-Type": "application/json;charset=utf-8" },
    body: JSON.stringify({
      sign,
      timestamp,
      appkey: getuiAppKey,
    }),
  });
  if (!response.ok) {
    throw new Error(`getui auth failed: ${await response.text()}`);
  }
  const json = await response.json();
  if (json.code !== 0 || !json.data?.token) {
    throw new Error(`getui auth error: ${JSON.stringify(json)}`);
  }
  return json.data.token as string;
}

function normalizeProvider(platform: string | null | undefined): "fcm" | "getui" {
  return String(platform || "").trim().toLowerCase() === "getui" ? "getui" : "fcm";
}

function parseTime(value: string | null | undefined): number {
  if (!value) return 0;
  const ts = Date.parse(value);
  return Number.isFinite(ts) ? ts : 0;
}

function isHuaweiLike(row: DeviceTokenRow): boolean {
  const manufacturer = String(row.manufacturer || "").toLowerCase();
  const brand = String(row.brand || "").toLowerCase();
  return manufacturer.includes("huawei") ||
    manufacturer.includes("honor") ||
    brand.includes("huawei") ||
    brand.includes("honor");
}

function choosePreferredProvider(rows: DeviceTokenRow[]): "fcm" | "getui" {
  const explicit = rows
    .map((row) => String(row.preferred_push_provider || "").trim().toLowerCase())
    .find((value) => value === "fcm" || value === "getui");
  if (explicit === "fcm" || explicit === "getui") return explicit;
  const hasFcm = rows.some((row) => normalizeProvider(row.platform) === "fcm");
  const hasGetui = rows.some((row) => normalizeProvider(row.platform) === "getui");
  if (hasFcm && hasGetui) {
    return rows.some(isHuaweiLike) ? "getui" : "fcm";
  }
  return hasGetui ? "getui" : "fcm";
}

function selectLatestPerProvider(rows: DeviceTokenRow[]): DeviceTokenRow[] {
  const map = new Map<string, DeviceTokenRow>();
  for (const row of rows) {
    const provider = normalizeProvider(row.platform);
    const existing = map.get(provider);
    if (!existing || parseTime(row.updated_at) >= parseTime(existing.updated_at)) {
      map.set(provider, row);
    }
  }
  return Array.from(map.values());
}

function buildDeliveryRows(rows: DeviceTokenRow[]): DeviceTokenRow[] {
  const delivery: DeviceTokenRow[] = [];
  const grouped = new Map<string, DeviceTokenRow[]>();
  const legacyRows: DeviceTokenRow[] = [];

  for (const row of rows) {
    const token = String(row.token || "").trim();
    if (!token) continue;
    const deviceId = String(row.device_id || "").trim();
    if (!deviceId) {
      legacyRows.push(row);
      continue;
    }
    const list = grouped.get(deviceId) || [];
    list.push(row);
    grouped.set(deviceId, list);
  }

  for (const rowsForDevice of grouped.values()) {
    const perProvider = selectLatestPerProvider(rowsForDevice);
    const preferred = choosePreferredProvider(perProvider);
    delivery.push(
      ...perProvider.filter((row) => normalizeProvider(row.platform) === preferred),
    );
  }

  // 兼容旧表结构：没有 device_id 时，按 token 逐条发，避免“有 FCM 就压掉个推”。
  delivery.push(...legacyRows);

  const dedup = new Map<string, DeviceTokenRow>();
  for (const row of delivery) {
    const provider = normalizeProvider(row.platform);
    dedup.set(`${provider}:${row.token}`, row);
  }
  return Array.from(dedup.values());
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const body: Payload = await req.json();
  if (!body.receiverId) {
    return new Response("Missing receiverId", { status: 400 });
  }
  if (body.senderId && body.receiverId === body.senderId) {
    return new Response(
      JSON.stringify({ skipped: "receiver is sender" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  let tokens: DeviceTokenRow[] | null = null;
  {
    const detailed = await supabase
      .from("device_tokens")
      .select(
        "token,platform,device_id,manufacturer,brand,model,os_name,os_version,app_version,app_build,preferred_push_provider,supports_fcm,supports_getui,updated_at",
      )
      .eq("user_id", body.receiverId);
    if (!detailed.error) {
      tokens = (detailed.data || []) as DeviceTokenRow[];
    } else {
      const legacy = await supabase
        .from("device_tokens")
        .select("token,platform,updated_at")
        .eq("user_id", body.receiverId);
      if (legacy.error) {
        return new Response(legacy.error.message, { status: 500 });
      }
      tokens = (legacy.data || []) as DeviceTokenRow[];
    }
  }

  if (!tokens || tokens.length === 0) {
    return new Response("No device tokens", { status: 200 });
  }

  // 查询接收方当前未读总数，随推送下发给客户端用于角标（不点开 App 也能更新图标数字）
  let badgeCount = 1;
  try {
    const { data: members } = await supabase
      .from("chat_members")
      .select("unread_count")
      .eq("user_id", body.receiverId);
    if (members && members.length > 0) {
      const total = members.reduce(
        (acc, r) => acc + (Number(r.unread_count) || 0),
        0,
      );
      badgeCount = total >= 1 ? Math.min(99, total) : 1;
    }
  } catch (_) {
    badgeCount = 1;
  }
  const badgeStr = String(badgeCount);

  const results: Array<{ platform: string; result: string }> = [];
  const deliveryRows = buildDeliveryRows(tokens);
  const fcmTokens = deliveryRows.filter((row) => normalizeProvider(row.platform) === "fcm");
  const getuiTokens = deliveryRows.filter((row) => normalizeProvider(row.platform) === "getui");

  if (fcmTokens.length > 0) {
    if (!serviceAccountBase64) {
      results.push({
        platform: "fcm",
        result: "Missing FIREBASE_SERVICE_ACCOUNT_BASE64",
      });
    } else {
      const serviceAccountJson = atob(serviceAccountBase64);
      const serviceAccount = JSON.parse(serviceAccountJson) as ServiceAccount;
      const accessToken = await getAccessToken(serviceAccount);
      const isCall = body.invitationId != null && body.invitationId !== "";
      const fcmTitle = isCall
        ? (body.callType === "video" ? "视频通话" : "语音通话")
        : (body.title ?? "新消息");
      const fcmBody = isCall
        ? `${body.fromUserName ?? "对方"} 邀请你${body.callType === "video" ? "视频" : "语音"}通话`
        : (body.body ?? "你收到一条新消息");
      // notification+data：由系统在后台/未运行时直接显示通知栏，来电用 incoming_call 渠道
      for (const row of fcmTokens) {
        const payload = {
          message: {
            token: row.token,
            notification: {
              title: fcmTitle,
              body: fcmBody,
            },
            data: {
              conversationId: body.conversationId ?? "",
              messageType: isCall ? "call_invitation" : (body.messageType ?? ""),
              title: fcmTitle,
              body: fcmBody,
              badge: badgeStr,
              ...(body.invitationId != null && { invitationId: body.invitationId }),
              ...(body.channelId != null && { channelId: body.channelId }),
              ...(body.callType != null && { callType: body.callType }),
              ...(body.fromUserName != null && { fromUserName: body.fromUserName }),
            },
            android: {
              priority: "HIGH",
              notification: {
                channel_id: isCall ? "incoming_call" : "messages",
                notification_priority: "PRIORITY_HIGH",
                default_sound: true,
                default_vibrate_timings: true,
                visibility: "PUBLIC",
                notification_count: badgeCount,
              },
            },
          },
        };
        const response = await fetch(
          `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify(payload),
          },
        );
        results.push({ platform: "fcm", result: await response.text() });
      }
    }
  }

  if (getuiTokens.length > 0) {
    try {
      const token = await getGetuiToken();
      const isCall = body.invitationId != null && body.invitationId !== "";
      const callPayload = isCall
        ? JSON.stringify({
            messageType: "call_invitation",
            invitationId: body.invitationId ?? "",
            channelId: body.channelId ?? "",
            callType: body.callType ?? "voice",
            fromUserName: body.fromUserName ?? "对方",
          })
        : undefined;
      for (const row of getuiTokens) {
        const notifTitle = isCall
          ? (body.callType === "video" ? "视频通话" : "语音通话")
          : body.title ?? "新消息";
        const notifBody = isCall
          ? `${body.fromUserName ?? "对方"} 邀请你${body.callType === "video" ? "视频" : "语音"}通话`
          : body.body ?? "你收到一条新消息";
        // 来电用 notification：透传在后台时可能不送达，导致完全无通知；notification 至少能保证有通知栏提示
        const payload: Record<string, unknown> = {
          request_id: crypto.randomUUID(),
          settings: {
            ttl: 2 * 60 * 60 * 1000,
            strategy: { default: 1 },
          },
          audience: { cid: [row.token] },
          push_message: {
            notification: {
              title: notifTitle,
              body: notifBody,
              click_type: isCall ? "payload" : "startapp",
              channel_id: isCall ? "incoming_call" : "messages",
              channel_name: isCall ? "来电" : "消息通知",
              channel_level: 4,
              ...(isCall && callPayload != null && { payload: callPayload }),
            },
          },
        };
        // 厂商通道：应用被杀死时由华为/小米等系统推送送达，否则退出应用后收不到
        if (isCall && callPayload != null) {
          const payloadEnc = encodeURIComponent(callPayload);
          payload.push_channel = {
            android: {
              ups: {
                notification: {
                  title: notifTitle,
                  body: notifBody,
                  click_type: "intent",
                  intent: `intent://com.getui.push/call?#Intent;scheme=gtpushscheme;launchFlags=0x4000000;package=com.example.teacher_hub;component=com.example.teacher_hub/com.example.teacher_hub.MainActivity;S.payload=${payloadEnc};S.gttask=;end`,
                },
                options: {
                  HW: {
                    "/message/android/urgency": "HIGH",
                    "/message/android/category": "PLAY_VOICE",
                  },
                  XM: { "/message/android/notification_channel_id": "incoming_call" },
                },
              },
            },
          };
        }
        const response = await fetch(
          `https://restapi.getui.com/v2/${getuiAppId}/push/single/cid`,
          {
            method: "POST",
            headers: {
              token,
              "Content-Type": "application/json;charset=utf-8",
            },
            body: JSON.stringify(payload),
          },
        );
        results.push({ platform: "getui", result: await response.text() });
      }
    } catch (error) {
      results.push({ platform: "getui", result: String(error) });
    }
  }

  return new Response(JSON.stringify({ results }), { status: 200 });
});
