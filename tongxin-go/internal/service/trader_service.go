package service

import (
	"context"
	"errors"
	"fmt"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

type TraderService struct {
	repo       *repository.TraderRepo
	walletRepo *repository.WalletRepo // 跟单本金（子账户）和主钱包之间的资金划转
}

func NewTraderService(repo *repository.TraderRepo, walletRepo *repository.WalletRepo) *TraderService {
	return &TraderService{repo: repo, walletRepo: walletRepo}
}

// 跟单本金最小分配额（USDT），防止 dust 订阅
const MinAllocatedCapital = 100.0

// ── Application ──

func (s *TraderService) SubmitApplication(ctx context.Context, uid string, req *model.SubmitApplicationRequest) (*model.TraderApplication, error) {
	if req.RealName == "" {
		return nil, errors.New("real name is required")
	}
	if req.IDNumber == "" {
		return nil, errors.New("ID number is required")
	}
	if req.Phone == "" {
		return nil, errors.New("phone is required")
	}
	if !req.RiskAgreed || !req.TermsAgreed {
		return nil, errors.New("must agree to risk disclosure and terms")
	}

	// Check for existing pending application
	existing, err := s.repo.GetApplicationByUserID(ctx, uid)
	if err == nil && existing.Status == "pending" {
		return nil, errors.New("you already have a pending application")
	}

	return s.repo.CreateApplication(ctx, uid, req)
}

func (s *TraderService) GetMyApplication(ctx context.Context, uid string) (*model.TraderApplication, error) {
	return s.repo.GetApplicationByUserID(ctx, uid)
}

func (s *TraderService) ListApplications(ctx context.Context, status string, limit, offset int) ([]model.TraderApplication, int, error) {
	return s.repo.ListApplications(ctx, status, limit, offset)
}

func (s *TraderService) ApproveApplication(ctx context.Context, appID, adminUID string) error {
	app, err := s.repo.GetApplicationByID(ctx, appID)
	if err != nil {
		return fmt.Errorf("application not found: %w", err)
	}
	if app.Status != "pending" {
		return errors.New("application is not pending")
	}

	if err := s.repo.UpdateApplicationStatus(ctx, appID, "approved", adminUID, ""); err != nil {
		return fmt.Errorf("update status: %w", err)
	}
	if err := s.repo.SetUserTrader(ctx, app.UserID, true); err != nil {
		return fmt.Errorf("set trader: %w", err)
	}
	// Initialize trader stats
	_ = s.repo.RefreshTraderStats(ctx, app.UserID)
	return nil
}

func (s *TraderService) RejectApplication(ctx context.Context, appID, adminUID, reason string) error {
	app, err := s.repo.GetApplicationByID(ctx, appID)
	if err != nil {
		return fmt.Errorf("application not found: %w", err)
	}
	if app.Status != "pending" {
		return errors.New("application is not pending")
	}

	return s.repo.UpdateApplicationStatus(ctx, appID, "rejected", adminUID, reason)
}

// ── Stats ──

func (s *TraderService) GetTraderStats(ctx context.Context, uid string) (*model.TraderStats, error) {
	// Refresh stats before returning
	_ = s.repo.RefreshTraderStats(ctx, uid)
	return s.repo.GetTraderStats(ctx, uid)
}

func (s *TraderService) GetTraderRankings(ctx context.Context, sortBy string, limit, offset int) ([]model.TraderRankingItem, int, error) {
	if limit <= 0 {
		limit = 20
	}
	return s.repo.ListTraderRankings(ctx, sortBy, limit, offset)
}

// ── Copy Trading ──

func (s *TraderService) ToggleCopyTrading(ctx context.Context, uid string, allow bool) error {
	return s.repo.UpdateAllowCopyTrading(ctx, uid, allow)
}

func (s *TraderService) FollowTrader(ctx context.Context, followerID, traderID string, req *model.FollowTraderRequest) (*model.CopyTrading, error) {
	if followerID == traderID {
		return nil, errors.New("cannot follow yourself")
	}
	// Check trader allows copy trading
	profile, err := s.repo.GetTraderProfile(ctx, traderID, "")
	if err != nil {
		return nil, errors.New("trader not found")
	}
	if !profile.IsTrader {
		return nil, errors.New("user is not a certified trader")
	}
	if !profile.AllowCopyTrading {
		return nil, errors.New("trader has disabled copy trading")
	}

	// 跟单本金校验：必填且 >= 最小阈值
	if req.AllocatedCapital < MinAllocatedCapital {
		return nil, fmt.Errorf("allocated capital must be >= %.2f USDT", MinAllocatedCapital)
	}
	// 钱包余额校验
	if s.walletRepo != nil {
		wallet, werr := s.walletRepo.GetWallet(ctx, followerID)
		if werr != nil {
			return nil, fmt.Errorf("wallet not found: %w", werr)
		}
		if wallet.Balance < req.AllocatedCapital {
			return nil, fmt.Errorf("insufficient wallet balance (need %.2f, have %.2f)",
				req.AllocatedCapital, wallet.Balance)
		}
	}

	if req.CopyRatio <= 0 {
		req.CopyRatio = 1.0
	}
	// Auto-follow when starting copy trading
	_ = s.repo.FollowUser(ctx, followerID, traderID)

	// 1) 创建/复活 copy_trading 行（仅配置，capital 字段保持 0）
	ct, err := s.repo.CreateCopyTrading(ctx, followerID, traderID, req)
	if err != nil {
		return nil, err
	}

	// 2) 钱包 → 子账户原子划转
	if s.walletRepo != nil {
		if _, err := s.walletRepo.AllocateToCopyBucket(ctx, followerID, ct.ID, req.AllocatedCapital); err != nil {
			// 回滚：不能让 copy_trading 留在 active 但 bucket=0 的状态 → 把它停掉
			_ = s.repo.StopCopyTrading(ctx, followerID, traderID)
			return nil, fmt.Errorf("allocate capital: %w", err)
		}
		// 拿最新快照（含 allocated/available）
		updated, gerr := s.repo.GetCopyTradingByID(ctx, ct.ID)
		if gerr == nil {
			ct = updated
		}
	}
	return ct, nil
}

// UnfollowTrader 取消跟单：先检查无未平仓位 → 子账户余额回主钱包 → status=stopped
// 错误信息「has open positions」会被前端用来弹「请先平仓」提示
func (s *TraderService) UnfollowTrader(ctx context.Context, followerID, traderID string) error {
	ct, err := s.repo.GetCopyRelation(ctx, followerID, traderID)
	if err != nil {
		// 找不到关系：直接走旧路径（幂等）
		return s.repo.StopCopyTrading(ctx, followerID, traderID)
	}
	if ct.Status == "stopped" {
		return nil
	}
	if ct.FrozenCapital > 0 {
		return fmt.Errorf("has open positions, please close first (frozen=%.2f)", ct.FrozenCapital)
	}
	// 子账户余额 → 钱包
	if s.walletRepo != nil && ct.AvailableCapital > 0 {
		if _, err := s.walletRepo.WithdrawFromCopyBucket(ctx, followerID, ct.ID, ct.AvailableCapital); err != nil {
			return fmt.Errorf("withdraw bucket: %w", err)
		}
	}
	return s.repo.StopCopyTrading(ctx, followerID, traderID)
}

// AdjustAllocatedCapital 用户主动追加 / 赎回某个跟单池子的本金。
// delta>0 追加（钱包→子账户），<0 赎回（子账户→钱包）。
// 赎回时检查子账户 available 是否充足；不能赎回到 allocated 以下（保留 PnL 增量逻辑给后续）。
func (s *TraderService) AdjustAllocatedCapital(ctx context.Context, followerID, traderID string, delta float64) (*model.CopyTrading, error) {
	if delta == 0 {
		return s.repo.GetCopyRelation(ctx, followerID, traderID)
	}
	if s.walletRepo == nil {
		return nil, errors.New("wallet not initialized")
	}
	ct, err := s.repo.GetCopyRelation(ctx, followerID, traderID)
	if err != nil {
		return nil, fmt.Errorf("copy relation not found: %w", err)
	}
	if ct.Status != "active" {
		return nil, errors.New("copy trading is not active")
	}

	if delta > 0 {
		// 追加：检查钱包余额
		wallet, werr := s.walletRepo.GetWallet(ctx, followerID)
		if werr != nil {
			return nil, fmt.Errorf("wallet not found: %w", werr)
		}
		if wallet.Balance < delta {
			return nil, fmt.Errorf("insufficient wallet balance (need %.2f, have %.2f)", delta, wallet.Balance)
		}
		if _, err := s.walletRepo.AllocateToCopyBucket(ctx, followerID, ct.ID, delta); err != nil {
			return nil, fmt.Errorf("top up bucket: %w", err)
		}
	} else {
		withdraw := -delta
		if ct.AvailableCapital < withdraw {
			return nil, fmt.Errorf("insufficient bucket available (need %.2f, have %.2f)", withdraw, ct.AvailableCapital)
		}
		if _, err := s.walletRepo.WithdrawFromCopyBucket(ctx, followerID, ct.ID, withdraw); err != nil {
			return nil, fmt.Errorf("withdraw from bucket: %w", err)
		}
	}
	return s.repo.GetCopyTradingByID(ctx, ct.ID)
}

func (s *TraderService) GetMyFollowers(ctx context.Context, uid string) ([]model.CopyTrading, error) {
	return s.repo.ListFollowers(ctx, uid)
}

func (s *TraderService) GetMyFollowing(ctx context.Context, uid string) ([]model.CopyTrading, error) {
	return s.repo.ListFollowing(ctx, uid)
}

func (s *TraderService) UpdateCopySettings(ctx context.Context, followerID, traderID string, req *model.FollowTraderRequest) (*model.CopyTrading, error) {
	return s.repo.UpdateCopyTradingSettings(ctx, followerID, traderID, req)
}

func (s *TraderService) PauseCopyTrading(ctx context.Context, followerID, traderID string) error {
	return s.repo.PauseCopyTrading(ctx, followerID, traderID)
}

func (s *TraderService) ResumeCopyTrading(ctx context.Context, followerID, traderID string) error {
	return s.repo.ResumeCopyTrading(ctx, followerID, traderID)
}

func (s *TraderService) GetCopyTradeLogs(ctx context.Context, followerID string, limit, offset int) ([]model.CopyTradeLog, int, error) {
	if limit <= 0 {
		limit = 50
	}
	return s.repo.ListCopyTradeLogsByFollower(ctx, followerID, limit, offset)
}

// ── Profile ──

func (s *TraderService) GetTraderProfile(ctx context.Context, uid string, viewerID string) (*model.TraderProfile, error) {
	return s.repo.GetTraderProfile(ctx, uid, viewerID)
}

// ── User Follow (lightweight, independent of copy trading) ──

func (s *TraderService) WatchTrader(ctx context.Context, userID, traderID string) error {
	if userID == traderID {
		return errors.New("cannot follow yourself")
	}
	return s.repo.FollowUser(ctx, userID, traderID)
}

func (s *TraderService) UnwatchTrader(ctx context.Context, userID, traderID string) error {
	return s.repo.UnfollowUser(ctx, userID, traderID)
}

func (s *TraderService) GetFollowedTraders(ctx context.Context, userID string) ([]model.FollowedTrader, error) {
	return s.repo.ListFollowedTraders(ctx, userID)
}

// SetTraderStatus directly promotes/demotes a user as trader (admin action)
func (s *TraderService) SetTraderStatus(ctx context.Context, uid string, isTrader bool) error {
	return s.repo.SetUserTrader(ctx, uid, isTrader)
}

func (s *TraderService) GetEquityHistory(ctx context.Context, uid string, period string) ([]model.EquityPoint, error) {
	return s.repo.GetEquityHistory(ctx, uid, period)
}
