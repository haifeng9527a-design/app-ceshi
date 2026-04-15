package repository

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	mathRand "math/rand"
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
		INSERT INTO users (uid, email, display_name, avatar_url, role, status, short_id, phone, bio, is_support_agent, password_hash, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		ON CONFLICT (uid) DO NOTHING
	`, u.UID, u.Email, u.DisplayName, u.AvatarURL, u.Role, u.Status, u.ShortID, u.Phone, u.Bio, u.IsSupportAgent, passwordHash, u.CreatedAt, u.UpdatedAt)
	return err
}

func (r *UserRepo) GetPasswordHash(ctx context.Context, email string) (string, string, error) {
	var uid, hash string
	err := r.pool.QueryRow(ctx, `
		SELECT uid, COALESCE(password_hash,'')
		FROM users
		WHERE email = $1 AND COALESCE(status,'active') = 'active'
	`, email).Scan(&uid, &hash)
	return uid, hash, err
}

func (r *UserRepo) GetPasswordHashByUID(ctx context.Context, uid string) (string, string, error) {
	var email, hash string
	err := r.pool.QueryRow(ctx, `
		SELECT email, COALESCE(password_hash,'')
		FROM users
		WHERE uid = $1
	`, uid).Scan(&email, &hash)
	return email, hash, err
}

func (r *UserRepo) GetByUID(ctx context.Context, uid string) (*model.User, error) {
	u := &model.User{}
	err := r.pool.QueryRow(ctx, `
		SELECT uid, email, display_name, COALESCE(avatar_url,''), COALESCE(role,'user'),
		       COALESCE(status,'active'), COALESCE(short_id,''), COALESCE(phone,''),
		       COALESCE(bio,''), COALESCE(is_trader, false), COALESCE(is_support_agent, false), COALESCE(allow_copy_trading, false),
		       trader_approved_at, COALESCE(vip_level, 0),
		       COALESCE(default_profit_share_rate, 0), COALESCE(lifetime_profit_shared_in, 0),
		       created_at, updated_at
		FROM users WHERE uid = $1
	`, uid).Scan(
		&u.UID, &u.Email, &u.DisplayName, &u.AvatarURL, &u.Role,
		&u.Status, &u.ShortID, &u.Phone, &u.Bio, &u.IsTrader, &u.IsSupportAgent, &u.AllowCopyTrading,
		&u.TraderApprovedAt, &u.VipLevel,
		&u.DefaultProfitShareRate, &u.LifetimeProfitSharedIn,
		&u.CreatedAt, &u.UpdatedAt,
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
		       COALESCE(bio,''), COALESCE(is_trader, false), COALESCE(is_support_agent, false), COALESCE(allow_copy_trading, false),
		       trader_approved_at, COALESCE(vip_level, 0),
		       COALESCE(default_profit_share_rate, 0), COALESCE(lifetime_profit_shared_in, 0),
		       created_at, updated_at
		FROM users WHERE email = $1
	`, email).Scan(
		&u.UID, &u.Email, &u.DisplayName, &u.AvatarURL, &u.Role,
		&u.Status, &u.ShortID, &u.Phone, &u.Bio, &u.IsTrader, &u.IsSupportAgent, &u.AllowCopyTrading,
		&u.TraderApprovedAt, &u.VipLevel,
		&u.DefaultProfitShareRate, &u.LifetimeProfitSharedIn,
		&u.CreatedAt, &u.UpdatedAt,
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

func (r *UserRepo) UpdatePasswordHash(ctx context.Context, uid, hash string) error {
	tag, err := r.pool.Exec(ctx, `UPDATE users SET password_hash = $2, updated_at = NOW() WHERE uid = $1`, uid, hash)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("user not found")
	}
	return nil
}

func (r *UserRepo) UpdateEmail(ctx context.Context, uid, email string) error {
	tag, err := r.pool.Exec(ctx, `UPDATE users SET email = $2, updated_at = NOW() WHERE uid = $1`, uid, email)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("user not found")
	}
	return nil
}

func (r *UserRepo) SetSupportAgent(ctx context.Context, uid string, enabled bool) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if enabled {
		if _, err := tx.Exec(ctx, `UPDATE users SET is_support_agent = false, updated_at = NOW() WHERE is_support_agent = true`); err != nil {
			return err
		}
	}

	if _, err := tx.Exec(ctx, `UPDATE users SET is_support_agent = $2, updated_at = NOW() WHERE uid = $1`, uid, enabled); err != nil {
		return err
	}

	if enabled {
		if _, err := tx.Exec(ctx, `
			UPDATE support_assignments
			SET status = 'transferred', updated_at = NOW()
			WHERE customer_uid = $1 AND status = 'active'
		`, uid); err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

func (r *UserRepo) GetDeleteAccountReasons(ctx context.Context, uid string) ([]string, error) {
	reasons := make([]string, 0, 6)

	var walletTotal float64
	if err := r.pool.QueryRow(ctx, `
		SELECT COALESCE(balance, 0) + COALESCE(frozen, 0)
		FROM wallets
		WHERE user_id = $1
	`, uid).Scan(&walletTotal); err == nil && walletTotal > 0 {
		reasons = append(reasons, "HAS_WALLET_BALANCE")
	}

	var openPositions int
	if err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM positions WHERE user_id = $1 AND status = 'open'
	`, uid).Scan(&openPositions); err != nil {
		return nil, err
	}
	if openPositions > 0 {
		reasons = append(reasons, "HAS_OPEN_POSITIONS")
	}

	var pendingOrders int
	if err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM orders WHERE user_id = $1 AND status = 'pending'
	`, uid).Scan(&pendingOrders); err != nil {
		return nil, err
	}
	if pendingOrders > 0 {
		reasons = append(reasons, "HAS_PENDING_ORDERS")
	}

	var ownsGroups int
	if err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM conversations WHERE type = 'group' AND created_by = $1
	`, uid).Scan(&ownsGroups); err != nil {
		return nil, err
	}
	if ownsGroups > 0 {
		reasons = append(reasons, "OWNS_GROUPS")
	}

	var activeCopyTrading int
	if err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM copy_trading
		WHERE (follower_id = $1 OR trader_id = $1)
		  AND status IN ('active', 'paused')
	`, uid).Scan(&activeCopyTrading); err != nil {
		return nil, err
	}
	if activeCopyTrading > 0 {
		reasons = append(reasons, "HAS_ACTIVE_COPY_TRADING")
	}

	user, err := r.GetByUID(ctx, uid)
	if err != nil {
		return nil, err
	}
	if user.IsSupportAgent {
		reasons = append(reasons, "IS_SUPPORT_AGENT")
	}
	if user.Role == "admin" {
		reasons = append(reasons, "IS_ADMIN")
	}

	return reasons, nil
}

func (r *UserRepo) SoftDeleteAccount(ctx context.Context, uid, archivedEmail string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `
		UPDATE support_assignments
		SET status = 'closed', updated_at = NOW()
		WHERE (customer_uid = $1 OR agent_uid = $1) AND status = 'active'
	`, uid); err != nil {
		return err
	}

	if _, err := tx.Exec(ctx, `
		UPDATE users
		SET
			email = $2,
			display_name = 'Deleted User',
			avatar_url = '',
			phone = '',
			bio = '',
			role = 'user',
			status = 'deleted',
			is_trader = false,
			is_support_agent = false,
			allow_copy_trading = false,
			password_hash = '',
			updated_at = NOW()
		WHERE uid = $1
	`, uid, archivedEmail); err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *UserRepo) Search(ctx context.Context, query string, limit int) ([]model.FriendProfile, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	rows, err := r.pool.Query(ctx, `
		SELECT uid, email, display_name, COALESCE(avatar_url,''), COALESCE(role,'user'),
		       COALESCE(status,'active'), COALESCE(short_id,'')
		FROM users
		WHERE (uid ILIKE $1 OR display_name ILIKE $1 OR email ILIKE $1 OR short_id ILIKE $1)
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
		if err := rows.Scan(&p.UserID, &p.Email, &p.DisplayName, &p.AvatarURL, &p.Role, &p.Status, &p.ShortID); err != nil {
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
		if err := rows.Scan(&p.UserID, &p.Email, &p.DisplayName, &p.AvatarURL, &p.Role, &p.Status, &p.ShortID); err != nil {
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
		       COALESCE(bio,''), COALESCE(is_trader, false), COALESCE(is_support_agent, false), COALESCE(allow_copy_trading, false),
		       trader_approved_at, COALESCE(vip_level, 0),
		       COALESCE(default_profit_share_rate, 0), COALESCE(lifetime_profit_shared_in, 0),
		       created_at, updated_at
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
			&u.Status, &u.ShortID, &u.Phone, &u.Bio, &u.IsTrader, &u.IsSupportAgent, &u.AllowCopyTrading,
			&u.TraderApprovedAt, &u.VipLevel,
			&u.DefaultProfitShareRate, &u.LifetimeProfitSharedIn,
			&u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, 0, err
		}
		users = append(users, u)
	}
	return users, total, nil
}

func (r *UserRepo) GetAdminStats(ctx context.Context) (totalUsers, adminCount, traderCount, pendingApps, activeUsers int, err error) {
	err = r.pool.QueryRow(ctx, `
		SELECT
			(SELECT COUNT(*) FROM users),
			(SELECT COUNT(*) FROM users WHERE role = 'admin'),
			(SELECT COUNT(*) FROM users WHERE is_trader = true),
			(SELECT COUNT(*) FROM trader_applications WHERE status = 'pending'),
			(SELECT COUNT(*) FROM users WHERE status = 'active')
	`).Scan(&totalUsers, &adminCount, &traderCount, &pendingApps, &activeUsers)
	return
}

func (r *UserRepo) ListByRole(ctx context.Context, role string) ([]model.User, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT uid, email, display_name, COALESCE(avatar_url,''), COALESCE(role,'user'),
		       COALESCE(status,'active'), COALESCE(short_id,''), COALESCE(phone,''),
		       COALESCE(bio,''), COALESCE(is_trader, false), COALESCE(is_support_agent, false), COALESCE(allow_copy_trading, false),
		       trader_approved_at, COALESCE(vip_level, 0),
		       COALESCE(default_profit_share_rate, 0), COALESCE(lifetime_profit_shared_in, 0),
		       created_at, updated_at
		From users WHERE role = $1 ORDER BY created_at DESC
	`, role)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []model.User
	for rows.Next() {
		var u model.User
		if err := rows.Scan(&u.UID, &u.Email, &u.DisplayName, &u.AvatarURL, &u.Role,
			&u.Status, &u.ShortID, &u.Phone, &u.Bio, &u.IsTrader, &u.IsSupportAgent, &u.AllowCopyTrading,
			&u.TraderApprovedAt, &u.VipLevel,
			&u.DefaultProfitShareRate, &u.LifetimeProfitSharedIn,
			&u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

func (r *UserRepo) ListSupportAgents(ctx context.Context) ([]model.User, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT uid, email, display_name, COALESCE(avatar_url,''), COALESCE(role,'user'),
		       COALESCE(status,'active'), COALESCE(short_id,''), COALESCE(phone,''),
		       COALESCE(bio,''), COALESCE(is_trader, false), COALESCE(is_support_agent, false), COALESCE(allow_copy_trading, false),
		       trader_approved_at, COALESCE(vip_level, 0),
		       COALESCE(default_profit_share_rate, 0), COALESCE(lifetime_profit_shared_in, 0),
		       created_at, updated_at
		FROM users
		WHERE is_support_agent = true
		ORDER BY updated_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []model.User
	for rows.Next() {
		var u model.User
		if err := rows.Scan(&u.UID, &u.Email, &u.DisplayName, &u.AvatarURL, &u.Role,
			&u.Status, &u.ShortID, &u.Phone, &u.Bio, &u.IsTrader, &u.IsSupportAgent, &u.AllowCopyTrading,
			&u.TraderApprovedAt, &u.VipLevel,
			&u.DefaultProfitShareRate, &u.LifetimeProfitSharedIn,
			&u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

func (r *UserRepo) SearchAll(ctx context.Context, query string, limit int) ([]model.User, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	rows, err := r.pool.Query(ctx, `
		SELECT uid, email, display_name, COALESCE(avatar_url,''), COALESCE(role,'user'),
		       COALESCE(status,'active'), COALESCE(short_id,''), COALESCE(phone,''),
		       COALESCE(bio,''), COALESCE(is_trader, false), COALESCE(is_support_agent, false), COALESCE(allow_copy_trading, false),
		       trader_approved_at, COALESCE(vip_level, 0),
		       COALESCE(default_profit_share_rate, 0), COALESCE(lifetime_profit_shared_in, 0),
		       created_at, updated_at
		FROM users
		WHERE display_name ILIKE $1 OR email ILIKE $1 OR short_id ILIKE $1
		ORDER BY created_at DESC
		LIMIT $2
	`, "%"+query+"%", limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []model.User
	for rows.Next() {
		var u model.User
		if err := rows.Scan(&u.UID, &u.Email, &u.DisplayName, &u.AvatarURL, &u.Role,
			&u.Status, &u.ShortID, &u.Phone, &u.Bio, &u.IsTrader, &u.IsSupportAgent, &u.AllowCopyTrading,
			&u.TraderApprovedAt, &u.VipLevel,
			&u.DefaultProfitShareRate, &u.LifetimeProfitSharedIn,
			&u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, nil
}

func (r *UserRepo) GetVipLevel(ctx context.Context, uid string) (int, error) {
	var level int
	err := r.pool.QueryRow(ctx, `SELECT COALESCE(vip_level, 0) FROM users WHERE uid = $1`, uid).Scan(&level)
	return level, err
}

func (r *UserRepo) UpdateVipLevel(ctx context.Context, uid string, level int) error {
	_, err := r.pool.Exec(ctx, `UPDATE users SET vip_level = $2, updated_at = NOW() WHERE uid = $1`, uid, level)
	return err
}

func generateShortID() string {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	b := make([]byte, 8)
	for i := range b {
		b[i] = chars[mathRand.Intn(len(chars))]
	}
	return fmt.Sprintf("TXN-%s", string(b))
}

func GenerateUID() string {
	// 10位纯数字随机 UID（1000000000-9999999999）
	n, err := rand.Int(rand.Reader, big.NewInt(9000000000))
	if err != nil {
		return fmt.Sprintf("%d", mathRand.Int63n(9000000000)+1000000000)
	}
	return fmt.Sprintf("%d", n.Int64()+1000000000)
}
