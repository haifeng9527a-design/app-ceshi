-- Native trading system: wallets, orders, positions, wallet_transactions

-- Drop legacy Alpaca trading_accounts table
DROP TABLE IF EXISTS trading_accounts;

-- Wallets
CREATE TABLE IF NOT EXISTS wallets (
    user_id       TEXT PRIMARY KEY REFERENCES users(uid),
    balance       NUMERIC(20,8) NOT NULL DEFAULT 0,
    frozen        NUMERIC(20,8) NOT NULL DEFAULT 0,
    total_deposit NUMERIC(20,8) NOT NULL DEFAULT 0,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Orders
CREATE TABLE IF NOT EXISTS orders (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       TEXT NOT NULL REFERENCES users(uid),
    symbol        TEXT NOT NULL,
    side          TEXT NOT NULL CHECK (side IN ('long','short')),
    order_type    TEXT NOT NULL CHECK (order_type IN ('market','limit')),
    qty           NUMERIC(20,8) NOT NULL,
    price         NUMERIC(20,8),
    filled_price  NUMERIC(20,8),
    leverage      INT NOT NULL DEFAULT 1,
    margin_mode   TEXT NOT NULL DEFAULT 'cross' CHECK (margin_mode IN ('cross','isolated')),
    margin_amount NUMERIC(20,8) NOT NULL DEFAULT 0,
    status        TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','filled','cancelled','rejected')),
    reject_reason TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    filled_at     TIMESTAMPTZ,
    cancelled_at  TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_orders_user_status ON orders(user_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_pending ON orders(status, symbol) WHERE status = 'pending';

-- Positions
CREATE TABLE IF NOT EXISTS positions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       TEXT NOT NULL REFERENCES users(uid),
    symbol        TEXT NOT NULL,
    side          TEXT NOT NULL CHECK (side IN ('long','short')),
    qty           NUMERIC(20,8) NOT NULL,
    entry_price   NUMERIC(20,8) NOT NULL,
    leverage      INT NOT NULL DEFAULT 1,
    margin_mode   TEXT NOT NULL DEFAULT 'cross',
    margin_amount NUMERIC(20,8) NOT NULL DEFAULT 0,
    liq_price     NUMERIC(20,8),
    tp_price      NUMERIC(20,8),
    sl_price      NUMERIC(20,8),
    status        TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
    realized_pnl  NUMERIC(20,8) NOT NULL DEFAULT 0,
    closed_at     TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_positions_user_symbol_side_open
    ON positions(user_id, symbol, side) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_positions_user_open ON positions(user_id) WHERE status = 'open';

-- Wallet transactions (audit log)
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       TEXT NOT NULL REFERENCES users(uid),
    type          TEXT NOT NULL CHECK (type IN ('deposit','withdraw','order_freeze',
                  'order_unfreeze','trade_pnl','fee')),
    amount        NUMERIC(20,8) NOT NULL,
    balance_after NUMERIC(20,8) NOT NULL,
    ref_id        TEXT,
    note          TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON wallet_transactions(user_id, created_at DESC);
