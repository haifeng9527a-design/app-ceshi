package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type FeeRepo struct {
	pool *pgxpool.Pool
}

func NewFeeRepo(pool *pgxpool.Pool) *FeeRepo {
	return &FeeRepo{pool: pool}
}

func (r *FeeRepo) ListAll(ctx context.Context) ([]model.FeeTier, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, vip_level, maker_fee, taker_fee, min_volume, updated_at, COALESCE(updated_by,'')
		 FROM fee_tiers ORDER BY vip_level`)
	if err != nil {
		return nil, fmt.Errorf("list fee tiers: %w", err)
	}
	defer rows.Close()

	var tiers []model.FeeTier
	for rows.Next() {
		var t model.FeeTier
		if err := rows.Scan(&t.ID, &t.VipLevel, &t.MakerFee, &t.TakerFee, &t.MinVolume, &t.UpdatedAt, &t.UpdatedBy); err != nil {
			return nil, err
		}
		tiers = append(tiers, t)
	}
	return tiers, nil
}

func (r *FeeRepo) GetByLevel(ctx context.Context, level int) (*model.FeeTier, error) {
	var t model.FeeTier
	err := r.pool.QueryRow(ctx,
		`SELECT id, vip_level, maker_fee, taker_fee, min_volume, updated_at, COALESCE(updated_by,'')
		 FROM fee_tiers WHERE vip_level=$1`, level).
		Scan(&t.ID, &t.VipLevel, &t.MakerFee, &t.TakerFee, &t.MinVolume, &t.UpdatedAt, &t.UpdatedBy)
	if err != nil {
		return nil, fmt.Errorf("get fee tier %d: %w", level, err)
	}
	return &t, nil
}

func (r *FeeRepo) Upsert(ctx context.Context, tier model.FeeTier) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO fee_tiers (vip_level, maker_fee, taker_fee, min_volume, updated_at, updated_by)
		 VALUES ($1, $2, $3, $4, $5, $6)
		 ON CONFLICT (vip_level) DO UPDATE SET
		   maker_fee=EXCLUDED.maker_fee, taker_fee=EXCLUDED.taker_fee,
		   min_volume=EXCLUDED.min_volume, updated_at=EXCLUDED.updated_at, updated_by=EXCLUDED.updated_by`,
		tier.VipLevel, tier.MakerFee, tier.TakerFee, tier.MinVolume, time.Now(), tier.UpdatedBy)
	if err != nil {
		return fmt.Errorf("upsert fee tier: %w", err)
	}
	return nil
}

func FeeTierFromModel(vipLevel int, makerFee, takerFee, minVolume float64, updatedBy string) model.FeeTier {
	return model.FeeTier{
		VipLevel:  vipLevel,
		MakerFee:  makerFee,
		TakerFee:  takerFee,
		MinVolume: minVolume,
		UpdatedBy: updatedBy,
	}
}

func (r *FeeRepo) Delete(ctx context.Context, level int) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM fee_tiers WHERE vip_level=$1`, level)
	if err != nil {
		return fmt.Errorf("delete fee tier: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("fee tier level %d not found", level)
	}
	return nil
}
