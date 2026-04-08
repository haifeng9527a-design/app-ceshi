package service

import (
	"context"
	"errors"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

type TraderStrategyService struct {
	repo       *repository.TraderStrategyRepo
	traderRepo *repository.TraderRepo
}

func NewTraderStrategyService(repo *repository.TraderStrategyRepo, traderRepo *repository.TraderRepo) *TraderStrategyService {
	return &TraderStrategyService{repo: repo, traderRepo: traderRepo}
}

// Create — only certified traders can create strategies
func (s *TraderStrategyService) Create(ctx context.Context, uid string, req *model.CreateTraderStrategyRequest) (*model.TraderStrategy, error) {
	profile, err := s.traderRepo.GetTraderProfile(ctx, uid)
	if err != nil || !profile.IsTrader {
		return nil, errors.New("only certified traders can publish strategies")
	}
	if req.Title == "" {
		return nil, errors.New("title is required")
	}
	if req.ContentHTML == "" {
		return nil, errors.New("content is required")
	}
	return s.repo.Create(ctx, uid, req)
}

// GetByID — anyone can view, increments view count
func (s *TraderStrategyService) GetByID(ctx context.Context, id string) (*model.TraderStrategy, error) {
	_ = s.repo.IncrementViews(ctx, id)
	return s.repo.GetByID(ctx, id)
}

// Update — only the author can update
func (s *TraderStrategyService) Update(ctx context.Context, id, uid string, req *model.UpdateTraderStrategyRequest) (*model.TraderStrategy, error) {
	return s.repo.Update(ctx, id, uid, req)
}

// Delete — only the author can delete
func (s *TraderStrategyService) Delete(ctx context.Context, id, uid string) error {
	return s.repo.Delete(ctx, id, uid)
}

// ListMy — list my strategies (all statuses)
func (s *TraderStrategyService) ListMy(ctx context.Context, uid, status string, limit, offset int) ([]model.TraderStrategy, int, error) {
	if limit <= 0 {
		limit = 20
	}
	return s.repo.ListByAuthor(ctx, uid, status, limit, offset)
}

// ListPublished — public feed
func (s *TraderStrategyService) ListPublished(ctx context.Context, category string, limit, offset int) ([]model.TraderStrategy, int, error) {
	if limit <= 0 {
		limit = 20
	}
	return s.repo.ListPublished(ctx, category, limit, offset)
}

// ListByTrader — public list of published strategies by a specific trader
func (s *TraderStrategyService) ListByTrader(ctx context.Context, uid string, limit, offset int) ([]model.TraderStrategy, int, error) {
	if limit <= 0 {
		limit = 20
	}
	return s.repo.ListByAuthor(ctx, uid, "published", limit, offset)
}

// Like — toggle like
func (s *TraderStrategyService) Like(ctx context.Context, strategyID, uid string) (bool, error) {
	return s.repo.LikeStrategy(ctx, strategyID, uid)
}

// HasLiked — check if user liked
func (s *TraderStrategyService) HasLiked(ctx context.Context, strategyID, uid string) bool {
	return s.repo.HasLiked(ctx, strategyID, uid)
}
