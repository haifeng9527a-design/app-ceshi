package service

import (
	"context"
	"errors"
	"fmt"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

type TraderService struct {
	repo *repository.TraderRepo
}

func NewTraderService(repo *repository.TraderRepo) *TraderService {
	return &TraderService{repo: repo}
}

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
	profile, err := s.repo.GetTraderProfile(ctx, traderID)
	if err != nil {
		return nil, errors.New("trader not found")
	}
	if !profile.IsTrader {
		return nil, errors.New("user is not a certified trader")
	}
	if !profile.AllowCopyTrading {
		return nil, errors.New("trader has disabled copy trading")
	}

	ratio := req.CopyRatio
	if ratio <= 0 {
		ratio = 1.0
	}
	return s.repo.CreateCopyTrading(ctx, followerID, traderID, ratio, req.MaxPosition)
}

func (s *TraderService) UnfollowTrader(ctx context.Context, followerID, traderID string) error {
	return s.repo.StopCopyTrading(ctx, followerID, traderID)
}

func (s *TraderService) GetMyFollowers(ctx context.Context, uid string) ([]model.CopyTrading, error) {
	return s.repo.ListFollowers(ctx, uid)
}

func (s *TraderService) GetMyFollowing(ctx context.Context, uid string) ([]model.CopyTrading, error) {
	return s.repo.ListFollowing(ctx, uid)
}

// ── Profile ──

func (s *TraderService) GetTraderProfile(ctx context.Context, uid string) (*model.TraderProfile, error) {
	return s.repo.GetTraderProfile(ctx, uid)
}

// SetTraderStatus directly promotes/demotes a user as trader (admin action)
func (s *TraderService) SetTraderStatus(ctx context.Context, uid string, isTrader bool) error {
	return s.repo.SetUserTrader(ctx, uid, isTrader)
}
