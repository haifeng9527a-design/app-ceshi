package service

import (
	"context"
	"fmt"
	"strings"
	"time"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

type CallService struct {
	callRepo *repository.CallRepo
	convRepo *repository.ConversationRepo
}

func NewCallService(callRepo *repository.CallRepo, convRepo *repository.ConversationRepo) *CallService {
	return &CallService{callRepo: callRepo, convRepo: convRepo}
}

func (s *CallService) Start(ctx context.Context, uid string, req *model.StartCallRequest) (*model.Call, []string, error) {
	if strings.TrimSpace(req.ConversationID) == "" {
		return nil, nil, fmt.Errorf("conversation_id is required")
	}

	ok, err := s.convRepo.IsUserInConversation(ctx, uid, req.ConversationID)
	if err != nil {
		return nil, nil, err
	}
	if !ok {
		return nil, nil, ErrNotConversationMember
	}

	if active, err := s.callRepo.FindActiveByConversation(ctx, req.ConversationID); err == nil && active != nil {
		return nil, nil, fmt.Errorf("call already in progress")
	}

	callType := strings.TrimSpace(req.CallType)
	if callType == "" {
		callType = "voice"
	}
	roomName := fmt.Sprintf("call:%s:%d", req.ConversationID, time.Now().Unix())
	call, err := s.callRepo.Create(ctx, req.ConversationID, uid, roomName, callType)
	if err != nil {
		return nil, nil, err
	}
	memberIDs, err := s.convRepo.GetMemberIDs(ctx, req.ConversationID)
	if err != nil {
		return nil, nil, err
	}
	return call, memberIDs, nil
}

func (s *CallService) Get(ctx context.Context, uid, callID string) (*model.Call, []string, error) {
	call, err := s.callRepo.GetByID(ctx, callID)
	if err != nil {
		return nil, nil, err
	}
	ok, err := s.convRepo.IsUserInConversation(ctx, uid, call.ConversationID)
	if err != nil {
		return nil, nil, err
	}
	if !ok {
		return nil, nil, ErrForbidden
	}
	memberIDs, err := s.convRepo.GetMemberIDs(ctx, call.ConversationID)
	if err != nil {
		return nil, nil, err
	}
	return call, memberIDs, nil
}

func (s *CallService) Accept(ctx context.Context, uid, callID string) (*model.Call, []string, error) {
	call, members, err := s.Get(ctx, uid, callID)
	if err != nil {
		return nil, nil, err
	}
	if call.Status != "ringing" {
		return nil, nil, fmt.Errorf("call is not ringing")
	}
	updated, err := s.callRepo.Accept(ctx, callID)
	if err != nil {
		return nil, nil, err
	}
	return updated, members, nil
}

func (s *CallService) Reject(ctx context.Context, uid, callID, reason string) (*model.Call, []string, error) {
	call, members, err := s.Get(ctx, uid, callID)
	if err != nil {
		return nil, nil, err
	}
	if call.Status != "ringing" {
		return nil, nil, fmt.Errorf("call is not ringing")
	}
	updated, err := s.callRepo.Reject(ctx, callID, uid, strings.TrimSpace(reason))
	if err != nil {
		return nil, nil, err
	}
	return updated, members, nil
}

func (s *CallService) End(ctx context.Context, uid, callID, reason string) (*model.Call, []string, error) {
	call, members, err := s.Get(ctx, uid, callID)
	if err != nil {
		return nil, nil, err
	}
	if call.Status != "ringing" && call.Status != "active" {
		return nil, nil, fmt.Errorf("call already finished")
	}
	updated, err := s.callRepo.End(ctx, callID, uid, strings.TrimSpace(reason))
	if err != nil {
		return nil, nil, err
	}
	return updated, members, nil
}
