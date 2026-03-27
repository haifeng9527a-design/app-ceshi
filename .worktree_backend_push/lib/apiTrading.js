const supabaseClient = require('./supabaseClient');
const { resolve, forTwelve, isCrypto, isFx } = require('./symbolResolver');
const quoteFetcher = require('./quoteFetcher');
const twelveData = require('./twelveData');

const DEFAULT_INITIAL_CASH_USD = 1000000;
const APP_CONFIG_DEFAULT_CASH_KEY = 'trading_default_initial_cash_usd';
const APP_CONFIG_DEFAULT_PRODUCT_TYPE_KEY = 'trading_default_product_type';
const APP_CONFIG_DEFAULT_MARGIN_MODE_KEY = 'trading_default_margin_mode';
const APP_CONFIG_DEFAULT_LEVERAGE_KEY = 'trading_default_leverage';
const APP_CONFIG_MAX_LEVERAGE_KEY = 'trading_max_leverage';
const APP_CONFIG_ALLOW_SHORT_KEY = 'trading_allow_short';
const APP_CONFIG_MAINTENANCE_MARGIN_RATE_KEY = 'trading_maintenance_margin_rate';
const DEFAULT_MAINTENANCE_MARGIN_RATE = Number.isFinite(Number(process.env.TRADING_MAINTENANCE_MARGIN_RATE))
  ? Number(process.env.TRADING_MAINTENANCE_MARGIN_RATE)
  : 0.005;

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
  if (isCrypto(s)) return 'crypto';
  if (isFx(s)) return 'forex';
  return 'stock';
}

function normalizeAssetClass(v, symbol) {
  const s = String(v || '').trim().toLowerCase();
  if (s === 'stock' || s === 'forex' || s === 'crypto') return s;
  return detectAssetType(symbol);
}

function normalizeProductType(v, assetClass = 'stock') {
  const t = String(v || '').trim().toLowerCase();
  if (t === 'spot' || t === 'perpetual' || t === 'future') return t;
  return assetClass === 'stock' ? 'spot' : 'spot';
}

function normalizePositionSide(v) {
  const s = String(v || '').trim().toLowerCase();
  return s === 'short' ? 'short' : 'long';
}

function normalizePositionAction(v) {
  const s = String(v || '').trim().toLowerCase();
  return s === 'close' || s === 'reduce' ? s : 'open';
}

function normalizeMarginMode(v) {
  const s = String(v || '').trim().toLowerCase();
  return s === 'isolated' ? 'isolated' : 'cross';
}

function isContractProduct(productType) {
  return productType === 'perpetual' || productType === 'future';
}

function validatePositionIntent({ side, productType, positionSide, positionAction }) {
  if (!isContractProduct(productType)) return null;
  if (positionSide === 'long' && positionAction === 'open' && side !== 'buy') {
    return '开多只能使用 buy';
  }
  if (positionSide === 'long' && positionAction === 'close' && side !== 'sell') {
    return '平多只能使用 sell';
  }
  if (positionSide === 'short' && positionAction === 'open' && side !== 'sell') {
    return '开空只能使用 sell';
  }
  if (positionSide === 'short' && positionAction === 'close' && side !== 'buy') {
    return '平空只能使用 buy';
  }
  return null;
}

function calcContractNotional(price, qty, contractSize = 1, multiplier = 1) {
  return price * qty * contractSize * multiplier;
}

function calcInitialMargin(notional, leverage) {
  if (!(leverage > 0)) return notional;
  return notional / leverage;
}

function calcMaintenanceMargin(notional, maintenanceMarginRate = DEFAULT_MAINTENANCE_MARGIN_RATE) {
  return notional * maintenanceMarginRate;
}

function calcContractUnrealized(mark, entry, qty, positionSide, contractSize = 1, multiplier = 1) {
  const diff = positionSide === 'short' ? (entry - mark) : (mark - entry);
  return diff * qty * contractSize * multiplier;
}

function calcLiquidationPrice({
  entryPrice,
  leverage,
  positionSide,
  maintenanceMarginRate = DEFAULT_MAINTENANCE_MARGIN_RATE,
}) {
  if (!(entryPrice > 0) || !(leverage > 0)) return null;
  if (positionSide === 'short') {
    return entryPrice * (1 + (1 / leverage) - maintenanceMarginRate);
  }
  return entryPrice * (1 - (1 / leverage) + maintenanceMarginRate);
}

function shouldLiquidatePosition(positionSide, markPrice, liquidationPrice) {
  if (!(markPrice > 0) || !(liquidationPrice > 0)) return false;
  if (positionSide === 'short') return markPrice >= liquidationPrice;
  return markPrice <= liquidationPrice;
}

function calcNotional({ price, quantity, contractSize = 1, multiplier = 1 }) {
  return num(price) * num(quantity) * Math.max(1, num(contractSize, 1)) * Math.max(1, num(multiplier, 1));
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

function parseBooleanConfig(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  const text = String(value ?? '').trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(text)) return true;
  if (['0', 'false', 'no', 'off'].includes(text)) return false;
  return fallback;
}

async function getTradingConfig(sb) {
  const keys = [
    APP_CONFIG_DEFAULT_CASH_KEY,
    APP_CONFIG_DEFAULT_PRODUCT_TYPE_KEY,
    APP_CONFIG_DEFAULT_MARGIN_MODE_KEY,
    APP_CONFIG_DEFAULT_LEVERAGE_KEY,
    APP_CONFIG_MAX_LEVERAGE_KEY,
    APP_CONFIG_ALLOW_SHORT_KEY,
    APP_CONFIG_MAINTENANCE_MARGIN_RATE_KEY,
  ];
  const { data, error } = await sb
    .from('app_config')
    .select('key,value')
    .in('key', keys);
  if (error) throw new Error(error.message);
  const map = new Map((data || []).map((row) => [String(row.key), row.value]));
  const defaultLeverage = Math.max(1, num(map.get(APP_CONFIG_DEFAULT_LEVERAGE_KEY), 5));
  const maxLeverage = Math.max(defaultLeverage, num(map.get(APP_CONFIG_MAX_LEVERAGE_KEY), 50));
  const maintenanceMarginRate = Math.min(
    0.5,
    Math.max(0.0001, num(map.get(APP_CONFIG_MAINTENANCE_MARGIN_RATE_KEY), DEFAULT_MAINTENANCE_MARGIN_RATE)),
  );
  const defaultProductRaw = String(map.get(APP_CONFIG_DEFAULT_PRODUCT_TYPE_KEY) || 'spot')
    .trim()
    .toLowerCase();
  const defaultMarginRaw = String(map.get(APP_CONFIG_DEFAULT_MARGIN_MODE_KEY) || 'cross')
    .trim()
    .toLowerCase();
  return {
    default_initial_cash_usd: await getDefaultInitialCash(sb),
    default_product_type: ['spot', 'perpetual', 'future'].includes(defaultProductRaw)
      ? defaultProductRaw
      : 'spot',
    default_margin_mode: defaultMarginRaw === 'isolated' ? 'isolated' : 'cross',
    default_leverage: defaultLeverage,
    max_leverage: maxLeverage,
    allow_short: parseBooleanConfig(map.get(APP_CONFIG_ALLOW_SHORT_KEY), true),
    maintenance_margin_rate: maintenanceMarginRate,
  };
}

async function getTradingSummaryFromDb(sb, teacherId) {
  const { data, error } = await sb.rpc('get_teacher_trading_summary', {
    p_teacher_id: teacherId,
  });
  if (error) throw new Error(error.message);
  if (!data || typeof data !== 'object') {
    throw new Error('trading summary rpc returned empty payload');
  }
  return data;
}

async function ensureTradingAccount(sb, teacherId) {
  const { data: existed, error: qErr } = await sb
    .from('teacher_trading_accounts')
    .select('*')
    .eq('teacher_id', teacherId)
    .maybeSingle();
  if (qErr) throw new Error(qErr.message);
  if (existed) return existed;

  const config = await getTradingConfig(sb);
  const initialCash = config.default_initial_cash_usd;
  const defaultProductType = config.default_product_type;
  const row = {
    teacher_id: teacherId,
    currency: 'USD',
    account_type: defaultProductType === 'spot' ? 'spot' : 'contract',
    margin_mode: defaultProductType === 'spot' ? 'cross' : config.default_margin_mode,
    leverage: defaultProductType === 'spot' ? 1 : config.default_leverage,
    initial_cash: initialCash,
    cash_balance: initialCash,
    cash_available: initialCash,
    cash_frozen: 0,
    market_value: 0,
    used_margin: 0,
    maintenance_margin: 0,
    margin_balance: initialCash,
    realized_pnl: 0,
    unrealized_pnl: 0,
    equity: initialCash,
    updated_at: nowIso(),
  };
  const { data: inserted, error: iErr } = await sb.from('teacher_trading_accounts').insert(row).select('*').single();
  if (iErr) throw new Error(iErr.message);
  return inserted;
}

async function getLatestPriceBySymbol(symbol, assetClassHint = null) {
  const polygonKey = process.env.POLYGON_API_KEY?.trim();
  const twelveKey = process.env.TWELVE_DATA_API_KEY?.trim();
  const assetClass = String(assetClassHint || detectAssetType(symbol)).trim().toLowerCase();
  const r = resolve(symbol);
  if (assetClass === 'stock' && polygonKey) {
    const snap = await quoteFetcher.fetchOneQuote(polygonKey, symbol, r.polygon);
    const p = num(snap?.close);
    if (p > 0) return p;
  }
  if (twelveKey) {
    const twelveSymbol = assetClass === 'stock' ? r.twelve : forTwelve(symbol);
    const map = await twelveData.getQuotes(twelveKey, [twelveSymbol]);
    const q = map?.[twelveSymbol];
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
    asset_class: payload.asset_class || null,
    product_type: payload.product_type || null,
    side: payload.side || null,
    position_side: payload.position_side || null,
    note: payload.note || null,
    created_at: nowIso(),
  };
  const { error } = await sb.from('teacher_account_ledger').insert(row);
  if (error) throw new Error(error.message);
}

async function getOpenPosition(sb, teacherId, symbol, options = {}) {
  const productType = normalizeProductType(options.productType || 'spot');
  const positionSide = normalizePositionSide(options.positionSide || 'long');
  let query = sb
    .from('teacher_positions')
    .select('*')
    .eq('teacher_id', teacherId)
    .eq('asset', symbol)
    .eq('is_history', false)
    .eq('product_type', productType)
    .eq('position_side', positionSide);
  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return data || null;
}

async function getReservedSellQty(sb, teacherId, symbol, options = {}) {
  const productType = normalizeProductType(options.productType || 'spot');
  const positionSide = normalizePositionSide(options.positionSide || 'long');
  const closingSide = isContractProduct(productType) && positionSide === 'short'
    ? 'buy'
    : 'sell';
  const { data, error } = await sb
    .from('teacher_orders')
    .select('remaining_quantity')
    .eq('teacher_id', teacherId)
    .eq('symbol', symbol)
    .eq('product_type', productType)
    .eq('position_side', positionSide)
    .eq('side', closingSide)
    .in('status', ['pending', 'partial']);
  if (error) throw new Error(error.message);
  return (data || []).reduce((acc, row) => acc + num(row.remaining_quantity), 0);
}

async function recomputeAccountSnapshot(sb, teacherId) {
  const account = await ensureTradingAccount(sb, teacherId);
  const tradingConfig = await getTradingConfig(sb);
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
    const sample = posList.find(
      (p) => String(p.asset || '').trim().toUpperCase() === s,
    );
    const price = await getLatestPriceBySymbol(
      s,
      sample?.asset_class || sample?.asset_type || null,
    );
    if (price != null) priceMap.set(s, price);
  }

  let marketValue = 0;
  let unrealized = 0;
  let usedMargin = 0;
  let maintenanceMargin = 0;
  let spotMarketValue = 0;
  let contractUnrealized = 0;
  let hasContractPosition = false;
  let dominantMarginMode = String(account.margin_mode || 'cross');
  let dominantLeverage = Math.max(1, num(account.leverage, 1));
  const positionUpdates = [];
  for (const p of posList) {
    const qty = num(p.buy_shares);
    if (qty <= 0) continue;
    const cost = num(p.cost_price, num(p.buy_price));
    const mark = priceMap.get(String(p.asset || '').toUpperCase());
    if (mark == null) continue;
    const contractSize = num(p.contract_size, 1);
    const multiplier = num(p.multiplier, 1);
    const productType = normalizeProductType(p.product_type, p.asset_class || p.asset_type);
    const positionSide = normalizePositionSide(p.position_side);
    const positionMarketValue = calcNotional({
      price: mark,
      quantity: qty,
      contractSize,
      multiplier,
    });
    const positionUnrealized = isContractProduct(productType)
      ? calcContractUnrealized(mark, cost, qty, positionSide, contractSize, multiplier)
      : (mark - cost) * qty * contractSize * multiplier;
    const leverage = Math.max(1, num(p.leverage, 1));
    const nextUsedMargin = isContractProduct(productType)
      ? calcInitialMargin(positionMarketValue, leverage)
      : 0;
    const nextMaintenanceMargin = isContractProduct(productType)
      ? calcMaintenanceMargin(positionMarketValue, tradingConfig.maintenance_margin_rate)
      : 0;
    const liquidationPrice = isContractProduct(productType)
      ? calcLiquidationPrice({
          entryPrice: cost,
          leverage,
          positionSide,
          maintenanceMarginRate: tradingConfig.maintenance_margin_rate,
        })
      : null;
    marketValue += positionMarketValue;
    unrealized += positionUnrealized;
    usedMargin += nextUsedMargin;
    maintenanceMargin += nextMaintenanceMargin;
    if (isContractProduct(productType)) {
      hasContractPosition = true;
      dominantMarginMode = normalizeMarginMode(p.margin_mode);
      dominantLeverage = Math.max(dominantLeverage, leverage);
      contractUnrealized += positionUnrealized;
    } else {
      spotMarketValue += positionMarketValue;
    }
    if (p.id) {
      positionUpdates.push({
        id: p.id,
        current_price: mark,
        mark_price: mark,
        floating_pnl: positionUnrealized,
        pnl_ratio: cost > 0
          ? ((positionSide === 'short' ? (cost - mark) : (mark - cost)) / cost) * 100
          : 0,
        used_margin: nextUsedMargin,
        maintenance_margin: nextMaintenanceMargin,
        liquidation_price: liquidationPrice,
      });
    }
  }

  for (const update of positionUpdates) {
    const { error: posErr } = await sb
      .from('teacher_positions')
      .update({
        current_price: update.current_price,
        mark_price: update.mark_price,
        floating_pnl: update.floating_pnl,
        pnl_ratio: update.pnl_ratio,
        used_margin: update.used_margin,
        maintenance_margin: update.maintenance_margin,
        liquidation_price: update.liquidation_price,
      })
      .eq('id', update.id);
    if (posErr) throw new Error(posErr.message);
  }

  const cashAvailable = num(account.cash_available);
  const cashFrozen = num(account.cash_frozen);
  const equity = cashAvailable + cashFrozen + usedMargin + spotMarketValue + contractUnrealized;
  const updated = {
    market_value: marketValue,
    used_margin: usedMargin,
    maintenance_margin: maintenanceMargin,
    margin_balance: equity,
    unrealized_pnl: unrealized,
    equity,
    account_type: hasContractPosition ? 'contract' : 'spot',
    margin_mode: hasContractPosition ? dominantMarginMode : 'cross',
    leverage: hasContractPosition ? dominantLeverage : 1,
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
  const assetClass = String(order.asset_class || order.asset_type || detectAssetType(symbol));
  const productType = normalizeProductType(order.product_type, assetClass);
  const positionSide = normalizePositionSide(order.position_side);
  const positionAction = normalizePositionAction(order.position_action);
  const marginMode = normalizeMarginMode(order.margin_mode);
  const leverage = num(order.leverage, 1);
  const contractSize = num(order.contract_size, 1);
  const multiplier = num(order.multiplier, 1);
  const settlementAsset = String(order.settlement_asset || 'USD');
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
  const tradingConfig = await getTradingConfig(sb);
  const frozen = num(order.frozen_cash);
  const fillNotional = calcNotional({
    price: fillPrice,
    quantity: qty,
    contractSize,
    multiplier,
  });
  const position = await getOpenPosition(sb, teacherId, symbol, {
    productType,
    positionSide,
  });
  const now = nowIso();
  let realizedPnlForFill = null;

  if (isContractProduct(productType)) {
    if (positionAction === 'open') {
      const requiredMargin = calcInitialMargin(fillNotional, leverage);
      const refund = Math.max(0, frozen - requiredMargin);
      const nextCashFrozen = Math.max(0, num(account.cash_frozen) - frozen);
      const nextCashAvailable = num(account.cash_available) + refund;
      const nextUsedMargin = num(account.used_margin) + requiredMargin;
      const nextMaintenance = num(account.maintenance_margin)
        + calcMaintenanceMargin(fillNotional, tradingConfig.maintenance_margin_rate);
      const { error: upAccErr } = await sb
        .from('teacher_trading_accounts')
        .update({
          cash_frozen: nextCashFrozen,
          cash_available: nextCashAvailable,
          used_margin: nextUsedMargin,
          maintenance_margin: nextMaintenance,
          updated_at: now,
        })
        .eq('teacher_id', teacherId);
      if (upAccErr) throw new Error(upAccErr.message);

      if (position) {
        const oldQty = num(position.buy_shares);
        const oldCost = num(position.cost_price, num(position.buy_price));
        const newQty = oldQty + qty;
        const newCost = newQty > 0
          ? ((oldQty * oldCost) + (qty * fillPrice)) / newQty
          : fillPrice;
        const newUsedMargin = num(position.used_margin) + requiredMargin;
        const newMaintenance = num(position.maintenance_margin)
          + calcMaintenanceMargin(fillNotional, tradingConfig.maintenance_margin_rate);
        const floatingPnl = calcContractUnrealized(
          fillPrice,
          newCost,
          newQty,
          positionSide,
          contractSize,
          multiplier,
        );
        const { error: upPosErr } = await sb
          .from('teacher_positions')
          .update({
            asset_class: assetClass,
            product_type: productType,
            position_side: positionSide,
            position_action: 'open',
            margin_mode: marginMode,
            leverage,
            contract_size: contractSize,
            multiplier,
            settlement_asset: settlementAsset,
            buy_shares: newQty,
            buy_price: fillPrice,
            cost_price: newCost,
            current_price: fillPrice,
            mark_price: fillPrice,
            floating_pnl: floatingPnl,
            pnl_ratio: newCost > 0
              ? ((positionSide === 'short' ? (newCost - fillPrice) : (fillPrice - newCost)) / newCost) * 100
              : 0,
            used_margin: newUsedMargin,
            maintenance_margin: newMaintenance,
            liquidation_price: calcLiquidationPrice({
              entryPrice: newCost,
              leverage,
              positionSide,
              maintenanceMarginRate: tradingConfig.maintenance_margin_rate,
            }),
          })
          .eq('id', position.id);
        if (upPosErr) throw new Error(upPosErr.message);
      } else {
        const { error: insPosErr } = await sb.from('teacher_positions').insert({
          teacher_id: teacherId,
          asset: symbol,
          asset_class: assetClass,
          product_type: productType,
          position_side: positionSide,
          position_action: 'open',
          margin_mode: marginMode,
          leverage,
          contract_size: contractSize,
          multiplier,
          settlement_asset: settlementAsset,
          buy_time: now,
          buy_shares: qty,
          buy_price: fillPrice,
          cost_price: fillPrice,
          current_price: fillPrice,
          mark_price: fillPrice,
          floating_pnl: 0,
          pnl_ratio: 0,
          used_margin: requiredMargin,
          maintenance_margin: calcMaintenanceMargin(
            fillNotional,
            tradingConfig.maintenance_margin_rate,
          ),
          liquidation_price: calcLiquidationPrice({
            entryPrice: fillPrice,
            leverage,
            positionSide,
            maintenanceMarginRate: tradingConfig.maintenance_margin_rate,
          }),
          is_history: false,
        });
        if (insPosErr) throw new Error(insPosErr.message);
      }

      await createLedger(sb, {
        teacher_id: teacherId,
        entry_type: order.side === 'buy' ? 'order_filled_buy' : 'order_filled_sell',
        amount: 0,
        balance_after: num(account.cash_balance),
        order_id: order.id,
        symbol,
        asset_class: assetClass,
        product_type: productType,
        side: order.side,
        position_side: positionSide,
        note: `contract ${positionSide} open ${qty}@${fillPrice}`,
      });
    } else {
      if (!position) throw new Error('position not found for close');
      const oldQty = num(position.buy_shares);
      if (oldQty < qty) throw new Error('position insufficient for close');
      const cost = num(position.cost_price, num(position.buy_price));
      const realized = calcContractUnrealized(
        fillPrice,
        cost,
        qty,
        positionSide,
        contractSize,
        multiplier,
      );
      realizedPnlForFill = realized;
      const remain = oldQty - qty;
      const releaseRatio = oldQty > 0 ? (qty / oldQty) : 1;
      const releasedMargin = num(position.used_margin) * releaseRatio;
      const releasedMaintenance = num(position.maintenance_margin) * releaseRatio;
      const nextCashBalance = num(account.cash_balance) + realized;
      const nextCashAvailable = num(account.cash_available) + releasedMargin + realized;
      const nextRealizedPnl = num(account.realized_pnl) + realized;
      const nextUsedMargin = Math.max(0, num(account.used_margin) - releasedMargin);
      const nextMaintenance = Math.max(0, num(account.maintenance_margin) - releasedMaintenance);

      const { error: upAccErr } = await sb
        .from('teacher_trading_accounts')
        .update({
          cash_balance: nextCashBalance,
          cash_available: nextCashAvailable,
          realized_pnl: nextRealizedPnl,
          used_margin: nextUsedMargin,
          maintenance_margin: nextMaintenance,
          updated_at: now,
        })
        .eq('teacher_id', teacherId);
      if (upAccErr) throw new Error(upAccErr.message);

      if (remain > 0) {
        const remainUsedMargin = Math.max(0, num(position.used_margin) - releasedMargin);
        const remainMaintenance = Math.max(0, num(position.maintenance_margin) - releasedMaintenance);
        const { error: upPosErr } = await sb
          .from('teacher_positions')
          .update({
            asset_class: assetClass,
            product_type: productType,
            position_side: positionSide,
            position_action: 'open',
            margin_mode: marginMode,
            leverage,
            contract_size: contractSize,
            multiplier,
            settlement_asset: settlementAsset,
            buy_shares: remain,
            current_price: fillPrice,
            mark_price: fillPrice,
            floating_pnl: calcContractUnrealized(
              fillPrice,
              cost,
              remain,
              positionSide,
              contractSize,
              multiplier,
            ),
            pnl_ratio: cost > 0
              ? ((positionSide === 'short' ? (cost - fillPrice) : (fillPrice - cost)) / cost) * 100
              : 0,
            used_margin: remainUsedMargin,
            maintenance_margin: remainMaintenance,
            liquidation_price: calcLiquidationPrice({
              entryPrice: cost,
              leverage,
              positionSide,
              maintenanceMarginRate: tradingConfig.maintenance_margin_rate,
            }),
          })
          .eq('id', position.id);
        if (upPosErr) throw new Error(upPosErr.message);
      } else {
        const { error: delPosErr } = await sb
          .from('teacher_positions')
          .delete()
          .eq('id', position.id);
        if (delPosErr) throw new Error(delPosErr.message);
      }

      const pnlRatio = cost > 0
        ? ((positionSide === 'short' ? (cost - fillPrice) : (fillPrice - cost)) / cost) * 100
        : 0;
      const { error: insHistoryErr } = await sb
        .from('teacher_positions')
        .insert({
          teacher_id: teacherId,
          asset: symbol,
          asset_class: assetClass,
          product_type: productType,
          position_side: positionSide,
          position_action: 'close',
          margin_mode: marginMode,
          leverage,
          contract_size: contractSize,
          multiplier,
          settlement_asset: settlementAsset,
          buy_time: position.buy_time || now,
          buy_shares: qty,
          buy_price: cost,
          cost_price: cost,
          current_price: fillPrice,
          mark_price: fillPrice,
          sell_time: now,
          sell_price: fillPrice,
          pnl_amount: realized,
          pnl_ratio: pnlRatio,
          used_margin: releasedMargin,
          maintenance_margin: releasedMaintenance,
          liquidation_price: calcLiquidationPrice({
            entryPrice: cost,
            leverage,
            positionSide,
            maintenanceMarginRate: tradingConfig.maintenance_margin_rate,
          }),
          is_history: true,
        });
      if (insHistoryErr) throw new Error(insHistoryErr.message);

      await createLedger(sb, {
        teacher_id: teacherId,
        entry_type: order.side === 'buy' ? 'order_filled_buy' : 'order_filled_sell',
        amount: realized,
        balance_after: nextCashBalance,
        order_id: order.id,
        symbol,
        asset_class: assetClass,
        product_type: productType,
        side: order.side,
        position_side: positionSide,
        note: `contract ${positionSide} close ${qty}@${fillPrice}`,
      });
    }
  } else if (order.side === 'buy') {
    const cost = fillNotional;
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
        updated_at: now,
      })
      .eq('teacher_id', teacherId);
    if (upAccErr) throw new Error(upAccErr.message);

    if (position) {
      const oldQty = num(position.buy_shares);
      const oldCost = num(position.cost_price, num(position.buy_price));
      const newQty = oldQty + qty;
      const newCost = newQty > 0 ? ((oldQty * oldCost) + (qty * fillPrice)) / newQty : fillPrice;
      const floatingPnl = (fillPrice - newCost) * newQty * contractSize * multiplier;
      const { error: upPosErr } = await sb
        .from('teacher_positions')
        .update({
          asset_class: assetClass,
          product_type: productType,
          position_side: positionSide,
          position_action: positionAction,
          margin_mode: marginMode,
          leverage,
          contract_size: contractSize,
          multiplier,
          settlement_asset: settlementAsset,
          buy_shares: newQty,
          buy_price: fillPrice,
          cost_price: newCost,
          current_price: fillPrice,
          mark_price: fillPrice,
          floating_pnl: floatingPnl,
          pnl_ratio: newCost > 0 ? ((fillPrice - newCost) / newCost * 100) : 0,
        })
        .eq('id', position.id);
      if (upPosErr) throw new Error(upPosErr.message);
    } else {
      const { error: insPosErr } = await sb.from('teacher_positions').insert({
        teacher_id: teacherId,
        asset: symbol,
        asset_class: assetClass,
        product_type: productType,
        position_side: positionSide,
        position_action: positionAction,
        margin_mode: marginMode,
        leverage,
        contract_size: contractSize,
        multiplier,
        settlement_asset: settlementAsset,
        buy_time: now,
        buy_shares: qty,
        buy_price: fillPrice,
        cost_price: fillPrice,
        current_price: fillPrice,
        mark_price: fillPrice,
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
      asset_class: assetClass,
      product_type: productType,
      side: 'buy',
      position_side: positionSide,
      note: `buy fill ${qty}@${fillPrice}`,
    });
  } else {
    if (!position) throw new Error('position not found for sell');
    const oldQty = num(position.buy_shares);
    if (oldQty < qty) throw new Error('position insufficient for sell');
    const cost = num(position.cost_price, num(position.buy_price));
    const proceeds = fillNotional;
    const realized = (fillPrice - cost) * qty * contractSize * multiplier;
    realizedPnlForFill = realized;
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
        updated_at: now,
      })
      .eq('teacher_id', teacherId);
    if (upAccErr) throw new Error(upAccErr.message);

    if (remain > 0) {
      const { error: upPosErr } = await sb
        .from('teacher_positions')
        .update({
          asset_class: assetClass,
          product_type: productType,
          position_side: positionSide,
          position_action: positionAction,
          margin_mode: marginMode,
          leverage,
          contract_size: contractSize,
          multiplier,
          settlement_asset: settlementAsset,
          buy_shares: remain,
          current_price: fillPrice,
          mark_price: fillPrice,
          floating_pnl: (fillPrice - cost) * remain * contractSize * multiplier,
          pnl_ratio: cost > 0 ? ((fillPrice - cost) / cost * 100) : 0,
        })
        .eq('id', position.id);
      if (upPosErr) throw new Error(upPosErr.message);
    } else {
      const { error: delPosErr } = await sb
        .from('teacher_positions')
        .delete()
        .eq('id', position.id);
      if (delPosErr) throw new Error(delPosErr.message);
    }

    const { error: insHistoryErr } = await sb
      .from('teacher_positions')
      .insert({
        teacher_id: teacherId,
        asset: symbol,
        asset_class: assetClass,
        product_type: productType,
        position_side: positionSide,
        position_action: 'close',
        margin_mode: marginMode,
        leverage,
        contract_size: contractSize,
        multiplier,
        settlement_asset: settlementAsset,
        buy_time: position.buy_time || now,
        buy_shares: qty,
        buy_price: cost,
        cost_price: cost,
        current_price: fillPrice,
        mark_price: fillPrice,
        sell_time: now,
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
        trade_time: now,
        note: 'generated by trading engine',
        created_at: now,
      });
    if (tradeRecordErr) {
      console.warn('[trading] trade_records insert skipped:', tradeRecordErr.message);
    }

    await createLedger(sb, {
      teacher_id: teacherId,
      entry_type: 'order_filled_sell',
      amount: proceeds,
      balance_after: cashBalance,
      order_id: order.id,
      symbol,
      asset_class: assetClass,
      product_type: productType,
      side: 'sell',
      position_side: positionSide,
      note: `sell fill ${qty}@${fillPrice}`,
    });
  }

  const fillRow = {
    order_id: order.id,
    teacher_id: teacherId,
    symbol,
    asset_class: assetClass,
    product_type: productType,
    side: order.side,
    position_side: positionSide,
    margin_mode: marginMode,
    leverage,
    fill_price: fillPrice,
    fill_quantity: qty,
    fill_notional: fillNotional,
    fill_time: now,
  };
  if (realizedPnlForFill != null) fillRow.realized_pnl = realizedPnlForFill;
  const { error: fillErr } = await sb.from('teacher_order_fills').insert(fillRow);
  if (fillErr) throw new Error(fillErr.message);

  const { error: upOrderErr } = await sb
    .from('teacher_orders')
    .update({
      status: 'filled',
      filled_quantity: num(order.filled_quantity) + qty,
      remaining_quantity: 0,
      avg_fill_price: fillPrice,
      updated_at: now,
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
    const px = await getLatestPriceBySymbol(
      symbol,
      o.asset_class || o.asset_type || null,
    );
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

async function liquidateContractPosition(sb, position, markPrice) {
  const teacherId = String(position.teacher_id || '').trim();
  const symbol = String(position.asset || position.symbol || '').trim().toUpperCase();
  if (!teacherId || !symbol) return;
  const qty = num(position.buy_shares);
  if (!(qty > 0)) return;
  const positionSide = normalizePositionSide(position.position_side);
  const leverage = Math.max(1, num(position.leverage, 1));
  const contractSize = Math.max(1, num(position.contract_size, 1));
  const multiplier = Math.max(1, num(position.multiplier, 1));
  const cost = num(position.cost_price, num(position.buy_price));
  const usedMargin = num(position.used_margin);
  const maintenanceMargin = num(position.maintenance_margin);
  const realized = calcContractUnrealized(
    markPrice,
    cost,
    qty,
    positionSide,
    contractSize,
    multiplier,
  );
  const now = nowIso();

  const { data: account, error: accErr } = await sb
    .from('teacher_trading_accounts')
    .select('*')
    .eq('teacher_id', teacherId)
    .single();
  if (accErr) throw new Error(accErr.message);

  const nextCashBalance = num(account.cash_balance) + realized;
  const nextCashAvailable = Math.max(0, num(account.cash_available) + usedMargin + realized);
  const nextUsedMargin = Math.max(0, num(account.used_margin) - usedMargin);
  const nextMaintenance = Math.max(0, num(account.maintenance_margin) - maintenanceMargin);
  const nextRealizedPnl = num(account.realized_pnl) + realized;

  const { error: upAccErr } = await sb
    .from('teacher_trading_accounts')
    .update({
      cash_balance: nextCashBalance,
      cash_available: nextCashAvailable,
      used_margin: nextUsedMargin,
      maintenance_margin: nextMaintenance,
      realized_pnl: nextRealizedPnl,
      updated_at: now,
    })
    .eq('teacher_id', teacherId);
  if (upAccErr) throw new Error(upAccErr.message);

  const pnlRatio = cost > 0
    ? ((positionSide === 'short' ? (cost - markPrice) : (markPrice - cost)) / cost) * 100
    : 0;
  const { error: insHistoryErr } = await sb
    .from('teacher_positions')
    .insert({
      teacher_id: teacherId,
      asset: symbol,
      asset_class: position.asset_class || position.asset_type || null,
      product_type: position.product_type || 'perpetual',
      position_side: positionSide,
      position_action: 'liquidated',
      margin_mode: position.margin_mode || 'cross',
      leverage,
      contract_size: contractSize,
      multiplier,
      settlement_asset: position.settlement_asset || 'USD',
      buy_time: position.buy_time || now,
      buy_shares: qty,
      buy_price: cost,
      cost_price: cost,
      current_price: markPrice,
      mark_price: markPrice,
      sell_time: now,
      sell_price: markPrice,
      pnl_amount: realized,
      pnl_ratio: pnlRatio,
      used_margin: usedMargin,
      maintenance_margin: maintenanceMargin,
      liquidation_price: num(position.liquidation_price),
      is_history: true,
    });
  if (insHistoryErr) throw new Error(insHistoryErr.message);

  const { error: delPosErr } = await sb
    .from('teacher_positions')
    .delete()
    .eq('id', position.id);
  if (delPosErr) throw new Error(delPosErr.message);

  await createLedger(sb, {
    teacher_id: teacherId,
    entry_type: 'position_liquidated',
    amount: realized,
    balance_after: nextCashBalance,
    symbol,
    asset_class: position.asset_class || position.asset_type || null,
    product_type: position.product_type || 'perpetual',
    side: positionSide === 'short' ? 'buy' : 'sell',
    position_side: positionSide,
    note: `liquidated ${qty}@${markPrice}`,
  });

  const { error: tradeRecordErr } = await sb
    .from('trade_records')
    .insert({
      teacher_id: teacherId,
      symbol,
      side: positionSide === 'short' ? 'buy' : 'sell',
      entry_price: cost,
      exit_price: markPrice,
      qty,
      pnl: realized,
      trade_time: now,
      note: 'generated by liquidation engine',
      created_at: now,
    });
  if (tradeRecordErr) {
    console.warn('[trading] liquidation trade_records insert skipped:', tradeRecordErr.message);
  }
}

async function tryLiquidateAllPositions(sb) {
  const tradingConfig = await getTradingConfig(sb);
  const { data: positions, error } = await sb
    .from('teacher_positions')
    .select('*')
    .eq('is_history', false)
    .in('product_type', ['perpetual', 'future'])
    .limit(500);
  if (error) throw new Error(error.message);
  for (const position of positions || []) {
    const symbol = String(position.asset || position.symbol || '').trim().toUpperCase();
    if (!symbol) continue;
    const markPrice = await getLatestPriceBySymbol(
      symbol,
      position.asset_class || position.asset_type || null,
    );
    if (!(markPrice > 0)) continue;
    const positionSide = normalizePositionSide(position.position_side);
    let liquidationPrice = num(position.liquidation_price);
    if (!(liquidationPrice > 0)) {
      liquidationPrice = calcLiquidationPrice({
        entryPrice: num(position.cost_price, num(position.buy_price)),
        leverage: Math.max(1, num(position.leverage, 1)),
        positionSide,
        maintenanceMarginRate: tradingConfig.maintenance_margin_rate,
      });
    }
    if (!shouldLiquidatePosition(positionSide, markPrice, liquidationPrice)) {
      continue;
    }
    await liquidateContractPosition(sb, position, markPrice);
  }
}

async function tryLiquidateTeacherPositions(sb, teacherId) {
  const tradingConfig = await getTradingConfig(sb);
  const { data: positions, error } = await sb
    .from('teacher_positions')
    .select('*')
    .eq('teacher_id', teacherId)
    .eq('is_history', false)
    .in('product_type', ['perpetual', 'future'])
    .limit(500);
  if (error) throw new Error(error.message);
  for (const position of positions || []) {
    const symbol = String(position.asset || position.symbol || '').trim().toUpperCase();
    if (!symbol) continue;
    const markPrice = await getLatestPriceBySymbol(
      symbol,
      position.asset_class || position.asset_type || null,
    );
    if (!(markPrice > 0)) continue;
    const positionSide = normalizePositionSide(position.position_side);
    let liquidationPrice = num(position.liquidation_price);
    if (!(liquidationPrice > 0)) {
      liquidationPrice = calcLiquidationPrice({
        entryPrice: num(position.cost_price, num(position.buy_price)),
        leverage: Math.max(1, num(position.leverage, 1)),
        positionSide,
        maintenanceMarginRate: tradingConfig.maintenance_margin_rate,
      });
    }
    if (!shouldLiquidatePosition(positionSide, markPrice, liquidationPrice)) {
      continue;
    }
    await liquidateContractPosition(sb, position, markPrice);
  }
}

let tradingMatchTimer = null;
let tradingMatchRunning = false;

async function tryMatchAllPendingOrders() {
  const sb = supabaseClient.getClient();
  if (!sb) return;
  const { data, error } = await sb
    .from('teacher_orders')
    .select('teacher_id')
    .in('status', ['pending', 'partial']);
  if (error) throw new Error(error.message);
  const teacherIds = [...new Set((data || [])
    .map((row) => String(row?.teacher_id || '').trim())
    .filter(Boolean))];
  for (const teacherId of teacherIds) {
    await tryMatchPendingOrders(sb, teacherId);
    await recomputeAccountSnapshot(sb, teacherId);
  }
  await tryLiquidateAllPositions(sb);
}

function startTradingMatchScheduler() {
  if (tradingMatchTimer) return;
  const intervalMs = Math.max(
    1000,
    parseInt(process.env.TRADING_MATCH_INTERVAL_MS || '3000', 10),
  );
  const tick = async () => {
    if (tradingMatchRunning) return;
    tradingMatchRunning = true;
    try {
      await tryMatchAllPendingOrders();
    } catch (e) {
      console.warn('[tradingMatchScheduler] tick failed:', String(e.message || e));
    } finally {
      tradingMatchRunning = false;
    }
  };
  tick().catch(() => {});
  tradingMatchTimer = setInterval(() => {
    tick().catch(() => {});
  }, intervalMs);
  console.log(`[tradingMatchScheduler] started intervalMs=${intervalMs}`);
}

function stopTradingMatchScheduler() {
  if (tradingMatchTimer) {
    clearInterval(tradingMatchTimer);
    tradingMatchTimer = null;
  }
}

function getPagination(query, defaults = {}) {
  const pageSize = Math.max(
    1,
    Math.min(
      parseInt(query.page_size, 10) || parseInt(query.limit, 10) || defaults.pageSize || 50,
      defaults.maxPageSize || 500,
    ),
  );
  const page = Math.max(1, parseInt(query.page, 10) || defaults.page || 1);
  const offset = Math.max(0, (page - 1) * pageSize);
  return { page, pageSize, offset };
}

function registerTradingRoutes(app, requireAuth) {
  app.get('/api/admin/trading/config', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    if (!(await ensureAdmin(req, res, sb))) return;
    try {
      return res.json(await getTradingConfig(sb));
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.patch('/api/admin/trading/config', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    if (!(await ensureAdmin(req, res, sb))) return;
    try {
      const defaultCash = num(req.body?.default_initial_cash_usd, 0);
      const defaultLeverage = Math.max(1, num(req.body?.default_leverage, 5));
      const maxLeverage = Math.max(defaultLeverage, num(req.body?.max_leverage, 50));
      const maintenanceMarginRate = Math.min(
        0.5,
        Math.max(0.0001, num(req.body?.maintenance_margin_rate, DEFAULT_MAINTENANCE_MARGIN_RATE)),
      );
      const defaultProductType = String(req.body?.default_product_type || 'spot').trim().toLowerCase();
      const defaultMarginMode = String(req.body?.default_margin_mode || 'cross').trim().toLowerCase();
      const allowShort = parseBooleanConfig(req.body?.allow_short, true);
      if (!(defaultCash > 0)) {
        return res.status(400).json({ error: 'default_initial_cash_usd 必须大于 0' });
      }
      if (!['spot', 'perpetual', 'future'].includes(defaultProductType)) {
        return res.status(400).json({ error: 'default_product_type 无效' });
      }
      if (!['cross', 'isolated'].includes(defaultMarginMode)) {
        return res.status(400).json({ error: 'default_margin_mode 无效' });
      }
      const rows = [
        { key: APP_CONFIG_DEFAULT_CASH_KEY, value: String(defaultCash), updated_at: nowIso() },
        { key: APP_CONFIG_DEFAULT_PRODUCT_TYPE_KEY, value: defaultProductType, updated_at: nowIso() },
        { key: APP_CONFIG_DEFAULT_MARGIN_MODE_KEY, value: defaultMarginMode, updated_at: nowIso() },
        { key: APP_CONFIG_DEFAULT_LEVERAGE_KEY, value: String(defaultLeverage), updated_at: nowIso() },
        { key: APP_CONFIG_MAX_LEVERAGE_KEY, value: String(maxLeverage), updated_at: nowIso() },
        { key: APP_CONFIG_ALLOW_SHORT_KEY, value: allowShort ? 'true' : 'false', updated_at: nowIso() },
        { key: APP_CONFIG_MAINTENANCE_MARGIN_RATE_KEY, value: String(maintenanceMarginRate), updated_at: nowIso() },
      ];
      const { error } = await sb.from('app_config').upsert(rows, { onConflict: 'key' });
      if (error) return res.status(502).json({ error: error.message });
      return res.json({ ok: true, ...(await getTradingConfig(sb)) });
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
      const config = await getTradingConfig(sb);
      const defaultProductType = config.default_product_type;
      const { error: accErr } = await sb
        .from('teacher_trading_accounts')
        .upsert({
          teacher_id: teacherId,
          currency: 'USD',
          account_type: defaultProductType === 'spot' ? 'spot' : 'contract',
          margin_mode: defaultProductType === 'spot' ? 'cross' : config.default_margin_mode,
          leverage: defaultProductType === 'spot' ? 1 : config.default_leverage,
          initial_cash: amount,
          cash_balance: amount,
          cash_available: amount,
          cash_frozen: 0,
          market_value: 0,
          used_margin: 0,
          maintenance_margin: 0,
          margin_balance: amount,
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
      await tryLiquidateTeacherPositions(sb, uid);
      const summary = await getTradingSummaryFromDb(sb, uid);
      return res.json(summary.account || {});
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
      await tryLiquidateTeacherPositions(sb, uid);
      return res.json(await getTradingSummaryFromDb(sb, uid));
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/trading/runtime-config', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      return res.json(await getTradingConfig(sb));
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/trading/positions', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    const { pageSize, offset } = getPagination(req.query, {
      pageSize: 50,
      maxPageSize: 200,
    });
    try {
      await ensureTradingAccount(sb, uid);
      await tryMatchPendingOrders(sb, uid);
      await tryLiquidateTeacherPositions(sb, uid);
      await recomputeAccountSnapshot(sb, uid);
      const { data, error } = await sb
        .from('teacher_positions')
        .select('*')
        .eq('teacher_id', uid)
        .eq('is_history', false)
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .range(offset, offset + pageSize - 1);
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
    const { pageSize, offset } = getPagination(req.query, {
      pageSize: 100,
      maxPageSize: 500,
    });
    try {
      const { data, error } = await sb
        .from('teacher_order_fills')
        .select('*')
        .eq('teacher_id', uid)
        .order('fill_time', { ascending: false })
        .order('id', { ascending: false })
        .range(offset, offset + pageSize - 1);
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
    const { pageSize, offset } = getPagination(req.query, {
      pageSize: 200,
      maxPageSize: 500,
    });
    try {
      await ensureTradingAccount(sb, uid);
      const { data, error } = await sb
        .from('teacher_account_ledger')
        .select('*')
        .eq('teacher_id', uid)
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .range(offset, offset + pageSize - 1);
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
    const { pageSize, offset } = getPagination(req.query, {
      pageSize: 100,
      maxPageSize: 500,
    });
    try {
      await ensureTradingAccount(sb, uid);
      await tryMatchPendingOrders(sb, uid);
      await tryLiquidateTeacherPositions(sb, uid);
      const { data, error } = await sb
        .from('teacher_orders')
        .select('*')
        .eq('teacher_id', uid)
        .in('status', ['pending', 'partial'])
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .range(offset, offset + pageSize - 1);
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
    const { pageSize, offset } = getPagination(req.query, {
      pageSize: 200,
      maxPageSize: 500,
    });
    try {
      await ensureTradingAccount(sb, uid);
      await tryMatchPendingOrders(sb, uid);
      await tryLiquidateTeacherPositions(sb, uid);
      const { data, error } = await sb
        .from('teacher_orders')
        .select('*')
        .eq('teacher_id', uid)
        .not('status', 'in', '(pending,partial)')
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .range(offset, offset + pageSize - 1);
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
      const tradingConfig = await getTradingConfig(sb);
      const assetClass = normalizeAssetClass(req.body?.asset_class, symbol);
      const requestedProductType = req.body?.product_type;
      const defaultProductType = assetClass === 'stock'
        ? 'spot'
        : tradingConfig.default_product_type;
      const productType = normalizeProductType(requestedProductType || defaultProductType, assetClass);
      const positionSide = normalizePositionSide(req.body?.position_side);
      const positionAction = normalizePositionAction(req.body?.position_action);
      const marginMode = normalizeMarginMode(
        req.body?.margin_mode || (productType === 'spot' ? 'cross' : tradingConfig.default_margin_mode),
      );
      const leverage = Math.max(
        1,
        num(req.body?.leverage, productType === 'spot' ? 1 : tradingConfig.default_leverage),
      );
      const contractSize = Math.max(1, num(req.body?.contract_size, 1));
      const multiplier = Math.max(1, num(req.body?.multiplier, 1));
      const settlementAsset = String(req.body?.settlement_asset || 'USD').trim().toUpperCase() || 'USD';
      const intentError = validatePositionIntent({
        side,
        productType,
        positionSide,
        positionAction,
      });
      if (intentError) {
        return res.status(400).json({ error: intentError });
      }
      if (positionSide === 'short' && !tradingConfig.allow_short) {
        return res.status(400).json({ error: '当前系统未开启做空交易' });
      }
      if (leverage > tradingConfig.max_leverage) {
        return res.status(400).json({ error: `杠杆不能超过 ${tradingConfig.max_leverage}x` });
      }
      if (!isContractProduct(productType)) {
        if (positionSide !== 'long') {
          return res.status(400).json({ error: '现货交易暂不支持 short 方向' });
        }
        if (positionAction !== 'open' && positionAction !== 'close') {
          return res.status(400).json({ error: '现货交易 position_action 无效' });
        }
        if (marginMode !== 'cross') {
          return res.status(400).json({ error: '现货交易暂不支持 isolated 模式' });
        }
        if (leverage !== 1) {
          return res.status(400).json({ error: '现货交易杠杆必须为 1' });
        }
      }
      const account = await ensureTradingAccount(sb, uid);
      await tryMatchPendingOrders(sb, uid);
      await tryLiquidateTeacherPositions(sb, uid);
      await recomputeAccountSnapshot(sb, uid);
      const markPrice = await getLatestPriceBySymbol(symbol, assetClass);
      const checkPrice = orderType === 'market' ? markPrice : limitPrice;
      if (!(checkPrice > 0)) {
        return res.status(400).json({ error: '行情不可用，无法下单' });
      }
      const now = nowIso();
      let frozenCash = 0;
      let reservedQty = 0;
      if (!isContractProduct(productType) && side === 'buy') {
        frozenCash = calcNotional({
          price: checkPrice,
          quantity,
          contractSize,
          multiplier,
        });
        if (num(account.cash_available) < frozenCash) {
          return res.status(400).json({ error: '可用资金不足' });
        }
      } else if (!isContractProduct(productType)) {
        const pos = await getOpenPosition(sb, uid, symbol, {
          productType,
          positionSide,
        });
        const totalQty = num(pos?.buy_shares);
        const reserved = await getReservedSellQty(sb, uid, symbol, {
          productType,
          positionSide,
        });
        const availableQty = totalQty - reserved;
        if (availableQty < quantity) {
          return res.status(400).json({ error: '可卖仓位不足' });
        }
        reservedQty = quantity;
      } else {
        if (positionAction === 'open') {
          const notional = calcContractNotional(
            checkPrice,
            quantity,
            contractSize,
            multiplier,
          );
          frozenCash = calcInitialMargin(notional, leverage);
          if (num(account.cash_available) < frozenCash) {
            return res.status(400).json({ error: '可用保证金不足' });
          }
        } else {
          const pos = await getOpenPosition(sb, uid, symbol, {
            productType,
            positionSide,
          });
          const totalQty = num(pos?.buy_shares);
          const reserved = await getReservedSellQty(sb, uid, symbol, {
            productType,
            positionSide,
          });
          const availableQty = totalQty - reserved;
          if (availableQty < quantity) {
            return res.status(400).json({ error: '可平仓位不足' });
          }
          reservedQty = quantity;
        }
      }

      const orderRow = {
        teacher_id: uid,
        symbol,
        asset_type: assetClass,
        asset_class: assetClass,
        product_type: productType,
        position_side: positionSide,
        position_action: positionAction,
        margin_mode: marginMode,
        leverage,
        contract_size: contractSize,
        multiplier,
        settlement_asset: settlementAsset,
        mark_price: markPrice,
        index_price: markPrice,
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

      if (frozenCash > 0) {
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
          asset_class: assetClass,
          product_type: productType,
          side,
          position_side: positionSide,
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
          asset_class: order.asset_class || order.asset_type || null,
          product_type: order.product_type || null,
          side: order.side,
          position_side: order.position_side || null,
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

module.exports = {
  registerTradingRoutes,
  startTradingMatchScheduler,
  stopTradingMatchScheduler,
};
