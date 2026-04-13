CREATE TABLE IF NOT EXISTS fee_tiers (
    id SERIAL PRIMARY KEY,
    vip_level INT NOT NULL UNIQUE,
    maker_fee NUMERIC(10,6) NOT NULL,
    taker_fee NUMERIC(10,6) NOT NULL,
    min_volume NUMERIC(20,2) NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by TEXT
);

INSERT INTO fee_tiers (vip_level, maker_fee, taker_fee) VALUES
    (0, 0.000200, 0.000500),
    (1, 0.000160, 0.000400),
    (2, 0.000140, 0.000350),
    (3, 0.000120, 0.000300),
    (4, 0.000100, 0.000250),
    (5, 0.000080, 0.000200)
ON CONFLICT (vip_level) DO NOTHING;
