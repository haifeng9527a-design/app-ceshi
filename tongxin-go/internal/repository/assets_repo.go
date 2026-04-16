package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/integrations/udun"
	"tongxin-go/internal/model"
)

type AssetsRepo struct {
	pool *pgxpool.Pool
}

func NewAssetsRepo(pool *pgxpool.Pool) *AssetsRepo {
	return &AssetsRepo{pool: pool}
}

func (r *AssetsRepo) GetAssetIconsByCategory(ctx context.Context, category string, assetCodes []string) (map[string]model.AssetIcon, error) {
	category = strings.ToLower(strings.TrimSpace(category))
	if category == "" || len(assetCodes) == 0 {
		return map[string]model.AssetIcon{}, nil
	}

	normalized := make([]string, 0, len(assetCodes))
	for _, code := range assetCodes {
		code = strings.ToUpper(strings.TrimSpace(code))
		if code == "" || slices.Contains(normalized, code) {
			continue
		}
		normalized = append(normalized, code)
	}
	if len(normalized) == 0 {
		return map[string]model.AssetIcon{}, nil
	}

	rows, err := r.pool.Query(ctx, `
		SELECT
			id::text,
			category,
			asset_code,
			display_name,
			source,
			source_id,
			remote_url,
			local_path,
			content_type,
			content_hash,
			status,
			updated_at
		FROM asset_icons
		WHERE category = $1
		  AND asset_code = ANY($2)
		  AND status = 'active'
	`, category, normalized)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make(map[string]model.AssetIcon, len(normalized))
	for rows.Next() {
		var item model.AssetIcon
		if err := rows.Scan(
			&item.ID,
			&item.Category,
			&item.AssetCode,
			&item.DisplayName,
			&item.Source,
			&item.SourceID,
			&item.RemoteURL,
			&item.LocalPath,
			&item.ContentType,
			&item.ContentHash,
			&item.Status,
			&item.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out[strings.ToUpper(strings.TrimSpace(item.AssetCode))] = item
	}

	return out, rows.Err()
}

func (r *AssetsRepo) UpsertAssetIcon(ctx context.Context, item *model.AssetIcon) error {
	if item == nil {
		return fmt.Errorf("asset icon is required")
	}
	item.Category = strings.ToLower(strings.TrimSpace(item.Category))
	item.AssetCode = strings.ToUpper(strings.TrimSpace(item.AssetCode))
	if item.Category == "" || item.AssetCode == "" {
		return fmt.Errorf("asset icon category and asset code are required")
	}
	if item.Status == "" {
		item.Status = "active"
	}

	_, err := r.pool.Exec(ctx, `
		INSERT INTO asset_icons (
			category,
			asset_code,
			display_name,
			source,
			source_id,
			remote_url,
			local_path,
			content_type,
			content_hash,
			status,
			updated_at
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW()
		)
		ON CONFLICT (category, asset_code) DO UPDATE SET
			display_name = EXCLUDED.display_name,
			source = EXCLUDED.source,
			source_id = EXCLUDED.source_id,
			remote_url = EXCLUDED.remote_url,
			local_path = EXCLUDED.local_path,
			content_type = EXCLUDED.content_type,
			content_hash = EXCLUDED.content_hash,
			status = EXCLUDED.status,
			updated_at = NOW()
	`, item.Category, item.AssetCode, item.DisplayName, item.Source, item.SourceID, item.RemoteURL, item.LocalPath, item.ContentType, item.ContentHash, item.Status)
	return err
}

func (r *AssetsRepo) ListDistinctAssetIconTargets(ctx context.Context) ([]model.AssetIconTarget, error) {
	rows, err := r.pool.Query(ctx, `
		WITH supported_assets AS (
			SELECT DISTINCT
				CASE WHEN LOWER(COALESCE(category, 'crypto')) = 'stocks' THEN 'stock' ELSE 'crypto' END AS category,
				UPPER(base_asset) AS asset_code,
				COALESCE(NULLIF(display_name, ''), UPPER(base_asset)) AS display_name
			FROM spot_supported_symbols
			WHERE is_active = true
		),
		balance_assets AS (
			SELECT DISTINCT
				CASE
					WHEN LOWER(COALESCE(ss.category, 'crypto')) = 'stocks' THEN 'stock'
					ELSE 'crypto'
				END AS category,
				UPPER(ab.asset_code) AS asset_code,
				COALESCE(NULLIF(ss.display_name, ''), UPPER(ab.asset_code)) AS display_name
			FROM asset_balances ab
			LEFT JOIN spot_supported_symbols ss
			  ON UPPER(ss.base_asset) = UPPER(ab.asset_code)
			WHERE COALESCE(ab.available, 0) > 0
			   OR COALESCE(ab.frozen, 0) > 0
		)
		SELECT DISTINCT category, asset_code, display_name
		FROM (
			SELECT category, asset_code, display_name FROM supported_assets
			UNION ALL
			SELECT category, asset_code, display_name FROM balance_assets
		) merged
		ORDER BY category, asset_code
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]model.AssetIconTarget, 0)
	for rows.Next() {
		var item model.AssetIconTarget
		if err := rows.Scan(&item.Category, &item.AssetCode, &item.DisplayName); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func resolveSpotAccountTypeQueryRow(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, userID string) (string, error) {
	var accountType string
	err := q.QueryRow(ctx, `
		SELECT account_type
		FROM asset_accounts
		WHERE user_id = $1
		  AND account_type IN ('spot', 'main')
		ORDER BY CASE WHEN account_type = 'spot' THEN 0 ELSE 1 END
		LIMIT 1
	`, userID).Scan(&accountType)
	if err != nil {
		return "", err
	}
	return accountType, nil
}

func (r *AssetsRepo) EnsureBaseAccounts(ctx context.Context, userID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err = tx.Exec(ctx, `
		INSERT INTO asset_accounts (user_id, account_type, display_name)
		VALUES ($1, 'main', '现货账户')
		ON CONFLICT (user_id, account_type) DO UPDATE SET
			display_name = EXCLUDED.display_name,
			updated_at = NOW()
	`, userID); err != nil {
		return err
	}

	if _, err = tx.Exec(ctx, `
		INSERT INTO asset_accounts (user_id, account_type, display_name)
		VALUES ($1, 'futures', '合约账户')
		ON CONFLICT (user_id, account_type) DO UPDATE SET
			display_name = EXCLUDED.display_name,
			updated_at = NOW()
	`, userID); err != nil {
		return err
	}

	if _, err = tx.Exec(ctx, `
		INSERT INTO asset_balances (account_id, asset_code, available, frozen)
		SELECT aa.id, 'USDT', 0, 0
		FROM asset_accounts aa
		WHERE aa.user_id = $1 AND aa.account_type = 'main'
		ON CONFLICT (account_id, asset_code) DO NOTHING
	`, userID); err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *AssetsRepo) GetMainBalance(ctx context.Context, userID string) (float64, float64, error) {
	if err := r.EnsureBaseAccounts(ctx, userID); err != nil {
		return 0, 0, err
	}

	spotAccountType, err := resolveSpotAccountTypeQueryRow(ctx, r.pool, userID)
	if err != nil {
		return 0, 0, err
	}

	var available, frozen float64
	err = r.pool.QueryRow(ctx, `
		SELECT COALESCE(ab.available, 0), COALESCE(ab.frozen, 0)
		FROM asset_accounts aa
		LEFT JOIN asset_balances ab
		  ON ab.account_id = aa.id
		 AND ab.asset_code = 'USDT'
		WHERE aa.user_id = $1
		  AND aa.account_type = $2
	`, userID, spotAccountType).Scan(&available, &frozen)
	return available, frozen, err
}

func (r *AssetsRepo) ListSpotBalances(ctx context.Context, userID string) (map[string]struct {
	Available float64
	Frozen    float64
}, error) {
	if err := r.EnsureBaseAccounts(ctx, userID); err != nil {
		return nil, err
	}

	spotAccountType, err := resolveSpotAccountTypeQueryRow(ctx, r.pool, userID)
	if err != nil {
		return nil, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT ab.asset_code, COALESCE(ab.available, 0), COALESCE(ab.frozen, 0)
		FROM asset_accounts aa
		JOIN asset_balances ab ON ab.account_id = aa.id
		WHERE aa.user_id = $1
		  AND aa.account_type = $2
	`, userID, spotAccountType)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make(map[string]struct {
		Available float64
		Frozen    float64
	})
	for rows.Next() {
		var assetCode string
		var available, frozen float64
		if err := rows.Scan(&assetCode, &available, &frozen); err != nil {
			return nil, err
		}
		items[strings.ToUpper(strings.TrimSpace(assetCode))] = struct {
			Available float64
			Frozen    float64
		}{
			Available: available,
			Frozen:    frozen,
		}
	}

	return items, rows.Err()
}

func (r *AssetsRepo) ListSpotTradeFills(ctx context.Context, userID string) ([]model.SpotTradeFill, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT
			UPPER(o.base_asset) AS asset_code,
			COALESCE(NULLIF(ss.display_name, ''), UPPER(o.base_asset)) AS asset_name,
			CASE
				WHEN LOWER(COALESCE(ss.category, 'crypto')) = 'stocks' THEN 'stock'
				ELSE 'crypto'
			END AS category,
			o.symbol,
			LOWER(o.side) AS side,
			COALESCE(o.filled_qty, 0) AS base_qty,
			COALESCE(o.quote_qty, 0) AS quote_qty,
			UPPER(COALESCE(o.quote_asset, 'USDT')) AS quote_asset,
			COALESCE(o.fee, 0) AS fee,
			UPPER(COALESCE(NULLIF(o.fee_asset, ''), o.quote_asset, 'USDT')) AS fee_asset,
			COALESCE(o.filled_at, o.created_at) AS filled_at
		FROM spot_orders o
		LEFT JOIN spot_supported_symbols ss
		  ON ss.symbol = o.symbol
		WHERE o.user_id = $1
		  AND o.status = 'filled'
		ORDER BY COALESCE(o.filled_at, o.created_at) ASC, o.created_at ASC, o.id ASC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]model.SpotTradeFill, 0)
	for rows.Next() {
		var item model.SpotTradeFill
		if err := rows.Scan(
			&item.AssetCode,
			&item.AssetName,
			&item.Category,
			&item.Symbol,
			&item.Side,
			&item.BaseQty,
			&item.QuoteQty,
			&item.QuoteAsset,
			&item.Fee,
			&item.FeeAsset,
			&item.FilledAt,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
	}

	return items, rows.Err()
}

func (r *AssetsRepo) GetDepositAddresses(ctx context.Context, userID, assetCode, network string) ([]model.AssetDepositAddress, error) {
	if err := r.EnsureBaseAccounts(ctx, userID); err != nil {
		return nil, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT
			ada.id::text,
			CASE
				WHEN ada.account_type = 'main' THEN 'spot'
				ELSE ada.account_type
			END AS account_type,
			ada.asset_code,
			ada.network,
			ada.address,
			COALESCE(ada.memo, ''),
			ada.provider,
			ada.status,
			ada.created_at
		FROM asset_deposit_addresses ada
		WHERE ada.user_id = $1
		  AND ($2 = '' OR ada.asset_code = $2)
		  AND ($3 = '' OR ada.network = $3)
		ORDER BY
			CASE WHEN ada.status = 'active' THEN 0 ELSE 1 END,
			ada.created_at DESC
	`, userID, assetCode, network)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []model.AssetDepositAddress{}
	for rows.Next() {
		var item model.AssetDepositAddress
		if err := rows.Scan(
			&item.ID,
			&item.AccountType,
			&item.AssetCode,
			&item.Network,
			&item.Address,
			&item.Memo,
			&item.Provider,
			&item.Status,
			&item.CreatedAt,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
	}

	return items, rows.Err()
}

func (r *AssetsRepo) GetDepositRecords(ctx context.Context, userID, assetCode string, limit, offset int) ([]model.AssetDepositRecord, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT
			ad.id::text,
			CASE WHEN ad.account_type = 'main' THEN 'spot' ELSE ad.account_type END AS account_type,
			ad.asset_code,
			ad.network,
			ad.address,
			COALESCE(ad.memo, ''),
			ad.amount,
			ad.confirmations,
			ad.status,
			COALESCE(ad.tx_hash, ''),
			ad.credited_at,
			ad.created_at
		FROM asset_deposits ad
		WHERE ad.user_id = $1
		  AND ($2 = '' OR ad.asset_code = $2)
		ORDER BY ad.created_at DESC
		LIMIT $3 OFFSET $4
	`, userID, assetCode, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]model.AssetDepositRecord, 0)
	for rows.Next() {
		var item model.AssetDepositRecord
		if err := rows.Scan(
			&item.ID,
			&item.AccountType,
			&item.AssetCode,
			&item.Network,
			&item.Address,
			&item.Memo,
			&item.Amount,
			&item.Confirmations,
			&item.Status,
			&item.TxHash,
			&item.CreditedAt,
			&item.CreatedAt,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *AssetsRepo) GetActiveDepositAddress(ctx context.Context, userID, assetCode, network string) (*model.AssetDepositAddress, error) {
	items, err := r.GetDepositAddresses(ctx, userID, assetCode, network)
	if err != nil {
		return nil, err
	}
	for _, item := range items {
		if item.Status == "active" {
			copy := item
			return &copy, nil
		}
	}
	return nil, pgx.ErrNoRows
}

func (r *AssetsRepo) CreateDepositAddress(
	ctx context.Context,
	userID, assetCode, network, address, memo, provider, providerAddressID, providerWalletID, rawPayload string,
) (*model.AssetDepositAddress, error) {
	if err := r.EnsureBaseAccounts(ctx, userID); err != nil {
		return nil, err
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	spotAccountType, err := resolveSpotAccountTypeQueryRow(ctx, tx, userID)
	if err != nil {
		return nil, err
	}

	var item model.AssetDepositAddress
	err = tx.QueryRow(ctx, `
		INSERT INTO asset_deposit_addresses (
			user_id,
			account_id,
			account_type,
			asset_code,
			network,
			address,
			memo,
			provider,
			provider_address_id,
			provider_wallet_id,
			raw_payload,
			status
		)
		SELECT
			$1,
			aa.id,
			$2,
			$3,
			$4,
			$5,
			NULLIF($6, ''),
			$7,
			NULLIF($8, ''),
			NULLIF($9, ''),
			CASE WHEN $10 = '' THEN NULL ELSE $10::jsonb END,
			'active'
		FROM asset_accounts aa
		WHERE aa.user_id = $1
		  AND aa.account_type = $2
		RETURNING
			id::text,
			CASE WHEN account_type = 'main' THEN 'spot' ELSE account_type END,
			asset_code,
			network,
			address,
			COALESCE(memo, ''),
			provider,
			status,
			created_at
	`, userID, spotAccountType, assetCode, network, address, memo, provider, providerAddressID, providerWalletID, rawPayload).Scan(
		&item.ID,
		&item.AccountType,
		&item.AssetCode,
		&item.Network,
		&item.Address,
		&item.Memo,
		&item.Provider,
		&item.Status,
		&item.CreatedAt,
	)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return &item, nil
}

func (r *AssetsRepo) LogIntegrationEvent(ctx context.Context, provider, eventType, externalID, status string, payload any, errorMessage string) error {
	var payloadJSON []byte
	switch v := payload.(type) {
	case nil:
		payloadJSON = []byte(`{}`)
	case []byte:
		if len(v) == 0 {
			payloadJSON = []byte(`{}`)
		} else {
			payloadJSON = v
		}
	case string:
		if strings.TrimSpace(v) == "" {
			payloadJSON = []byte(`{}`)
		} else {
			payloadJSON = []byte(v)
		}
	default:
		encoded, err := json.Marshal(v)
		if err != nil {
			payloadJSON = []byte(`{}`)
		} else {
			payloadJSON = encoded
		}
	}

	_, err := r.pool.Exec(ctx, `
		INSERT INTO integration_event_logs (
			provider,
			event_type,
			external_id,
			status,
			payload,
			error_message
		) VALUES (
			$1,
			$2,
			NULLIF($3, ''),
			$4,
			$5::jsonb,
			NULLIF($6, '')
		)
	`, provider, eventType, externalID, status, string(payloadJSON), errorMessage)
	return err
}

func (r *AssetsRepo) lookupDepositAddressBinding(
	ctx context.Context,
	q interface {
		QueryRow(context.Context, string, ...any) pgx.Row
	},
	address, assetCode, network, memo string,
) (userID, accountID, accountType string, err error) {
	baseQuery := `
		SELECT
			user_id,
			account_id::text,
			account_type
		FROM asset_deposit_addresses
		WHERE provider = 'udun'
		  AND asset_code = $1
		  AND network = $2
		  AND address = $3
	`

	if memo != "" {
		err = q.QueryRow(ctx, baseQuery+`
		  AND COALESCE(memo, '') = $4
		ORDER BY CASE WHEN status = 'active' THEN 0 ELSE 1 END, created_at DESC
		LIMIT 1
		`, assetCode, network, address, memo).Scan(&userID, &accountID, &accountType)
		if err == nil {
			return userID, accountID, accountType, nil
		}
		if err != pgx.ErrNoRows {
			return "", "", "", err
		}
	}

	err = q.QueryRow(ctx, baseQuery+`
		ORDER BY CASE WHEN status = 'active' THEN 0 ELSE 1 END, created_at DESC
		LIMIT 1
	`, assetCode, network, address).Scan(&userID, &accountID, &accountType)
	return userID, accountID, accountType, err
}

func mapUdunDepositStatus(status string) string {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "3", "credited", "completed", "confirmed", "success", "succeeded", "done", "finish", "finished":
		return "credited"
	case "0", "1", "pending", "pending_confirm", "pending_confirmations", "confirming", "processing", "detected":
		return "pending_confirm"
	case "2", "4", "failed", "error", "rejected", "cancelled", "canceled":
		return "failed"
	default:
		return "detected"
	}
}

func (r *AssetsRepo) ProcessUdunDepositCallback(ctx context.Context, cb *udun.DepositCallback) (*model.AssetDepositCallbackResult, error) {
	if cb == nil {
		return nil, fmt.Errorf("deposit callback is required")
	}
	if cb.TxHash == "" {
		return nil, fmt.Errorf("deposit callback tx hash is required")
	}
	if cb.AssetCode == "" || cb.Network == "" || cb.Address == "" {
		return nil, fmt.Errorf("deposit callback missing address metadata")
	}
	if cb.Amount <= 0 {
		return nil, fmt.Errorf("deposit callback amount must be positive")
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	userID, accountID, accountType, err := r.lookupDepositAddressBinding(ctx, tx, cb.Address, cb.AssetCode, cb.Network, cb.Memo)
	if err != nil {
		if err == pgx.ErrNoRows {
			return &model.AssetDepositCallbackResult{
				AccountType:   "spot",
				AssetCode:     cb.AssetCode,
				Network:       cb.Network,
				Amount:        cb.Amount,
				TxHash:        cb.TxHash,
				Status:        "ignored",
				Credited:      false,
				Confirmations: cb.Confirmations,
			}, nil
		}
		return nil, err
	}

	rawPayload, _ := json.Marshal(cb.RawValues)
	providerTradeID := cb.ProviderTradeID
	if providerTradeID == "" {
		providerTradeID = cb.TxHash
	}

	desiredStatus := mapUdunDepositStatus(cb.Status)
	var depositID string
	var currentStatus string
	var creditedAt *time.Time

	err = tx.QueryRow(ctx, `
		SELECT id::text, status, credited_at
		FROM asset_deposits
		WHERE provider = 'udun'
		  AND tx_hash = $1
		  AND asset_code = $2
		  AND network = $3
		FOR UPDATE
	`, cb.TxHash, cb.AssetCode, cb.Network).Scan(&depositID, &currentStatus, &creditedAt)
	switch err {
	case nil:
		if _, err = tx.Exec(ctx, `
			UPDATE asset_deposits
			SET user_id = $2,
			    account_id = $3::uuid,
			    account_type = $4,
			    address = $5,
			    memo = NULLIF($6, ''),
			    amount = $7,
			    confirmations = GREATEST(confirmations, $8),
			    status = CASE
			        WHEN status = 'credited' THEN status
			        WHEN $9 = 'credited' THEN 'credited'
			        ELSE $9
			    END,
			    provider_trade_id = COALESCE(NULLIF($10, ''), provider_trade_id),
			    provider_tx_id = COALESCE(NULLIF($1, ''), provider_tx_id),
			    raw_payload = $11::jsonb,
			    updated_at = NOW()
			WHERE id = $12::uuid
		`, cb.TxHash, userID, accountID, accountType, cb.Address, cb.Memo, cb.Amount, cb.Confirmations, desiredStatus, providerTradeID, string(rawPayload), depositID); err != nil {
			return nil, err
		}
		if err = tx.QueryRow(ctx, `
			SELECT status, credited_at
			FROM asset_deposits
			WHERE id = $1::uuid
		`, depositID).Scan(&currentStatus, &creditedAt); err != nil {
			return nil, err
		}
	case pgx.ErrNoRows:
		if err = tx.QueryRow(ctx, `
			INSERT INTO asset_deposits (
				user_id,
				account_id,
				account_type,
				asset_code,
				network,
				address,
				memo,
				tx_hash,
				amount,
				confirmations,
				status,
				provider,
				provider_trade_id,
				provider_tx_id,
				raw_payload
			) VALUES (
				$1,
				$2::uuid,
				$3,
				$4,
				$5,
				$6,
				NULLIF($7, ''),
				$8,
				$9,
				$10,
				$11,
				'udun',
				NULLIF($12, ''),
				NULLIF($8, ''),
				$13::jsonb
			)
			RETURNING id::text, status, credited_at
		`, userID, accountID, accountType, cb.AssetCode, cb.Network, cb.Address, cb.Memo, cb.TxHash, cb.Amount, cb.Confirmations, desiredStatus, providerTradeID, string(rawPayload)).Scan(&depositID, &currentStatus, &creditedAt); err != nil {
			return nil, err
		}
	default:
		return nil, err
	}

	credited := false
	if currentStatus == "credited" && creditedAt == nil {
		if _, err = tx.Exec(ctx, `
			INSERT INTO asset_balances (account_id, asset_code, available, frozen)
			VALUES ($1::uuid, $2, 0, 0)
			ON CONFLICT (account_id, asset_code) DO NOTHING
		`, accountID, cb.AssetCode); err != nil {
			return nil, err
		}

		var availableAfter, frozenAfter float64
		if err = tx.QueryRow(ctx, `
			UPDATE asset_balances
			SET available = available + $2,
			    updated_at = NOW()
			WHERE account_id = $1::uuid
			  AND asset_code = $3
			RETURNING available, frozen
		`, accountID, cb.Amount, cb.AssetCode).Scan(&availableAfter, &frozenAfter); err != nil {
			return nil, err
		}

		if _, err = tx.Exec(ctx, `
			INSERT INTO asset_ledger_entries (
				user_id,
				account_id,
				asset_code,
				direction,
				entry_type,
				amount,
				available_after,
				frozen_after,
				ref_type,
				ref_id,
				note
			) VALUES (
				$1,
				$2::uuid,
				$3,
				'credit',
				'deposit',
				$4,
				$5,
				$6,
				'asset_deposit',
				$7,
				'Udun deposit credited to Spot Account'
			)
		`, userID, accountID, cb.AssetCode, cb.Amount, availableAfter, frozenAfter, depositID); err != nil {
			return nil, err
		}

		if _, err = tx.Exec(ctx, `
			UPDATE asset_deposits
			SET credited_at = NOW(),
			    status = 'credited',
			    updated_at = NOW()
			WHERE id = $1::uuid
		`, depositID); err != nil {
			return nil, err
		}
		credited = true
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	if accountType == "main" {
		accountType = "spot"
	}

	return &model.AssetDepositCallbackResult{
		DepositID:     depositID,
		AccountType:   accountType,
		AssetCode:     cb.AssetCode,
		Network:       cb.Network,
		Amount:        cb.Amount,
		TxHash:        cb.TxHash,
		Status:        currentStatus,
		Credited:      credited || creditedAt != nil,
		Confirmations: cb.Confirmations,
	}, nil
}

func (r *AssetsRepo) GetCopySummary(ctx context.Context, userID string) (*model.CopySummaryResponse, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT
			ct.trader_id,
			COALESCE(u.display_name, ''),
			COALESCE(u.avatar_url, ''),
			ct.status,
			COALESCE(ct.allocated_capital, 0),
			COALESCE(ct.available_capital, 0),
			COALESCE(ct.frozen_capital, 0),
			(
				SELECT COUNT(*)
				FROM positions p
				WHERE p.copy_trading_id = ct.id
				  AND p.status = 'open'
			) AS open_position_count,
			ct.updated_at
		FROM copy_trading ct
		JOIN users u ON u.uid = ct.trader_id
		WHERE ct.follower_id = $1
		  AND ct.status IN ('active', 'paused')
		ORDER BY ct.updated_at DESC, ct.created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	resp := &model.CopySummaryResponse{
		Items: []model.CopySummaryItem{},
	}

	for rows.Next() {
		var item model.CopySummaryItem
		if err := rows.Scan(
			&item.TraderUID,
			&item.TraderName,
			&item.TraderAvatar,
			&item.Status,
			&item.AllocatedCapital,
			&item.AvailableCapital,
			&item.FrozenCapital,
			&item.OpenPositionCount,
			&item.UpdatedAt,
		); err != nil {
			return nil, err
		}

		resp.TotalAllocated += item.AllocatedCapital
		resp.TotalAvailable += item.AvailableCapital
		resp.TotalFrozen += item.FrozenCapital
		resp.OpenPositionCount += item.OpenPositionCount
		if item.Status == "active" {
			resp.ActiveTraderCount++
		}
		resp.Items = append(resp.Items, item)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return resp, nil
}

func copyAccountPoolStatusClause(status string) string {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "", "current":
		return "ct.status IN ('active', 'paused')"
	case "active":
		return "ct.status = 'active'"
	case "paused":
		return "ct.status = 'paused'"
	case "stopped", "history":
		return "ct.status = 'stopped'"
	case "all":
		return "ct.status IN ('active', 'paused', 'stopped')"
	default:
		return "ct.status IN ('active', 'paused')"
	}
}

func (r *AssetsRepo) GetCopyAccountOverview(ctx context.Context, userID string) (*model.CopyAccountOverviewResponse, error) {
	resp := &model.CopyAccountOverviewResponse{}
	err := r.pool.QueryRow(ctx, `
		WITH pools AS (
			SELECT *
			FROM copy_trading
			WHERE follower_id = $1
			  AND status IN ('active', 'paused')
		),
		copy_closed_today AS (
			SELECT COALESCE(SUM(realized_pnl - open_fee - close_fee), 0) AS pnl
			FROM positions
			WHERE user_id = $1
			  AND is_copy_trade = true
			  AND status IN ('closed', 'liquidated')
			  AND closed_at >= date_trunc('day', NOW())
		),
		copy_share_today AS (
			SELECT COALESCE(SUM(share_amount), 0) AS share
			FROM copy_profit_share_records
			WHERE follower_user_id = $1
			  AND status = 'settled'
			  AND created_at >= date_trunc('day', NOW())
		),
		copy_closed_lifetime AS (
			SELECT COALESCE(SUM(realized_pnl - open_fee - close_fee), 0) AS pnl
			FROM positions
			WHERE user_id = $1
			  AND is_copy_trade = true
			  AND status IN ('closed', 'liquidated')
		),
		copy_share_lifetime AS (
			SELECT COALESCE(SUM(share_amount), 0) AS share
			FROM copy_profit_share_records
			WHERE follower_user_id = $1
			  AND status = 'settled'
		),
		open_positions AS (
			SELECT COUNT(*) AS total
			FROM positions
			WHERE user_id = $1
			  AND is_copy_trade = true
			  AND status = 'open'
		)
		SELECT
			COALESCE((SELECT SUM(available_capital + frozen_capital) FROM pools), 0) AS total_equity,
			COALESCE((SELECT SUM(allocated_capital) FROM pools), 0) AS total_allocated,
			COALESCE((SELECT SUM(available_capital) FROM pools), 0) AS total_available,
			COALESCE((SELECT SUM(frozen_capital) FROM pools), 0) AS total_frozen,
			COALESCE((SELECT COUNT(*) FROM pools WHERE status = 'active'), 0) AS active_pool_count,
			COALESCE((SELECT COUNT(*) FROM pools), 0) AS current_pool_count,
			COALESCE((SELECT total FROM open_positions), 0) AS open_position_count,
			COALESCE((SELECT pnl FROM copy_closed_today), 0) AS today_realized_pnl,
			COALESCE((SELECT share FROM copy_share_today), 0) AS today_profit_share,
			COALESCE((SELECT pnl FROM copy_closed_lifetime), 0) AS lifetime_realized_pnl,
			COALESCE((SELECT share FROM copy_share_lifetime), 0) AS lifetime_profit_share
	`, userID).Scan(
		&resp.TotalEquity,
		&resp.TotalAllocated,
		&resp.TotalAvailable,
		&resp.TotalFrozen,
		&resp.ActivePoolCount,
		&resp.CurrentPoolCount,
		&resp.OpenPositionCount,
		&resp.TodayRealizedPnl,
		&resp.TodayProfitShare,
		&resp.LifetimeRealizedPnl,
		&resp.LifetimeProfitShare,
	)
	if err != nil {
		return nil, err
	}
	resp.TodayNetPnl = resp.TodayRealizedPnl - resp.TodayProfitShare
	resp.LifetimeNetPnl = resp.LifetimeRealizedPnl - resp.LifetimeProfitShare
	return resp, nil
}

func (r *AssetsRepo) ListCopyAccountPools(ctx context.Context, userID, status string) (*model.CopyAccountPoolsResponse, error) {
	clause := copyAccountPoolStatusClause(status)
	rows, err := r.pool.Query(ctx, fmt.Sprintf(`
		WITH open_counts AS (
			SELECT copy_trading_id, COUNT(*) AS open_position_count
			FROM positions
			WHERE status = 'open'
			  AND is_copy_trade = true
			  AND user_id = $1
			  AND copy_trading_id IS NOT NULL
			GROUP BY copy_trading_id
		),
		realized AS (
			SELECT copy_trading_id, COALESCE(SUM(realized_pnl - open_fee - close_fee), 0) AS realized_pnl
			FROM positions
			WHERE status IN ('closed', 'liquidated')
			  AND is_copy_trade = true
			  AND user_id = $1
			  AND copy_trading_id IS NOT NULL
			GROUP BY copy_trading_id
		),
		profit_shared AS (
			SELECT copy_trading_id, COALESCE(SUM(share_amount), 0) AS profit_shared
			FROM copy_profit_share_records
			WHERE status = 'settled'
			  AND follower_user_id = $1
			GROUP BY copy_trading_id
		)
		SELECT
			ct.id::text,
			ct.trader_id,
			COALESCE(u.display_name, ''),
			COALESCE(u.avatar_url, ''),
			ct.status,
			COALESCE(ct.allocated_capital, 0),
			COALESCE(ct.available_capital, 0),
			COALESCE(ct.frozen_capital, 0),
			COALESCE(o.open_position_count, 0),
			COALESCE(r.realized_pnl, 0),
			COALESCE(ps.profit_shared, 0),
			COALESCE(ct.cumulative_net_deposit, 0),
			ct.updated_at
		FROM copy_trading ct
		JOIN users u ON u.uid = ct.trader_id
		LEFT JOIN open_counts o ON o.copy_trading_id = ct.id
		LEFT JOIN realized r ON r.copy_trading_id = ct.id
		LEFT JOIN profit_shared ps ON ps.copy_trading_id = ct.id
		WHERE ct.follower_id = $1
		  AND %s
		ORDER BY ct.updated_at DESC, ct.created_at DESC
	`, clause), userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	resp := &model.CopyAccountPoolsResponse{Items: []model.CopyAccountPoolItem{}}
	for rows.Next() {
		var item model.CopyAccountPoolItem
		var cumulativeNetDeposit float64
		if err := rows.Scan(
			&item.CopyTradingID,
			&item.TraderUID,
			&item.TraderName,
			&item.TraderAvatar,
			&item.Status,
			&item.AllocatedCapital,
			&item.AvailableCapital,
			&item.FrozenCapital,
			&item.OpenPositionCount,
			&item.LifetimeRealizedPnl,
			&item.LifetimeProfitShare,
			&cumulativeNetDeposit,
			&item.UpdatedAt,
		); err != nil {
			return nil, err
		}
		item.CurrentEquity = item.AvailableCapital + item.FrozenCapital
		item.LifetimeNetPnl = item.LifetimeRealizedPnl - item.LifetimeProfitShare
		baseline := cumulativeNetDeposit
		if baseline <= 0 {
			baseline = item.AllocatedCapital
		}
		item.CurrentNetPnl = item.CurrentEquity - baseline
		if baseline > 0 {
			item.CurrentReturnRate = item.CurrentNetPnl / baseline
		}
		resp.TotalCount++
		if item.Status == "active" {
			resp.ActiveCount++
		}
		resp.Items = append(resp.Items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return resp, nil
}

func (r *AssetsRepo) ListCopyAccountOpenPositions(ctx context.Context, userID, traderUID string) (*model.CopyAccountOpenPositionsResponse, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT
			p.id::text,
			COALESCE(p.copy_trading_id::text, ''),
			ct.trader_id,
			COALESCE(u.display_name, ''),
			COALESCE(u.avatar_url, ''),
			p.symbol,
			p.side,
			p.qty,
			p.entry_price,
			p.margin_amount,
			p.leverage,
			p.created_at
		FROM positions p
		JOIN copy_trading ct ON ct.id = p.copy_trading_id
		JOIN users u ON u.uid = ct.trader_id
		WHERE p.user_id = $1
		  AND p.is_copy_trade = true
		  AND p.status = 'open'
		  AND ($2 = '' OR ct.trader_id = $2)
		ORDER BY p.created_at DESC
	`, userID, traderUID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	resp := &model.CopyAccountOpenPositionsResponse{Items: []model.CopyAccountOpenPositionItem{}}
	for rows.Next() {
		var item model.CopyAccountOpenPositionItem
		if err := rows.Scan(
			&item.PositionID,
			&item.CopyTradingID,
			&item.TraderUID,
			&item.TraderName,
			&item.TraderAvatar,
			&item.Symbol,
			&item.Side,
			&item.Qty,
			&item.EntryPrice,
			&item.MarginAmount,
			&item.Leverage,
			&item.OpenedAt,
		); err != nil {
			return nil, err
		}
		resp.Items = append(resp.Items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	resp.TotalCount = len(resp.Items)
	return resp, nil
}

func (r *AssetsRepo) ListCopyAccountHistory(ctx context.Context, userID, traderUID string, limit, offset int) (*model.CopyAccountHistoryResponse, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	if offset < 0 {
		offset = 0
	}

	var total int
	if err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM positions p
		JOIN copy_trading ct ON ct.id = p.copy_trading_id
		WHERE p.user_id = $1
		  AND p.is_copy_trade = true
		  AND p.status IN ('closed', 'liquidated')
		  AND ($2 = '' OR ct.trader_id = $2)
	`, userID, traderUID).Scan(&total); err != nil {
		return nil, err
	}

	rows, err := r.pool.Query(ctx, `
		WITH share_by_position AS (
			SELECT position_id, follower_user_id, COALESCE(SUM(share_amount), 0) AS profit_shared
			FROM copy_profit_share_records
			WHERE status = 'settled'
			GROUP BY position_id, follower_user_id
		)
		SELECT
			p.id::text,
			COALESCE(p.copy_trading_id::text, ''),
			ct.trader_id,
			COALESCE(u.display_name, ''),
			COALESCE(u.avatar_url, ''),
			p.symbol,
			p.side,
			p.qty,
			p.entry_price,
			COALESCE(p.close_price, 0),
			p.margin_amount,
			COALESCE(p.realized_pnl, 0),
			COALESCE(p.open_fee, 0),
			COALESCE(p.close_fee, 0),
			COALESCE(sp.profit_shared, 0),
			p.created_at,
			p.closed_at
		FROM positions p
		JOIN copy_trading ct ON ct.id = p.copy_trading_id
		JOIN users u ON u.uid = ct.trader_id
		LEFT JOIN share_by_position sp
		  ON sp.position_id = p.id
		 AND sp.follower_user_id = p.user_id
		WHERE p.user_id = $1
		  AND p.is_copy_trade = true
		  AND p.status IN ('closed', 'liquidated')
		  AND ($2 = '' OR ct.trader_id = $2)
		ORDER BY COALESCE(p.closed_at, p.updated_at, p.created_at) DESC
		LIMIT $3 OFFSET $4
	`, userID, traderUID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	resp := &model.CopyAccountHistoryResponse{Items: []model.CopyAccountHistoryItem{}, TotalCount: total}
	for rows.Next() {
		var item model.CopyAccountHistoryItem
		if err := rows.Scan(
			&item.PositionID,
			&item.CopyTradingID,
			&item.TraderUID,
			&item.TraderName,
			&item.TraderAvatar,
			&item.Symbol,
			&item.Side,
			&item.Qty,
			&item.EntryPrice,
			&item.ClosePrice,
			&item.MarginAmount,
			&item.GrossPnl,
			&item.OpenFee,
			&item.CloseFee,
			&item.ProfitShared,
			&item.OpenedAt,
			&item.ClosedAt,
		); err != nil {
			return nil, err
		}
		item.NetPnl = item.GrossPnl - item.OpenFee - item.CloseFee - item.ProfitShared
		switch {
		case item.NetPnl > 0:
			item.Result = "profit"
		case item.NetPnl < 0:
			item.Result = "loss"
		default:
			item.Result = "flat"
		}
		resp.Items = append(resp.Items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return resp, nil
}

func (r *AssetsRepo) GetTodayPnl(ctx context.Context, userID string) (float64, error) {
	var total float64
	err := r.pool.QueryRow(ctx, `
		WITH wallet_net AS (
			SELECT COALESCE(SUM(amount), 0) AS pnl
			FROM wallet_transactions
			WHERE user_id = $1
			  AND created_at >= date_trunc('day', NOW())
			  AND type IN ('trade_pnl', 'fee')
		),
		copy_closed_net AS (
			SELECT COALESCE(SUM(realized_pnl - open_fee - close_fee), 0) AS pnl
			FROM positions
			WHERE user_id = $1
			  AND is_copy_trade = true
			  AND status IN ('closed', 'liquidated')
			  AND closed_at >= date_trunc('day', NOW())
		)
		SELECT COALESCE((SELECT pnl FROM wallet_net), 0) + COALESCE((SELECT pnl FROM copy_closed_net), 0)
	`, userID).Scan(&total)
	return total, err
}

func (r *AssetsRepo) GetTransactions(ctx context.Context, userID string, limit, offset int, status string) ([]model.AssetTransaction, error) {
	if err := r.EnsureBaseAccounts(ctx, userID); err != nil {
		return nil, err
	}
	if limit <= 0 {
		limit = 50
	}

	rows, err := r.pool.Query(ctx, `
		WITH wallet_rows AS (
			SELECT
				wt.id::text AS id,
				wt.type,
				CASE WHEN wt.amount >= 0 THEN 'credit' ELSE 'debit' END AS direction,
				ABS(wt.amount) AS amount,
				wt.amount AS net_amount,
				COALESCE(wt.balance_after, 0) AS balance_after,
				'futures'::text AS account_type,
				''::text AS counterparty_account_type,
				''::text AS status,
				COALESCE(wt.note, '') AS note,
				wt.created_at
			FROM wallet_transactions wt
			WHERE wt.user_id = $1
		),
		spot_ledger_rows AS (
			SELECT
				ale.id::text AS id,
				ale.entry_type AS type,
				ale.direction,
				ale.amount AS amount,
				CASE
					WHEN ale.direction = 'credit' THEN ale.amount
					ELSE -ale.amount
				END AS net_amount,
				COALESCE(ale.available_after, 0) AS balance_after,
				CASE
					WHEN aa.account_type = 'main' THEN 'spot'
					ELSE aa.account_type
				END AS account_type,
				''::text AS counterparty_account_type,
				COALESCE(aw.status, '') AS status,
				COALESCE(ale.note, '') AS note,
				ale.created_at
			FROM asset_ledger_entries ale
			JOIN asset_accounts aa ON aa.id = ale.account_id
			LEFT JOIN asset_withdrawals aw
			  ON ale.ref_type = 'asset_withdrawal'
			 AND ale.ref_id = aw.id::text
			WHERE ale.user_id = $1
			  AND ale.entry_type IN ('deposit', 'withdraw', 'withdraw_fee', 'system_adjustment', 'reward')
		),
		transfer_rows AS (
			SELECT
				at.id::text AS id,
				CASE
					WHEN af.account_type IN ('main', 'spot') THEN 'transfer_to_futures'
					ELSE 'transfer_to_main'
				END AS type,
				'internal'::text AS direction,
				at.amount AS amount,
				0::numeric AS net_amount,
				0::numeric AS balance_after,
				CASE
					WHEN af.account_type = 'main' THEN 'spot'
					ELSE af.account_type
				END AS account_type,
				CASE
					WHEN af2.account_type = 'main' THEN 'spot'
					ELSE af2.account_type
				END AS counterparty_account_type,
				''::text AS status,
				COALESCE(at.note, '') AS note,
				at.created_at
			FROM asset_transfers at
			JOIN asset_accounts af ON af.id = at.from_account_id
			JOIN asset_accounts af2 ON af2.id = at.to_account_id
			WHERE at.user_id = $1
			  AND at.status = 'completed'
		)
		SELECT
			id, type, direction, amount, net_amount, balance_after,
			account_type, counterparty_account_type, status, note, created_at
		FROM (
			SELECT * FROM wallet_rows
			UNION ALL
			SELECT * FROM spot_ledger_rows
			UNION ALL
			SELECT * FROM transfer_rows
		) tx
		WHERE ($4 = '' OR tx.status = $4)
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, userID, limit, offset, status)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []model.AssetTransaction{}
	for rows.Next() {
		var item model.AssetTransaction
		if err := rows.Scan(
			&item.ID,
			&item.Type,
			&item.Direction,
			&item.Amount,
			&item.NetAmount,
			&item.BalanceAfter,
			&item.AccountType,
			&item.CounterpartyAccount,
			&item.Status,
			&item.Note,
			&item.CreatedAt,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (r *AssetsRepo) GetPendingWithdrawals(ctx context.Context, userID string, limit int) ([]model.AssetPendingWithdrawal, int, float64, error) {
	if err := r.EnsureBaseAccounts(ctx, userID); err != nil {
		return nil, 0, 0, err
	}
	if limit <= 0 {
		limit = 3
	}

	var totalCount int
	var totalAmount float64
	if err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*), COALESCE(SUM(amount), 0)
		FROM asset_withdrawals
		WHERE user_id = $1
		  AND status IN ('pending_review', 'approved', 'processing')
	`, userID).Scan(&totalCount, &totalAmount); err != nil {
		return nil, 0, 0, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id::text, network, address, amount, status, COALESCE(provider_status, ''), created_at
		FROM asset_withdrawals
		WHERE user_id = $1
		  AND status IN ('pending_review', 'approved', 'processing')
		ORDER BY created_at DESC
		LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, 0, 0, err
	}
	defer rows.Close()

	items := make([]model.AssetPendingWithdrawal, 0, limit)
	for rows.Next() {
		var item model.AssetPendingWithdrawal
		if err := rows.Scan(
			&item.ID,
			&item.Network,
			&item.Address,
			&item.Amount,
			&item.Status,
			&item.ProviderStatus,
			&item.CreatedAt,
		); err != nil {
			return nil, 0, 0, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, 0, err
	}

	return items, totalCount, totalAmount, nil
}

func (r *AssetsRepo) GetChangeSeries(ctx context.Context, userID string, days int) ([]model.AssetChangePoint, error) {
	if days <= 0 {
		days = 7
	}
	rows, err := r.pool.Query(ctx, `
		WITH days AS (
			SELECT generate_series(
				date_trunc('day', NOW()) - (($2::int - 1) * interval '1 day'),
				date_trunc('day', NOW()),
				interval '1 day'
			) AS day
		)
		SELECT
			TO_CHAR(d.day, 'YYYY-MM-DD') AS date,
			TO_CHAR(d.day, 'MM/DD') AS label,
			COALESCE(SUM(
				CASE
					WHEN wt.type IN ('deposit', 'trade_pnl') THEN wt.amount
					WHEN wt.type IN ('withdraw', 'fee') THEN wt.amount
					ELSE 0
				END
			), 0) +
			COALESCE((
				SELECT SUM(
					CASE
						WHEN ale.entry_type IN ('deposit', 'reward') AND ale.direction = 'credit' THEN ale.amount
						WHEN ale.entry_type = 'system_adjustment' AND ale.direction = 'credit' AND COALESCE(ale.ref_type, '') <> 'asset_withdrawal_reject' THEN ale.amount
						WHEN ale.entry_type IN ('withdraw', 'withdraw_fee') AND ale.direction = 'debit' AND COALESCE(aw.status, 'completed') = 'completed' THEN -ale.amount
						ELSE 0
					END
				)
				FROM asset_ledger_entries ale
				JOIN asset_accounts aa ON aa.id = ale.account_id
				LEFT JOIN asset_withdrawals aw
				  ON ale.ref_type = 'asset_withdrawal'
				 AND ale.ref_id = aw.id::text
				WHERE ale.user_id = $1
				  AND aa.account_type IN ('main', 'spot')
				  AND COALESCE(
					CASE
						WHEN ale.ref_type = 'asset_withdrawal' AND aw.status = 'completed' THEN aw.updated_at
						ELSE ale.created_at
					END,
					ale.created_at
				  ) >= d.day
				  AND COALESCE(
					CASE
						WHEN ale.ref_type = 'asset_withdrawal' AND aw.status = 'completed' THEN aw.updated_at
						ELSE ale.created_at
					END,
					ale.created_at
				  ) < d.day + interval '1 day'
			), 0) +
			COALESCE((
				SELECT SUM(p.realized_pnl - p.open_fee - p.close_fee)
				FROM positions p
				WHERE p.user_id = $1
				  AND p.is_copy_trade = true
				  AND p.status IN ('closed', 'liquidated')
				  AND p.closed_at >= d.day
				  AND p.closed_at < d.day + interval '1 day'
			), 0) AS net_change
		FROM days d
		LEFT JOIN wallet_transactions wt
		  ON wt.user_id = $1
		 AND wt.created_at >= d.day
		 AND wt.created_at < d.day + interval '1 day'
		GROUP BY d.day
		ORDER BY d.day ASC
	`, userID, days)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	points := []model.AssetChangePoint{}
	for rows.Next() {
		var item model.AssetChangePoint
		if err := rows.Scan(&item.Date, &item.Label, &item.NetChange); err != nil {
			return nil, err
		}
		points = append(points, item)
	}
	return points, rows.Err()
}

func (r *AssetsRepo) GetPnlCalendar(ctx context.Context, userID string, year, month int) (*model.AssetPnlCalendarResponse, error) {
	now := time.Now()
	if year <= 0 {
		year = now.Year()
	}
	if month < 1 || month > 12 {
		month = int(now.Month())
	}

	location := now.Location()
	monthStart := time.Date(year, time.Month(month), 1, 0, 0, 0, 0, location)
	nextMonth := monthStart.AddDate(0, 1, 0)
	monthEnd := nextMonth.Add(-24 * time.Hour)

	rows, err := r.pool.Query(ctx, `
		WITH days AS (
			SELECT generate_series($2::date, $3::date, interval '1 day') AS day
		)
		SELECT
			TO_CHAR(d.day, 'YYYY-MM-DD') AS date,
			EXTRACT(DAY FROM d.day)::int AS day,
			(
				COALESCE(SUM(
					CASE
						WHEN wt.type IN ('deposit', 'trade_pnl') THEN wt.amount
						WHEN wt.type IN ('withdraw', 'fee') THEN wt.amount
						ELSE 0
					END
				), 0) +
				COALESCE((
					SELECT SUM(
						CASE
							WHEN ale.entry_type IN ('deposit', 'reward') AND ale.direction = 'credit' THEN ale.amount
							WHEN ale.entry_type = 'system_adjustment' AND ale.direction = 'credit' AND COALESCE(ale.ref_type, '') <> 'asset_withdrawal_reject' THEN ale.amount
							WHEN ale.entry_type IN ('withdraw', 'withdraw_fee') AND ale.direction = 'debit' AND COALESCE(aw.status, 'completed') = 'completed' THEN -ale.amount
							ELSE 0
						END
					)
					FROM asset_ledger_entries ale
					JOIN asset_accounts aa ON aa.id = ale.account_id
					LEFT JOIN asset_withdrawals aw
					  ON ale.ref_type = 'asset_withdrawal'
					 AND ale.ref_id = aw.id::text
					WHERE ale.user_id = $1
					  AND aa.account_type IN ('main', 'spot')
					  AND COALESCE(
						CASE
							WHEN ale.ref_type = 'asset_withdrawal' AND aw.status = 'completed' THEN aw.updated_at
							ELSE ale.created_at
						END,
						ale.created_at
					  ) >= d.day
					  AND COALESCE(
						CASE
							WHEN ale.ref_type = 'asset_withdrawal' AND aw.status = 'completed' THEN aw.updated_at
							ELSE ale.created_at
						END,
						ale.created_at
					  ) < d.day + interval '1 day'
				), 0) +
				COALESCE((
					SELECT SUM(p.realized_pnl - p.open_fee - p.close_fee)
					FROM positions p
					WHERE p.user_id = $1
					  AND p.is_copy_trade = true
					  AND p.status IN ('closed', 'liquidated')
					  AND p.closed_at >= d.day
					  AND p.closed_at < d.day + interval '1 day'
				), 0)
			) AS net_pnl
		FROM days d
		LEFT JOIN wallet_transactions wt
		  ON wt.user_id = $1
		 AND wt.created_at >= d.day
		 AND wt.created_at < d.day + interval '1 day'
		GROUP BY d.day
		ORDER BY d.day ASC
	`, userID, monthStart, monthEnd)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	resp := &model.AssetPnlCalendarResponse{
		Year:       year,
		Month:      month,
		MonthLabel: monthStart.Format("2006-01"),
		Days:       []model.AssetPnlCalendarDay{},
	}
	today := now.Format("2006-01-02")

	for rows.Next() {
		var item model.AssetPnlCalendarDay
		if err := rows.Scan(&item.Date, &item.Day, &item.NetPnl); err != nil {
			return nil, err
		}
		item.HasData = item.NetPnl != 0
		item.IsToday = item.Date == today
		switch {
		case item.NetPnl > 0:
			resp.PositiveDays++
		case item.NetPnl < 0:
			resp.NegativeDays++
		default:
			resp.FlatDays++
		}
		resp.NetPnl += item.NetPnl
		resp.Days = append(resp.Days, item)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}
	return resp, nil
}

func (r *AssetsRepo) DepositToSpot(ctx context.Context, userID string, amount float64) (*model.AssetDepositResponse, error) {
	if amount <= 0 {
		return nil, fmt.Errorf("amount must be positive")
	}
	if err := r.EnsureBaseAccounts(ctx, userID); err != nil {
		return nil, err
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	spotAccountType, err := resolveSpotAccountTypeQueryRow(ctx, tx, userID)
	if err != nil {
		return nil, err
	}

	var accountID string
	if err = tx.QueryRow(ctx, `
		SELECT id::text
		FROM asset_accounts
		WHERE user_id = $1
		  AND account_type = $2
	`, userID, spotAccountType).Scan(&accountID); err != nil {
		return nil, err
	}

	var available, frozen float64
	if err = tx.QueryRow(ctx, `
		UPDATE asset_balances ab
		SET available = available + $3,
		    updated_at = NOW()
		FROM asset_accounts aa
		WHERE ab.account_id = aa.id
		  AND aa.user_id = $1
		  AND aa.account_type = $2
		  AND ab.asset_code = 'USDT'
		RETURNING ab.available, ab.frozen
	`, userID, spotAccountType, amount).Scan(&available, &frozen); err != nil {
		return nil, err
	}

	if _, err = tx.Exec(ctx, `
		INSERT INTO asset_ledger_entries (
			user_id,
			account_id,
			asset_code,
			direction,
			entry_type,
			amount,
			available_after,
			frozen_after,
			ref_type,
			note
		) VALUES (
			$1,
			$2::uuid,
			'USDT',
			'credit',
			'deposit',
			$3,
			$4,
			$5,
			'asset_deposit',
			'Spot account deposit'
		)
	`, userID, accountID, amount, available, frozen); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return &model.AssetDepositResponse{
		AccountType:   "spot",
		Amount:        amount,
		SpotAvailable: available,
		SpotFrozen:    frozen,
	}, nil
}

func (r *AssetsRepo) WithdrawFromSpot(ctx context.Context, userID string, amount float64, network, address string) (*model.AssetWithdrawResponse, error) {
	if amount <= 0 {
		return nil, fmt.Errorf("amount must be positive")
	}
	if network == "" {
		return nil, fmt.Errorf("network is required")
	}
	if address == "" {
		return nil, fmt.Errorf("address is required")
	}
	if err := r.EnsureBaseAccounts(ctx, userID); err != nil {
		return nil, err
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	spotAccountType, err := resolveSpotAccountTypeQueryRow(ctx, tx, userID)
	if err != nil {
		return nil, err
	}

	var accountID string
	if err = tx.QueryRow(ctx, `
		SELECT id::text
		FROM asset_accounts
		WHERE user_id = $1
		  AND account_type = $2
	`, userID, spotAccountType).Scan(&accountID); err != nil {
		return nil, err
	}

	var available, frozen float64
	if err = tx.QueryRow(ctx, `
		UPDATE asset_balances ab
		SET available = available - $3,
		    frozen = frozen + $3,
		    updated_at = NOW()
		FROM asset_accounts aa
		WHERE ab.account_id = aa.id
		  AND aa.user_id = $1
		  AND aa.account_type = $2
		  AND ab.asset_code = 'USDT'
		  AND ab.available >= $3
		RETURNING ab.available, ab.frozen
	`, userID, spotAccountType, amount).Scan(&available, &frozen); err != nil {
		return nil, fmt.Errorf("insufficient spot account balance")
	}

	var withdrawalID string
	if err = tx.QueryRow(ctx, `
		INSERT INTO asset_withdrawals (
			user_id,
			account_id,
			asset_code,
			network,
			address,
			amount,
			status
		) VALUES (
			$1,
			$2::uuid,
			'USDT',
			$3,
			$4,
			$5,
			'pending_review'
		)
		RETURNING id::text
	`, userID, accountID, network, address, amount).Scan(&withdrawalID); err != nil {
		return nil, err
	}

	if _, err = tx.Exec(ctx, `
		INSERT INTO asset_ledger_entries (
			user_id,
			account_id,
			asset_code,
			direction,
			entry_type,
			amount,
			available_after,
			frozen_after,
			ref_type,
			ref_id,
			note
		) VALUES (
			$1,
			$2::uuid,
			'USDT',
			'debit',
			'withdraw',
			$3,
			$4,
			$5,
			'asset_withdrawal',
			$6,
			'Spot withdrawal request pending review'
		)
	`, userID, accountID, amount, available, frozen, withdrawalID); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return &model.AssetWithdrawResponse{
		WithdrawalID:  withdrawalID,
		AccountType:   "spot",
		Amount:        amount,
		Address:       address,
		Network:       network,
		SpotAvailable: available,
		SpotFrozen:    frozen,
		Status:        "pending_review",
	}, nil
}

func (r *AssetsRepo) ListAdminWithdrawals(ctx context.Context, status string, limit, offset int) ([]model.AdminAssetWithdrawal, int, error) {
	if limit <= 0 {
		limit = 50
	}

	where := "1=1"
	args := []any{}
	argPos := 1
	if status != "" {
		where += fmt.Sprintf(" AND aw.status = $%d", argPos)
		args = append(args, status)
		argPos++
	}

	var total int
	if err := r.pool.QueryRow(ctx, fmt.Sprintf(`
		SELECT COUNT(*)
		FROM asset_withdrawals aw
		WHERE %s
	`, where), args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	args = append(args, limit, offset)
	rows, err := r.pool.Query(ctx, fmt.Sprintf(`
		SELECT
			aw.id::text,
			aw.user_id,
			COALESCE(u.display_name, ''),
			COALESCE(u.email, ''),
			aw.asset_code,
			aw.network,
			aw.address,
			aw.amount,
			aw.fee,
			aw.status,
			COALESCE(aw.provider, ''),
			COALESCE(aw.provider_trade_id, ''),
			COALESCE(aw.provider_tx_id, ''),
			COALESCE(aw.provider_status, ''),
			COALESCE(aw.reject_reason, ''),
			COALESCE(aw.tx_hash, ''),
			COALESCE(aw.reviewed_by, ''),
			aw.reviewed_at,
			aw.submitted_to_provider_at,
			aw.completed_at,
			aw.failed_at,
			aw.created_at,
			aw.updated_at
		FROM asset_withdrawals aw
		LEFT JOIN users u ON u.uid = aw.user_id
		WHERE %s
		ORDER BY
			CASE WHEN aw.status = 'pending_review' THEN 0 ELSE 1 END,
			aw.created_at DESC
		LIMIT $%d OFFSET $%d
	`, where, argPos, argPos+1), args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := []model.AdminAssetWithdrawal{}
	for rows.Next() {
		var item model.AdminAssetWithdrawal
		if err := rows.Scan(
			&item.ID,
			&item.UserID,
			&item.DisplayName,
			&item.Email,
			&item.AssetCode,
			&item.Network,
			&item.Address,
			&item.Amount,
			&item.Fee,
			&item.Status,
			&item.Provider,
			&item.ProviderTradeID,
			&item.ProviderTxID,
			&item.ProviderStatus,
			&item.RejectReason,
			&item.TxHash,
			&item.ReviewedBy,
			&item.ReviewedAt,
			&item.SubmittedToProviderAt,
			&item.CompletedAt,
			&item.FailedAt,
			&item.CreatedAt,
			&item.UpdatedAt,
		); err != nil {
			return nil, 0, err
		}
		items = append(items, item)
	}

	return items, total, rows.Err()
}

type assetWithdrawalProviderTarget struct {
	ID        string
	UserID    string
	AccountID string
	AssetCode string
	Network   string
	Address   string
	Memo      string
	Amount    float64
	Status    string
}

func (r *AssetsRepo) GetWithdrawalForProviderSubmission(ctx context.Context, withdrawalID string) (*assetWithdrawalProviderTarget, error) {
	var item assetWithdrawalProviderTarget
	if err := r.pool.QueryRow(ctx, `
		SELECT
			id::text,
			user_id,
			account_id::text,
			asset_code,
			network,
			address,
			COALESCE(memo, ''),
			amount,
			status
		FROM asset_withdrawals
		WHERE id = $1::uuid
	`, withdrawalID).Scan(
		&item.ID,
		&item.UserID,
		&item.AccountID,
		&item.AssetCode,
		&item.Network,
		&item.Address,
		&item.Memo,
		&item.Amount,
		&item.Status,
	); err != nil {
		return nil, err
	}
	return &item, nil
}

func (r *AssetsRepo) fetchAdminWithdrawalByID(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, withdrawalID string) (*model.AdminAssetWithdrawal, error) {
	var item model.AdminAssetWithdrawal
	if err := q.QueryRow(ctx, `
		SELECT
			aw.id::text,
			aw.user_id,
			COALESCE(u.display_name, ''),
			COALESCE(u.email, ''),
			aw.asset_code,
			aw.network,
			aw.address,
			aw.amount,
			aw.fee,
			aw.status,
			COALESCE(aw.provider, ''),
			COALESCE(aw.provider_trade_id, ''),
			COALESCE(aw.provider_tx_id, ''),
			COALESCE(aw.provider_status, ''),
			COALESCE(aw.reject_reason, ''),
			COALESCE(aw.tx_hash, ''),
			COALESCE(aw.reviewed_by, ''),
			aw.reviewed_at,
			aw.submitted_to_provider_at,
			aw.completed_at,
			aw.failed_at,
			aw.created_at,
			aw.updated_at
		FROM asset_withdrawals aw
		LEFT JOIN users u ON u.uid = aw.user_id
		WHERE aw.id = $1::uuid
	`, withdrawalID).Scan(
		&item.ID,
		&item.UserID,
		&item.DisplayName,
		&item.Email,
		&item.AssetCode,
		&item.Network,
		&item.Address,
		&item.Amount,
		&item.Fee,
		&item.Status,
		&item.Provider,
		&item.ProviderTradeID,
		&item.ProviderTxID,
		&item.ProviderStatus,
		&item.RejectReason,
		&item.TxHash,
		&item.ReviewedBy,
		&item.ReviewedAt,
		&item.SubmittedToProviderAt,
		&item.CompletedAt,
		&item.FailedAt,
		&item.CreatedAt,
		&item.UpdatedAt,
	); err != nil {
		return nil, err
	}
	return &item, nil
}

func (r *AssetsRepo) MarkWithdrawalSubmittedToProvider(ctx context.Context, withdrawalID, adminUID, providerTradeID, providerStatus string, rawPayload []byte) (*model.AdminAssetWithdrawal, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `
		UPDATE asset_withdrawals
		SET status = 'approved',
		    provider = 'udun',
		    provider_trade_id = COALESCE(NULLIF($2, ''), provider_trade_id),
		    provider_status = COALESCE(NULLIF($3, ''), provider_status),
		    raw_payload = CASE
		      WHEN $4 = '' THEN raw_payload
		      ELSE $4::jsonb
		    END,
		    reviewed_by = COALESCE(NULLIF($5, ''), reviewed_by),
		    reviewed_at = COALESCE(reviewed_at, NOW()),
		    submitted_to_provider_at = COALESCE(submitted_to_provider_at, NOW()),
		    updated_at = NOW()
		WHERE id = $1::uuid
		  AND status = 'pending_review'
	`, withdrawalID, providerTradeID, providerStatus, string(rawPayload), adminUID)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, fmt.Errorf("withdrawal is not pending review")
	}

	item, err := r.fetchAdminWithdrawalByID(ctx, tx, withdrawalID)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return item, nil
}

func mapUdunWithdrawStatus(status string) string {
	switch strings.TrimSpace(status) {
	case "0":
		return "approved"
	case "1":
		return "processing"
	case "2":
		return "rejected"
	case "3":
		return "completed"
	case "4":
		return "failed"
	default:
		return "approved"
	}
}

func (r *AssetsRepo) refundProviderWithdrawalTx(ctx context.Context, tx pgx.Tx, item *model.AdminAssetWithdrawal, accountID, refType, note string) error {
	var availableAfter, frozenAfter float64
	if err := tx.QueryRow(ctx, `
		UPDATE asset_balances
		SET available = available + $2,
		    frozen = frozen - $2,
		    updated_at = NOW()
		WHERE account_id = $1::uuid
		  AND asset_code = 'USDT'
		  AND frozen >= $2
		RETURNING available, frozen
	`, accountID, item.Amount).Scan(&availableAfter, &frozenAfter); err != nil {
		return err
	}

	_, err := tx.Exec(ctx, `
		INSERT INTO asset_ledger_entries (
			user_id,
			account_id,
			asset_code,
			direction,
			entry_type,
			amount,
			available_after,
			frozen_after,
			ref_type,
			ref_id,
			note
		) VALUES (
			$1,
			$2::uuid,
			'USDT',
			'credit',
			'system_adjustment',
			$3,
			$4,
			$5,
			$6,
			$7,
			$8
		)
	`, item.UserID, accountID, item.Amount, availableAfter, frozenAfter, refType, item.ID, note)
	return err
}

func (r *AssetsRepo) ProcessUdunWithdrawCallback(ctx context.Context, cb *udun.WithdrawCallback) (*model.AdminAssetWithdrawal, error) {
	if cb == nil {
		return nil, fmt.Errorf("withdraw callback is required")
	}
	if cb.TradeType != 0 && cb.TradeType != 2 {
		return nil, fmt.Errorf("unsupported udun withdraw callback trade type: %d", cb.TradeType)
	}
	identifier := strings.TrimSpace(cb.BusinessID)
	if identifier == "" {
		identifier = strings.TrimSpace(cb.ProviderTradeID)
	}
	if identifier == "" {
		return nil, fmt.Errorf("withdraw callback missing business identifier")
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var item model.AdminAssetWithdrawal
	var accountID string
	if err := tx.QueryRow(ctx, `
		SELECT
			aw.id::text,
			aw.user_id,
			COALESCE(u.display_name, ''),
			COALESCE(u.email, ''),
			aw.asset_code,
			aw.network,
			aw.address,
			aw.amount,
			aw.fee,
			aw.status,
			COALESCE(aw.provider, ''),
			COALESCE(aw.provider_trade_id, ''),
			COALESCE(aw.provider_tx_id, ''),
			COALESCE(aw.provider_status, ''),
			COALESCE(aw.reject_reason, ''),
			COALESCE(aw.tx_hash, ''),
			COALESCE(aw.reviewed_by, ''),
			aw.reviewed_at,
			aw.submitted_to_provider_at,
			aw.completed_at,
			aw.failed_at,
			aw.account_id::text,
			aw.created_at,
			aw.updated_at
		FROM asset_withdrawals aw
		LEFT JOIN users u ON u.uid = aw.user_id
		WHERE aw.id::text = $1
		   OR COALESCE(aw.provider_trade_id, '') = $2
		ORDER BY CASE WHEN aw.id::text = $1 THEN 0 ELSE 1 END
		LIMIT 1
		FOR UPDATE OF aw
	`, identifier, strings.TrimSpace(cb.ProviderTradeID)).Scan(
		&item.ID,
		&item.UserID,
		&item.DisplayName,
		&item.Email,
		&item.AssetCode,
		&item.Network,
		&item.Address,
		&item.Amount,
		&item.Fee,
		&item.Status,
		&item.Provider,
		&item.ProviderTradeID,
		&item.ProviderTxID,
		&item.ProviderStatus,
		&item.RejectReason,
		&item.TxHash,
		&item.ReviewedBy,
		&item.ReviewedAt,
		&item.SubmittedToProviderAt,
		&item.CompletedAt,
		&item.FailedAt,
		&accountID,
		&item.CreatedAt,
		&item.UpdatedAt,
	); err != nil {
		return nil, err
	}

	rawPayload, _ := json.Marshal(cb.RawValues)
	providerStatus := strings.TrimSpace(cb.Status)
	nextStatus := mapUdunWithdrawStatus(providerStatus)
	rejectReason := item.RejectReason
	if cb.ErrorMessage != "" {
		rejectReason = cb.ErrorMessage
	}

	switch nextStatus {
	case "approved", "processing":
		if _, err := tx.Exec(ctx, `
			UPDATE asset_withdrawals
			SET status = $2,
			    provider = 'udun',
			    provider_trade_id = COALESCE(NULLIF($3, ''), provider_trade_id),
			    provider_tx_id = COALESCE(NULLIF($4, ''), provider_tx_id),
			    provider_status = NULLIF($5, ''),
			    tx_hash = COALESCE(NULLIF($4, ''), tx_hash),
			    raw_payload = CASE WHEN $6 = '' THEN raw_payload ELSE $6::jsonb END,
			    broadcast_at = CASE
			      WHEN $2 = 'processing' THEN COALESCE(broadcast_at, NOW())
			      ELSE broadcast_at
			    END,
			    updated_at = NOW()
			WHERE id = $1::uuid
		`, item.ID, nextStatus, cb.ProviderTradeID, cb.TxHash, providerStatus, string(rawPayload)); err != nil {
			return nil, err
		}
	case "rejected", "failed":
		if item.Status != "rejected" && item.Status != "failed" && item.Status != "completed" {
			refType := "asset_withdrawal_provider_reject"
			note := "Udun rejected withdrawal and refunded frozen funds"
			if nextStatus == "failed" {
				refType = "asset_withdrawal_provider_fail"
				note = "Udun withdrawal failed and refunded frozen funds"
			}
			if err := r.refundProviderWithdrawalTx(ctx, tx, &item, accountID, refType, note); err != nil {
				return nil, err
			}
		}
		if _, err := tx.Exec(ctx, `
			UPDATE asset_withdrawals
			SET status = $2,
			    provider = 'udun',
			    provider_trade_id = COALESCE(NULLIF($3, ''), provider_trade_id),
			    provider_tx_id = COALESCE(NULLIF($4, ''), provider_tx_id),
			    provider_status = NULLIF($5, ''),
			    tx_hash = COALESCE(NULLIF($4, ''), tx_hash),
			    reject_reason = COALESCE(NULLIF($6, ''), reject_reason),
			    raw_payload = CASE WHEN $7 = '' THEN raw_payload ELSE $7::jsonb END,
			    failed_at = COALESCE(failed_at, NOW()),
			    updated_at = NOW()
			WHERE id = $1::uuid
		`, item.ID, nextStatus, cb.ProviderTradeID, cb.TxHash, providerStatus, rejectReason, string(rawPayload)); err != nil {
			return nil, err
		}
	case "completed":
		if item.Status != "completed" {
			if _, err := tx.Exec(ctx, `
				UPDATE asset_balances
				SET frozen = frozen - $2,
				    updated_at = NOW()
				WHERE account_id = $1::uuid
				  AND asset_code = 'USDT'
				  AND frozen >= $2
			`, accountID, item.Amount); err != nil {
				return nil, err
			}
		}
		if _, err := tx.Exec(ctx, `
			UPDATE asset_withdrawals
			SET status = 'completed',
			    provider = 'udun',
			    provider_trade_id = COALESCE(NULLIF($2, ''), provider_trade_id),
			    provider_tx_id = COALESCE(NULLIF($3, ''), provider_tx_id),
			    provider_status = NULLIF($4, ''),
			    tx_hash = COALESCE(NULLIF($3, ''), tx_hash),
			    fee = CASE WHEN $5 > 0 THEN $5 ELSE fee END,
			    raw_payload = CASE WHEN $6 = '' THEN raw_payload ELSE $6::jsonb END,
			    broadcast_at = COALESCE(broadcast_at, NOW()),
			    completed_at = COALESCE(completed_at, NOW()),
			    updated_at = NOW()
			WHERE id = $1::uuid
		`, item.ID, cb.ProviderTradeID, cb.TxHash, providerStatus, cb.Fee, string(rawPayload)); err != nil {
			return nil, err
		}
	}

	updated, err := r.fetchAdminWithdrawalByID(ctx, tx, item.ID)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return updated, nil
}

func (r *AssetsRepo) ApproveWithdrawal(ctx context.Context, withdrawalID, adminUID, txHash string) (*model.AdminAssetWithdrawal, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var item model.AdminAssetWithdrawal
	var accountID string
	if err := tx.QueryRow(ctx, `
		SELECT
			aw.id::text,
			aw.user_id,
			COALESCE(u.display_name, ''),
			COALESCE(u.email, ''),
			aw.asset_code,
			aw.network,
			aw.address,
			aw.amount,
			aw.fee,
			aw.status,
			COALESCE(aw.reject_reason, ''),
			COALESCE(aw.tx_hash, ''),
			aw.account_id::text,
			aw.created_at,
			aw.updated_at
		FROM asset_withdrawals aw
		LEFT JOIN users u ON u.uid = aw.user_id
		WHERE aw.id = $1::uuid
		FOR UPDATE OF aw
	`, withdrawalID).Scan(
		&item.ID,
		&item.UserID,
		&item.DisplayName,
		&item.Email,
		&item.AssetCode,
		&item.Network,
		&item.Address,
		&item.Amount,
		&item.Fee,
		&item.Status,
		&item.RejectReason,
		&item.TxHash,
		&accountID,
		&item.CreatedAt,
		&item.UpdatedAt,
	); err != nil {
		return nil, err
	}
	if item.Status != "pending_review" {
		return nil, fmt.Errorf("withdrawal is not pending review")
	}

	var frozenAfter float64
	if err := tx.QueryRow(ctx, `
		UPDATE asset_balances
		SET frozen = frozen - $2,
		    updated_at = NOW()
		WHERE account_id = $1::uuid
		  AND asset_code = 'USDT'
		  AND frozen >= $2
		RETURNING frozen
	`, accountID, item.Amount).Scan(&frozenAfter); err != nil {
		return nil, err
	}
	_ = frozenAfter

	if _, err := tx.Exec(ctx, `
		UPDATE asset_withdrawals
		SET status = 'completed',
		    tx_hash = NULLIF($2, ''),
		    reviewed_by = $3,
		    reviewed_at = NOW(),
		    updated_at = NOW()
		WHERE id = $1::uuid
	`, withdrawalID, txHash, adminUID); err != nil {
		return nil, err
	}

	if err := tx.QueryRow(ctx, `
		SELECT status, COALESCE(tx_hash, ''), COALESCE(reviewed_by, ''), reviewed_at, updated_at
		FROM asset_withdrawals
		WHERE id = $1::uuid
	`, withdrawalID).Scan(&item.Status, &item.TxHash, &item.ReviewedBy, &item.ReviewedAt, &item.UpdatedAt); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &item, nil
}

func (r *AssetsRepo) RejectWithdrawal(ctx context.Context, withdrawalID, adminUID, reason string) (*model.AdminAssetWithdrawal, error) {
	if reason == "" {
		return nil, fmt.Errorf("reject reason is required")
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var item model.AdminAssetWithdrawal
	var accountID string
	if err := tx.QueryRow(ctx, `
		SELECT
			aw.id::text,
			aw.user_id,
			COALESCE(u.display_name, ''),
			COALESCE(u.email, ''),
			aw.asset_code,
			aw.network,
			aw.address,
			aw.amount,
			aw.fee,
			aw.status,
			COALESCE(aw.reject_reason, ''),
			COALESCE(aw.tx_hash, ''),
			aw.account_id::text,
			aw.created_at,
			aw.updated_at
		FROM asset_withdrawals aw
		LEFT JOIN users u ON u.uid = aw.user_id
		WHERE aw.id = $1::uuid
		FOR UPDATE OF aw
	`, withdrawalID).Scan(
		&item.ID,
		&item.UserID,
		&item.DisplayName,
		&item.Email,
		&item.AssetCode,
		&item.Network,
		&item.Address,
		&item.Amount,
		&item.Fee,
		&item.Status,
		&item.RejectReason,
		&item.TxHash,
		&accountID,
		&item.CreatedAt,
		&item.UpdatedAt,
	); err != nil {
		return nil, err
	}
	if item.Status != "pending_review" {
		return nil, fmt.Errorf("withdrawal is not pending review")
	}

	var availableAfter, frozenAfter float64
	if err := tx.QueryRow(ctx, `
		UPDATE asset_balances
		SET available = available + $2,
		    frozen = frozen - $2,
		    updated_at = NOW()
		WHERE account_id = $1::uuid
		  AND asset_code = 'USDT'
		  AND frozen >= $2
		RETURNING available, frozen
	`, accountID, item.Amount).Scan(&availableAfter, &frozenAfter); err != nil {
		return nil, err
	}

	if _, err := tx.Exec(ctx, `
		UPDATE asset_withdrawals
		SET status = 'rejected',
		    reject_reason = $2,
		    reviewed_by = $3,
		    reviewed_at = NOW(),
		    updated_at = NOW()
		WHERE id = $1::uuid
	`, withdrawalID, reason, adminUID); err != nil {
		return nil, err
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO asset_ledger_entries (
			user_id,
			account_id,
			asset_code,
			direction,
			entry_type,
			amount,
			available_after,
			frozen_after,
			ref_type,
			ref_id,
			note
		) VALUES (
			$1,
			$2::uuid,
			'USDT',
			'credit',
			'system_adjustment',
			$3,
			$4,
			$5,
			'asset_withdrawal_reject',
			$6,
			'Rejected withdrawal refunded back to Spot Account'
		)
	`, item.UserID, accountID, item.Amount, availableAfter, frozenAfter, withdrawalID); err != nil {
		return nil, err
	}

	if err := tx.QueryRow(ctx, `
		SELECT status, COALESCE(reject_reason, ''), COALESCE(reviewed_by, ''), reviewed_at, updated_at
		FROM asset_withdrawals
		WHERE id = $1::uuid
	`, withdrawalID).Scan(&item.Status, &item.RejectReason, &item.ReviewedBy, &item.ReviewedAt, &item.UpdatedAt); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &item, nil
}

func (r *AssetsRepo) TransferBetweenAccounts(ctx context.Context, userID, fromAccount, toAccount string, amount float64) (*model.AssetTransferResponse, error) {
	if amount <= 0 {
		return nil, fmt.Errorf("amount must be positive")
	}
	if fromAccount == toAccount {
		return nil, fmt.Errorf("source and destination accounts must be different")
	}
	logicalFrom := fromAccount
	logicalTo := toAccount
	validPair := ((logicalFrom == "main" || logicalFrom == "spot") && logicalTo == "futures") ||
		(logicalFrom == "futures" && (logicalTo == "main" || logicalTo == "spot"))
	if !validPair {
		return nil, fmt.Errorf("unsupported transfer pair")
	}
	if err := r.EnsureBaseAccounts(ctx, userID); err != nil {
		return nil, err
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	spotAccountType, err := resolveSpotAccountTypeQueryRow(ctx, tx, userID)
	if err != nil {
		return nil, err
	}
	if fromAccount == "spot" {
		fromAccount = spotAccountType
	}
	if toAccount == "spot" {
		toAccount = spotAccountType
	}

	if _, err = tx.Exec(ctx, `
		INSERT INTO wallets (user_id) VALUES ($1)
		ON CONFLICT (user_id) DO NOTHING
	`, userID); err != nil {
		return nil, err
	}

	var fromAccountID, toAccountID string
	if err = tx.QueryRow(ctx, `
		SELECT id::text
		FROM asset_accounts
		WHERE user_id = $1 AND account_type = $2
	`, userID, fromAccount).Scan(&fromAccountID); err != nil {
		return nil, err
	}
	if err = tx.QueryRow(ctx, `
		SELECT id::text
		FROM asset_accounts
		WHERE user_id = $1 AND account_type = $2
	`, userID, toAccount).Scan(&toAccountID); err != nil {
		return nil, err
	}

	var mainAvailable float64
	var futuresAvailable float64

	if fromAccount == spotAccountType {
		tag, err := tx.Exec(ctx, `
			UPDATE asset_balances ab
			SET available = available - $2,
			    updated_at = NOW()
			FROM asset_accounts aa
			WHERE ab.account_id = aa.id
			  AND aa.user_id = $1
			  AND aa.account_type = $3
			  AND ab.asset_code = 'USDT'
			  AND ab.available >= $2
		`, userID, amount, spotAccountType)
		if err != nil {
			return nil, err
		}
		if tag.RowsAffected() == 0 {
			return nil, fmt.Errorf("insufficient spot account balance")
		}

		if err = tx.QueryRow(ctx, `
			UPDATE wallets
			SET balance = balance + $2,
			    updated_at = NOW()
			WHERE user_id = $1
			RETURNING balance
		`, userID, amount).Scan(&futuresAvailable); err != nil {
			return nil, err
		}
	} else {
		if err = tx.QueryRow(ctx, `
			UPDATE wallets
			SET balance = balance - $2,
			    updated_at = NOW()
			WHERE user_id = $1
			  AND balance >= $2
			RETURNING balance
		`, userID, amount).Scan(&futuresAvailable); err != nil {
			return nil, fmt.Errorf("insufficient futures account balance")
		}

		if _, err = tx.Exec(ctx, `
			UPDATE asset_balances ab
			SET available = available + $2,
			    updated_at = NOW()
			FROM asset_accounts aa
			WHERE ab.account_id = aa.id
			  AND aa.user_id = $1
			  AND aa.account_type = $3
			  AND ab.asset_code = 'USDT'
		`, userID, amount, spotAccountType); err != nil {
			return nil, err
		}
	}

	if err = tx.QueryRow(ctx, `
		SELECT COALESCE(ab.available, 0)
		FROM asset_accounts aa
		LEFT JOIN asset_balances ab
		  ON ab.account_id = aa.id AND ab.asset_code = 'USDT'
		WHERE aa.user_id = $1 AND aa.account_type = $2
	`, userID, spotAccountType).Scan(&mainAvailable); err != nil {
		return nil, err
	}

	var transferID string
	note := fmt.Sprintf("%s to %s transfer", logicalFrom, logicalTo)
	if err = tx.QueryRow(ctx, `
		INSERT INTO asset_transfers (
			user_id, from_account_id, to_account_id, asset_code, amount, status, note
		) VALUES ($1, $2::uuid, $3::uuid, 'USDT', $4, 'completed', $5)
		RETURNING id::text
	`, userID, fromAccountID, toAccountID, amount, note).Scan(&transferID); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	return &model.AssetTransferResponse{
		TransferID:       transferID,
		FromAccount:      logicalFrom,
		ToAccount:        logicalTo,
		Amount:           amount,
		MainAvailable:    mainAvailable,
		FuturesAvailable: futuresAvailable,
	}, nil
}
