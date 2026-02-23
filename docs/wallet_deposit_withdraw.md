# 钱包充值 / 提现（方案 B 托管）

## 当前已实现

- **App 内转账**：用户之间 USDT 转账（扣 A 加 B，写流水），已可用。
- **收款展示**：每个用户有唯一 `deposit_memo`，App 展示充值地址 + 备注 + 二维码；充值地址来自 `.env` 的 `WALLET_DEPOSIT_ADDRESS`（平台 TRC20 地址）。

## 充值（链上 USDT → 用户余额）

1. 用户向 **平台 TRC20 地址** 转入 USDT，并在链上转账的 **memo/备注** 中填写自己的 **充值备注**（App 内「收款」页展示）。
2. 后端需要：
   - 监听该 TRC20 地址的入账（TronGrid / 自建节点 API 或 webhook）。
   - 根据 **memo** 查到对应用户（`user_wallets.deposit_memo`），校验金额、重复入账等。
   - 对该用户执行：`update user_wallets set balance_usdt = balance_usdt + 入账金额, updated_at = now() where user_id = 对应用户`。
   - 插入一条 `wallet_transactions`：`type = 'deposit'`, `amount`, `tx_hash` 等。

建议：使用 Supabase Edge Function 或独立服务定时拉取 / 接收 webhook，写库时用 **service_role** 或带 RLS 豁免的写入。

## 提现（用户余额 → 链上地址）

1. 用户在 App 内发起提现：填写链上地址、金额；后端校验余额、风控等。
2. 后端从 **平台热钱包** 向用户地址转出 USDT（TRC20），扣减该用户余额并写入流水：
   - `update user_wallets set balance_usdt = balance_usdt - 金额 where user_id = ?`
   - `insert into wallet_transactions (user_id, type, amount, external_address, tx_hash) values (..., 'withdraw', ...)`

热钱包私钥需安全存储（KMS / 环境变量 / 专用服务），且仅后端可访问。

## 环境变量

在 App 的 `.env` 中：

- `WALLET_DEPOSIT_ADDRESS`：平台 USDT 充值地址（TRC20），用于 App 展示「收款」页。未配置时 App 显示「充值地址未配置」。

后端如需单独配置（如热钱包地址、RPC、webhook 密钥），可在后端自己的环境中配置，不必写在 App 的 `.env` 里。
