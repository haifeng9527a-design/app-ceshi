package service

import (
	"context"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

type FriendService struct {
	repo *repository.FriendRepo
}

func NewFriendService(repo *repository.FriendRepo) *FriendService {
	return &FriendService{repo: repo}
}

func (s *FriendService) SendRequest(ctx context.Context, fromUID, toUID, message string) (*model.FriendRequest, error) {
	return s.repo.SendRequest(ctx, fromUID, toUID, message)
}

func (s *FriendService) AcceptRequest(ctx context.Context, requestID, currentUID string) (fromUID string, err error) {
	return s.repo.AcceptRequest(ctx, requestID, currentUID)
}

func (s *FriendService) RejectRequest(ctx context.Context, requestID, currentUID string) error {
	return s.repo.RejectRequest(ctx, requestID, currentUID)
}

func (s *FriendService) GetIncoming(ctx context.Context, uid string) ([]model.FriendRequest, error) {
	return s.repo.GetIncoming(ctx, uid)
}

func (s *FriendService) GetOutgoing(ctx context.Context, uid string) ([]model.FriendRequest, error) {
	return s.repo.GetOutgoing(ctx, uid)
}

func (s *FriendService) ListFriends(ctx context.Context, uid string) ([]model.FriendProfile, error) {
	return s.repo.ListFriends(ctx, uid)
}

func (s *FriendService) DeleteFriend(ctx context.Context, uid, friendID string) error {
	return s.repo.DeleteFriend(ctx, uid, friendID)
}

func (s *FriendService) BlockUser(ctx context.Context, uid, targetID string) error {
	return s.repo.BlockUser(ctx, uid, targetID)
}
