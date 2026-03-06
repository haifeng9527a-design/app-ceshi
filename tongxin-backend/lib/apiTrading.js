const supabaseClient = require('./supabaseClient');
const { resolve } = require('./symbolResolver');
const quoteFetcher = require('./quoteFetcher');
const twelveData = require('./twelveData');

const DEFAULT_INITIAL_CASH_USD = 1000000;
const APP_CONFIG_DEFAULT_CASH_KEY = 'trading_default_initial_cash_usd';

function num(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function nowIso() {
  return new Date().toISOString();
}

function normalizeSide(v) {
  const s = String(v || '').trim().toLowerCase();
  return s === 'buy' || s === 'sell' ? s : '';
}

function normalizeOrderType(v) {
  const t = String(v || '').trim().toLowerCase();
  return t === 'market' || t === 'limit' ? t : '';
}

function detectAssetType(symbol) {
  const s = String(symbol || '').trim().toUpperCase();
  if (!s) return 'stock';
  if (s.includes('/')) return 'forex';
  if (s.startsWith('X:') || s.endsWith('USD') || s.endsWith('USDT')) return 'crypto';
  return 'stock';
}

async function getUserRole(sb, uid) {
  const { data, error } = await sb.from('user_profiles').select('role').eq('user_id', uid).maybeSingle();
  if (error) throw new Error(error.message);
  return String(data?.role || '').toLowerCase();
}

async function ensureAdmin(req, res, sb) {
  if (req.isAdminByKey === true) return true;
  const uid = req.firebaseUid;
  if (!uid) {
    res.status(401).json({ error: '未鉴权' });
    return false;
  }
  try {
    const role = await getUserRole(sb, uid);
    if (role !== 'admin' && role !== 'customer_service_admin') {
      res.status(403).json({ error: 'forbidden' });
      return false;
    }
    return true;
  } catch (e) {
    res.status(502).json({ error: String(e.message || e) });
    return false;
  }
}

async function getDefaultInitialCash(sb) {
  const { data, error } = await sb.from('app_config').select('value').eq('key', APP_CONFIG_DEFAULT_CASH_KEY).maybeSingle();
  if (error) throw new Error(error.message);
  const value = num(data?.value, DEFAULT_INITIAL_CASH_USD);
  return value > 0 ? value : DEFAULT_INITIAL_CASH_USD;
}

async function ensureTradingAccount(sb, teacherId) {
  const { data: existed, error: qErr } = await sb
    .from('teacher_trading_accounts')
    .select('*')
    .eq('teacher_id', teacherId)
    .maybeSingle();
  if (qErr) throw new Error(qErr.message);
  if (existed) return existed;

  const initialCash = await getDefaultInitialCash(sb);
  const row = {
    teacher_id: teacherId,
    currency: 'USD',
    initial_cash: initialCash,
    cash_balance: initialCash,
    cash_available: initialCash,
    cash_frozen: 0,
    market_value: 0,
    realized_pnl: 0,
    unrealized_pnl: 0,
    equity: initialCash,
    updated_at: nowIso(),
  };
  const { data: inserted, error: iErr } = await sb.from('teacher_trading_accounts').insert(row).select('*').single();
  if (iErr) throw new Error(iErr.message);
  return inserted;
}

async function getLatestPriceBySymbol(symbol) {
  const polygonKey = process.env.POLYGON_API_KEY?.trim();
  const twelveKey = process.env.TWELVE_DATA_API_KEY?.trim();
  const r = resolve(symbol);
  if (r.usePolygon && polygonKey) {
    const snap = await quoteFetcher.fetchOneQuote(polygonKey, symbol, r.polygon);
    const p = num(snap?.close);
    if (p > 0) return p;
  }
  if (r.useTwelve && twelveKey) {
    const map = await twelveData.getQuotes(twelveKey, [r.twelve]);
    const q = map?.[r.twelve];
    const p = num(q?.close);
    if (p > 0) return p;
  }
  return null;
}

async function createLedger(sb, payload) {
  const row = {
    teacher_id: payload.teacher_id,
    entry_type: payload.entry_type,
    amount: num(payload.amount),
    balance_after: num(payload.balance_after),
    order_id: payload.order_id || null,
    symbol: payload.symbol || null,
    side: payload.side || null,
    note: payload.note || null,
    created_at: nowIso(),
  };
  const { error } = await sb.from('teacher_account_ledger').insert(row);
  if (error) throw new Error(error.message);
}

async function getOpenPosition(sb, teacherId, symbol) {
  const { data, error } = await sb
    .from('teacher_positions')
    .select('*')
    .eq('teacher_id', teacherId)
    .eq('asset', symbol)
    .eq('is_history', false)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return data || null;
}

async function getReservedSellQty(sb, teacherId, symbol) {
  const { data, error } = await sb
    .from('teacher_orders')
    .select('remaining_quantity')
    .eq('teacher_id', teacherId)
    .eq('symbol', symbol)
    .eq('side', 'sell')
    .in('status', ['pending', 'partial']);
  if (error) throw new Error(error.message);
  return (data || []).reduce((acc, row) => acc + num(row.remaining_quantity), 0);
}

async function recomputeAccountSnapshot(sb, teacherId) {
  const account = await ensureTradingAccount(sb, teacherId);
  const { data: positions, error: pErr } = await sb
    .from('teacher_positions')
    .select('*')
    .eq('teacher_id', teacherId)
    .eq('is_history', false);
  if (pErr) throw new Error(pErr.message);
  const posList = positions || [];
  const symbols = posList.map((p) => String(p.asset || '').trim().toUpperCase()).filter(Boolean);
  const unique = [...new Set(symbols)];

  const priceMap = new Map();
  for (const s of unique) {
    const price = await getLatestPriceBySymbol(s);
    if (price != null) priceMap.set(s, price);
  }

  let marketValue = 0;
  let unrealized = 0;
  for (const p of posList) {
    const qty = num(p.buy_shares);
    if (qty <= 0) continue;
    const cost = num(p.cost_price, num(p.buy_price));
    const mark = priceMap.get(String(p.asset || '').toUpperCase());
    if (mark == null) continue;
    marketValue += mark * qty;
    unrealized += (mark - cost) * qty;
  }

  const cashBalance = num(account.cash_balance);
  const equity = cashBalance + marketValue;
  const updated = {
    market_value: marketValue,
    unrealized_pnl: unrealized,
    equity,
    updated_at: nowIso(),
  };
  const { data: acc2, error: uErr } = await sb
    .from('teacher_trading_accounts')
    .update(updated)
    .eq('teacher_id', teacherId)
    .select('*')
    .single();
  if (uErr) throw new Error(uErr.message);
  return {
    account: acc2,
    positions: posList,
  };
}

async function executeOrderFullFill(sb, order) {
  const teacherId = String(order.teacher_id);
  const symbol = String(order.symbol).toUpperCase();
  const qty = num(order.remaining_quantity, num(order.quantity));
  if (qty <= 0) return;

  const fillPrice = num(order.fill_price_target, num(order.limit_price));
  if (fillPrice <= 0) throw new Error('fill price invalid');

  const { data: account, error: aErr } = await sb
    .from('teacher_trading_accounts')
    .select('*')
    .eq('teacher_id', teacherId)
    .single();
  if (aErr) throw new Error(aErr.message);

  if (order.side === 'buy') {
    const frozen = num(order.frozen_cash);
    const cost = fillPrice * qty;
    const refund = Math.max(0, frozen - cost);
    const cashBalance = num(account.cash_balance) - cost;
    const cashFrozen = Math.max(0, num(account.cash_frozen) - frozen);
    const cashAvailable = num(account.cash_available) + refund;
    const { error: upAccErr } = await sb
      .from('teacher_trading_accounts')
      .update({
        cash_balance: cashBalance,
        cash_frozen: cashFrozen,
        cash_available: cashAvailable,
        updated_at: nowIso(),
      })
      .eq('teacher_id', teacherId);
    if (upAccErr) throw new Error(upAccErr.message);

    const pos = await getOpenPosition(sb, teacherId, symbol);
    if (pos) {
      const oldQty = num(pos.buy_shares);
      const oldCost = num(pos.cost_price, num(pos.buy_price));
      const newQty = oldQty + qty;
      const newCost = newQty > 0 ? ((oldQty * oldCost) + (qty * fillPrice)) / newQty : fillPrice;
      const { error: upPosErr } = await sb
        .from('teacher_positions')
        .update({
          buy_shares: newQty,
          buy_price: fillPrice,
          cost_price: newCost,
          current_price: fillPrice,
          floating_pnl: (fillPrice - newCost) * newQty,
          pnl_ratio: newCost > 0 ? ((fillPrice - newCost) / newCost * 100) : 0,
        })
        .eq('id', pos.id);
      if (upPosErr) throw new Error(upPosErr.message);
    } else {
      const { error: insPosErr } = await sb.from('teacher_positions').insert({
        teacher_id: teacherId,
        asset: symbol,
        buy_time: nowIso(),
        buy_shares: qty,
        buy_price: fillPrice,
        cost_price: fillPrice,
        current_price: fillPrice,
        floating_pnl: 0,
        pnl_ratio: 0,
        is_history: false,
      });
      if (insPosErr) throw new Error(insPosErr.message);
    }

    await createLedger(sb, {
      teacher_id: teacherId,
      entry_type: 'order_filled_buy',
      amount: -cost,
      balance_after: cashBalance,
      order_id: order.id,
      symbol,
      side: 'buy',
      note: `buy fill ${qty}@${fillPrice}`,
    });
  } else {
    const pos = await getOpenPosition(sb, teacherId, symbol);
    if (!pos) throw new Error('position not found for sell');
    const oldQty = num(pos.buy_shares);
    if (oldQty < qty) throw new Error('position insufficient for sell');
    const cost = num(pos.cost_price, num(pos.buy_price));
    const proceeds = fillPrice * qty;
    const realized = (fillPrice - cost) * qty;
    const remain = oldQty - qty;

    const cashBalance = num(account.cash_balance) + proceeds;
    const cashAvailable = num(account.cash_available) + proceeds;
    const realizedPnl = num(account.realized_pnl) + realized;

    const { error: upAccErr } = await sb
      .from('teacher_trading_accounts')
      .update({
        cash_balance: cashBalance,
        cash_available: cashAvailable,
        realized_pnl: realizedPnl,
        updated_at: nowIso(),
      })
      .eq('teacher_id', teacherId);
    if (upAccErr) throw new Error(upAccErr.message);

    if (remain > 0) {
      const { error: upPosErr } = await sb
        .from('teacher_positions')
        .update({
          buy_shares: remain,
          current_price: fillPrice,
          floating_pnl: (fillPrice - cost) * remain,
          pnl_ratio: cost > 0 ? ((fillPrice - cost) / cost * 100) : 0,
        })
        .eq('id', pos.id);
      if (upPosErr) throw new Error(upPosErr.message);
    } else {
      const { error: delPosErr } = await sb
        .from('teacher_positions')
        .delete()
        .eq('id', pos.id);
      if (delPosErr) throw new Error(delPosErr.message);
    }

    const { error: insHistoryErr } = await sb
      .from('teacher_positions')
      .insert({
        teacher_id: teacherId,
        asset: symbol,
        buy_time: pos.buy_time || nowIso(),
        buy_shares: qty,
        buy_price: cost,
        cost_price: cost,
        current_price: fillPrice,
        sell_time: nowIso(),
        sell_price: fillPrice,
        pnl_amount: realized,
        pnl_ratio: cost > 0 ? ((fillPrice - cost) / cost * 100) : 0,
        is_history: true,
      });
    if (insHistoryErr) throw new Error(insHistoryErr.message);

    const { error: tradeRecordErr } = await sb
      .from('trade_records')
      .insert({
        teacher_id: teacherId,
        symbol,
        side: 'sell',
        entry_price: cost,
        exit_price: fillPrice,
        qty,
        pnl: realized,
        trade_time: nowIso(),
        note: 'generated by trading engine',
        created_at: nowIso(),
      });
    if (tradeRecordErr) {
      // 兼容旧库字段差异：不阻断核心撮合闭环
      console.warn('[trading] trade_records insert skipped:', tradeRecordErr.message);
    }

    await createLedger(sb, {
      teacher_id: teacherId,
      entry_type: 'order_filled_sell',
      amount: proceeds,
      balance_after: cashBalance,
      order_id: order.id,
      symbol,
      side: 'sell',
      note: `sell fill ${qty}@${fillPrice}`,
    });
  }

  const { error: fillErr } = await sb.from('teacher_order_fills').insert({
    order_id: order.id,
    teacher_id: teacherId,
    symbol,
    side: order.side,
    fill_price: fillPrice,
    fill_quantity: qty,
    fill_time: nowIso(),
  });
  if (fillErr) throw new Error(fillErr.message);

  const { error: upOrderErr } = await sb
    .from('teacher_orders')
    .update({
      status: 'filled',
      filled_quantity: num(order.filled_quantity) + qty,
      remaining_quantity: 0,
      avg_fill_price: fillPrice,
      updated_at: nowIso(),
    })
    .eq('id', order.id);
  if (upOrderErr) throw new Error(upOrderErr.message);
}

async function tryMatchPendingOrders(sb, teacherId) {
  const { data: orders, error } = await sb
    .from('teacher_orders')
    .select('*')
    .eq('teacher_id', teacherId)
    .in('status', ['pending', 'partial'])
    .order('created_at', { ascending: true })
    .limit(100);
  if (error) throw new Error(error.message);
  const list = orders || [];
  for (const o of list) {
    const symbol = String(o.symbol || '').trim().toUpperCase();
    if (!symbol) continue;
    const px = await getLatestPriceBySymbol(symbol);
    if (px == null || px <= 0) continue;
    const isMarket = o.order_type === 'market';
    const limit = num(o.limit_price);
    let shouldFill = isMarket;
    if (!isMarket) {
      if (o.side === 'buy') shouldFill = px <= limit;
      if (o.side === 'sell') shouldFill = px >= limit;
    }
    if (!shouldFill) continue;
    const withTarget = { ...o, fill_price_target: px };
    await executeOrderFullFill(sb, withTarget);
  }
}

function registerTradingRoutes(app, requireAuth) {
  app.get('/api/admin/trading/config', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    if (!(await ensureAdmin(req, res, sb))) return;
    try {
      const value = await getDefaultInitialCash(sb);
      return res.json({ default_initial_cash_usd: value });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.patch('/api/admin/trading/config', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    if (!(await ensureAdmin(req, res, sb))) return;
    const value = num(req.body?.default_initial_cash_usd, 0);
    if (!(value > 0)) return res.status(400).json({ error: 'default_initial_cash_usd 必须大于 0' });
    try {
      const { error } = await sb.from('app_config').upsert({
        key: APP_CONFIG_DEFAULT_CASH_KEY,
        value: String(value),
        updated_at: nowIso(),
      }, { onConflict: 'key' });
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true, default_initial_cash_usd: value });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.post('/api/admin/trading/accounts/:teacherId/reset', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    if (!(await ensureAdmin(req, res, sb))) return;
    const teacherId = String(req.params.teacherId || '').trim();
    if (!teacherId) return res.status(400).json({ error: 'missing teacherId' });
    const amount = num(req.body?.initial_cash_usd, DEFAULT_INITIAL_CASH_USD);
    const clearHistory = req.body?.clear_history !== false;
    if (!(amount > 0)) return res.status(400).json({ error: 'initial_cash_usd 必须大于 0' });
    try {
      const { error: accErr } = await sb
        .from('teacher_trading_accounts')
        .upsert({
          teacher_id: teacherId,
          currency: 'USD',
          initial_cash: amount,
          cash_balance: amount,
          cash_available: amount,
          cash_frozen: 0,
          market_value: 0,
          realized_pnl: 0,
          unrealized_pnl: 0,
          equity: amount,
          updated_at: nowIso(),
        }, { onConflict: 'teacher_id' });
      if (accErr) return res.status(502).json({ error: accErr.message });

      if (clearHistory) {
        await sb.from('teacher_orders').delete().eq('teacher_id', teacherId);
        await sb.from('teacher_order_fills').delete().eq('teacher_id', teacherId);
        await sb.from('teacher_positions').delete().eq('teacher_id', teacherId);
        await sb.from('teacher_account_ledger').delete().eq('teacher_id', teacherId);
      } else {
        await sb.from('teacher_orders').delete().eq('teacher_id', teacherId).in('status', ['pending', 'partial']);
        await sb.from('teacher_positions').delete().eq('teacher_id', teacherId).eq('is_history', false);
      }

      await createLedger(sb, {
        teacher_id: teacherId,
        entry_type: 'account_reset',
        amount,
        balance_after: amount,
        note: clearHistory ? 'admin reset account (clear history)' : 'admin reset account (keep history)',
      });
      return res.json({ ok: true, clear_history: clearHistory });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/trading/account', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      await ensureTradingAccount(sb, uid);
      await tryMatchPendingOrders(sb, uid);
      const snap = await recomputeAccountSnapshot(sb, uid);
      return res.json(snap.account);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/trading/summary', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      await ensureTradingAccount(sb, uid);
      await tryMatchPendingOrders(sb, uid);
      const snap = await recomputeAccountSnapshot(sb, uid);
      const { data: openOrders, error: oErr } = await sb
        .from('teacher_orders')
        .select('id')
        .eq('teacher_id', uid)
        .in('status', ['pending', 'partial']);
      if (oErr) return res.status(502).json({ error: oErr.message });
      return res.json({
        account: snap.account,
        open_orders: (openOrders || []).length,
        positions: (snap.positions || []).length,
      });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/trading/positions', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      await ensureTradingAccount(sb, uid);
      await tryMatchPendingOrders(sb, uid);
      await recomputeAccountSnapshot(sb, uid);
      const { data, error } = await sb
        .from('teacher_positions')
        .select('*')
        .eq('teacher_id', uid)
        .eq('is_history', false)
        .order('created_at', { ascending: false });
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/trading/fills', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    const limit = Math.max(1, Math.min(parseInt(req.query.limit, 10) || 100, 500));
    try {
      const { data, error } = await sb
        .from('teacher_order_fills')
        .select('*')
        .eq('teacher_id', uid)
        .order('fill_time', { ascending: false })
        .limit(limit);
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/trading/ledger', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    const limit = Math.max(1, Math.min(parseInt(req.query.limit, 10) || 200, 500));
    try {
      await ensureTradingAccount(sb, uid);
      const { data, error } = await sb
        .from('teacher_account_ledger')
        .select('*')
        .eq('teacher_id', uid)
        .order('created_at', { ascending: false })
        .limit(limit);
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/trading/orders/open', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      await ensureTradingAccount(sb, uid);
      await tryMatchPendingOrders(sb, uid);
      const { data, error } = await sb
        .from('teacher_orders')
        .select('*')
        .eq('teacher_id', uid)
        .in('status', ['pending', 'partial'])
        .order('created_at', { ascending: false });
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/trading/orders/history', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    const limit = Math.max(1, Math.min(parseInt(req.query.limit, 10) || 200, 500));
    try {
      await ensureTradingAccount(sb, uid);
      await tryMatchPendingOrders(sb, uid);
      const { data, error } = await sb
        .from('teacher_orders')
        .select('*')
        .eq('teacher_id', uid)
        .not('status', 'in', '(pending,partial)')
        .order('created_at', { ascending: false })
        .limit(limit);
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.post('/api/trading/orders', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    const symbol = String(req.body?.symbol || '').trim().toUpperCase();
    const side = normalizeSide(req.body?.side);
    const orderType = normalizeOrderType(req.body?.order_type);
    const quantity = num(req.body?.quantity);
    const limitPrice = num(req.body?.limit_price);
    if (!symbol) return res.status(400).json({ error: 'symbol required' });
    if (!side) return res.status(400).json({ error: 'side invalid' });
    if (!orderType) return res.status(400).json({ error: 'order_type invalid' });
    if (!(quantity > 0)) return res.status(400).json({ error: 'quantity invalid' });
    if (orderType === 'limit' && !(limitPrice > 0)) return res.status(400).json({ error: 'limit_price invalid' });
    try {
      const account = await ensureTradingAccount(sb, uid);
      await tryMatchPendingOrders(sb, uid);
      await recomputeAccountSnapshot(sb, uid);
      const markPrice = await getLatestPriceBySymbol(symbol);
      const checkPrice = orderType === 'market' ? markPrice : limitPrice;
      if (!(checkPrice > 0)) {
        return res.status(400).json({ error: '行情不可用，无法下单' });
      }
      const now = nowIso();
      let frozenCash = 0;
      let reservedQty = 0;
      if (side === 'buy') {
        frozenCash = checkPrice * quantity;
        if (num(account.cash_available) < frozenCash) {
          return res.status(400).json({ error: '可用资金不足' });
        }
      } else {
        const pos = await getOpenPosition(sb, uid, symbol);
        const totalQty = num(pos?.buy_shares);
        const reserved = await getReservedSellQty(sb, uid, symbol);
        const availableQty = totalQty - reserved;
        if (availableQty < quantity) {
          return res.status(400).json({ error: '可卖仓位不足' });
        }
        reservedQty = quantity;
      }

      const orderRow = {
        teacher_id: uid,
        symbol,
        asset_type: detectAssetType(symbol),
        side,
        order_type: orderType,
        limit_price: orderType === 'limit' ? limitPrice : null,
        quantity,
        filled_quantity: 0,
        remaining_quantity: quantity,
        avg_fill_price: null,
        status: 'pending',
        frozen_cash: frozenCash,
        reserved_quantity: reservedQty,
        created_at: now,
        updated_at: now,
      };
      const { data: inserted, error: insErr } = await sb
        .from('teacher_orders')
        .insert(orderRow)
        .select('*')
        .single();
      if (insErr) return res.status(502).json({ error: insErr.message });

      if (side === 'buy') {
        const cashAvailable = num(account.cash_available) - frozenCash;
        const cashFrozen = num(account.cash_frozen) + frozenCash;
        const { error: upAccErr } = await sb
          .from('teacher_trading_accounts')
          .update({
            cash_available: cashAvailable,
            cash_frozen: cashFrozen,
            updated_at: nowIso(),
          })
          .eq('teacher_id', uid);
        if (upAccErr) return res.status(502).json({ error: upAccErr.message });
        await createLedger(sb, {
          teacher_id: uid,
          entry_type: 'order_cash_frozen',
          amount: -frozenCash,
          balance_after: num(account.cash_balance),
          order_id: inserted.id,
          symbol,
          side,
          note: `freeze cash for ${side} ${quantity}@${checkPrice}`,
        });
      }

      let shouldFill = false;
      if (orderType === 'market') shouldFill = true;
      else if (markPrice != null && markPrice > 0) {
        if (side === 'buy') shouldFill = markPrice <= limitPrice;
        else shouldFill = markPrice >= limitPrice;
      }
      if (shouldFill) {
        await executeOrderFullFill(sb, { ...inserted, fill_price_target: markPrice || limitPrice });
      }

      await recomputeAccountSnapshot(sb, uid);
      const { data: finalOrder, error: finalErr } = await sb
        .from('teacher_orders')
        .select('*')
        .eq('id', inserted.id)
        .single();
      if (finalErr) return res.status(502).json({ error: finalErr.message });
      return res.json(finalOrder);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.post('/api/trading/orders/:id/cancel', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'missing id' });
    try {
      const { data: order, error: oErr } = await sb
        .from('teacher_orders')
        .select('*')
        .eq('id', id)
        .eq('teacher_id', uid)
        .maybeSingle();
      if (oErr) return res.status(502).json({ error: oErr.message });
      if (!order) return res.status(404).json({ error: 'order not found' });
      if (order.status !== 'pending' && order.status !== 'partial') {
        return res.status(400).json({ error: 'order cannot cancel' });
      }
      if (order.side === 'buy') {
        const { data: acc, error: aErr } = await sb
          .from('teacher_trading_accounts')
          .select('*')
          .eq('teacher_id', uid)
          .single();
        if (aErr) return res.status(502).json({ error: aErr.message });
        const frozen = num(order.frozen_cash);
        const cashFrozen = Math.max(0, num(acc.cash_frozen) - frozen);
        const cashAvailable = num(acc.cash_available) + frozen;
        const { error: upAccErr } = await sb
          .from('teacher_trading_accounts')
          .update({
            cash_frozen: cashFrozen,
            cash_available: cashAvailable,
            updated_at: nowIso(),
          })
          .eq('teacher_id', uid);
        if (upAccErr) return res.status(502).json({ error: upAccErr.message });
        await createLedger(sb, {
          teacher_id: uid,
          entry_type: 'order_cancel_unfreeze',
          amount: frozen,
          balance_after: num(acc.cash_balance),
          order_id: order.id,
          symbol: order.symbol,
          side: order.side,
          note: 'cancel order unfreeze cash',
        });
      }
      const { error: upOrderErr } = await sb
        .from('teacher_orders')
        .update({
          status: 'cancelled',
          updated_at: nowIso(),
        })
        .eq('id', id)
        .eq('teacher_id', uid);
      if (upOrderErr) return res.status(502).json({ error: upOrderErr.message });
      await recomputeAccountSnapshot(sb, uid);
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });
}

module.exports = { registerTradingRoutes };
