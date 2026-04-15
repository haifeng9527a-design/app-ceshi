package service

import (
	"context"
	"errors"

	"tongxin-go/internal/model"
)

type ChatProfileService struct {
	userSvc   *UserService
	friendSvc *FriendService
	traderSvc *TraderService
}

func NewChatProfileService(userSvc *UserService, friendSvc *FriendService, traderSvc *TraderService) *ChatProfileService {
	return &ChatProfileService{
		userSvc:   userSvc,
		friendSvc: friendSvc,
		traderSvc: traderSvc,
	}
}

func (s *ChatProfileService) GetChatProfile(ctx context.Context, viewerUID, targetUID string) (*model.ChatProfile, error) {
	if targetUID == "" {
		return nil, errors.New("target uid required")
	}
	if s.userSvc == nil {
		return nil, errors.New("user service unavailable")
	}

	user, err := s.userSvc.GetProfile(ctx, targetUID)
	if err != nil {
		return nil, err
	}

	profile := &model.ChatProfile{
		UID:            user.UID,
		DisplayName:    user.DisplayName,
		AvatarURL:      user.AvatarURL,
		Email:          user.Email,
		ShortID:        user.ShortID,
		Bio:            user.Bio,
		Role:           user.Role,
		Status:         user.Status,
		IsSelf:         viewerUID == targetUID,
		IsSupportAgent: user.IsSupportAgent,
	}

	switch {
	case profile.IsSelf:
		profile.RelationshipStatus = model.ChatRelationshipSelf
	case user.IsSupportAgent:
		profile.RelationshipStatus = model.ChatRelationshipSupport
	case s.friendSvc != nil:
		status, requestID, err := s.friendSvc.GetRelationshipStatus(ctx, viewerUID, targetUID)
		if err != nil {
			return nil, err
		}
		profile.RelationshipStatus = status
		profile.RelationshipRequestID = requestID
	default:
		profile.RelationshipStatus = model.ChatRelationshipNotFriend
	}

	profile.CanAddFriend = profile.RelationshipStatus == model.ChatRelationshipNotFriend
	profile.CanAcceptFriend = profile.RelationshipStatus == model.ChatRelationshipPendingIncoming && profile.RelationshipRequestID != ""

	if user.IsTrader && s.traderSvc != nil {
		trader, err := s.traderSvc.GetTraderProfile(ctx, targetUID, viewerUID)
		if err == nil && trader != nil {
			summary := &model.ChatTraderSummary{
				IsTrader:         trader.IsTrader,
				AllowCopyTrading: trader.AllowCopyTrading,
			}
			if trader.Stats != nil {
				summary.WinRate = trader.Stats.WinRate
				summary.CopiersCount = trader.Stats.FollowersCount
				summary.TotalTrades = trader.Stats.TotalTrades
				summary.TotalPnl = trader.Stats.TotalPnl
			}
			profile.TraderSummary = summary
		}
	}

	return profile, nil
}
