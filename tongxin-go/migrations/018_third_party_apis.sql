CREATE TABLE IF NOT EXISTS third_party_apis (
    id SERIAL PRIMARY KEY,
    service_name TEXT NOT NULL,
    display_name TEXT NOT NULL,
    category TEXT NOT NULL,
    base_url TEXT DEFAULT '',
    ws_url TEXT DEFAULT '',
    api_key TEXT NOT NULL DEFAULT '',
    api_secret TEXT NOT NULL DEFAULT '',
    extra_config JSONB DEFAULT '{}',
    is_active BOOLEAN NOT NULL DEFAULT true,
    description TEXT DEFAULT '',
    last_verified_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(service_name)
);

INSERT INTO third_party_apis (service_name, display_name, category, base_url, ws_url, description) VALUES
    ('polygon', 'Polygon.io', 'market_data', 'https://api.polygon.io', 'wss://delayed.polygon.io/stocks', '美股/外汇/指数实时行情与历史数据'),
    ('binance', 'Binance', 'market_data', 'https://fapi.binance.com', 'wss://fstream.binance.com', '加密货币期货实时行情（公开 API，无需 Key）'),
    ('livekit', 'LiveKit', 'communication', '', '', '实时音视频通话（WebRTC）'),
    ('alpaca', 'Alpaca', 'trading', 'https://paper-api.alpaca.markets', '', '模拟交易（Paper Trading）'),
    ('twelve_data', 'Twelve Data', 'market_data', 'https://api.twelvedata.com', '', '备用行情数据源（暂未启用）')
ON CONFLICT (service_name) DO NOTHING;

CREATE TABLE IF NOT EXISTS api_key_history (
    id SERIAL PRIMARY KEY,
    service_name TEXT NOT NULL,
    old_key_masked TEXT,
    new_key_masked TEXT,
    changed_by TEXT,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reason TEXT DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_api_key_history_service ON api_key_history(service_name);
