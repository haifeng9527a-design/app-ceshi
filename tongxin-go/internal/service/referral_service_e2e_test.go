//go:build integration

package service

import (
	"context"
	"errors"
	"fmt"
	"math"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"tongxin-go/internal/config"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

// setupTestDB creates a connection pool using DATABASE_URL env var.
// Skips the test if DATABASE_URL is not set.
func setupTestDB(t *testing.T) (*pgxpool.Pool, func()) {
	t.Helper()
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		t.Skip("DATABASE_URL not set, skipping integration test")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}
	return pool, pool.Close
}

func testConfig() *config.Config {
	return &config.Config{
		ReferralEnabled:         true,
		PlatformUserDefaultRate: 0.10,
		PlatformUserMaxRate:     0.20,
		PlatformAgentMaxRate:    1.00,
		DailyCommissionCapUSD:   10000,
	}
}

// cleanupTestUsers removes all test data matching the given prefix from
// referral-related tables, in correct FK order.
func cleanupTestUsers(t *testing.T, pool *pgxpool.Pool, prefix string) {
	t.Helper()
	ctx := context.Background()
	pool.Exec(ctx, "DELETE FROM commission_events WHERE invitee_uid LIKE $1 OR inviter_uid LIKE $1", prefix+"%")
	pool.Exec(ctx, "DELETE FROM commission_records WHERE inviter_uid LIKE $1", prefix+"%")
	pool.Exec(ctx, "DELETE FROM invite_links WHERE owner_uid LIKE $1", prefix+"%")
	pool.Exec(ctx, "DELETE FROM agent_applications WHERE applicant_uid LIKE $1", prefix+"%")
	pool.Exec(ctx, "DELETE FROM users WHERE uid LIKE $1", prefix+"%")
}

// insertTestUser inserts a minimal user row for integration tests.
func insertTestUser(t *testing.T, pool *pgxpool.Pool, uid, email string, rate float64, isAgent bool) {
	t.Helper()
	ctx := context.Background()
	_, err := pool.Exec(ctx, `
		INSERT INTO users (uid, email, display_name, my_rebate_rate, is_agent)
		VALUES ($1, $2, $3, $4::numeric, $5)
		ON CONFLICT (uid) DO NOTHING
	`, uid, email, uid, rate, isAgent)
	if err != nil {
		t.Fatalf("insertTestUser %s: %v", uid, err)
	}
}

// setInviter sets user.inviter_uid directly via SQL.
func setInviter(t *testing.T, pool *pgxpool.Pool, uid, inviterUID string) {
	t.Helper()
	ctx := context.Background()
	_, err := pool.Exec(ctx, `UPDATE users SET inviter_uid = $2 WHERE uid = $1`, uid, inviterUID)
	if err != nil {
		t.Fatalf("setInviter %s -> %s: %v", uid, inviterUID, err)
	}
}

// createInviteLink inserts an active invite link for an owner.
func createInviteLink(t *testing.T, pool *pgxpool.Pool, ownerUID, code string) {
	t.Helper()
	ctx := context.Background()
	_, err := pool.Exec(ctx, `
		INSERT INTO invite_links (owner_uid, code, name, is_active)
		VALUES ($1, $2, 'test', true)
		ON CONFLICT (code) DO NOTHING
	`, ownerUID, code)
	if err != nil {
		t.Fatalf("createInviteLink %s/%s: %v", ownerUID, code, err)
	}
}

// e2eApproxEq compares two floats with tolerance.
func e2eApproxEq(a, b float64) bool {
	return math.Abs(a-b) < 0.01
}

// queryCommissionEvents returns all commission_events for a given invitee, ordered by created_at.
func queryCommissionEvents(t *testing.T, pool *pgxpool.Pool, inviteeUID string) []struct {
	InviterUID       string
	Kind             string
	CommissionAmount float64
	Status           string
} {
	t.Helper()
	ctx := context.Background()
	rows, err := pool.Query(ctx, `
		SELECT inviter_uid, kind, commission_amount::float8, status
		FROM commission_events
		WHERE invitee_uid = $1
		ORDER BY created_at
	`, inviteeUID)
	if err != nil {
		t.Fatalf("queryCommissionEvents: %v", err)
	}
	defer rows.Close()

	var results []struct {
		InviterUID       string
		Kind             string
		CommissionAmount float64
		Status           string
	}
	for rows.Next() {
		var r struct {
			InviterUID       string
			Kind             string
			CommissionAmount float64
			Status           string
		}
		if err := rows.Scan(&r.InviterUID, &r.Kind, &r.CommissionAmount, &r.Status); err != nil {
			t.Fatalf("scan event: %v", err)
		}
		results = append(results, r)
	}
	return results
}

// ══════════════════════════════════════════════════════════════
// Test 1: Normal user invites and earns default 10%
// ══════════════════════════════════════════════════════════════

func TestE2E_NormalUserInvitesAndEarns(t *testing.T) {
	pool, cleanup := setupTestDB(t)
	defer cleanup()

	const prefix = "test_e2e_1_"
	defer cleanupTestUsers(t, pool, prefix)
	cleanupTestUsers(t, pool, prefix) // clean before too

	// A = inviter (default rate 10%), B = invitee
	insertTestUser(t, pool, prefix+"a", prefix+"a@test.com", 0.10, false)
	insertTestUser(t, pool, prefix+"b", prefix+"b@test.com", 0.10, false)
	setInviter(t, pool, prefix+"b", prefix+"a")

	cfg := testConfig()
	repo := repository.NewReferralRepo(pool)
	svc := NewReferralService(cfg, repo)

	ctx := context.Background()
	err := svc.RecordCommissionEvent(ctx, prefix+"b", 100.0, model.ProductTypeSpot, "")
	if err != nil {
		t.Fatalf("RecordCommissionEvent: %v", err)
	}

	events := queryCommissionEvents(t, pool, prefix+"b")
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	if events[0].InviterUID != prefix+"a" {
		t.Errorf("expected inviter %sa, got %s", prefix, events[0].InviterUID)
	}
	if events[0].Kind != model.CommissionKindDirect {
		t.Errorf("expected direct, got %s", events[0].Kind)
	}
	if !e2eApproxEq(events[0].CommissionAmount, 10.0) {
		t.Errorf("expected $10 commission, got %.2f", events[0].CommissionAmount)
	}
}

// ══════════════════════════════════════════════════════════════
// Test 2: Agent invites and earns 80%
// ══════════════════════════════════════════════════════════════

func TestE2E_AgentInvitesAndEarns(t *testing.T) {
	pool, cleanup := setupTestDB(t)
	defer cleanup()

	const prefix = "test_e2e_2_"
	defer cleanupTestUsers(t, pool, prefix)
	cleanupTestUsers(t, pool, prefix)

	// A = agent at 80%, B = invitee
	insertTestUser(t, pool, prefix+"a", prefix+"a@test.com", 0.80, true)
	insertTestUser(t, pool, prefix+"b", prefix+"b@test.com", 0.10, false)
	setInviter(t, pool, prefix+"b", prefix+"a")

	cfg := testConfig()
	repo := repository.NewReferralRepo(pool)
	svc := NewReferralService(cfg, repo)

	ctx := context.Background()
	err := svc.RecordCommissionEvent(ctx, prefix+"b", 100.0, model.ProductTypeFuturesClose, "")
	if err != nil {
		t.Fatalf("RecordCommissionEvent: %v", err)
	}

	events := queryCommissionEvents(t, pool, prefix+"b")
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	if !e2eApproxEq(events[0].CommissionAmount, 80.0) {
		t.Errorf("expected $80 commission, got %.2f", events[0].CommissionAmount)
	}
}

// ══════════════════════════════════════════════════════════════
// Test 3: Three-layer cascade — admin -> A(80%) -> B(60%) -> C(15%) -> U
// ══════════════════════════════════════════════════════════════

func TestE2E_ThreeLayerCascade(t *testing.T) {
	pool, cleanup := setupTestDB(t)
	defer cleanup()

	const prefix = "test_e2e_3_"
	defer cleanupTestUsers(t, pool, prefix)
	cleanupTestUsers(t, pool, prefix)

	// admin -> A(80%) -> B(60%) -> C(15%) -> U
	insertTestUser(t, pool, prefix+"admin", prefix+"admin@test.com", 1.00, true)
	insertTestUser(t, pool, prefix+"a", prefix+"a@test.com", 0.80, true)
	insertTestUser(t, pool, prefix+"b", prefix+"b@test.com", 0.60, true)
	insertTestUser(t, pool, prefix+"c", prefix+"c@test.com", 0.15, false)
	insertTestUser(t, pool, prefix+"u", prefix+"u@test.com", 0.10, false)

	setInviter(t, pool, prefix+"a", prefix+"admin")
	setInviter(t, pool, prefix+"b", prefix+"a")
	setInviter(t, pool, prefix+"c", prefix+"b")
	setInviter(t, pool, prefix+"u", prefix+"c")

	cfg := testConfig()
	repo := repository.NewReferralRepo(pool)
	svc := NewReferralService(cfg, repo)

	ctx := context.Background()
	err := svc.RecordCommissionEvent(ctx, prefix+"u", 100.0, model.ProductTypeFuturesClose, "")
	if err != nil {
		t.Fatalf("RecordCommissionEvent: %v", err)
	}

	events := queryCommissionEvents(t, pool, prefix+"u")
	// Expect: C=$15 direct, B=$45 override (60-15=45), A=$20 override (80-60=20)
	if len(events) != 3 {
		t.Fatalf("expected 3 events, got %d", len(events))
	}

	// Find each event by inviter
	var cEvent, bEvent, aEvent *struct {
		InviterUID       string
		Kind             string
		CommissionAmount float64
		Status           string
	}
	for i := range events {
		switch events[i].InviterUID {
		case prefix + "c":
			cEvent = &events[i]
		case prefix + "b":
			bEvent = &events[i]
		case prefix + "a":
			aEvent = &events[i]
		}
	}

	if cEvent == nil || cEvent.Kind != model.CommissionKindDirect || !e2eApproxEq(cEvent.CommissionAmount, 15.0) {
		t.Errorf("C should get $15 direct, got %+v", cEvent)
	}
	if bEvent == nil || bEvent.Kind != model.CommissionKindOverride || !e2eApproxEq(bEvent.CommissionAmount, 45.0) {
		t.Errorf("B should get $45 override, got %+v", bEvent)
	}
	if aEvent == nil || aEvent.Kind != model.CommissionKindOverride || !e2eApproxEq(aEvent.CommissionAmount, 20.0) {
		t.Errorf("A should get $20 override, got %+v", aEvent)
	}
}

// ══════════════════════════════════════════════════════════════
// Test 4: Equal rate — no override event generated
// ══════════════════════════════════════════════════════════════

func TestE2E_EqualRateNoOverride(t *testing.T) {
	pool, cleanup := setupTestDB(t)
	defer cleanup()

	const prefix = "test_e2e_4_"
	defer cleanupTestUsers(t, pool, prefix)
	cleanupTestUsers(t, pool, prefix)

	// A(80%) -> B(80%) -> U
	insertTestUser(t, pool, prefix+"a", prefix+"a@test.com", 0.80, true)
	insertTestUser(t, pool, prefix+"b", prefix+"b@test.com", 0.80, true)
	insertTestUser(t, pool, prefix+"u", prefix+"u@test.com", 0.10, false)

	setInviter(t, pool, prefix+"b", prefix+"a")
	setInviter(t, pool, prefix+"u", prefix+"b")

	cfg := testConfig()
	repo := repository.NewReferralRepo(pool)
	svc := NewReferralService(cfg, repo)

	ctx := context.Background()
	err := svc.RecordCommissionEvent(ctx, prefix+"u", 100.0, model.ProductTypeSpot, "")
	if err != nil {
		t.Fatalf("RecordCommissionEvent: %v", err)
	}

	events := queryCommissionEvents(t, pool, prefix+"u")
	// B gets $80 direct, A gets nothing (delta = 80 - 80 = 0)
	if len(events) != 1 {
		t.Fatalf("expected 1 event (direct only), got %d", len(events))
	}
	if events[0].InviterUID != prefix+"b" || !e2eApproxEq(events[0].CommissionAmount, 80.0) {
		t.Errorf("expected B=$80 direct, got %+v", events[0])
	}
}

// ══════════════════════════════════════════════════════════════
// Test 5: Admin lowers rate — negative delta is skipped
// ══════════════════════════════════════════════════════════════

func TestE2E_AdminLowersRateNegativeDelta(t *testing.T) {
	pool, cleanup := setupTestDB(t)
	defer cleanup()

	const prefix = "test_e2e_5_"
	defer cleanupTestUsers(t, pool, prefix)
	cleanupTestUsers(t, pool, prefix)

	// A(40% agent) -> B(60% agent) -> U
	// A was lowered to 40% but B still at 60% => delta = max(0, 40-60) = 0
	insertTestUser(t, pool, prefix+"a", prefix+"a@test.com", 0.40, true)
	insertTestUser(t, pool, prefix+"b", prefix+"b@test.com", 0.60, true)
	insertTestUser(t, pool, prefix+"u", prefix+"u@test.com", 0.10, false)

	setInviter(t, pool, prefix+"b", prefix+"a")
	setInviter(t, pool, prefix+"u", prefix+"b")

	cfg := testConfig()
	repo := repository.NewReferralRepo(pool)
	svc := NewReferralService(cfg, repo)

	ctx := context.Background()
	err := svc.RecordCommissionEvent(ctx, prefix+"u", 100.0, model.ProductTypeFuturesOpen, "")
	if err != nil {
		t.Fatalf("RecordCommissionEvent: %v", err)
	}

	events := queryCommissionEvents(t, pool, prefix+"u")
	// B gets $60 direct, A gets nothing (delta <= 0)
	if len(events) != 1 {
		t.Fatalf("expected 1 event (B direct only), got %d", len(events))
	}
	if events[0].InviterUID != prefix+"b" || !e2eApproxEq(events[0].CommissionAmount, 60.0) {
		t.Errorf("expected B=$60 direct, got %+v", events[0])
	}
}

// ══════════════════════════════════════════════════════════════
// Test 6: Circular invite rejected
// ══════════════════════════════════════════════════════════════

func TestE2E_CircularInviteRejected(t *testing.T) {
	pool, cleanup := setupTestDB(t)
	defer cleanup()

	const prefix = "test_e2e_6_"
	defer cleanupTestUsers(t, pool, prefix)
	cleanupTestUsers(t, pool, prefix)

	// A invites B (via invite link). Then B tries to set A as inviter -> circular
	insertTestUser(t, pool, prefix+"a", prefix+"a@test.com", 0.10, false)
	insertTestUser(t, pool, prefix+"b", prefix+"b@test.com", 0.10, false)

	// A already has B as invitee
	setInviter(t, pool, prefix+"b", prefix+"a")

	// Create invite link for B
	createInviteLink(t, pool, prefix+"b", prefix+"link6")

	cfg := testConfig()
	repo := repository.NewReferralRepo(pool)
	svc := NewReferralService(cfg, repo)

	ctx := context.Background()
	err := svc.BindReferrer(ctx, prefix+"a", prefix+"link6")
	if err == nil {
		t.Fatal("expected circular invite error, got nil")
	}
	if !errors.Is(err, repository.ErrCircularInvite) {
		t.Errorf("expected ErrCircularInvite, got: %v", err)
	}
}

// ══════════════════════════════════════════════════════════════
// Test 7: Non-agent rate capped at PlatformUserMaxRate (20%)
// ══════════════════════════════════════════════════════════════

func TestE2E_NonAgentRateCapped(t *testing.T) {
	pool, cleanup := setupTestDB(t)
	defer cleanup()

	const prefix = "test_e2e_7_"
	defer cleanupTestUsers(t, pool, prefix)
	cleanupTestUsers(t, pool, prefix)

	// Non-agent user
	insertTestUser(t, pool, prefix+"a", prefix+"a@test.com", 0.10, false)

	cfg := testConfig()
	repo := repository.NewReferralRepo(pool)
	svc := NewReferralService(cfg, repo)

	ctx := context.Background()
	// Try to set rate to 25% for a non-agent -> should fail (max 20%)
	err := svc.AdminSetUserRate(ctx, prefix+"a", 0.25)
	if err == nil {
		t.Fatal("expected error for setting non-agent rate > 20%, got nil")
	}
	if !errors.Is(err, repository.ErrRateOutOfBounds) {
		t.Errorf("expected ErrRateOutOfBounds, got: %v", err)
	}

	// Verify rate was NOT changed
	info, err := repo.GetUserRebateInfo(ctx, prefix+"a")
	if err != nil {
		t.Fatalf("GetUserRebateInfo: %v", err)
	}
	if !e2eApproxEq(info.MyRebateRate, 0.10) {
		t.Errorf("rate should still be 0.10, got %.4f", info.MyRebateRate)
	}
}

// ══════════════════════════════════════════════════════════════
// Test 8: Agent cannot set sub-agent rate exceeding own rate
// ══════════════════════════════════════════════════════════════

func TestE2E_AgentSetSubRateExceedsSelf(t *testing.T) {
	pool, cleanup := setupTestDB(t)
	defer cleanup()

	const prefix = "test_e2e_8_"
	defer cleanupTestUsers(t, pool, prefix)
	cleanupTestUsers(t, pool, prefix)

	// A = agent at 60%, B = direct invitee
	insertTestUser(t, pool, prefix+"a", prefix+"a@test.com", 0.60, true)
	insertTestUser(t, pool, prefix+"b", prefix+"b@test.com", 0.30, true)
	setInviter(t, pool, prefix+"b", prefix+"a")

	cfg := testConfig()
	repo := repository.NewReferralRepo(pool)
	svc := NewReferralService(cfg, repo)

	ctx := context.Background()
	// Try to set B's rate to 70% (> A's 60%) -> should fail
	err := svc.AgentSetSubRate(ctx, prefix+"a", prefix+"b", 0.70)
	if err == nil {
		t.Fatal("expected error for setting sub rate > parent rate, got nil")
	}
	if !errors.Is(err, repository.ErrRateExceedsParent) {
		t.Errorf("expected ErrRateExceedsParent, got: %v", err)
	}

	// Verify B's rate unchanged
	info, err := repo.GetUserRebateInfo(ctx, prefix+"b")
	if err != nil {
		t.Fatalf("GetUserRebateInfo: %v", err)
	}
	if !e2eApproxEq(info.MyRebateRate, 0.30) {
		t.Errorf("B rate should still be 0.30, got %.4f", info.MyRebateRate)
	}
}

// ══════════════════════════════════════════════════════════════
// Test 9: Frozen agent — events written with skipped_risk status
// ══════════════════════════════════════════════════════════════

func TestE2E_FrozenAgentSkipsEvents(t *testing.T) {
	pool, cleanup := setupTestDB(t)
	defer cleanup()

	const prefix = "test_e2e_9_"
	defer cleanupTestUsers(t, pool, prefix)
	cleanupTestUsers(t, pool, prefix)

	// A = frozen agent, B = invitee
	insertTestUser(t, pool, prefix+"a", prefix+"a@test.com", 0.50, true)
	insertTestUser(t, pool, prefix+"b", prefix+"b@test.com", 0.10, false)
	setInviter(t, pool, prefix+"b", prefix+"a")

	cfg := testConfig()
	repo := repository.NewReferralRepo(pool)
	svc := NewReferralService(cfg, repo)

	ctx := context.Background()

	// Freeze agent A
	err := svc.AdminSetFrozen(ctx, prefix+"a", true)
	if err != nil {
		t.Fatalf("AdminSetFrozen: %v", err)
	}

	// B trades, fee=$100 -> event should be skipped_risk
	err = svc.RecordCommissionEvent(ctx, prefix+"b", 100.0, model.ProductTypeSpot, "")
	if err != nil {
		t.Fatalf("RecordCommissionEvent: %v", err)
	}

	events := queryCommissionEvents(t, pool, prefix+"b")
	if len(events) != 1 {
		t.Fatalf("expected 1 event (frozen but still written for audit), got %d", len(events))
	}
	if events[0].Status != model.CommissionEventStatusSkippedRisk {
		t.Errorf("expected status skipped_risk, got %s", events[0].Status)
	}
	// Commission amount is still computed (for audit), just not settled
	if !e2eApproxEq(events[0].CommissionAmount, 50.0) {
		t.Errorf("expected $50 commission amount (audit), got %.2f", events[0].CommissionAmount)
	}
}

// ══════════════════════════════════════════════════════════════
// Test 10: Daily cap triggers — only $50 settles when cap=$50
// ══════════════════════════════════════════════════════════════

func TestE2E_DailyCapTrigger(t *testing.T) {
	pool, cleanup := setupTestDB(t)
	defer cleanup()

	const prefix = "test_e2e_10_"
	defer cleanupTestUsers(t, pool, prefix)
	cleanupTestUsers(t, pool, prefix)

	// A = inviter at 100%, generates multiple trades
	insertTestUser(t, pool, prefix+"a", prefix+"a@test.com", 1.00, true)
	insertTestUser(t, pool, prefix+"b", prefix+"b@test.com", 0.10, false)
	setInviter(t, pool, prefix+"b", prefix+"a")

	// Ensure wallet exists for settlement
	ctx := context.Background()
	pool.Exec(ctx, `INSERT INTO wallets (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`, prefix+"a")

	// Low cap config: only $50 per day
	cfg := testConfig()
	cfg.DailyCommissionCapUSD = 50

	repo := repository.NewReferralRepo(pool)
	svc := NewReferralService(cfg, repo)

	// Record two trades: fee=$60 and fee=$40 => total commission = $60 + $40 = $100
	// With rate=100%, all fee becomes commission. Cap at $50 means only $50 settles.
	for i, fee := range []float64{60.0, 40.0} {
		err := svc.RecordCommissionEvent(ctx, prefix+"b", fee, model.ProductTypeSpot,
			fmt.Sprintf("tx_%s_%d", prefix, i))
		if err != nil {
			t.Fatalf("RecordCommissionEvent #%d: %v", i, err)
		}
	}

	// Verify events were created
	events := queryCommissionEvents(t, pool, prefix+"b")
	if len(events) != 2 {
		t.Fatalf("expected 2 events, got %d", len(events))
	}

	// Now settle today's commission
	today := time.Now().UTC()
	err := svc.SettleDailyCommission(ctx, today)
	if err != nil {
		t.Fatalf("SettleDailyCommission: %v", err)
	}

	// Check commission_records: should be capped at $50
	var recordAmount float64
	var recordStatus string
	err = pool.QueryRow(ctx, `
		SELECT commission_amount::float8, status
		FROM commission_records
		WHERE inviter_uid = $1 AND kind = 'direct'
		ORDER BY created_at DESC LIMIT 1
	`, prefix+"a").Scan(&recordAmount, &recordStatus)
	if err != nil {
		t.Fatalf("query commission_records: %v", err)
	}
	if !e2eApproxEq(recordAmount, 50.0) {
		t.Errorf("expected capped commission $50, got %.2f", recordAmount)
	}
	if recordStatus != model.CommissionRecordStatusCapped {
		t.Errorf("expected status 'capped', got %s", recordStatus)
	}

	// Clean up wallet data created during settle
	defer func() {
		pool.Exec(ctx, "DELETE FROM wallet_transactions WHERE user_id LIKE $1", prefix+"%")
		pool.Exec(ctx, "DELETE FROM wallets WHERE user_id LIKE $1", prefix+"%")
	}()
}
