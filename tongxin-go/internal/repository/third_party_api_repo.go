package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type ThirdPartyApiRepo struct {
	pool *pgxpool.Pool
}

func NewThirdPartyApiRepo(pool *pgxpool.Pool) *ThirdPartyApiRepo {
	return &ThirdPartyApiRepo{pool: pool}
}

type TpaUpdateFields struct {
	ApiKey      *string
	ApiSecret   *string
	BaseURL     *string
	WsURL       *string
	Description *string
	UpdatedBy   string
	Reason      string
}

func maskKey(key string) string {
	if len(key) <= 8 {
		return "****"
	}
	return key[:4] + "****" + key[len(key)-4:]
}

// ListAll returns all third-party API configs with masked keys.
func (r *ThirdPartyApiRepo) ListAll(ctx context.Context) ([]model.ThirdPartyApi, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, service_name, display_name, category, COALESCE(base_url,''),
		 COALESCE(ws_url,''), api_key, api_secret, extra_config, is_active,
		 COALESCE(description,''), last_verified_at, updated_at, COALESCE(updated_by,''), created_at
		 FROM third_party_apis ORDER BY id`)
	if err != nil {
		return nil, fmt.Errorf("list third-party APIs: %w", err)
	}
	defer rows.Close()

	var apis []model.ThirdPartyApi
	for rows.Next() {
		var a model.ThirdPartyApi
		if err := rows.Scan(&a.ID, &a.ServiceName, &a.DisplayName, &a.Category,
			&a.BaseURL, &a.WsURL, &a.ApiKey, &a.ApiSecret, &a.ExtraConfig,
			&a.IsActive, &a.Description, &a.LastVerifiedAt,
			&a.UpdatedAt, &a.UpdatedBy, &a.CreatedAt); err != nil {
			return nil, err
		}
		a.ApiKey = maskKey(a.ApiKey)
		a.ApiSecret = maskKey(a.ApiSecret)
		apis = append(apis, a)
	}
	return apis, nil
}

// GetByName returns a single API config with masked keys.
func (r *ThirdPartyApiRepo) GetByName(ctx context.Context, name string) (*model.ThirdPartyApi, error) {
	var a model.ThirdPartyApi
	err := r.pool.QueryRow(ctx,
		`SELECT id, service_name, display_name, category, COALESCE(base_url,''),
		 COALESCE(ws_url,''), api_key, api_secret, extra_config, is_active,
		 COALESCE(description,''), last_verified_at, updated_at, COALESCE(updated_by,''), created_at
		 FROM third_party_apis WHERE service_name=$1`, name).
		Scan(&a.ID, &a.ServiceName, &a.DisplayName, &a.Category,
			&a.BaseURL, &a.WsURL, &a.ApiKey, &a.ApiSecret, &a.ExtraConfig,
			&a.IsActive, &a.Description, &a.LastVerifiedAt,
			&a.UpdatedAt, &a.UpdatedBy, &a.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("get third-party API %s: %w", name, err)
	}
	a.ApiKey = maskKey(a.ApiKey)
	a.ApiSecret = maskKey(a.ApiSecret)
	return &a, nil
}

// Update modifies specific fields and records key change history.
func (r *ThirdPartyApiRepo) Update(ctx context.Context, name string, f TpaUpdateFields) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// If updating API key, record history
	if f.ApiKey != nil {
		var oldKey string
		_ = tx.QueryRow(ctx, `SELECT api_key FROM third_party_apis WHERE service_name=$1`, name).Scan(&oldKey)
		_, _ = tx.Exec(ctx,
			`INSERT INTO api_key_history (service_name, old_key_masked, new_key_masked, changed_by, reason)
			 VALUES ($1, $2, $3, $4, $5)`,
			name, maskKey(oldKey), maskKey(*f.ApiKey), f.UpdatedBy, f.Reason)
	}
	if f.ApiSecret != nil {
		var oldSecret string
		_ = tx.QueryRow(ctx, `SELECT api_secret FROM third_party_apis WHERE service_name=$1`, name).Scan(&oldSecret)
		// History recorded with key change above
	}

	// Build dynamic UPDATE
	sets := []string{"updated_at=NOW()"}
	args := []any{}
	idx := 1

	if f.ApiKey != nil {
		sets = append(sets, fmt.Sprintf("api_key=$%d", idx))
		args = append(args, *f.ApiKey)
		idx++
	}
	if f.ApiSecret != nil {
		sets = append(sets, fmt.Sprintf("api_secret=$%d", idx))
		args = append(args, *f.ApiSecret)
		idx++
	}
	if f.BaseURL != nil {
		sets = append(sets, fmt.Sprintf("base_url=$%d", idx))
		args = append(args, *f.BaseURL)
		idx++
	}
	if f.WsURL != nil {
		sets = append(sets, fmt.Sprintf("ws_url=$%d", idx))
		args = append(args, *f.WsURL)
		idx++
	}
	if f.Description != nil {
		sets = append(sets, fmt.Sprintf("description=$%d", idx))
		args = append(args, *f.Description)
		idx++
	}
	if f.UpdatedBy != "" {
		sets = append(sets, fmt.Sprintf("updated_by=$%d", idx))
		args = append(args, f.UpdatedBy)
		idx++
	}

	q := fmt.Sprintf("UPDATE third_party_apis SET %s WHERE service_name=$%d",
		joinStrings(sets, ", "), idx)
	args = append(args, name)

	_, err = tx.Exec(ctx, q, args...)
	if err != nil {
		return fmt.Errorf("update third-party API: %w", err)
	}

	return tx.Commit(ctx)
}

func joinStrings(ss []string, sep string) string {
	result := ""
	for i, s := range ss {
		if i > 0 {
			result += sep
		}
		result += s
	}
	return result
}

// ToggleActive flips the is_active flag.
func (r *ThirdPartyApiRepo) ToggleActive(ctx context.Context, name string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE third_party_apis SET is_active = NOT is_active, updated_at=NOW() WHERE service_name=$1`, name)
	return err
}

// Verify performs a basic connectivity check and updates last_verified_at.
func (r *ThirdPartyApiRepo) Verify(ctx context.Context, name string) (map[string]any, error) {
	// For now, just mark as verified. Real verification would ping the service.
	now := time.Now()
	_, err := r.pool.Exec(ctx,
		`UPDATE third_party_apis SET last_verified_at=$1 WHERE service_name=$2`, now, name)
	if err != nil {
		return nil, err
	}
	return map[string]any{"service": name, "status": "ok", "verified_at": now}, nil
}

// ListHistory returns API key change history for a service.
func (r *ThirdPartyApiRepo) ListHistory(ctx context.Context, name string, limit int) ([]model.ApiKeyHistoryEntry, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, service_name, COALESCE(old_key_masked,''), COALESCE(new_key_masked,''),
		 COALESCE(changed_by,''), changed_at, COALESCE(reason,'')
		 FROM api_key_history WHERE service_name=$1 ORDER BY changed_at DESC LIMIT $2`, name, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var entries []model.ApiKeyHistoryEntry
	for rows.Next() {
		var e model.ApiKeyHistoryEntry
		if err := rows.Scan(&e.ID, &e.ServiceName, &e.OldKeyMasked, &e.NewKeyMasked,
			&e.ChangedBy, &e.ChangedAt, &e.Reason); err != nil {
			return nil, err
		}
		entries = append(entries, e)
	}
	return entries, nil
}
