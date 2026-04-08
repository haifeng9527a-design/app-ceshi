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
		`UPDATE wallets SET balance = balance + $2, frozen = frozen - $2, updated_at = NOW()
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
		 WHERE user_id = $1
		 RETURNING balance`,
		userID, amount).Scan(&balanceAfter)
	if err != nil {
		return fmt.Errorf("charge fee update: %w", err)
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

	// balance += margin + pnl - closeFee
	var balanceAfter float64
	err = tx.QueryRow(ctx,
		`UPDATE wallets SET balance = balance + $2 + $3 - $4, frozen = frozen - $2, updated_at = NOW()
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
