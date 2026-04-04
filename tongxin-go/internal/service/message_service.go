package service

import (
	"context"
	"time"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

type MessageService struct {
	msgRepo  *repository.MessageRepo
	convRepo *repository.ConversationRepo
}

func NewMessageService(msgRepo *repository.MessageRepo, convRepo *repository.ConversationRepo) *MessageService {
	return &MessageService{msgRepo: msgRepo, convRepo: convRepo}
}

func (s *MessageService) SendMessage(ctx context.Context, uid string, req *model.SendMessageRequest) (*model.Message, error) {
	msg := &model.Message{
		ConversationID:   req.ConversationID,
		SenderID:         uid,
		Content:          req.Content,
		MessageType:      req.MessageType,
		MediaURL:         req.MediaURL,
		ReplyToMessageID: req.ReplyToID,
	}
	if err := s.msgRepo.Create(ctx, msg); err != nil {
		return nil, err
	}
	return msg, nil
}

func (s *MessageService) ListMessages(ctx context.Context, conversationID string, limit int, before *time.Time) ([]model.Message, error) {
	return s.msgRepo.ListByConversation(ctx, conversationID, limit, before)
}

func (s *MessageService) DeleteMessage(ctx context.Context, id, senderID string) error {
	return s.msgRepo.Delete(ctx, id, senderID)
}

// Conversation operations delegated
func (s *MessageService) ListConversations(ctx context.Context, uid string) ([]model.Conversation, error) {
	return s.convRepo.ListByUser(ctx, uid)
}

func (s *MessageService) GetConversation(ctx context.Context, id string) (*model.Conversation, error) {
	return s.convRepo.GetByID(ctx, id)
}

func (s *MessageService) CreateDirect(ctx context.Context, uid, peerID string) (*model.Conversation, bool, error) {
	return s.convRepo.CreateDirect(ctx, uid, peerID)
}

func (s *MessageService) CreateGroup(ctx context.Context, uid string, req *model.CreateGroupRequest) (*model.Conversation, error) {
	return s.convRepo.CreateGroup(ctx, uid, req)
}

func (s *MessageService) MarkAsRead(ctx context.Context, uid, conversationID string) error {
	return s.convRepo.MarkAsRead(ctx, uid, conversationID)
}

func (s *MessageService) GetUnreadCount(ctx context.Context, uid string) (int, error) {
	return s.convRepo.GetUnreadCount(ctx, uid)
}

func (s *MessageService) GetGroupInfo(ctx context.Context, conversationID string) (*model.Conversation, []model.ConversationMember, error) {
	return s.convRepo.GetGroupInfo(ctx, conversationID)
}

func (s *MessageService) GetMemberIDs(ctx context.Context, conversationID string) ([]string, error) {
	return s.convRepo.GetMemberIDs(ctx, conversationID)
}
