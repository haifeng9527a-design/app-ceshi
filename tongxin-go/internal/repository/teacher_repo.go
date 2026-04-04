package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type TeacherRepo struct {
	pool *pgxpool.Pool
}

func NewTeacherRepo(pool *pgxpool.Pool) *TeacherRepo {
	return &TeacherRepo{pool: pool}
}

func (r *TeacherRepo) List(ctx context.Context, limit, offset int, status string) ([]model.Teacher, error) {
	if limit <= 0 {
		limit = 20
	}
	if status == "" {
		status = "approved"
	}

	rows, err := r.pool.Query(ctx, `
		SELECT t.user_id, t.status, COALESCE(t.bio,''), t.specialties, t.rating, t.follower_count,
		       t.created_at, t.updated_at,
		       COALESCE(u.display_name,''), COALESCE(u.avatar_url,'')
		FROM teachers t
		JOIN users u ON u.uid = t.user_id
		WHERE t.status = $1
		ORDER BY t.follower_count DESC, t.rating DESC
		LIMIT $2 OFFSET $3
	`, status, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var teachers []model.Teacher
	for rows.Next() {
		var t model.Teacher
		if err := rows.Scan(&t.UserID, &t.Status, &t.Bio, &t.Specialties, &t.Rating, &t.FollowerCount,
			&t.CreatedAt, &t.UpdatedAt, &t.DisplayName, &t.AvatarURL); err != nil {
			return nil, err
		}
		teachers = append(teachers, t)
	}
	return teachers, nil
}

func (r *TeacherRepo) GetByUserID(ctx context.Context, uid string) (*model.Teacher, error) {
	t := &model.Teacher{}
	err := r.pool.QueryRow(ctx, `
		SELECT t.user_id, t.status, COALESCE(t.bio,''), t.specialties, t.rating, t.follower_count,
		       t.created_at, t.updated_at,
		       COALESCE(u.display_name,''), COALESCE(u.avatar_url,'')
		FROM teachers t JOIN users u ON u.uid = t.user_id
		WHERE t.user_id = $1
	`, uid).Scan(&t.UserID, &t.Status, &t.Bio, &t.Specialties, &t.Rating, &t.FollowerCount,
		&t.CreatedAt, &t.UpdatedAt, &t.DisplayName, &t.AvatarURL)
	return t, err
}

func (r *TeacherRepo) Apply(ctx context.Context, uid string, req *model.ApplyTeacherRequest) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO teachers (user_id, bio, specialties, status)
		VALUES ($1, $2, $3, 'pending')
		ON CONFLICT (user_id) DO UPDATE SET bio = $2, specialties = $3, updated_at = NOW()
	`, uid, req.Bio, req.Specialties)
	return err
}

func (r *TeacherRepo) UpdateStatus(ctx context.Context, uid, status string) error {
	_, err := r.pool.Exec(ctx, `UPDATE teachers SET status = $2, updated_at = NOW() WHERE user_id = $1`, uid, status)
	return err
}

func (r *TeacherRepo) Update(ctx context.Context, uid string, bio string, specialties []string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE teachers SET bio = $2, specialties = $3, updated_at = NOW() WHERE user_id = $1
	`, uid, bio, specialties)
	return err
}

// Strategies
func (r *TeacherRepo) CreateStrategy(ctx context.Context, uid string, req *model.CreateStrategyRequest) (*model.Strategy, error) {
	s := &model.Strategy{TeacherID: uid}
	err := r.pool.QueryRow(ctx, `
		INSERT INTO teacher_strategies (teacher_id, title, content, images, category)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, created_at
	`, uid, req.Title, req.Content, req.Images, req.Category).Scan(&s.ID, &s.CreatedAt)
	if err != nil {
		return nil, err
	}
	s.Title = req.Title
	s.Content = req.Content
	s.Images = req.Images
	s.Category = req.Category
	return s, nil
}

func (r *TeacherRepo) ListStrategies(ctx context.Context, teacherID string, limit, offset int) ([]model.Strategy, error) {
	if limit <= 0 {
		limit = 20
	}
	rows, err := r.pool.Query(ctx, `
		SELECT id, teacher_id, title, content, COALESCE(images, '{}'), COALESCE(category,''), likes, created_at
		FROM teacher_strategies
		WHERE teacher_id = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, teacherID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var strategies []model.Strategy
	for rows.Next() {
		var s model.Strategy
		if err := rows.Scan(&s.ID, &s.TeacherID, &s.Title, &s.Content, &s.Images, &s.Category, &s.Likes, &s.CreatedAt); err != nil {
			return nil, err
		}
		strategies = append(strategies, s)
	}
	return strategies, nil
}

func (r *TeacherRepo) DeleteStrategy(ctx context.Context, strategyID, teacherID string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM teacher_strategies WHERE id = $1 AND teacher_id = $2`, strategyID, teacherID)
	return err
}

// Follow / Unfollow
func (r *TeacherRepo) Follow(ctx context.Context, teacherID, userID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO teacher_followers (teacher_id, user_id) VALUES ($1, $2)
		ON CONFLICT DO NOTHING
	`, teacherID, userID)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `
		UPDATE teachers SET follower_count = (SELECT COUNT(*) FROM teacher_followers WHERE teacher_id = $1)
		WHERE user_id = $1
	`, teacherID)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *TeacherRepo) Unfollow(ctx context.Context, teacherID, userID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `DELETE FROM teacher_followers WHERE teacher_id = $1 AND user_id = $2`, teacherID, userID)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `
		UPDATE teachers SET follower_count = (SELECT COUNT(*) FROM teacher_followers WHERE teacher_id = $1)
		WHERE user_id = $1
	`, teacherID)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *TeacherRepo) LikeStrategy(ctx context.Context, strategyID, userID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO strategy_likes (strategy_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING
	`, strategyID, userID)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `
		UPDATE teacher_strategies SET likes = (SELECT COUNT(*) FROM strategy_likes WHERE strategy_id = $1)
		WHERE id = $1
	`, strategyID)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}
