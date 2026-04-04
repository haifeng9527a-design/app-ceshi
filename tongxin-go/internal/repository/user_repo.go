package repository

import (
	"context"
	"fmt"
	"math/rand"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

type UserRepo struct {
	pool *pgxpool.Pool
}

func NewUserRepo(pool *pgxpool.Pool) *UserRepo {
	return &UserRepo{pool: pool}
}

func (r *UserRepo) Create(ctx context.Context, u *model.User, passwordHash string) error {
	if u.ShortID == "" {
		u.ShortID = generateShortID()
	}
	if u.Status == "" {
		u.Status = "active"
	}
	if u.Role == "" {
		u.Role = "user"
	}
	now := time.Now()
	u.CreatedAt = now
	u.UpdatedAt = now

	_, err := r.pool.Exec(ctx, `
		INSERT INTO users (uid, email, display_name, avatar_url, role, status, short_id, phone, bio, password_hash, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		ON CONFLICT (uid) DO NOTHING
	`, u.UID, u.Email, u.DisplayName, u.AvatarURL, u.Role, u.Status, u.ShortID, u.Phone, u.Bio, passwordHash, u.CreatedAt, u.UpdatedAt)
	return err
}

func (r *UserRepo) GetPasswordHash(ctx context.Context, email string) (string, string, error) {
	var uid, hash string
	err := r.pool.QueryRow(ctx, `SELECT uid, COALESCE(password_hash,'') FROM users WHERE email = $1`, email).Scan(&uid, &hash)
	return uid, hash, err
}

func (r *UserRepo) GetByUID(ctx context.Context, uid string) (*model.User, error) {
	u := &model.User{}
	err := r.pool.QueryRow(ctx, `
		SELECT uid, email, display_name, COALESCE(avatar_url,''), COALESCE(role,'user'),
		       COALESCE(status,'active'), COALESCE(short_id,''), COALESCE(phone,''),
		       COALESCE(bio,''), created_at, updated_at
		FROM users WHERE uid = $1
	`, uid).Scan(
		&u.UID, &u.Email, &u.DisplayName, &u.AvatarURL, &u.Role,
		&u.Status, &u.ShortID, &u.Phone, &u.Bio, &u.CreatedAt, &u.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return u, nil
}

func (r *UserRepo) GetByEmail(ctx context.Context, email string) (*model.User, error) {
	u := &model.User{}
	err := r.pool.QueryRow(ctx, `
		SELECT uid, email, display_name, COALESCE(avatar_url,''), COALESCE(role,'user'),
		       COALESCE(status,'active'), COALESCE(short_id,''), COALESCE(phone,''),
		       COALESCE(bio,''), created_at, updated_at
		FROM users WHERE email = $1
	`, email).Scan(
		&u.UID, &u.Email, &u.DisplayName, &u.AvatarURL, &u.Role,
		&u.Status, &u.ShortID, &u.Phone, &u.Bio, &u.CreatedAt, &u.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return u, nil
}

func (r *UserRepo) Update(ctx context.Context, uid string, req *model.UpdateProfileRequest) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE users SET
			display_name = COALESCE(NULLIF($2,''), display_name),
			avatar_url = COALESCE(NULLIF($3,''), avatar_url),
			bio = COALESCE(NULLIF($4,''), bio),
			phone = COALESCE(NULLIF($5,''), phone),
			updated_at = NOW()
		WHERE uid = $1
	`, uid, req.DisplayName, req.AvatarURL, req.Bio, req.Phone)
	return err
}

func (r *UserRepo) UpdateRole(ctx context.Context, uid, role string) error {
	_, err := r.pool.Exec(ctx, `UPDATE users SET role = $2, updated_at = NOW() WHERE uid = $1`, uid, role)
	return err
}

func (r *UserRepo) UpdateStatus(ctx context.Context, uid, status string) error {
	_, err := r.pool.Exec(ctx, `UPDATE users SET status = $2, updated_at = NOW() WHERE uid = $1`, uid, status)
	return err
}

func (r *UserRepo) Search(ctx context.Context, query string, limit int) ([]model.FriendProfile, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	rows, err := r.pool.Query(ctx, `
		SELECT uid, email, display_name, COALESCE(avatar_url,''), COALESCE(role,'user'),
		       COALESCE(status,'active'), COALESCE(short_id,'')
		FROM users
		WHERE (display_name ILIKE $1 OR email ILIKE $1 OR short_id ILIKE $1)
		  AND status = 'active'
		LIMIT $2
	`, "%"+query+"%", limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []model.FriendProfile
	for rows.Next() {
		var p model.FriendProfile
		if err := rows.Scan(&p.UID, &p.Email, &p.DisplayName, &p.AvatarURL, &p.Role, &p.Status, &p.ShortID); err != nil {
			return nil, err
		}
		results = append(results, p)
	}
	return results, nil
}

func (r *UserRepo) BatchGetProfiles(ctx context.Context, uids []string) ([]model.FriendProfile, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT uid, email, display_name, COALESCE(avatar_url,''), COALESCE(role,'user'),
		       COALESCE(status,'active'), COALESCE(short_id,'')
		FROM users WHERE uid = ANY($1)
	`, uids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []model.FriendProfile
	for rows.Next() {
		var p model.FriendProfile
		if err := rows.Scan(&p.UID, &p.Email, &p.DisplayName, &p.AvatarURL, &p.Role, &p.Status, &p.ShortID); err != nil {
			return nil, err
		}
		results = append(results, p)
	}
	return results, nil
}

func (r *UserRepo) ListAll(ctx context.Context, limit, offset int) ([]model.User, int, error) {
	var total int
	err := r.pool.QueryRow(ctx, `SELECT COUNT(*) FROM users`).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT uid, email, display_name, COALESCE(avatar_url,''), COALESCE(role,'user'),
		       COALESCE(status,'active'), COALESCE(short_id,''), COALESCE(phone,''),
		       COALESCE(bio,''), created_at, updated_at
		FROM users ORDER BY created_at DESC LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var users []model.User
	for rows.Next() {
		var u model.User
		if err := rows.Scan(&u.UID, &u.Email, &u.DisplayName, &u.AvatarURL, &u.Role,
			&u.Status, &u.ShortID, &u.Phone, &u.Bio, &u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, 0, err
		}
		users = append(users, u)
	}
	return users, total, nil
}

func generateShortID() string {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	b := make([]byte, 8)
	for i := range b {
		b[i] = chars[rand.Intn(len(chars))]
	}
	return fmt.Sprintf("TXN-%s", string(b))
}

func GenerateUID() string {
	const chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, 24)
	for i := range b {
		b[i] = chars[rand.Intn(len(chars))]
	}
	return fmt.Sprintf("u_%s", string(b))
}
