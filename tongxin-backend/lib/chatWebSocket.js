/**
 * 聊天 WebSocket 服务：/ws/chat
 * - 连接时需带 token: ws://host/ws/chat?token=Firebase_ID_Token
 * - 客户端发送：{ type: 'subscribe', conversation_ids: ['id1','id2'] }
 * - 客户端发送：{ type: 'subscribe_market', symbols: ['AAPL','EUR/USD','BTC/USD'] }
 * - 客户端发送：{ type: 'send', conversation_id, content, message_type?, reply_to_*? }
 * - 服务端推送：{ type: 'new_message', message: {...} }
 * - 服务端推送：{ type: 'market_quote', symbol, price, market?, change?, percent_change?, ... }
 * - 依赖 Supabase Realtime 订阅 chat_messages INSERT，需在 Supabase 启用 chat_messages 的 Realtime
 */
const WebSocket = require('ws');
const supabaseClient = require('./supabaseClient');
const restrictionGuard = require('./restrictionGuard');
const authMiddleware = require('./authMiddleware');
const { triggerChatMessagePush } = require('./chatPush');
const { marketBroadcast } = require('./marketBroadcast');

// conversation_id -> Set<WebSocket>
const conversationSubs = new Map();
// symbol -> Set<WebSocket>（行情订阅）
const marketSubs = new Map();
// WebSocket -> { userId, conversationIds, marketSymbols }
const clientMeta = new WeakMap();

async function verifyToken(token) {
  if (!token || !authMiddleware.isAuthConfigured()) return null;
  try {
    const admin = require('firebase-admin');
    const decoded = await admin.auth().verifyIdToken(token);
    return decoded.uid;
  } catch (_) {
    return null;
  }
}

function broadcastToConversation(conversationId, payload) {
  const set = conversationSubs.get(conversationId);
  if (!set) return;
  const data = JSON.stringify(payload);
  for (const ws of set) {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(data);
    }
  }
}

function unsubscribeClient(ws) {
  const meta = clientMeta.get(ws);
  if (!meta) return;
  for (const cid of meta.conversationIds) {
    const set = conversationSubs.get(cid);
    if (set) {
      set.delete(ws);
      if (set.size === 0) conversationSubs.delete(cid);
    }
  }
  if (meta.marketSubscribeAll) {
    const set = marketSubs.get(MARKET_ALL_KEY);
    if (set) {
      set.delete(ws);
      if (set.size === 0) marketSubs.delete(MARKET_ALL_KEY);
    }
  }
  for (const sym of meta.marketSymbols || []) {
    const set = marketSubs.get(sym);
    if (set) {
      set.delete(ws);
      if (set.size === 0) marketSubs.delete(sym);
    }
  }
  clientMeta.delete(ws);
}

function subscribeClient(ws, conversationIds) {
  const meta = clientMeta.get(ws) || { userId: null, conversationIds: new Set(), marketSymbols: new Set() };
  clientMeta.set(ws, meta);
  const ids = Array.isArray(conversationIds) ? conversationIds : [];
  for (const cid of ids) {
    if (!cid || typeof cid !== 'string') continue;
    meta.conversationIds.add(cid);
    let set = conversationSubs.get(cid);
    if (!set) {
      set = new Set();
      conversationSubs.set(cid, set);
    }
    set.add(ws);
  }
}

const MARKET_ALL_KEY = '__ALL__'; // 订阅全部行情时使用

function subscribeMarketClient(ws, symbols) {
  const meta = clientMeta.get(ws) || { userId: null, conversationIds: new Set(), marketSymbols: new Set(), marketSubscribeAll: false };
  clientMeta.set(ws, meta);
  const syms = Array.isArray(symbols) ? symbols : [];
  const hasAll = syms.some((s) => String(s).trim().toUpperCase() === '*');
  if (hasAll) {
    meta.marketSubscribeAll = true;
    let set = marketSubs.get(MARKET_ALL_KEY);
    if (!set) {
      set = new Set();
      marketSubs.set(MARKET_ALL_KEY, set);
    }
    set.add(ws);
    return;
  }
  meta.marketSubscribeAll = false;
  for (const s of syms) {
    const sym = String(s).trim().toUpperCase();
    if (!sym) continue;
    meta.marketSymbols.add(sym);
    let set = marketSubs.get(sym);
    if (!set) {
      set = new Set();
      marketSubs.set(sym, set);
    }
    set.add(ws);
  }
}

function broadcastToMarket(symbol, payload) {
  const data = JSON.stringify(payload);
  const allSet = marketSubs.get(MARKET_ALL_KEY);
  if (allSet) {
    for (const ws of allSet) {
      if (ws.readyState === WebSocket.OPEN) ws.send(data);
    }
  }
  const symSet = marketSubs.get(symbol);
  if (symSet) {
    for (const ws of symSet) {
      if (ws.readyState === WebSocket.OPEN) ws.send(data);
    }
  }
}

function createChatWsServer(httpServer) {
  const sb = supabaseClient.getClient();
  if (!sb) {
    console.warn('[chatWs] Supabase 未配置，聊天 WebSocket 未启动');
    return;
  }

  const wss = new WebSocket.Server({ path: '/ws/chat', noServer: true });

  // 心跳保活：防止 Render 等代理因空闲超时关闭连接
  const HEARTBEAT_INTERVAL_MS = 25000; // 25 秒 ping 一次
  const CLIENT_TIMEOUT_MS = 35000;
  const heartbeatInterval = setInterval(() => {
    wss.clients.forEach((ws) => {
      if (ws.isAlive === false) {
        const lastActivityAt = ws.lastActivityAt || ws.connectedAt || Date.now();
        const inactiveMs = Date.now() - lastActivityAt;
        ws.closedByHeartbeat = true;
        console.warn(`[chatWs] 心跳超时 uid=${ws.userId?.slice(0, 12)} inactive_ms=${inactiveMs} threshold_ms=${CLIENT_TIMEOUT_MS}`);
        ws.terminate();
        return;
      }
      ws.isAlive = false;
      ws.lastPingAt = Date.now();
      ws.ping();
    });
  }, HEARTBEAT_INTERVAL_MS);
  wss.on('close', () => clearInterval(heartbeatInterval));

  httpServer.on('upgrade', (request, socket, head) => {
    const url = new URL(request.url || '', `http://${request.headers.host}`);
    if (url.pathname !== '/ws/chat') return;
    const token = url.searchParams.get('token')?.trim();
    if (!token) {
      console.log('[chatWs] 连接拒绝: 缺少 token');
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }
    verifyToken(token).then((uid) => {
      if (!uid) {
        console.log('[chatWs] 连接拒绝: token 无效');
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }
      wss.handleUpgrade(request, socket, head, (ws) => {
        ws.userId = uid;
        clientMeta.set(ws, { userId: uid, conversationIds: new Set(), marketSymbols: new Set() });
        wss.emit('connection', ws, request);
      });
    }).catch(() => {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
    });
  });

  wss.on('connection', (ws, req) => {
    const uid = ws.userId;
    ws.isAlive = true;
    ws.connectedAt = Date.now();
    ws.lastActivityAt = ws.connectedAt;
    ws.on('pong', () => {
      ws.isAlive = true;
      ws.lastActivityAt = Date.now();
    });
    ws.on('message', () => {
      ws.isAlive = true;
      ws.lastActivityAt = Date.now();
    });

    console.log(`[chatWs] 连接成功 uid=${uid?.slice(0, 12)}`);

    ws.on('close', (code, reasonBuffer) => {
      const reason = Buffer.isBuffer(reasonBuffer) ? reasonBuffer.toString() : String(reasonBuffer || '');
      const inactiveMs = Date.now() - (ws.lastActivityAt || ws.connectedAt || Date.now());
      const source = ws.closedByHeartbeat ? 'heartbeat_timeout' : 'peer_or_network';
      console.log(`[chatWs] 连接断开 uid=${uid?.slice(0, 12)} code=${code || 0} reason=${reason || '-'} source=${source} inactive_ms=${inactiveMs}`);
      unsubscribeClient(ws);
    });

    ws.on('error', (error) => {
      console.warn(`[chatWs] 连接异常 uid=${uid?.slice(0, 12)} error=${error?.message || error}`);
      unsubscribeClient(ws);
    });

    ws.on('message', async (data) => {
      try {
        const msg = JSON.parse(data.toString());
        const type = msg?.type;
        if (type === 'ping') {
          try { ws.send(JSON.stringify({ type: 'pong' })); } catch (_) {}
          return;
        }
        if (type === 'subscribe') {
          const ids = msg.conversation_ids || [];
          console.log(`[chatWs] 收到订阅 uid=${uid?.slice(0, 12)} conversation_ids=[${ids.slice(0, 3).join(',')}${ids.length > 3 ? '...' : ''}]`);
          subscribeClient(ws, ids);
        } else if (type === 'subscribe_market') {
          const symbols = msg.symbols || [];
          const symList = symbols.map((s) => String(s).trim().toUpperCase()).filter(Boolean);
          if (symList.length > 0) {
            console.log(`[chatWs] 收到行情订阅 uid=${uid?.slice(0, 12)} symbols=[${symList.slice(0, 5).join(',')}${symList.length > 5 ? '...' : ''}]`);
            subscribeMarketClient(ws, symList);
          }
        } else if (type === 'send') {
          const { conversation_id, content, message_type, media_url, duration_ms, reply_to_message_id, reply_to_sender_name, reply_to_content } = msg;
          const contentPreview = typeof content === 'string' ? (content.length > 30 ? content.slice(0, 30) + '...' : content) : String(content).slice(0, 30);
          console.log(`[chatWs] 收到发送 uid=${uid?.slice(0, 12)} conv=${conversation_id?.slice(0, 8)} type=${message_type || 'text'} content=${contentPreview}`);
          if (!conversation_id || content === undefined) {
            ws.send(JSON.stringify({ type: 'error', error: 'missing conversation_id or content' }));
            return;
          }
          const role = await (async () => {
            const { data: r, error } = await sb.from('chat_members').select('role').eq('conversation_id', conversation_id).eq('user_id', uid).maybeSingle();
            if (error || !r) return null;
            return r.role;
          })();
          if (!role) {
            ws.send(JSON.stringify({ type: 'error', error: 'not member' }));
            return;
          }
          const gate = await restrictionGuard.assertActionAllowed(sb, uid, 'send_message');
          if (!gate.allowed) {
            ws.send(JSON.stringify({ type: 'error', error: gate.reason }));
            return;
          }
          const { data: profile } = await sb.from('user_profiles').select('display_name').eq('user_id', uid).maybeSingle();
          const senderName = String(profile?.display_name || '').trim() || '用户';
          const row = {
            conversation_id,
            sender_id: uid,
            sender_name: senderName,
            content: String(content || ''),
            message_type: message_type || 'text',
            media_url: media_url || null,
            duration_ms: duration_ms || null,
            reply_to_message_id: reply_to_message_id || null,
            reply_to_sender_name: reply_to_sender_name || null,
            reply_to_content: reply_to_content || null,
          };
          const { data: inserted, error } = await sb.from('chat_messages').insert(row).select('*').single();
          if (error) {
            console.log(`[chatWs] 发送失败 uid=${uid?.slice(0, 12)} conv=${conversation_id?.slice(0, 8)} error=${error.message}`);
            ws.send(JSON.stringify({ type: 'error', error: error.message }));
            return;
          }
          console.log(`[chatWs] 发送成功 uid=${uid?.slice(0, 12)} conv=${conversation_id?.slice(0, 8)} msgId=${inserted?.id?.slice(0, 8)}`);
          triggerChatMessagePush(sb, inserted).catch((e) => {
            console.warn(`[chatWs] send_push failed conv=${conversation_id?.slice(0, 8)} error=${e?.message || e}`);
          });
          broadcastToConversation(conversation_id, { type: 'new_message', message: inserted });
        }
      } catch (e) {
        try {
          ws.send(JSON.stringify({ type: 'error', error: String(e.message || e) }));
        } catch (_) {}
      }
    });

  });

  // 行情广播：ingestors 写入时推送，发给订阅了该 symbol 的客户端
  marketBroadcast.on('quote', (update) => {
    const sym = String(update.symbol || '').trim().toUpperCase();
    if (!sym) return;
    broadcastToMarket(sym, { type: 'market_quote', ...update });
  });

  // Supabase Realtime：监听 chat_messages 新插入，推送给订阅了该会话的客户端
  sb.channel('chat_messages_changes')
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages' }, (payload) => {
      const record = payload?.new;
      if (!record?.conversation_id) return;
      const contentPreview = (record.content || '').toString().slice(0, 20);
      console.log(`[chatWs] Realtime 新消息 conv=${record.conversation_id?.slice(0, 8)} sender=${record.sender_id?.slice(0, 12)} content=${contentPreview}`);
      broadcastToConversation(record.conversation_id, { type: 'new_message', message: record });
    })
    .subscribe((status) => {
      if (status === 'SUBSCRIBED') {
        console.log('[chatWs] Supabase Realtime chat_messages subscribed');
      } else if (status === 'CHANNEL_ERROR') {
        console.warn('[chatWs] Supabase Realtime 订阅失败，需在 Supabase Dashboard 为 chat_messages 启用 Realtime');
      }
    });

  return wss;
}

module.exports = { createChatWsServer };
