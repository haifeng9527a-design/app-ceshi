package repository

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type TraderStrategyRepo struct {
	pool *pgxpool.Pool
}

func NewTraderStrategyRepo(pool *pgxpool.Pool) *TraderStrategyRepo {
	return &TraderStrategyRepo{pool: pool}
}

// ── Create ──

func (r *TraderStrategyRepo) Create(ctx context.Context, authorID string, req *model.CreateTraderStrategyRequest) (*model.TraderStrategy, error) {
	status := req.Status
	if status == "" {
		status = "published"
	}
	s := &model.TraderStrategy{}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO trader_strategies (author_id, title, summary, content_html, cover_image, category, tags, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id, author_id, title, summary, content_html, cover_image, category, tags, status,
			views, likes, created_at, updated_at
	`, authorID, req.Title, req.Summary, req.ContentHTML, req.CoverImage, req.Category, req.Tags, status,
	).Scan(
		&s.ID, &s.AuthorID, &s.Title, &s.Summary, &s.ContentHTML, &s.CoverImage,
		&s.Category, &s.Tags, &s.Status, &s.Views, &s.Likes, &s.CreatedAt, &s.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("create strategy: %w", err)
	}
	return s, nil
}

// ── GetByID ──

func (r *TraderStrategyRepo) GetByID(ctx context.Context, id string) (*model.TraderStrategy, error) {
	s := &model.TraderStrategy{}
	err := r.pool.QueryRow(ctx, `
		SELECT s.id, s.author_id, s.title, s.summary, s.content_html, s.cover_image,
			s.category, s.tags, s.status, s.views, s.likes, s.created_at, s.updated_at,
			COALESCE(u.display_name,''), COALESCE(u.avatar_url,''), COALESCE(u.is_trader, false)
		FROM trader_strategies s
		JOIN users u ON u.uid = s.author_id
		WHERE s.id = $1
	`, id).Scan(
		&s.ID, &s.AuthorID, &s.Title, &s.Summary, &s.ContentHTML, &s.CoverImage,
		&s.Category, &s.Tags, &s.Status, &s.Views, &s.Likes, &s.CreatedAt, &s.UpdatedAt,
		&s.AuthorName, &s.AuthorAvatar, &s.IsTrader,
	)
	if err != nil {
		return nil, fmt.Errorf("get strategy: %w", err)
	}
	return s, nil
}

// ── Update ──

func (r *TraderStrategyRepo) Update(ctx context.Context, id, authorID string, req *model.UpdateTraderStrategyRequest) (*model.TraderStrategy, error) {
	sets := []string{}
	args := []any{}
	argIdx := 1

	addArg := func(col string, val any) {
		sets = append(sets, fmt.Sprintf("%s = $%d", col, argIdx))
		args = append(args, val)
		argIdx++
	}

	if req.Title != nil {
		addArg("title", *req.Title)
	}
	if req.Summary != nil {
		addArg("summary", *req.Summary)
	}
	if req.ContentHTML != nil {
		addArg("content_html", *req.ContentHTML)
	}
	if req.CoverImage != nil {
		addArg("cover_image", *req.CoverImage)
	}
	if req.Category != nil {
		addArg("category", *req.Category)
	}
	if req.Tags != nil {
		addArg("tags", req.Tags)
	}
	if req.Status != nil {
		addArg("status", *req.Status)
	}

	if len(sets) == 0 {
		return r.GetByID(ctx, id)
	}

	addArg("updated_at", time.Now())

	query := fmt.Sprintf(`
		UPDATE trader_strategies SET %s
		WHERE id = $%d AND author_id = $%d
		RETURNING id, author_id, title, summary, content_html, cover_image, category, tags, status,
			views, likes, created_at, updated_at
	`, strings.Join(sets, ", "), argIdx, argIdx+1)
	args = append(args, id, authorID)

	s := &model.TraderStrategy{}
	err := r.pool.QueryRow(ctx, query, args...).Scan(
		&s.ID, &s.AuthorID, &s.Title, &s.Summary, &s.ContentHTML, &s.CoverImage,
		&s.Category, &s.Tags, &s.Status, &s.Views, &s.Likes, &s.CreatedAt, &s.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("update strategy: %w", err)
	}
	return s, nil
}

// ── Delete ──

func (r *TraderStrategyRepo) Delete(ctx context.Context, id, authorID string) error {
	tag, err := r.pool.Exec(ctx, `
		DELETE FROM trader_strategies WHERE id = $1 AND author_id = $2
	`, id, authorID)
	if err != nil {
		return fmt.Errorf("delete strategy: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("strategy not found or not owned")
	}
	return nil
}

// ── ListByAuthor ──

func (r *TraderStrategyRepo) ListByAuthor(ctx context.Context, authorID, status string, limit, offset int) ([]model.TraderStrategy, int, error) {
	countQuery := `SELECT COUNT(*) FROM trader_strategies WHERE author_id = $1`
	countArgs := []any{authorID}
	if status != "" {
		countQuery += ` AND status = $2`
		countArgs = append(countArgs, status)
	}

	var total int
	if err := r.pool.QueryRow(ctx, countQuery, countArgs...).Scan(&total); err != nil {
		return nil, 0, err
	}

	listQuery := `
		SELECT s.id, s.author_id, s.title, s.summary, s.content_html, s.cover_image,
			s.category, s.tags, s.status, s.views, s.likes, s.created_at, s.updated_at,
			COALESCE(u.display_name,''), COALESCE(u.avatar_url,''), COALESCE(u.is_trader, false)
		FROM trader_strategies s
		JOIN users u ON u.uid = s.author_id
		WHERE s.author_id = $1`
	listArgs := []any{authorID}
	if status != "" {
		listQuery += ` AND s.status = $2 ORDER BY s.created_at DESC LIMIT $3 OFFSET $4`
		listArgs = append(listArgs, status, limit, offset)
	} else {
		listQuery += ` ORDER BY s.created_at DESC LIMIT $2 OFFSET $3`
		listArgs = append(listArgs, limit, offset)
	}

	rows, err := r.pool.Query(ctx, listQuery, listArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var items []model.TraderStrategy
	for rows.Next() {
		var s model.TraderStrategy
		if err := rows.Scan(
			&s.ID, &s.AuthorID, &s.Title, &s.Summary, &s.ContentHTML, &s.CoverImage,
			&s.Category, &s.Tags, &s.Status, &s.Views, &s.Likes, &s.CreatedAt, &s.UpdatedAt,
			&s.AuthorName, &s.AuthorAvatar, &s.IsTrader,
		); err != nil {
			return nil, 0, err
		}
		items = append(items, s)
	}
	return items, total, nil
}

// ── ListPublished (public feed) ──

func (r *TraderStrategyRepo) ListPublished(ctx context.Context, category string, limit, offset int) ([]model.TraderStrategy, int, error) {
	countQuery := `SELECT COUNT(*) FROM trader_strategies WHERE status = 'published'`
	countArgs := []any{}
	if category != "" {
		countQuery += ` AND category = $1`
		countArgs = append(countArgs, category)
	}

	var total int
	if err := r.pool.QueryRow(ctx, countQuery, countArgs...).Scan(&total); err != nil {
		return nil, 0, err
	}

	listQuery := `
		SELECT s.id, s.author_id, s.title, s.summary, '', s.cover_image,
			s.category, s.tags, s.status, s.views, s.likes, s.created_at, s.updated_at,
			COALESCE(u.display_name,''), COALESCE(u.avatar_url,''), COALESCE(u.is_trader, false)
		FROM trader_strategies s
		JOIN users u ON u.uid = s.author_id
		WHERE s.status = 'published'`
	listArgs := []any{}
	if category != "" {
		listQuery += ` AND s.category = $1 ORDER BY s.created_at DESC LIMIT $2 OFFSET $3`
		listArgs = append(listArgs, category, limit, offset)
	} else {
		listQuery += ` ORDER BY s.created_at DESC LIMIT $1 OFFSET $2`
		listArgs = append(listArgs, limit, offset)
	}

	rows, err := r.pool.Query(ctx, listQuery, listArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var items []model.TraderStrategy
	for rows.Next() {
		var s model.TraderStrategy
		if err := rows.Scan(
			&s.ID, &s.AuthorID, &s.Title, &s.Summary, &s.ContentHTML, &s.CoverImage,
			&s.Category, &s.Tags, &s.Status, &s.Views, &s.Likes, &s.CreatedAt, &s.UpdatedAt,
			&s.AuthorName, &s.AuthorAvatar, &s.IsTrader,
		); err != nil {
			return nil, 0, err
		}
		items = append(items, s)
	}
	return items, total, nil
}

// ── IncrementViews ──

func (r *TraderStrategyRepo) IncrementViews(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `UPDATE trader_strategies SET views = views + 1 WHERE id = $1`, id)
	return err
}

// ── Like / Unlike ──

func (r *TraderStrategyRepo) LikeStrategy(ctx context.Context, strategyID, userID string) (bool, error) {
	// Try insert, if conflict -> remove (toggle)
	tag, err := r.pool.Exec(ctx, `
		INSERT INTO trader_strategy_likes (strategy_id, user_id) VALUES ($1, $2)
		ON CONFLICT (strategy_id, user_id) DO NOTHING
	`, strategyID, userID)
	if err != nil {
		return false, err
	}

	if tag.RowsAffected() == 1 {
		// New like
		_, _ = r.pool.Exec(ctx, `UPDATE trader_strategies SET likes = likes + 1 WHERE id = $1`, strategyID)
		return true, nil
	}
	// Already liked -> unlike
	_, _ = r.pool.Exec(ctx, `DELETE FROM trader_strategy_likes WHERE strategy_id = $1 AND user_id = $2`, strategyID, userID)
	_, _ = r.pool.Exec(ctx, `UPDATE trader_strategies SET likes = GREATEST(likes - 1, 0) WHERE id = $1`, strategyID)
	return false, nil
}

// ── Check if user liked ──

func (r *TraderStrategyRepo) HasLiked(ctx context.Context, strategyID, userID string) bool {
	var exists bool
	_ = r.pool.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM trader_strategy_likes WHERE strategy_id = $1 AND user_id = $2)
	`, strategyID, userID).Scan(&exists)
	return exists
}
