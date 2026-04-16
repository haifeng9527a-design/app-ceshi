package repository

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"tongxin-go/internal/model"
)

// ReferralRepo 封装邀请返佣 + 代理体系的所有 DB 操作。
type ReferralRepo struct {
	pool *pgxpool.Pool
}

func NewReferralRepo(pool *pgxpool.Pool) *ReferralRepo {
	return &ReferralRepo{pool: pool}
}

// ── 错误 ──

var (
	ErrInviterNotFound      = errors.New("inviter not found")
	ErrInviteCodeNotFound   = errors.New("invite code not found or inactive")
	ErrInviteCodeInvalid    = errors.New("invite code format invalid")
	ErrInviteCodeDuplicate  = errors.New("invite code already exists")
	ErrSelfInvite           = errors.New("cannot invite self")
	ErrCircularInvite       = errors.New("circular invite chain")
	ErrAlreadyBound         = errors.New("user already has an inviter")
	ErrNotDirectChild       = errors.New("target is not a direct invitee of caller")
	ErrRateExceedsParent    = errors.New("rate exceeds parent rate")
	ErrRateOutOfBounds      = errors.New("rate out of allowed bounds")
	ErrApplicationExists    = errors.New("user already has a pending application")
	ErrApplicationNotFound  = errors.New("agent application not found")
	ErrAlreadySettled       = errors.New("commission record for this inviter/date/kind already exists")
)

// ── 数据结构（跨 service 边界） ──

// UserRebateInfo 服务层做 cascade 时需要的用户关键字段。
type UserRebateInfo struct {
	UID              string
	InviterUID       *string
	MyRebateRate     float64
	IsAgent          bool
	IsFrozenReferral bool
	Depth            int // GetInviterChain 返回时填充：1 = 直接 inviter, 2 = inviter 的 inviter …
}

// AggregatedPending 日结扫描结果：(inviter, kind) 粒度聚合。
type AggregatedPending struct {
	InviterUID       string
	Kind             string
	EventIDs         []string
	TotalCommission  float64
	TotalFeeBase     float64
	EventCount       int
}

// InsertableEvent 一条待写入的 commission_event。
type InsertableEvent struct {
	InviteeUID          string
	InviterUID          string
	SourceInviterUID    *string
	Kind                string
	ProductType         string
	FeeBase             float64
	RateSnapshot        float64
	CommissionAmount    float64
	SourceTransactionID *string
	Status              string
}

// InviteeRow 我邀请的人列表一行。
type InviteeRow struct {
	UID          string     `json:"uid"`
	DisplayName  string     `json:"display_name"`
	Email        string     `json:"email"`
	CreatedAt    time.Time  `json:"created_at"`
	MyRebateRate float64    `json:"my_rebate_rate"`
	IsAgent      bool       `json:"is_agent"`
	LastActiveAt *time.Time `json:"last_active_at,omitempty"`
}

// ══════════════════════════════════════════════════════════════
// 1. users / inviter 链查询
// ══════════════════════════════════════════════════════════════

// GetUserRebateInfo 取一个用户的 cascade-相关字段。service 层在 RecordCommissionEvent
// 入口会先调此方法拿 invitee 的 inviter。
func (r *ReferralRepo) GetUserRebateInfo(ctx context.Context, uid string) (*UserRebateInfo, error) {
	var info UserRebateInfo
	info.UID = uid
	err := r.pool.QueryRow(ctx, `
		SELECT inviter_uid, my_rebate_rate, is_agent, is_frozen_referral
		FROM users WHERE uid = $1
	`, uid).Scan(&info.InviterUID, &info.MyRebateRate, &info.IsAgent, &info.IsFrozenReferral)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrInviterNotFound
		}
		return nil, fmt.Errorf("get user rebate info: %w", err)
	}
	return &info, nil
}

// GetInviterChain 返回 uid 的祖先链（直接 inviter → inviter 的 inviter → …），
// 最多 maxDepth 层。单次 SQL（递归 CTE），避免 N+1。
// 结果按 depth 升序：Result[0].Depth == 1（直接 inviter）。
func (r *ReferralRepo) GetInviterChain(ctx context.Context, uid string, maxDepth int) ([]UserRebateInfo, error) {
	if maxDepth <= 0 {
		return nil, nil
	}
	rows, err := r.pool.Query(ctx, `
		WITH RECURSIVE chain AS (
		  SELECT uid, inviter_uid, my_rebate_rate, is_agent, is_frozen_referral, 0 AS depth
		  FROM users WHERE uid = $1
		  UNION ALL
		  SELECT u.uid, u.inviter_uid, u.my_rebate_rate, u.is_agent, u.is_frozen_referral, c.depth + 1
		  FROM users u JOIN chain c ON u.uid = c.inviter_uid
		  WHERE c.depth < $2
		)
		SELECT uid, inviter_uid, my_rebate_rate, is_agent, is_frozen_referral, depth
		FROM chain
		WHERE depth > 0
		ORDER BY depth ASC
	`, uid, maxDepth)
	if err != nil {
		return nil, fmt.Errorf("get inviter chain: %w", err)
	}
	defer rows.Close()

	var result []UserRebateInfo
	for rows.Next() {
		var n UserRebateInfo
		if err := rows.Scan(&n.UID, &n.InviterUID, &n.MyRebateRate, &n.IsAgent, &n.IsFrozenReferral, &n.Depth); err != nil {
			return nil, fmt.Errorf("scan inviter chain row: %w", err)
		}
		result = append(result, n)
	}
	return result, rows.Err()
}

// ══════════════════════════════════════════════════════════════
// 2. invite_links CRUD
// ══════════════════════════════════════════════════════════════

func (r *ReferralRepo) CreateInviteLink(ctx context.Context, ownerUID, code, name string, landingPage *string) (*model.InviteLink, error) {
	var l model.InviteLink
	err := r.pool.QueryRow(ctx, `
		INSERT INTO invite_links (owner_uid, code, name, landing_page, is_active)
		VALUES ($1, $2, $3, $4, true)
		RETURNING id::text, owner_uid, code, landing_page, name, is_active,
		          registration_count, created_at, updated_at
	`, ownerUID, code, name, landingPage).Scan(
		&l.ID, &l.OwnerUID, &l.Code, &l.LandingPage, &l.Name, &l.IsActive,
		&l.RegistrationCount, &l.CreatedAt, &l.UpdatedAt,
	)
	if err != nil {
		// 23505 = unique_violation (code taken)
		if strings.Contains(err.Error(), "23505") {
			return nil, ErrInviteCodeDuplicate
		}
		// 23514 = check_violation (格式不匹配)
		if strings.Contains(err.Error(), "chk_invite_links_code_format") {
			return nil, ErrInviteCodeInvalid
		}
		return nil, fmt.Errorf("create invite link: %w", err)
	}
	return &l, nil
}

func (r *ReferralRepo) GetLinkByCode(ctx context.Context, code string) (*model.InviteLink, error) {
	var l model.InviteLink
	err := r.pool.QueryRow(ctx, `
		SELECT id::text, owner_uid, code, landing_page, name, is_active,
		       registration_count, created_at, updated_at
		FROM invite_links WHERE code = $1
	`, code).Scan(
		&l.ID, &l.OwnerUID, &l.Code, &l.LandingPage, &l.Name, &l.IsActive,
		&l.RegistrationCount, &l.CreatedAt, &l.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrInviteCodeNotFound
		}
		return nil, fmt.Errorf("get link by code: %w", err)
	}
	return &l, nil
}

func (r *ReferralRepo) ListLinksByOwner(ctx context.Context, ownerUID string) ([]*model.InviteLink, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id::text, owner_uid, code, landing_page, name, is_active,
		       registration_count, created_at, updated_at
		FROM invite_links WHERE owner_uid = $1 ORDER BY created_at ASC
	`, ownerUID)
	if err != nil {
		return nil, fmt.Errorf("list links: %w", err)
	}
	defer rows.Close()

	var out []*model.InviteLink
	for rows.Next() {
		var l model.InviteLink
		if err := rows.Scan(
			&l.ID, &l.OwnerUID, &l.Code, &l.LandingPage, &l.Name, &l.IsActive,
			&l.RegistrationCount, &l.CreatedAt, &l.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan link: %w", err)
		}
		out = append(out, &l)
	}
	return out, rows.Err()
}

// DisableLink 禁用（不删除，保留审计）。只能禁用自己的链接。
func (r *ReferralRepo) DisableLink(ctx context.Context, ownerUID, linkID string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE invite_links SET is_active = false, updated_at = NOW()
		WHERE id = $1::uuid AND owner_uid = $2
	`, linkID, ownerUID)
	if err != nil {
		return fmt.Errorf("disable link: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrInviteCodeNotFound
	}
	return nil
}

// IncrementRegistrationCount 原子 +1。在 Register 成功绑定邀请时调用。
func (r *ReferralRepo) IncrementRegistrationCount(ctx context.Context, code string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE invite_links SET registration_count = registration_count + 1, updated_at = NOW()
		WHERE code = $1
	`, code)
	return err
}

// EnsureDefaultLink 懒生成：如果用户还没有默认链接（short_id 不合法的老用户）则创建一条
// 随机 code。幂等。
func (r *ReferralRepo) EnsureDefaultLink(ctx context.Context, ownerUID string) (*model.InviteLink, error) {
	// 先看是否已有任何链接
	existing, err := r.ListLinksByOwner(ctx, ownerUID)
	if err != nil {
		return nil, err
	}
	if len(existing) > 0 {
		return existing[0], nil
	}

	// 尝试用 short_id。失败（已被占或格式不合法）则退回随机 code。
	var shortID *string
	if err := r.pool.QueryRow(ctx, `SELECT short_id FROM users WHERE uid = $1`, ownerUID).Scan(&shortID); err != nil {
		return nil, fmt.Errorf("read short_id: %w", err)
	}
	if shortID != nil && *shortID != "" {
		if l, cErr := r.CreateInviteLink(ctx, ownerUID, *shortID, "Default", nil); cErr == nil {
			return l, nil
		}
		// fall through to random
	}
	// 随机 code：8位大写字母+数字（类似 Bitget/Bybit 风格）
	randomCode := generateInviteCode(ownerUID)
	return r.CreateInviteLink(ctx, ownerUID, randomCode, "Default", nil)
}

// generateInviteCode 生成 8 位大写字母+数字的邀请码。
// 基于 UID 做确定性 hash，同一用户每次生成结果一致。
func generateInviteCode(uid string) string {
	const charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // 去掉易混淆的 I/O/0/1
	// 用 UID 的 hash 作为种子，确保同 UID 生成同码
	h := uint64(0)
	for _, c := range uid {
		h = h*31 + uint64(c)
	}
	code := make([]byte, 8)
	for i := range code {
		code[i] = charset[h%uint64(len(charset))]
		h = h / uint64(len(charset))
		if h == 0 {
			h = uint64(i+1)*7 + 42 // fallback entropy
		}
	}
	return string(code)
}

// ══════════════════════════════════════════════════════════════
// 3. users rate / agent flags
// ══════════════════════════════════════════════════════════════

// SetUserInviter 注册成功后绑定 inviter（永久）。CHECK 约束保证 inviter != self。
// 如果用户已有 inviter，返回 ErrAlreadyBound。
func (r *ReferralRepo) SetUserInviter(ctx context.Context, uid, inviterUID string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE users SET inviter_uid = $2, updated_at = NOW()
		WHERE uid = $1 AND inviter_uid IS NULL
	`, uid, inviterUID)
	if err != nil {
		return fmt.Errorf("set inviter: %w", err)
	}
	if tag.RowsAffected() == 0 {
		// 可能是 uid 不存在 or 已经绑定
		return ErrAlreadyBound
	}
	return nil
}

// SetUserRate admin 专用：无条件修改 rate（trigger 会自动处理 rate > 0.20 → is_agent=true）。
func (r *ReferralRepo) SetUserRate(ctx context.Context, uid string, rate float64) error {
	if rate < 0 || rate > 1.0 {
		return ErrRateOutOfBounds
	}
	tag, err := r.pool.Exec(ctx, `
		UPDATE users SET my_rebate_rate = $2::numeric, updated_at = NOW() WHERE uid = $1
	`, uid, rate)
	if err != nil {
		return fmt.Errorf("set user rate: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrInviterNotFound
	}
	return nil
}

// SetSubAgentRate 代理专用：给直接下级改 rate。校验：
//  1. targetUID.inviter == parentUID
//  2. 0 <= rate <= parent.my_rebate_rate
// 一条 UPDATE 带 WHERE 条件子查询完成原子校验。
func (r *ReferralRepo) SetSubAgentRate(ctx context.Context, parentUID, targetUID string, rate float64) error {
	if rate < 0 || rate > 1.0 {
		return ErrRateOutOfBounds
	}
	tag, err := r.pool.Exec(ctx, `
		UPDATE users target
		SET my_rebate_rate = $3::numeric, updated_at = NOW()
		FROM users parent
		WHERE target.uid = $2
		  AND parent.uid = $1
		  AND target.inviter_uid = parent.uid
		  AND $3::numeric <= parent.my_rebate_rate
		  AND $3::numeric >= 0
	`, parentUID, targetUID, rate)
	if err != nil {
		return fmt.Errorf("set sub-agent rate: %w", err)
	}
	if tag.RowsAffected() == 0 {
		// 区分 NotDirectChild vs RateExceedsParent：再做一次探测查询
		var isChild bool
		var parentRate float64
		qErr := r.pool.QueryRow(ctx, `
			SELECT EXISTS(SELECT 1 FROM users WHERE uid = $1 AND inviter_uid = $2),
			       COALESCE((SELECT my_rebate_rate FROM users WHERE uid = $2), 0)
		`, targetUID, parentUID).Scan(&isChild, &parentRate)
		if qErr != nil {
			return fmt.Errorf("probe sub-agent: %w", qErr)
		}
		if !isChild {
			return ErrNotDirectChild
		}
		if rate > parentRate {
			return ErrRateExceedsParent
		}
		return ErrInviterNotFound
	}
	return nil
}

// PromoteSubAgent：代理把直接下级升级为子代理（is_agent=true）+ 设 rate（≤ parent.rate）。
// 一个事务完成：校验关系 → UPDATE。
func (r *ReferralRepo) PromoteSubAgent(ctx context.Context, parentUID, targetUID string, rate float64) error {
	if rate < 0 || rate > 1.0 {
		return ErrRateOutOfBounds
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("promote begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	var isChild bool
	var parentRate float64
	if err := tx.QueryRow(ctx, `
		SELECT EXISTS(SELECT 1 FROM users WHERE uid = $1 AND inviter_uid = $2),
		       COALESCE((SELECT my_rebate_rate FROM users WHERE uid = $2), 0)
	`, targetUID, parentUID).Scan(&isChild, &parentRate); err != nil {
		return fmt.Errorf("promote probe: %w", err)
	}
	if !isChild {
		return ErrNotDirectChild
	}
	if rate > parentRate {
		return ErrRateExceedsParent
	}

	if _, err := tx.Exec(ctx, `
		UPDATE users
		SET is_agent = true,
		    my_rebate_rate = $2::numeric,
		    agent_approved_at = COALESCE(agent_approved_at, NOW()),
		    updated_at = NOW()
		WHERE uid = $1
	`, targetUID, rate); err != nil {
		return fmt.Errorf("promote update: %w", err)
	}

	return tx.Commit(ctx)
}

// SetFrozenReferral admin-only: 风控冻结/解冻。
func (r *ReferralRepo) SetFrozenReferral(ctx context.Context, uid string, frozen bool) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE users SET is_frozen_referral = $2, updated_at = NOW() WHERE uid = $1
	`, uid, frozen)
	if err != nil {
		return fmt.Errorf("set frozen: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrInviterNotFound
	}
	return nil
}

// ══════════════════════════════════════════════════════════════
// 4. commission_events
// ══════════════════════════════════════════════════════════════

// InsertCommissionEvents 批量写入。一次 SQL（multi-VALUES），N≤11（1 direct + 10 override）。
// 比 N 次独立 INSERT 省 N-1 次 RTT。
func (r *ReferralRepo) InsertCommissionEvents(ctx context.Context, events []InsertableEvent) error {
	if len(events) == 0 {
		return nil
	}

	valueGroups := make([]string, 0, len(events))
	args := make([]interface{}, 0, len(events)*10)
	for i, e := range events {
		base := i * 10
		valueGroups = append(valueGroups, fmt.Sprintf(
			"($%d, $%d, $%d, $%d, $%d, $%d::numeric, $%d::numeric, $%d::numeric, $%d, $%d)",
			base+1, base+2, base+3, base+4, base+5, base+6, base+7, base+8, base+9, base+10,
		))
		args = append(args,
			e.InviteeUID, e.InviterUID, e.SourceInviterUID, e.Kind, e.ProductType,
			e.FeeBase, e.RateSnapshot, e.CommissionAmount, e.SourceTransactionID, e.Status,
		)
	}

	query := `INSERT INTO commission_events
	  (invitee_uid, inviter_uid, source_inviter_uid, kind, product_type,
	   fee_base, rate_snapshot, commission_amount, source_transaction_id, status)
	  VALUES ` + strings.Join(valueGroups, ", ")

	if _, err := r.pool.Exec(ctx, query, args...); err != nil {
		return fmt.Errorf("insert commission events: %w", err)
	}
	return nil
}

// ListPendingEventsForDate 日结扫描入口：扫 target_date (UTC) 当日所有 pending events，
// 按 (inviter_uid, kind) 聚合。返回一组 AggregatedPending，service 遍历各组调
// SettleDailyForInviter。
func (r *ReferralRepo) ListPendingEventsForDate(ctx context.Context, date time.Time) ([]AggregatedPending, error) {
	// 用 DATE 类型精确匹配 UTC 日历日。pgx 对 time.Time → DATE 有自动转换。
	rows, err := r.pool.Query(ctx, `
		SELECT inviter_uid,
		       kind,
		       ARRAY_AGG(event_id::text ORDER BY created_at)  AS event_ids,
		       SUM(commission_amount)::numeric(20,8)          AS total_commission,
		       SUM(fee_base)::numeric(20,8)                   AS total_fee_base,
		       COUNT(*)                                       AS event_count
		FROM commission_events
		WHERE status = 'pending'
		  AND (created_at AT TIME ZONE 'UTC')::date = $1::date
		GROUP BY inviter_uid, kind
		ORDER BY inviter_uid, kind
	`, date)
	if err != nil {
		return nil, fmt.Errorf("list pending events: %w", err)
	}
	defer rows.Close()

	var out []AggregatedPending
	for rows.Next() {
		var a AggregatedPending
		if err := rows.Scan(&a.InviterUID, &a.Kind, &a.EventIDs,
			&a.TotalCommission, &a.TotalFeeBase, &a.EventCount); err != nil {
			return nil, fmt.Errorf("scan pending: %w", err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// SettleDailyForInviter 对单一 (inviter, kind, date) 组执行结算，单事务原子完成：
//   1) UPSERT wallets （ensure 存在）
//   2) UPDATE wallets.balance += payout
//   3) INSERT wallet_transactions
//   4) INSERT commission_records（幂等：UNIQUE (inviter, date, kind) → 冲突 = 已结）
//   5) UPDATE commission_events.status → 'settled'（WHERE status='pending' 保幂等）
//   6) UPDATE users.lifetime_commission_earned += payout
//
// capUSD ≤ 0 代表无上限。
// 幂等性：如果 commission_records 已有同键，直接返回 ErrAlreadySettled（不重复入账）。
func (r *ReferralRepo) SettleDailyForInviter(
	ctx context.Context,
	inviterUID string,
	kind string,
	date time.Time,
	eventIDs []string,
	totalCommission float64,
	totalFeeBase float64,
	capUSD float64,
) (*model.CommissionRecord, error) {
	if len(eventIDs) == 0 {
		return nil, fmt.Errorf("no events")
	}
	if kind != model.CommissionKindDirect && kind != model.CommissionKindOverride {
		return nil, fmt.Errorf("invalid kind: %s", kind)
	}

	// 计算实际入账额 + 状态
	payout := totalCommission
	capped := false
	if capUSD > 0 && payout > capUSD {
		payout = capUSD
		capped = true
	}
	status := model.CommissionRecordStatusSettled
	if capped {
		status = model.CommissionRecordStatusCapped
	}

	txType := "referral_commission_in"
	if kind == model.CommissionKindOverride {
		txType = "agent_override_in"
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("settle begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// 1) ensure wallet
	if _, err := tx.Exec(ctx, `
		INSERT INTO wallets (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING
	`, inviterUID); err != nil {
		return nil, fmt.Errorf("ensure wallet: %w", err)
	}

	// 2) balance 加法（列锚定，无需 ::numeric）
	var balanceAfter float64
	if err := tx.QueryRow(ctx, `
		UPDATE wallets SET balance = balance + $2, updated_at = NOW()
		WHERE user_id = $1
		RETURNING balance
	`, inviterUID, payout).Scan(&balanceAfter); err != nil {
		return nil, fmt.Errorf("update balance: %w", err)
	}

	// 3) wallet_transaction
	note := fmt.Sprintf("Referral commission (%s, %d events, %s)", kind, len(eventIDs), date.Format("2006-01-02"))
	if _, err := tx.Exec(ctx, `
		INSERT INTO wallet_transactions (user_id, type, amount, balance_after, note)
		VALUES ($1, $2, $3::numeric, $4::numeric, $5)
	`, inviterUID, txType, payout, balanceAfter, note); err != nil {
		return nil, fmt.Errorf("insert wallet tx: %w", err)
	}

	// 4) commission_records（幂等：UNIQUE constraint 冲突 → 回滚返回 ErrAlreadySettled）
	var rec model.CommissionRecord
	err = tx.QueryRow(ctx, `
		INSERT INTO commission_records (inviter_uid, period_date, kind, total_fee_base,
		                                 commission_amount, event_count, status)
		VALUES ($1, $2::date, $3, $4::numeric, $5::numeric, $6, $7)
		RETURNING id::text, inviter_uid, period_date, kind, total_fee_base,
		          commission_amount, event_count, status, created_at
	`, inviterUID, date, kind, totalFeeBase, payout, len(eventIDs), status).Scan(
		&rec.ID, &rec.InviterUID, &rec.PeriodDate, &rec.Kind, &rec.TotalFeeBase,
		&rec.CommissionAmount, &rec.EventCount, &rec.Status, &rec.CreatedAt,
	)
	if err != nil {
		if strings.Contains(err.Error(), "uq_cr_inviter_date_kind") {
			return nil, ErrAlreadySettled
		}
		return nil, fmt.Errorf("insert commission record: %w", err)
	}

	// 5) 事件标 settled（WHERE status='pending' 保幂等，已 settled 的不重复改）
	if _, err := tx.Exec(ctx, `
		UPDATE commission_events
		SET status = 'settled', settled_at = NOW()
		WHERE event_id = ANY($1::uuid[]) AND status = 'pending'
	`, eventIDs); err != nil {
		return nil, fmt.Errorf("mark events settled: %w", err)
	}

	// 6) users.lifetime_commission_earned
	if _, err := tx.Exec(ctx, `
		UPDATE users SET lifetime_commission_earned = lifetime_commission_earned + $2, updated_at = NOW()
		WHERE uid = $1
	`, inviterUID, payout); err != nil {
		return nil, fmt.Errorf("update lifetime: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("settle commit: %w", err)
	}
	return &rec, nil
}

// ══════════════════════════════════════════════════════════════
// 5. agent_applications
// ══════════════════════════════════════════════════════════════

func (r *ReferralRepo) CreateAgentApplication(
	ctx context.Context, applicantUID, channelDesc string,
	audienceSize *int, contactInfo json.RawMessage,
) (*model.AgentApplication, error) {
	if len(contactInfo) == 0 {
		contactInfo = json.RawMessage(`{}`)
	}
	var a model.AgentApplication
	err := r.pool.QueryRow(ctx, `
		INSERT INTO agent_applications
		  (applicant_uid, status, channel_description, audience_size, contact_info)
		VALUES ($1, 'pending', $2, $3, $4::jsonb)
		RETURNING id::text, applicant_uid, status, channel_description, audience_size,
		          contact_info, proposed_rate, review_note, submitted_at, reviewed_at, reviewed_by
	`, applicantUID, channelDesc, audienceSize, contactInfo).Scan(
		&a.ID, &a.ApplicantUID, &a.Status, &a.ChannelDescription, &a.AudienceSize,
		&a.ContactInfo, &a.ProposedRate, &a.ReviewNote, &a.SubmittedAt, &a.ReviewedAt, &a.ReviewedBy,
	)
	if err != nil {
		if strings.Contains(err.Error(), "uq_aa_applicant_pending") {
			return nil, ErrApplicationExists
		}
		return nil, fmt.Errorf("create agent application: %w", err)
	}
	return &a, nil
}

func (r *ReferralRepo) GetAgentApplication(ctx context.Context, id string) (*model.AgentApplication, error) {
	var a model.AgentApplication
	err := r.pool.QueryRow(ctx, `
		SELECT id::text, applicant_uid, status, channel_description, audience_size,
		       contact_info, proposed_rate, review_note, submitted_at, reviewed_at, reviewed_by
		FROM agent_applications WHERE id = $1::uuid
	`, id).Scan(
		&a.ID, &a.ApplicantUID, &a.Status, &a.ChannelDescription, &a.AudienceSize,
		&a.ContactInfo, &a.ProposedRate, &a.ReviewNote, &a.SubmittedAt, &a.ReviewedAt, &a.ReviewedBy,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrApplicationNotFound
		}
		return nil, fmt.Errorf("get agent application: %w", err)
	}
	return &a, nil
}

// GetActivePendingApplication 检查 applicant 是否已有 pending 申请（前端防重复提交）
func (r *ReferralRepo) GetActivePendingApplication(ctx context.Context, applicantUID string) (*model.AgentApplication, error) {
	var a model.AgentApplication
	err := r.pool.QueryRow(ctx, `
		SELECT id::text, applicant_uid, status, channel_description, audience_size,
		       contact_info, proposed_rate, review_note, submitted_at, reviewed_at, reviewed_by
		FROM agent_applications
		WHERE applicant_uid = $1 AND status = 'pending'
		LIMIT 1
	`, applicantUID).Scan(
		&a.ID, &a.ApplicantUID, &a.Status, &a.ChannelDescription, &a.AudienceSize,
		&a.ContactInfo, &a.ProposedRate, &a.ReviewNote, &a.SubmittedAt, &a.ReviewedAt, &a.ReviewedBy,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil // 没有 = 正常
		}
		return nil, fmt.Errorf("get active application: %w", err)
	}
	return &a, nil
}

func (r *ReferralRepo) ListAgentApplications(ctx context.Context, status string, limit, offset int) ([]*model.AgentApplication, error) {
	var rows pgx.Rows
	var err error
	if status == "" {
		rows, err = r.pool.Query(ctx, `
			SELECT id::text, applicant_uid, status, channel_description, audience_size,
			       contact_info, proposed_rate, review_note, submitted_at, reviewed_at, reviewed_by
			FROM agent_applications
			ORDER BY submitted_at DESC
			LIMIT $1 OFFSET $2
		`, limit, offset)
	} else {
		rows, err = r.pool.Query(ctx, `
			SELECT id::text, applicant_uid, status, channel_description, audience_size,
			       contact_info, proposed_rate, review_note, submitted_at, reviewed_at, reviewed_by
			FROM agent_applications
			WHERE status = $3
			ORDER BY submitted_at DESC
			LIMIT $1 OFFSET $2
		`, limit, offset, status)
	}
	if err != nil {
		return nil, fmt.Errorf("list applications: %w", err)
	}
	defer rows.Close()

	var out []*model.AgentApplication
	for rows.Next() {
		var a model.AgentApplication
		if err := rows.Scan(
			&a.ID, &a.ApplicantUID, &a.Status, &a.ChannelDescription, &a.AudienceSize,
			&a.ContactInfo, &a.ProposedRate, &a.ReviewNote, &a.SubmittedAt, &a.ReviewedAt, &a.ReviewedBy,
		); err != nil {
			return nil, fmt.Errorf("scan application: %w", err)
		}
		out = append(out, &a)
	}
	return out, rows.Err()
}

// ApproveApplication 批准申请（tx）：
//   UPDATE agent_applications → approved
//   UPDATE users.is_agent=true + my_rebate_rate=proposed_rate + agent_approved_at=NOW()
// 一个事务完成。
func (r *ReferralRepo) ApproveApplication(
	ctx context.Context, appID, reviewerUID string, proposedRate float64, note string,
) (*model.AgentApplication, error) {
	if proposedRate < 0 || proposedRate > 1.0 {
		return nil, ErrRateOutOfBounds
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("approve begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	var a model.AgentApplication
	err = tx.QueryRow(ctx, `
		UPDATE agent_applications
		SET status = 'approved',
		    reviewed_at = NOW(),
		    reviewed_by = $2,
		    proposed_rate = $3::numeric,
		    review_note = $4
		WHERE id = $1::uuid AND status = 'pending'
		RETURNING id::text, applicant_uid, status, channel_description, audience_size,
		          contact_info, proposed_rate, review_note, submitted_at, reviewed_at, reviewed_by
	`, appID, reviewerUID, proposedRate, note).Scan(
		&a.ID, &a.ApplicantUID, &a.Status, &a.ChannelDescription, &a.AudienceSize,
		&a.ContactInfo, &a.ProposedRate, &a.ReviewNote, &a.SubmittedAt, &a.ReviewedAt, &a.ReviewedBy,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrApplicationNotFound
		}
		return nil, fmt.Errorf("approve update app: %w", err)
	}

	// 升级 user
	if _, err := tx.Exec(ctx, `
		UPDATE users
		SET is_agent = true,
		    my_rebate_rate = $2::numeric,
		    agent_approved_at = COALESCE(agent_approved_at, NOW()),
		    updated_at = NOW()
		WHERE uid = $1
	`, a.ApplicantUID, proposedRate); err != nil {
		return nil, fmt.Errorf("approve update user: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("approve commit: %w", err)
	}
	return &a, nil
}

func (r *ReferralRepo) RejectApplication(ctx context.Context, appID, reviewerUID, note string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE agent_applications
		SET status = 'rejected', reviewed_at = NOW(), reviewed_by = $2, review_note = $3
		WHERE id = $1::uuid AND status = 'pending'
	`, appID, reviewerUID, note)
	if err != nil {
		return fmt.Errorf("reject: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrApplicationNotFound
	}
	return nil
}

// ══════════════════════════════════════════════════════════════
// 6. DLQ
// ══════════════════════════════════════════════════════════════

func (r *ReferralRepo) WriteToDLQ(
	ctx context.Context,
	inviteeUID string,
	feeBase float64,
	productType string,
	sourceTxID *string,
	payload json.RawMessage,
	errText string,
	retryCount int,
) error {
	if len(payload) == 0 {
		payload = json.RawMessage(`{}`)
	}
	_, err := r.pool.Exec(ctx, `
		INSERT INTO commission_events_dlq
		  (invitee_uid, fee_base, product_type, source_transaction_id, payload, error_text, retry_count)
		VALUES ($1, $2::numeric, $3, $4, $5::jsonb, $6, $7)
	`, inviteeUID, feeBase, productType, sourceTxID, payload, errText, retryCount)
	if err != nil {
		return fmt.Errorf("write to dlq: %w", err)
	}
	return nil
}

// ══════════════════════════════════════════════════════════════
// 7. Dashboard / 用户查询
// ══════════════════════════════════════════════════════════════

// GetOverviewMetrics 「我的邀请」首页数据。lifetime 从 users 列直接读；本月聚合 commission_records。
func (r *ReferralRepo) GetOverviewMetrics(ctx context.Context, uid string) (
	lifetime, thisMonth float64, inviteesCount int, err error,
) {
	err = r.pool.QueryRow(ctx, `
		SELECT
		  COALESCE(u.lifetime_commission_earned, 0)::float8 AS lifetime,
		  COALESCE((
		    SELECT SUM(commission_amount)
		    FROM commission_records
		    WHERE inviter_uid = u.uid
		      AND period_date >= date_trunc('month', NOW() AT TIME ZONE 'UTC')::date
		  ), 0)::float8 AS this_month,
		  COALESCE((
		    SELECT COUNT(*) FROM users WHERE inviter_uid = u.uid
		  ), 0)::int AS invitees
		FROM users u WHERE u.uid = $1
	`, uid).Scan(&lifetime, &thisMonth, &inviteesCount)
	if err != nil {
		return 0, 0, 0, fmt.Errorf("get overview metrics: %w", err)
	}
	return
}

// GetAgentDashboard 代理后台首页：本月 direct / override 分拆 + 下级数量等。
func (r *ReferralRepo) GetAgentDashboard(ctx context.Context, uid string) (*model.AgentDashboardSummary, error) {
	var s model.AgentDashboardSummary
	s.UID = uid
	err := r.pool.QueryRow(ctx, `
		SELECT
		  u.my_rebate_rate::float8,
		  COALESCE(u.lifetime_commission_earned, 0)::float8,
		  COALESCE((
		    SELECT SUM(commission_amount) FROM commission_records
		    WHERE inviter_uid = u.uid AND kind = 'direct'
		      AND period_date >= date_trunc('month', NOW() AT TIME ZONE 'UTC')::date
		  ), 0)::float8,
		  COALESCE((
		    SELECT SUM(commission_amount) FROM commission_records
		    WHERE inviter_uid = u.uid AND kind = 'override'
		      AND period_date >= date_trunc('month', NOW() AT TIME ZONE 'UTC')::date
		  ), 0)::float8,
		  COALESCE((SELECT COUNT(*) FROM users WHERE inviter_uid = u.uid), 0)::int,
		  COALESCE((SELECT COUNT(*) FROM users WHERE inviter_uid = u.uid AND is_agent = true), 0)::int,
		  u.is_frozen_referral
		FROM users u WHERE u.uid = $1
	`, uid).Scan(
		&s.MyRebateRate, &s.LifetimeCommissionEarned,
		&s.ThisMonthDirect, &s.ThisMonthOverride,
		&s.DirectInvitees, &s.SubAgentsCount, &s.IsFrozen,
	)
	if err != nil {
		return nil, fmt.Errorf("get agent dashboard: %w", err)
	}
	return &s, nil
}

func (r *ReferralRepo) ListInvitees(ctx context.Context, inviterUID string, limit, offset int) ([]InviteeRow, int, error) {
	var total int
	if err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM users WHERE inviter_uid = $1
	`, inviterUID).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count invitees: %w", err)
	}
	rows, err := r.pool.Query(ctx, `
		SELECT uid, display_name, email, created_at, my_rebate_rate, is_agent, updated_at
		FROM users WHERE inviter_uid = $1
		ORDER BY created_at DESC LIMIT $2 OFFSET $3
	`, inviterUID, limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("list invitees: %w", err)
	}
	defer rows.Close()
	var out []InviteeRow
	for rows.Next() {
		var r InviteeRow
		var updatedAt time.Time
		if err := rows.Scan(&r.UID, &r.DisplayName, &r.Email, &r.CreatedAt,
			&r.MyRebateRate, &r.IsAgent, &updatedAt); err != nil {
			return nil, 0, fmt.Errorf("scan invitee: %w", err)
		}
		r.LastActiveAt = &updatedAt
		out = append(out, r)
	}
	return out, total, rows.Err()
}

func (r *ReferralRepo) ListCommissionRecords(
	ctx context.Context, inviterUID, kind string, limit, offset int,
) ([]*model.CommissionRecord, int, error) {
	var total int
	countQ := `SELECT COUNT(*) FROM commission_records WHERE inviter_uid = $1`
	args := []interface{}{inviterUID}
	if kind != "" {
		countQ += ` AND kind = $2`
		args = append(args, kind)
	}
	if err := r.pool.QueryRow(ctx, countQ, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count records: %w", err)
	}

	listQ := `
		SELECT id::text, inviter_uid, period_date, kind, total_fee_base,
		       commission_amount, event_count, status, created_at
		FROM commission_records WHERE inviter_uid = $1`
	listArgs := []interface{}{inviterUID}
	if kind != "" {
		listQ += ` AND kind = $4`
		listArgs = append(listArgs, limit, offset, kind)
	} else {
		listArgs = append(listArgs, limit, offset)
	}
	listQ += ` ORDER BY period_date DESC, created_at DESC LIMIT $2 OFFSET $3`

	rows, err := r.pool.Query(ctx, listQ, listArgs...)
	if err != nil {
		return nil, 0, fmt.Errorf("list records: %w", err)
	}
	defer rows.Close()
	var out []*model.CommissionRecord
	for rows.Next() {
		var rec model.CommissionRecord
		if err := rows.Scan(&rec.ID, &rec.InviterUID, &rec.PeriodDate, &rec.Kind,
			&rec.TotalFeeBase, &rec.CommissionAmount, &rec.EventCount, &rec.Status, &rec.CreatedAt); err != nil {
			return nil, 0, fmt.Errorf("scan record: %w", err)
		}
		out = append(out, &rec)
	}
	return out, total, rows.Err()
}

// ListSubAgents 代理的下级列表（不区分是否代理身份，但本期 UI 只显示直接下级）。
// 每行包含本月 fee_base 合计和本月给我贡献的 override 合计。
func (r *ReferralRepo) ListSubAgents(ctx context.Context, parentUID string) ([]model.SubAgentRow, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT
		  u.uid,
		  u.display_name,
		  u.email,
		  u.my_rebate_rate::float8,
		  u.is_agent,
		  COALESCE((
		    SELECT SUM(fee_base) FROM commission_events
		    WHERE invitee_uid = u.uid
		      AND (created_at AT TIME ZONE 'UTC') >= date_trunc('month', NOW() AT TIME ZONE 'UTC')
		  ), 0)::float8 AS this_month_volume,
		  COALESCE((
		    SELECT SUM(commission_amount) FROM commission_events
		    WHERE inviter_uid = $1 AND source_inviter_uid = u.uid AND kind = 'override'
		      AND (created_at AT TIME ZONE 'UTC') >= date_trunc('month', NOW() AT TIME ZONE 'UTC')
		  ), 0)::float8 AS contrib_to_parent,
		  u.is_frozen_referral
		FROM users u
		WHERE u.inviter_uid = $1
		ORDER BY u.created_at DESC
	`, parentUID)
	if err != nil {
		return nil, fmt.Errorf("list sub-agents: %w", err)
	}
	defer rows.Close()
	var out []model.SubAgentRow
	for rows.Next() {
		var r model.SubAgentRow
		if err := rows.Scan(&r.UID, &r.DisplayName, &r.Email, &r.MyRebateRate, &r.IsAgent,
			&r.ThisMonthVolume, &r.ContribToParent, &r.IsFrozenReferral); err != nil {
			return nil, fmt.Errorf("scan sub-agent: %w", err)
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// ══════════════════════════════════════════════════════════════
// Misc helpers
// ══════════════════════════════════════════════════════════════

// UserBasic holds minimal user info for display purposes.
type UserBasic struct {
	UID         string
	DisplayName string
}

// GetUserBasic returns minimal user info by UID.
func (r *ReferralRepo) GetUserBasic(ctx context.Context, uid string) (*UserBasic, error) {
	var u UserBasic
	err := r.pool.QueryRow(ctx,
		`SELECT uid, display_name FROM users WHERE uid = $1`, uid,
	).Scan(&u.UID, &u.DisplayName)
	if err != nil {
		return nil, fmt.Errorf("get user basic: %w", err)
	}
	return &u, nil
}
