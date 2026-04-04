package service

import (
	"context"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

type TeacherService struct {
	repo *repository.TeacherRepo
}

func NewTeacherService(repo *repository.TeacherRepo) *TeacherService {
	return &TeacherService{repo: repo}
}

func (s *TeacherService) List(ctx context.Context, limit, offset int) ([]model.Teacher, error) {
	return s.repo.List(ctx, limit, offset, "approved")
}

func (s *TeacherService) ListPending(ctx context.Context, limit, offset int) ([]model.Teacher, error) {
	return s.repo.List(ctx, limit, offset, "pending")
}

func (s *TeacherService) GetByUserID(ctx context.Context, uid string) (*model.Teacher, error) {
	return s.repo.GetByUserID(ctx, uid)
}

func (s *TeacherService) Apply(ctx context.Context, uid string, req *model.ApplyTeacherRequest) error {
	return s.repo.Apply(ctx, uid, req)
}

func (s *TeacherService) Approve(ctx context.Context, uid string) error {
	return s.repo.UpdateStatus(ctx, uid, "approved")
}

func (s *TeacherService) Reject(ctx context.Context, uid string) error {
	return s.repo.UpdateStatus(ctx, uid, "rejected")
}

func (s *TeacherService) Update(ctx context.Context, uid, bio string, specialties []string) error {
	return s.repo.Update(ctx, uid, bio, specialties)
}

func (s *TeacherService) CreateStrategy(ctx context.Context, uid string, req *model.CreateStrategyRequest) (*model.Strategy, error) {
	return s.repo.CreateStrategy(ctx, uid, req)
}

func (s *TeacherService) ListStrategies(ctx context.Context, teacherID string, limit, offset int) ([]model.Strategy, error) {
	return s.repo.ListStrategies(ctx, teacherID, limit, offset)
}

func (s *TeacherService) DeleteStrategy(ctx context.Context, strategyID, teacherID string) error {
	return s.repo.DeleteStrategy(ctx, strategyID, teacherID)
}

func (s *TeacherService) Follow(ctx context.Context, teacherID, userID string) error {
	return s.repo.Follow(ctx, teacherID, userID)
}

func (s *TeacherService) Unfollow(ctx context.Context, teacherID, userID string) error {
	return s.repo.Unfollow(ctx, teacherID, userID)
}

func (s *TeacherService) LikeStrategy(ctx context.Context, strategyID, userID string) error {
	return s.repo.LikeStrategy(ctx, strategyID, userID)
}
