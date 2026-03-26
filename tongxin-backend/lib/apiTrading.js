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
const APP_CONFIG_FORCED_LIQ_RATIO_KEY = 'trading_forced_liquidation_ratio';
const DEFAULT_MAINTENANCE_MARGIN_RATE = Number.isFinite(Number(process.env.TRADING_MAINTENANCE_MARGIN_RATE))
  ? Number(process.env.TRADING_MAINTENANCE_MARGIN_RATE)
  : 0.005;
const DEFAULT_FORCED_LIQ_RATIO = Number.isFinite(Number(process.env.TRADING_FORCED_LIQ_RATIO))
  ? Number(process.env.TRADING_FORCED_LIQ_RATIO)
  : 0.95;

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

function normalizeTradingAccountType(v) {
  const s = String(v || '').trim().toLowerCase();
  return s === 'contract' ? 'contract' : 'spot';
}

function currencyForAccountType(accountType) {
  return normalizeTradingAccountType(accountType) === 'spot' ? 'USDT' : 'USD';
}

function isContractProduct(productType) {
  return productType === 'perpetual' || productType === 'future';
}

function accountTypeForProductType(productType) {
  return isContractProduct(productType) ? 'contract' : 'spot';
}

function splitInitialCash(totalCash) {
  const total = Math.max(0, num(totalCash, DEFAULT_INITIAL_CASH_USD));
  const contract = total / 2;
  const spot = total - contract;
  return { spot, contract };
}

function buildTradingAccountSeed({ teacherId, accountType, initialCash, config }) {
  const normalizedType = normalizeTradingAccountType(accountType);
  const isContract = normalizedType === 'contract';
  return {
    teacher_id: teacherId,
    currency: currencyForAccountType(normalizedType),
    account_type: normalizedType,
    margin_mode: isContract ? config.default_margin_mode : 'cross',
    leverage: isContract ? config.default_leverage : 1,
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
  if (req.isAdminByKey === true || req.isAdminSession === true) return true;
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
    APP_CONFIG_FORCED_LIQ_RATIO_KEY,
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
  const forcedLiqRatio = Math.min(
    5,
    Math.max(0.1, num(map.get(APP_CONFIG_FORCED_LIQ_RATIO_KEY), DEFAULT_FORCED_LIQ_RATIO)),
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
    forced_liquidation_ratio: forcedLiqRatio,
  };
}

function shouldLiquidateByRisk({
  account,
  position,
  markPrice,
  tradingConfig,
}) {
  const marginBalance = Math.max(0, num(account?.margin_balance, num(account?.equity)));
  if (!(marginBalance > 0)) return true;
  const maintenanceFromPosition = Math.max(0, num(position?.maintenance_margin));
  let maintenanceMargin = maintenanceFromPosition;
  if (!(maintenanceMargin > 0)) {
    const qty = Math.max(0, num(position?.buy_shares));
    const contractSize = Math.max(1, num(position?.contract_size, 1));
    const multiplier = Math.max(1, num(position?.multiplier, 1));
    const notional = calcNotional({
      price: markPrice,
      quantity: qty,
      contractSize,
      multiplier,
    });
    maintenanceMargin = calcMaintenanceMargin(notional, tradingConfig.maintenance_margin_rate);
  }
  if (!(maintenanceMargin > 0)) return false;
  const riskRatio = maintenanceMargin / marginBalance;
  return riskRatio >= Math.max(0.1, num(tradingConfig?.forced_liquidation_ratio, DEFAULT_FORCED_LIQ_RATIO));
}

async function getTradingAccounts(sb, teacherId) {
  const { data, error } = await sb
    .from('teacher_trading_accounts')
    .select('*')
    .eq('teacher_id', teacherId)
    .order('account_type', { ascending: true });
  if (error) throw new Error(error.message);
  return data || [];
}

async function ensureTradingAccounts(sb, teacherId) {
  const existed = await getTradingAccounts(sb, teacherId);
  const config = await getTradingConfig(sb);
  const byType = new Map(
    existed.map((row) => [normalizeTradingAccountType(row.account_type), row]),
  );
  const inserts = [];
  if (!byType.has('spot') && !byType.has('contract')) {
    const split = splitInitialCash(config.default_initial_cash_usd);
    inserts.push(buildTradingAccountSeed({
      teacherId,
      accountType: 'spot',
      initialCash: split.spot,
      config,
    }));
    inserts.push(buildTradingAccountSeed({
      teacherId,
      accountType: 'contract',
      initialCash: split.contract,
      config,
    }));
  } else {
    if (!byType.has('spot')) {
      inserts.push(buildTradingAccountSeed({
        teacherId,
        accountType: 'spot',
        initialCash: 0,
        config,
      }));
    }
    if (!byType.has('contract')) {
      inserts.push(buildTradingAccountSeed({
        teacherId,
        accountType: 'contract',
        initialCash: 0,
        config,
      }));
    }
  }
  if (inserts.length > 0) {
    const { error: insertErr } = await sb
      .from('teacher_trading_accounts')
      .insert(inserts);
    if (insertErr) throw new Error(insertErr.message);
  }
  const finalRows = await getTradingAccounts(sb, teacherId);
  const normalizedRows = [];
  for (const row of finalRows) {
    const accountType = normalizeTradingAccountType(row.account_type);
    const wantedCurrency = currencyForAccountType(accountType);
    const currentCurrency = String(row.currency || '').trim().toUpperCase();
    if (currentCurrency !== wantedCurrency) {
      const { error: currencyErr } = await sb
        .from('teacher_trading_accounts')
        .update({
          currency: wantedCurrency,
          updated_at: nowIso(),
        })
        .eq('teacher_id', teacherId)
        .eq('account_type', accountType);
      if (currencyErr) throw new Error(currencyErr.message);
      normalizedRows.push({
        ...row,
        currency: wantedCurrency,
      });
      continue;
    }
    normalizedRows.push(row);
  }
  return normalizedRows.sort((a, b) => {
    const aType = normalizeTradingAccountType(a.account_type);
    const bType = normalizeTradingAccountType(b.account_type);
    return aType.localeCompare(bType);
  });
}

async function ensureTradingAccount(sb, teacherId, accountType = 'spot') {
  const wanted = normalizeTradingAccountType(accountType);
  const accounts = await ensureTradingAccounts(sb, teacherId);
  const existed = accounts.find(
    (row) => normalizeTradingAccountType(row.account_type) === wanted,
  );
  if (existed) return existed;

  throw new Error(`missing trading account: ${wanted}`);
}

function resolveRowAccountType(row, fallbackProductType = null) {
  const direct = String(row?.account_type || '').trim().toLowerCase();
  if (direct === 'spot' || direct === 'contract') return direct;
  if (row?.product_type || fallbackProductType) {
    return accountTypeForProductType(
      normalizeProductType(row?.product_type || fallbackProductType),
    );
  }
  return 'spot';
}

function readRequestedAccountType(query) {
  const raw = String(query?.account_type || '').trim().toLowerCase();
  if (raw === 'spot' || raw === 'contract') return raw;
  return null;
}

function resolveAccountForRow(accounts, row, fallbackProductType = null) {
  const accountId = String(row?.account_id || '').trim();
  if (accountId) {
    const matched = accounts.find((item) => String(item.id || '') === accountId);
    if (matched) return matched;
  }
  const accountType = resolveRowAccountType(row, fallbackProductType);
  return accounts.find(
    (item) => normalizeTradingAccountType(item.account_type) === accountType,
  ) || null;
}

async function getTradingSummaryFromDb(sb, teacherId, accountType = null) {
  const wanted = accountType ? normalizeTradingAccountType(accountType) : null;
  let { data, error } = await sb.rpc('get_teacher_trading_summary', {
    p_teacher_id: teacherId,
    p_account_type: wanted,
  });
  if (error && /does not exist|function/i.test(String(error.message || ''))) {
    ({ data, error } = await sb.rpc('get_teacher_trading_summary', {
      p_teacher_id: teacherId,
    }));
  }
  if (error) throw new Error(error.message);
  if (!data || typeof data !== 'object') {
    throw new Error('trading summary rpc returned empty payload');
  }
  if (!wanted) return data;
  const payload = data;
  const account = payload.account && typeof payload.account === 'object' ? payload.account : null;
  const accountTypeInPayload = normalizeTradingAccountType(account?.account_type);
  if (account && accountTypeInPayload === wanted) return payload;
  const { data: rows, error: rowsErr } = await sb
    .from('teacher_trading_accounts')
    .select('*')
    .eq('teacher_id', teacherId)
    .eq('account_type', wanted)
    .limit(1);
  if (rowsErr) throw new Error(rowsErr.message);
  const selected = (rows && rows[0]) || null;
  const counts = await Promise.all([
    sb.from('teacher_orders').select('*', { count: 'exact', head: true })
      .eq('teacher_id', teacherId)
      .eq('account_type', wanted)
      .in('status', ['pending', 'partial']),
    sb.from('teacher_positions').select('*', { count: 'exact', head: true })
      .eq('teacher_id', teacherId)
      .eq('account_type', wanted)
      .eq('is_history', false),
  ]);
  if (counts[0].error) throw new Error(counts[0].error.message);
  if (counts[1].error) throw new Error(counts[1].error.message);
  return {
    ...payload,
    account: selected || account || {},
    selected_account_type: wanted,
    open_orders: counts[0].count || 0,
    positions: counts[1].count || 0,
  };
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
    account_id: payload.account_id || null,
    account_type: normalizeTradingAccountType(
      payload.account_type || accountTypeForProductType(payload.product_type),
    ),
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
  const accountType = normalizeTradingAccountType(
    options.accountType || accountTypeForProductType(productType),
  );
  let query = sb
    .from('teacher_positions')
    .select('*')
    .eq('teacher_id', teacherId)
    .eq('asset', symbol)
    .eq('is_history', false)
    .eq('account_type', accountType)
    .eq('product_type', productType)
    .eq('position_side', positionSide);
  if (options.accountId) {
    query = query.eq('account_id', options.accountId);
  }
  const { data, error } = await query.maybeSingle();
  if (error) throw new Error(error.message);
  return data || null;
}

async function getReservedSellQty(sb, teacherId, symbol, options = {}) {
  const productType = normalizeProductType(options.productType || 'spot');
  const positionSide = normalizePositionSide(options.positionSide || 'long');
  const accountType = normalizeTradingAccountType(
    options.accountType || accountTypeForProductType(productType),
  );
  const closingSide = isContractProduct(productType) && positionSide === 'short'
    ? 'buy'
    : 'sell';
  let query = sb
    .from('teacher_orders')
    .select('remaining_quantity')
    .eq('teacher_id', teacherId)
    .eq('account_type', accountType)
    .eq('symbol', symbol)
    .eq('product_type', productType)
    .eq('position_side', positionSide)
    .eq('side', closingSide)
    .in('status', ['pending', 'partial']);
  if (options.accountId) {
    query = query.eq('account_id', options.accountId);
  }
  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return (data || []).reduce((acc, row) => acc + num(row.remaining_quantity), 0);
}

async function recomputeAccountSnapshot(sb, teacherId) {
  const accounts = await ensureTradingAccounts(sb, teacherId);
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

  const statsByAccountId = new Map();
  for (const account of accounts) {
    statsByAccountId.set(String(account.id), {
      marketValue: 0,
      unrealized: 0,
      usedMargin: 0,
      maintenanceMargin: 0,
      spotMarketValue: 0,
      contractUnrealized: 0,
      hasContractPosition: false,
      dominantMarginMode: normalizeMarginMode(account.margin_mode),
      dominantLeverage: Math.max(1, num(account.leverage, 1)),
    });
  }
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
    const account = resolveAccountForRow(accounts, p, productType);
    if (!account) continue;
    const accountId = String(account.id);
    const accountStats = statsByAccountId.get(accountId);
    if (!accountStats) continue;
    accountStats.marketValue += positionMarketValue;
    accountStats.unrealized += positionUnrealized;
    accountStats.usedMargin += nextUsedMargin;
    accountStats.maintenanceMargin += nextMaintenanceMargin;
    if (isContractProduct(productType)) {
      accountStats.hasContractPosition = true;
      accountStats.dominantMarginMode = normalizeMarginMode(p.margin_mode);
      accountStats.dominantLeverage = Math.max(accountStats.dominantLeverage, leverage);
      accountStats.contractUnrealized += positionUnrealized;
    } else {
      accountStats.spotMarketValue += positionMarketValue;
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

  const updatedAccounts = [];
  for (const account of accounts) {
    const accountId = String(account.id);
    const stats = statsByAccountId.get(accountId) || {
      marketValue: 0,
      unrealized: 0,
      usedMargin: 0,
      maintenanceMargin: 0,
      spotMarketValue: 0,
      contractUnrealized: 0,
      hasContractPosition: false,
      dominantMarginMode: normalizeMarginMode(account.margin_mode),
      dominantLeverage: Math.max(1, num(account.leverage, 1)),
    };
    const cashBalance = num(account.cash_balance);
    const cashFrozen = num(account.cash_frozen);
    const cashAvailable = Math.max(0, cashBalance - cashFrozen - stats.usedMargin);
    const equity = cashAvailable + cashFrozen + stats.usedMargin + stats.spotMarketValue + stats.contractUnrealized;
    const updated = {
      cash_available: cashAvailable,
      market_value: stats.marketValue,
      used_margin: stats.usedMargin,
      maintenance_margin: stats.maintenanceMargin,
      margin_balance: equity,
      unrealized_pnl: stats.unrealized,
      equity,
      margin_mode: normalizeTradingAccountType(account.account_type) === 'contract'
        ? stats.dominantMarginMode
        : 'cross',
      leverage: normalizeTradingAccountType(account.account_type) === 'contract'
        ? stats.dominantLeverage
        : 1,
      updated_at: nowIso(),
    };
    const { data: updatedRows, error: uErr } = await sb
      .from('teacher_trading_accounts')
      .update(updated)
      .eq('id', accountId)
      .select('*');
    if (uErr) throw new Error(uErr.message);
    if (!Array.isArray(updatedRows) || updatedRows.length === 0) {
      throw new Error(
        `recompute account snapshot affected no rows (teacher_id=${teacherId}, account_id=${accountId}, account_type=${normalizeTradingAccountType(account.account_type)})`,
      );
    }
    if (updatedRows.length > 1) {
      console.warn(
        '[trading] recomputeAccountSnapshot matched multiple accounts',
        {
          teacherId,
          accountId,
          accountType: normalizeTradingAccountType(account.account_type),
          affectedRows: updatedRows.length,
        },
      );
    }
    updatedAccounts.push(updatedRows[0]);
  }
  return {
    accounts: updatedAccounts,
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
  const accountType = normalizeTradingAccountType(
    order.account_type || accountTypeForProductType(productType),
  );
  const qty = num(order.remaining_quantity, num(order.quantity));
  if (qty <= 0) return;

  const fillPrice = num(order.fill_price_target, num(order.limit_price));
  if (fillPrice <= 0) throw new Error('fill price invalid');

  const account = await ensureTradingAccount(sb, teacherId, accountType);
  const accountId = String(account.id || '');
  const tradingConfig = await getTradingConfig(sb);
  const frozen = num(order.frozen_cash);
  const fillNotional = calcNotional({
    price: fillPrice,
    quantity: qty,
    contractSize,
    multiplier,
  });
  const position = await getOpenPosition(sb, teacherId, symbol, {
    accountId,
    accountType,
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
        .eq('id', accountId);
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
          account_id: accountId,
          account_type: accountType,
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
        account_id: accountId,
        account_type: accountType,
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
        .eq('id', accountId);
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
          account_id: accountId,
          account_type: accountType,
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
        account_id: accountId,
        account_type: accountType,
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
      .eq('id', accountId);
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
        account_id: accountId,
        account_type: accountType,
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
      account_id: accountId,
      account_type: accountType,
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
      .eq('id', accountId);
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
        account_id: accountId,
        account_type: accountType,
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
      account_id: accountId,
      account_type: accountType,
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
    account_id: accountId,
    account_type: accountType,
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
  const accountType = normalizeTradingAccountType(
    position.account_type || accountTypeForProductType(position.product_type),
  );
  const realized = calcContractUnrealized(
    markPrice,
    cost,
    qty,
    positionSide,
    contractSize,
    multiplier,
  );
  const now = nowIso();

  const account = await ensureTradingAccount(sb, teacherId, accountType);
  const accountId = String(account.id || '');

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
    .eq('id', accountId);
  if (upAccErr) throw new Error(upAccErr.message);

  const pnlRatio = cost > 0
    ? ((positionSide === 'short' ? (cost - markPrice) : (markPrice - cost)) / cost) * 100
    : 0;
  const { error: insHistoryErr } = await sb
    .from('teacher_positions')
    .insert({
      account_id: accountId,
      account_type: accountType,
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
    account_id: accountId,
    account_type: accountType,
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

async function forceCloseSpotPosition(sb, position, markPrice) {
  const teacherId = String(position.teacher_id || '').trim();
  const symbol = String(position.asset || position.symbol || '').trim().toUpperCase();
  if (!teacherId || !symbol) {
    throw new Error('invalid position payload');
  }
  const qty = num(position.buy_shares);
  if (!(qty > 0)) {
    throw new Error('position quantity invalid');
  }
  const accountType = normalizeTradingAccountType(
    position.account_type || accountTypeForProductType(position.product_type),
  );
  const account = await ensureTradingAccount(sb, teacherId, accountType);
  const accountId = String(account.id || '');
  const contractSize = Math.max(1, num(position.contract_size, 1));
  const multiplier = Math.max(1, num(position.multiplier, 1));
  const cost = num(position.cost_price, num(position.buy_price));
  const proceeds = calcNotional({
    price: markPrice,
    quantity: qty,
    contractSize,
    multiplier,
  });
  const realized = (markPrice - cost) * qty * contractSize * multiplier;
  const now = nowIso();

  const nextCashBalance = num(account.cash_balance) + proceeds;
  const nextCashAvailable = num(account.cash_available) + proceeds;
  const nextRealizedPnl = num(account.realized_pnl) + realized;

  const { error: upAccErr } = await sb
    .from('teacher_trading_accounts')
    .update({
      cash_balance: nextCashBalance,
      cash_available: nextCashAvailable,
      realized_pnl: nextRealizedPnl,
      updated_at: now,
    })
    .eq('id', accountId);
  if (upAccErr) throw new Error(upAccErr.message);

  const pnlRatio = cost > 0 ? ((markPrice - cost) / cost) * 100 : 0;
  const { error: insHistoryErr } = await sb
    .from('teacher_positions')
    .insert({
      account_id: accountId,
      account_type: accountType,
      teacher_id: teacherId,
      asset: symbol,
      asset_class: position.asset_class || position.asset_type || 'stock',
      product_type: position.product_type || 'spot',
      position_side: position.position_side || 'long',
      position_action: 'close',
      margin_mode: position.margin_mode || 'cross',
      leverage: Math.max(1, num(position.leverage, 1)),
      contract_size: contractSize,
      multiplier,
      settlement_asset: position.settlement_asset || 'USDT',
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
      is_history: true,
    });
  if (insHistoryErr) throw new Error(insHistoryErr.message);

  const { error: delPosErr } = await sb
    .from('teacher_positions')
    .delete()
    .eq('id', position.id);
  if (delPosErr) throw new Error(delPosErr.message);

  await createLedger(sb, {
    account_id: accountId,
    account_type: accountType,
    teacher_id: teacherId,
    entry_type: 'admin_force_close',
    amount: proceeds,
    balance_after: nextCashBalance,
    symbol,
    asset_class: position.asset_class || position.asset_type || 'stock',
    product_type: position.product_type || 'spot',
    side: 'sell',
    position_side: position.position_side || 'long',
    note: `admin force close spot ${qty}@${markPrice}`,
  });
}

async function tryLiquidateAllPositions(sb) {
  const tradingConfig = await getTradingConfig(sb);
  const accounts = await sb
    .from('teacher_trading_accounts')
    .select('*');
  if (accounts.error) throw new Error(accounts.error.message);
  const accountMap = new Map((accounts.data || []).map((row) => [String(row.id || ''), row]));
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
    const account = accountMap.get(String(position.account_id || '')) || null;
    const shouldByPrice = shouldLiquidatePosition(positionSide, markPrice, liquidationPrice);
    const shouldByRisk = shouldLiquidateByRisk({
      account,
      position,
      markPrice,
      tradingConfig,
    });
    if (!shouldByPrice && !shouldByRisk) {
      continue;
    }
    await liquidateContractPosition(sb, position, markPrice);
  }
}

async function tryLiquidateTeacherPositions(sb, teacherId) {
  const tradingConfig = await getTradingConfig(sb);
  const { data: accountRows, error: accountErr } = await sb
    .from('teacher_trading_accounts')
    .select('*')
    .eq('teacher_id', teacherId);
  if (accountErr) throw new Error(accountErr.message);
  const accountMap = new Map((accountRows || []).map((row) => [String(row.id || ''), row]));
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
    const account = accountMap.get(String(position.account_id || '')) || null;
    const shouldByPrice = shouldLiquidatePosition(positionSide, markPrice, liquidationPrice);
    const shouldByRisk = shouldLiquidateByRisk({
      account,
      position,
      markPrice,
      tradingConfig,
    });
    if (!shouldByPrice && !shouldByRisk) {
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
      const forcedLiqRatio = Math.min(
        5,
        Math.max(0.1, num(req.body?.forced_liquidation_ratio, DEFAULT_FORCED_LIQ_RATIO)),
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
        { key: APP_CONFIG_FORCED_LIQ_RATIO_KEY, value: String(forcedLiqRatio), updated_at: nowIso() },
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
      if (clearHistory) {
        await sb.from('teacher_orders').delete().eq('teacher_id', teacherId);
        await sb.from('teacher_order_fills').delete().eq('teacher_id', teacherId);
        await sb.from('teacher_positions').delete().eq('teacher_id', teacherId);
        await sb.from('teacher_account_ledger').delete().eq('teacher_id', teacherId);
      } else {
        await sb.from('teacher_orders').delete().eq('teacher_id', teacherId).in('status', ['pending', 'partial']);
        await sb.from('teacher_positions').delete().eq('teacher_id', teacherId).eq('is_history', false);
      }

      const split = splitInitialCash(amount);
      const rows = [
        buildTradingAccountSeed({
          teacherId,
          accountType: 'spot',
          initialCash: split.spot,
          config,
        }),
        buildTradingAccountSeed({
          teacherId,
          accountType: 'contract',
          initialCash: split.contract,
          config,
        }),
      ];
      const { error: accErr } = await sb
        .from('teacher_trading_accounts')
        .upsert(rows, { onConflict: 'teacher_id,account_type' });
      if (accErr) return res.status(502).json({ error: accErr.message });

      const accounts = await ensureTradingAccounts(sb, teacherId);
      for (const account of accounts) {
        await createLedger(sb, {
          teacher_id: teacherId,
          account_id: account.id,
          account_type: account.account_type,
          entry_type: 'account_reset',
          amount: num(account.initial_cash),
          balance_after: num(account.initial_cash),
          note: clearHistory
            ? `admin reset ${account.account_type} account (clear history)`
            : `admin reset ${account.account_type} account (keep history)`,
        });
      }
      return res.json({ ok: true, clear_history: clearHistory });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/admin/trading/users/:teacherId/overview', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    if (!(await ensureAdmin(req, res, sb))) return;
    const teacherId = String(req.params.teacherId || '').trim();
    if (!teacherId) return res.status(400).json({ error: 'missing teacherId' });
    try {
      await ensureTradingAccounts(sb, teacherId);
      const requestedAccountType = readRequestedAccountType(req.query);
      const summary = await getTradingSummaryFromDb(sb, teacherId, requestedAccountType);
      return res.json(summary);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/admin/trading/users/:teacherId/positions', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    if (!(await ensureAdmin(req, res, sb))) return;
    const teacherId = String(req.params.teacherId || '').trim();
    if (!teacherId) return res.status(400).json({ error: 'missing teacherId' });
    const { pageSize, offset } = getPagination(req.query, {
      pageSize: 50,
      maxPageSize: 500,
    });
    try {
      const requestedAccountType = readRequestedAccountType(req.query);
      const includeHistory = String(req.query?.include_history || 'false').trim().toLowerCase() === 'true';
      let query = sb
        .from('teacher_positions')
        .select('*')
        .eq('teacher_id', teacherId)
        .eq('is_history', includeHistory)
        .order('created_at', { ascending: false })
        .order('id', { ascending: false });
      if (requestedAccountType) query = query.eq('account_type', requestedAccountType);
      const { data, error } = await query.range(offset, offset + pageSize - 1);
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.post('/api/admin/trading/users/:teacherId/positions/:positionId/close', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    if (!(await ensureAdmin(req, res, sb))) return;
    const teacherId = String(req.params.teacherId || '').trim();
    const positionId = String(req.params.positionId || '').trim();
    if (!teacherId) return res.status(400).json({ error: 'missing teacherId' });
    if (!positionId) return res.status(400).json({ error: 'missing positionId' });
    try {
      const { data: position, error: posErr } = await sb
        .from('teacher_positions')
        .select('*')
        .eq('id', positionId)
        .eq('teacher_id', teacherId)
        .eq('is_history', false)
        .maybeSingle();
      if (posErr) return res.status(502).json({ error: posErr.message });
      if (!position) return res.status(404).json({ error: 'position not found' });
      const symbol = String(position.asset || position.symbol || '').trim().toUpperCase();
      const markPriceRaw = await getLatestPriceBySymbol(
        symbol,
        position.asset_class || position.asset_type || null,
      );
      const markPrice = num(markPriceRaw, num(position.current_price, num(position.cost_price)));
      if (!(markPrice > 0)) {
        return res.status(400).json({ error: '行情不可用，无法平仓' });
      }
      const productType = normalizeProductType(
        position.product_type,
        position.asset_class || position.asset_type || null,
      );
      if (isContractProduct(productType)) {
        await liquidateContractPosition(sb, position, markPrice);
      } else {
        await forceCloseSpotPosition(sb, position, markPrice);
      }
      await recomputeAccountSnapshot(sb, teacherId);
      return res.json({
        ok: true,
        teacher_id: teacherId,
        position_id: positionId,
        symbol,
        mark_price: markPrice,
      });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.get('/api/admin/trading/users/:teacherId/ledger', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    if (!(await ensureAdmin(req, res, sb))) return;
    const teacherId = String(req.params.teacherId || '').trim();
    if (!teacherId) return res.status(400).json({ error: 'missing teacherId' });
    const { pageSize, offset } = getPagination(req.query, {
      pageSize: 100,
      maxPageSize: 500,
    });
    try {
      const requestedAccountType = readRequestedAccountType(req.query);
      let query = sb
        .from('teacher_account_ledger')
        .select('*')
        .eq('teacher_id', teacherId)
        .order('created_at', { ascending: false })
        .order('id', { ascending: false });
      if (requestedAccountType) query = query.eq('account_type', requestedAccountType);
      const { data, error } = await query.range(offset, offset + pageSize - 1);
      if (error) return res.status(502).json({ error: error.message });
      return res.json(data || []);
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.post('/api/admin/trading/users/:teacherId/adjust-balance', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    if (!(await ensureAdmin(req, res, sb))) return;
    const teacherId = String(req.params.teacherId || '').trim();
    if (!teacherId) return res.status(400).json({ error: 'missing teacherId' });
    try {
      const accountType = normalizeTradingAccountType(req.body?.account_type || 'spot');
      const delta = num(req.body?.amount);
      const note = String(req.body?.note || '').trim();
      if (!(delta !== 0)) {
        return res.status(400).json({ error: 'amount 不能为 0' });
      }
      await ensureTradingAccounts(sb, teacherId);
      const account = await ensureTradingAccount(sb, teacherId, accountType);
      const currentAvailable = num(account.cash_available);
      const currentBalance = num(account.cash_balance);
      if (delta < 0 && currentAvailable < Math.abs(delta)) {
        return res.status(400).json({ error: '可用资金不足，无法下分' });
      }
      const nextBalance = currentBalance + delta;
      const nextAvailable = currentAvailable + delta;
      if (nextBalance < 0 || nextAvailable < 0) {
        return res.status(400).json({ error: '调整后资金不能为负数' });
      }
      const now = nowIso();
      const { data: updatedRows, error: upErr } = await sb
        .from('teacher_trading_accounts')
        .update({
          cash_balance: nextBalance,
          cash_available: nextAvailable,
          updated_at: now,
        })
        .eq('id', account.id)
        .select('*');
      if (upErr) return res.status(502).json({ error: upErr.message });
      const updated = Array.isArray(updatedRows) && updatedRows.length > 0 ? updatedRows[0] : null;
      await createLedger(sb, {
        teacher_id: teacherId,
        account_id: account.id,
        account_type: accountType,
        entry_type: delta > 0 ? 'admin_adjust_in' : 'admin_adjust_out',
        amount: delta,
        balance_after: nextBalance,
        note: note || (delta > 0 ? 'admin 上分' : 'admin 下分'),
      });
      await recomputeAccountSnapshot(sb, teacherId);
      return res.json({
        ok: true,
        teacher_id: teacherId,
        account_type: accountType,
        amount: delta,
        account: updated || account,
      });
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
      const requestedAccountType = readRequestedAccountType(req.query);
      await ensureTradingAccounts(sb, uid);
      const summary = await getTradingSummaryFromDb(sb, uid, requestedAccountType);
      if (req.query?.include_accounts === 'true') {
        return res.json(summary);
      }
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
      const requestedAccountType = readRequestedAccountType(req.query);
      await ensureTradingAccounts(sb, uid);
      return res.json(await getTradingSummaryFromDb(sb, uid, requestedAccountType));
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
      const requestedAccountType = readRequestedAccountType(req.query);
      await ensureTradingAccounts(sb, uid);
      let query = sb
        .from('teacher_positions')
        .select('*')
        .eq('teacher_id', uid)
        .eq('is_history', false)
        .order('created_at', { ascending: false })
        .order('id', { ascending: false });
      if (requestedAccountType) {
        query = query.eq('account_type', requestedAccountType);
      }
      const { data, error } = await query.range(offset, offset + pageSize - 1);
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
      const requestedAccountType = readRequestedAccountType(req.query);
      let query = sb
        .from('teacher_order_fills')
        .select('*')
        .eq('teacher_id', uid)
        .order('fill_time', { ascending: false })
        .order('id', { ascending: false });
      if (requestedAccountType) {
        query = query.eq('account_type', requestedAccountType);
      }
      const { data, error } = await query.range(offset, offset + pageSize - 1);
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
      const requestedAccountType = readRequestedAccountType(req.query);
      await ensureTradingAccounts(sb, uid);
      let query = sb
        .from('teacher_account_ledger')
        .select('*')
        .eq('teacher_id', uid)
        .order('created_at', { ascending: false })
        .order('id', { ascending: false });
      if (requestedAccountType) {
        query = query.eq('account_type', requestedAccountType);
      }
      const { data, error } = await query.range(offset, offset + pageSize - 1);
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
      const requestedAccountType = readRequestedAccountType(req.query);
      await ensureTradingAccounts(sb, uid);
      let query = sb
        .from('teacher_orders')
        .select('*')
        .eq('teacher_id', uid)
        .in('status', ['pending', 'partial'])
        .order('created_at', { ascending: false })
        .order('id', { ascending: false });
      if (requestedAccountType) {
        query = query.eq('account_type', requestedAccountType);
      }
      const { data, error } = await query.range(offset, offset + pageSize - 1);
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
      const requestedAccountType = readRequestedAccountType(req.query);
      await ensureTradingAccounts(sb, uid);
      let query = sb
        .from('teacher_orders')
        .select('*')
        .eq('teacher_id', uid)
        .not('status', 'in', '(pending,partial)')
        .order('created_at', { ascending: false })
        .order('id', { ascending: false });
      if (requestedAccountType) {
        query = query.eq('account_type', requestedAccountType);
      }
      const { data, error } = await query.range(offset, offset + pageSize - 1);
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
      const accountType = accountTypeForProductType(productType);
      await ensureTradingAccounts(sb, uid);
      const account = await ensureTradingAccount(sb, uid, accountType);
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
          accountId: account.id,
          accountType,
          productType,
          positionSide,
        });
        const totalQty = num(pos?.buy_shares);
        const reserved = await getReservedSellQty(sb, uid, symbol, {
          accountId: account.id,
          accountType,
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
            accountId: account.id,
            accountType,
            productType,
            positionSide,
          });
          const totalQty = num(pos?.buy_shares);
          const reserved = await getReservedSellQty(sb, uid, symbol, {
            accountId: account.id,
            accountType,
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
        account_id: account.id,
        account_type: accountType,
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
          .eq('id', account.id);
        if (upAccErr) return res.status(502).json({ error: upAccErr.message });
        await createLedger(sb, {
          account_id: account.id,
          account_type: accountType,
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
      const frozen = num(order.frozen_cash);
      if (frozen > 0) {
        const accountType = resolveRowAccountType(order);
        const acc = await ensureTradingAccount(sb, uid, accountType);
        const cashFrozen = Math.max(0, num(acc.cash_frozen) - frozen);
        const cashAvailable = num(acc.cash_available) + frozen;
        const { error: upAccErr } = await sb
          .from('teacher_trading_accounts')
          .update({
            cash_frozen: cashFrozen,
            cash_available: cashAvailable,
            updated_at: nowIso(),
          })
          .eq('id', acc.id);
        if (upAccErr) return res.status(502).json({ error: upAccErr.message });
        await createLedger(sb, {
          account_id: acc.id,
          account_type: accountType,
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
      return res.json({ ok: true });
    } catch (e) {
      return res.status(502).json({ error: String(e.message || e) });
    }
  });

  app.post('/api/trading/accounts/transfer', requireAuth, async (req, res) => {
    const sb = supabaseClient.getClient();
    const uid = req.firebaseUid;
    if (!uid) return res.status(401).json({ error: '未鉴权' });
    if (!sb) return res.status(503).json({ error: 'Supabase 未配置' });
    try {
      const fromType = normalizeTradingAccountType(req.body?.from_account_type);
      const toType = normalizeTradingAccountType(req.body?.to_account_type);
      const amount = num(req.body?.amount);
      if (fromType === toType) {
        return res.status(400).json({ error: '转出账户和转入账户不能相同' });
      }
      if (!(amount > 0)) {
        return res.status(400).json({ error: 'amount 必须大于 0' });
      }
      await ensureTradingAccounts(sb, uid);
      const fromAcc = await ensureTradingAccount(sb, uid, fromType);
      const toAcc = await ensureTradingAccount(sb, uid, toType);
      const fromAvailable = num(fromAcc.cash_available);
      if (fromAvailable < amount) {
        return res.status(400).json({ error: '转出账户可用资金不足' });
      }
      const now = nowIso();
      const fromNextAvailable = fromAvailable - amount;
      const fromNextBalance = num(fromAcc.cash_balance) - amount;
      const toNextAvailable = num(toAcc.cash_available) + amount;
      const toNextBalance = num(toAcc.cash_balance) + amount;
      const { error: fromErr } = await sb
        .from('teacher_trading_accounts')
        .update({
          cash_available: fromNextAvailable,
          cash_balance: fromNextBalance,
          updated_at: now,
        })
        .eq('id', fromAcc.id);
      if (fromErr) return res.status(502).json({ error: fromErr.message });
      const { error: toErr } = await sb
        .from('teacher_trading_accounts')
        .update({
          cash_available: toNextAvailable,
          cash_balance: toNextBalance,
          updated_at: now,
        })
        .eq('id', toAcc.id);
      if (toErr) return res.status(502).json({ error: toErr.message });

      await createLedger(sb, {
        account_id: fromAcc.id,
        account_type: fromType,
        teacher_id: uid,
        entry_type: 'account_transfer_out',
        amount: -amount,
        balance_after: fromNextBalance,
        note: `transfer to ${toType}`,
      });
      await createLedger(sb, {
        account_id: toAcc.id,
        account_type: toType,
        teacher_id: uid,
        entry_type: 'account_transfer_in',
        amount,
        balance_after: toNextBalance,
        note: `transfer from ${fromType}`,
      });

      return res.json({
        ok: true,
        from_account_type: fromType,
        to_account_type: toType,
        amount,
      });
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
