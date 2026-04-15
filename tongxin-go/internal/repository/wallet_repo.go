package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type WalletRepo struct {
	pool *pgxpool.Pool
}

func NewWalletRepo(pool *pgxpool.Pool) *WalletRepo {
	return &WalletRepo{pool: pool}
}

// EnsureWallet creates a wallet if it doesn't exist and returns it.
func (r *WalletRepo) EnsureWallet(ctx context.Context, userID string) (*model.Wallet, error) {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO wallets (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`, userID)
	if err != nil {
		return nil, fmt.Errorf("ensure wallet: %w", err)
	}
	return r.GetWallet(ctx, userID)
}

func (r *WalletRepo) GetWallet(ctx context.Context, userID string) (*model.Wallet, error) {
	var w model.Wallet
	err := r.pool.QueryRow(ctx,
		`SELECT user_id, balance, frozen, total_deposit, updated_at, created_at
		 FROM wallets WHERE user_id = $1`, userID).
		Scan(&w.UserID, &w.Balance, &w.Frozen, &w.TotalDeposit, &w.UpdatedAt, &w.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("get wallet: %w", err)
	}
	return &w, nil
}

// Deposit adds amount to balance atomically and records the transaction.
func (r *WalletRepo) Deposit(ctx context.Context, userID string, amount float64) (*model.Wallet, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("deposit begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Ensure wallet exists
	_, err = tx.Exec(ctx,
		`INSERT INTO wallets (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`, userID)
	if err != nil {
		return nil, fmt.Errorf("deposit ensure wallet: %w", err)
	}

	var w model.Wallet
	err = tx.QueryRow(ctx,
		`UPDATE wallets SET balance = balance + $2, total_deposit = total_deposit + $2, updated_at = NOW()
		 WHERE user_id = $1
		 RETURNING user_id, balance, frozen, total_deposit, updated_at, created_at`,
		userID, amount).
		Scan(&w.UserID, &w.Balance, &w.Frozen, &w.TotalDeposit, &w.UpdatedAt, &w.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("deposit update: %w", err)
	}

	// Record transaction
	_, err = tx.Exec(ctx,
		`INSERT INTO wallet_transactions (user_id, type, amount, balance_after, note)
		 VALUES ($1, 'deposit', $2, $3, 'Simulated deposit')`,
		userID, amount, w.Balance)
	if err != nil {
		return nil, fmt.Errorf("deposit record tx: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("deposit commit: %w", err)
	}
	return &w, nil
}

// FreezeMargin moves amount from balance to frozen. Fails if insufficient balance.
func (r *WalletRepo) FreezeMargin(ctx context.Context, userID string, amount float64) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE wallets SET balance = balance - $2, frozen = frozen + $2, updated_at = NOW()
		 WHERE user_id = $1 AND balance >= $2`,
		userID, amount)
	if err != nil {
		return fmt.Errorf("freeze margin: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("insufficient balance")
	}
	return nil
}

// UnfreezeMargin moves amount from frozen back to balance (cancelled order).
func (r *WalletRepo) UnfreezeMargin(ctx context.Context, userID string, amount float64) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE wallets SET balance = balance + $2, frozen = GREATEST(frozen - $2, 0), updated_at = NOW()
		 WHERE user_id = $1`,
		userID, amount)
	if err != nil {
		return fmt.Errorf("unfreeze margin: %w", err)
	}
	return nil
}

// ChargeFee deducts a fee from the user's balance and records a wallet transaction.
func (r *WalletRepo) ChargeFee(ctx context.Context, userID string, amount float64, refID, note string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("charge fee begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	var balanceAfter float64
	err = tx.QueryRow(ctx,
		`UPDATE wallets SET balance = balance - $2, updated_at = NOW()
		 WHERE user_id = $1 AND balance >= $2
		 RETURNING balance`,
		userID, amount).Scan(&balanceAfter)
	if err != nil {
		return fmt.Errorf("insufficient balance for fee")
	}

	_, err = tx.Exec(ctx,
		`INSERT INTO wallet_transactions (user_id, type, amount, balance_after, ref_id, note)
		 VALUES ($1, 'fee', $2, $3, $4, $5)`,
		userID, -amount, balanceAfter, refID, note)
	if err != nil {
		return fmt.Errorf("charge fee record tx: %w", err)
	}

	return tx.Commit(ctx)
}

// SettleTrade unfreezes margin and applies PnL when closing a position.
// closeFee is deducted from the settlement amount.
func (r *WalletRepo) SettleTrade(ctx context.Context, userID string, unfreezeAmount, pnl, closeFee float64) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("settle begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// balance += margin + pnl - closeFee; protect frozen from going negative
	var balanceAfter float64
	err = tx.QueryRow(ctx,
		`UPDATE wallets SET
		 balance = balance + $2 + $3 - $4,
		 frozen = GREATEST(frozen - $2, 0),
		 updated_at = NOW()
		 WHERE user_id = $1
		 RETURNING balance`,
		userID, unfreezeAmount, pnl, closeFee).Scan(&balanceAfter)
	if err != nil {
		return fmt.Errorf("settle update: %w", err)
	}

	_, err = tx.Exec(ctx,
		`INSERT INTO wallet_transactions (user_id, type, amount, balance_after, note)
		 VALUES ($1, 'trade_pnl', $2, $3, 'Position closed')`,
		userID, pnl, balanceAfter+closeFee)
	if err != nil {
		return fmt.Errorf("settle record pnl tx: %w", err)
	}

	if closeFee > 0 {
		_, err = tx.Exec(ctx,
			`INSERT INTO wallet_transactions (user_id, type, amount, balance_after, note)
			 VALUES ($1, 'fee', $2, $3, 'Close position fee')`,
			userID, -closeFee, balanceAfter)
		if err != nil {
			return fmt.Errorf("settle record fee tx: %w", err)
		}
	}

	return tx.Commit(ctx)
}

// AllocateToCopyBucket atomically transfers from main wallet to a copy_trading bucket.
// 单事务里：wallets.balance -= amount，copy_trading.allocated/available += amount，
// 写一条 wallet_transactions(type='copy_allocate')。
// 返回更新后的 wallet 给 service 层用。
func (r *WalletRepo) AllocateToCopyBucket(ctx context.Context, userID, copyTradingID string, amount float64) (*model.Wallet, error) {
	if amount <= 0 {
		return nil, fmt.Errorf("allocate amount must be positive")
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("allocate begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// 1. 扣钱包
	var w model.Wallet
	err = tx.QueryRow(ctx,
		`UPDATE wallets SET balance = balance - $2, updated_at = NOW()
		 WHERE user_id = $1 AND balance >= $2
		 RETURNING user_id, balance, frozen, total_deposit, updated_at, created_at`,
		userID, amount).
		Scan(&w.UserID, &w.Balance, &w.Frozen, &w.TotalDeposit, &w.UpdatedAt, &w.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("insufficient balance for copy allocate")
	}

	// 2. 加子账户（必须存在且 status='active'，且 follower_id 必须匹配，防越权）
	//    分润 HWM 同步（migration 027）：追加本金 → cumulative_net_deposit & high_water_mark 同步抬高，
	//    保证 HWM 永远 >= 真实净入金，新注入的资金不会被立刻当成"创新高"抽分润。
	tag, err := tx.Exec(ctx,
		`UPDATE copy_trading
		 SET allocated_capital      = allocated_capital + $3,
		     available_capital      = available_capital + $3,
		     cumulative_net_deposit = cumulative_net_deposit + $3,
		     high_water_mark        = high_water_mark + $3,
		     updated_at = NOW()
		 WHERE id = $1 AND follower_id = $2 AND status = 'active'`,
		copyTradingID, userID, amount)
	if err != nil {
		return nil, fmt.Errorf("allocate to bucket: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return nil, fmt.Errorf("copy_trading not active or not owned by user")
	}

	// 3. 写流水
	_, err = tx.Exec(ctx,
		`INSERT INTO wallet_transactions (user_id, type, amount, balance_after, ref_id, note)
		 VALUES ($1, 'copy_allocate', $2, $3, $4, 'Allocate to copy trading bucket')`,
		userID, -amount, w.Balance, copyTradingID)
	if err != nil {
		return nil, fmt.Errorf("allocate record tx: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("allocate commit: %w", err)
	}
	return &w, nil
}

// WithdrawFromCopyBucket atomically transfers from a copy_trading bucket back to main wallet.
// 单事务里：copy_trading.available -= amount，allocated 同步缩减但不为负
// （用 GREATEST(0, ...) 兜底），wallets.balance += amount，写一条
// wallet_transactions(type='copy_withdraw')。
//
// 设计要点：amount 上限 = available_capital（含已实现盈亏），允许把盈利提走。
// allocated_capital 跟着减是为了维持「allocated = 累计净注入」的语义，
// 一旦盈利全部提走，allocated 会归零（≠ 负数），下次按比例算仓位的基数也归零，
// 用户想继续跟单需要重新追加本金 —— 这是符合预期的。
func (r *WalletRepo) WithdrawFromCopyBucket(ctx context.Context, userID, copyTradingID string, amount float64) (*model.Wallet, error) {
	if amount <= 0 {
		return nil, fmt.Errorf("withdraw amount must be positive")
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("withdraw begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// 1. 扣子账户（先扣再加，防止并发拿空）。
	//    守卫只检查 available — 允许提取盈利让 allocated < 实际投入，
	//    GREATEST 把 allocated 钳到 0（chk_capital_nonneg 约束要求非负）。
	//    分润 HWM 同步（migration 027）：赎回 → cumulative_net_deposit & high_water_mark
	//    同步降低（钳到 0），保证后续创新高判定不会因为 HWM 没动而失效。
	tag, err := tx.Exec(ctx,
		`UPDATE copy_trading
		 SET allocated_capital       = GREATEST(0, allocated_capital - $3),
		     available_capital       = available_capital - $3,
		     cumulative_net_deposit  = GREATEST(0, cumulative_net_deposit - $3),
		     high_water_mark         = GREATEST(0, high_water_mark - $3),
		     updated_at = NOW()
		 WHERE id = $1 AND follower_id = $2
		   AND available_capital >= $3`,
		copyTradingID, userID, amount)
	if err != nil {
		return nil, fmt.Errorf("withdraw from bucket: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return nil, fmt.Errorf("withdraw exceeds bucket available")
	}

	// 2. 加钱包
	var w model.Wallet
	err = tx.QueryRow(ctx,
		`UPDATE wallets SET balance = balance + $2, updated_at = NOW()
		 WHERE user_id = $1
		 RETURNING user_id, balance, frozen, total_deposit, updated_at, created_at`,
		userID, amount).
		Scan(&w.UserID, &w.Balance, &w.Frozen, &w.TotalDeposit, &w.UpdatedAt, &w.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("withdraw update wallet: %w", err)
	}

	// 3. 写流水
	_, err = tx.Exec(ctx,
		`INSERT INTO wallet_transactions (user_id, type, amount, balance_after, ref_id, note)
		 VALUES ($1, 'copy_withdraw', $2, $3, $4, 'Withdraw from copy trading bucket')`,
		userID, amount, w.Balance, copyTradingID)
	if err != nil {
		return nil, fmt.Errorf("withdraw record tx: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("withdraw commit: %w", err)
	}
	return &w, nil
}

// GetTransactions returns paginated transaction history.
func (r *WalletRepo) GetTransactions(ctx context.Context, userID string, limit, offset int) ([]model.WalletTransaction, error) {
	if limit <= 0 {
		limit = 50
	}
	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, type, amount, balance_after, COALESCE(ref_id,''), COALESCE(note,''), created_at
		 FROM wallet_transactions WHERE user_id = $1
		 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
		userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("get transactions: %w", err)
	}
	defer rows.Close()

	var txs []model.WalletTransaction
	for rows.Next() {
		var t model.WalletTransaction
		if err := rows.Scan(&t.ID, &t.UserID, &t.Type, &t.Amount, &t.BalanceAfter,
			&t.RefID, &t.Note, &t.CreatedAt); err != nil {
			return nil, err
		}
		txs = append(txs, t)
	}
	return txs, nil
}
