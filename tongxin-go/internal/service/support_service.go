package service

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

var (
	ErrSupportAssignmentNotFound = errors.New("support assignment not found")
	ErrSupportAgentNotFound      = errors.New("support agent not found")
	ErrSupportAgentUnavailable   = errors.New("support agent unavailable")
	ErrSupportAgentViewer        = errors.New("support agent does not require support assignment")
)

type SupportService struct {
	repo     *repository.SupportRepo
	userRepo *repository.UserRepo
	convRepo *repository.ConversationRepo
}

func NewSupportService(repo *repository.SupportRepo, userRepo *repository.UserRepo, convRepo *repository.ConversationRepo) *SupportService {
	return &SupportService{repo: repo, userRepo: userRepo, convRepo: convRepo}
}

func (s *SupportService) ListAgents(ctx context.Context) ([]model.User, error) {
	agents, err := s.userRepo.ListSupportAgents(ctx)
	if err != nil {
		return nil, err
	}
	if agents == nil {
		agents = []model.User{}
	}
	return agents, nil
}

func (s *SupportService) GetAgentLoads(ctx context.Context, agentUIDs []string) ([]model.SupportAgentLoad, error) {
	counts, err := s.repo.CountActiveByAgentUIDs(ctx, agentUIDs)
	if err != nil {
		return nil, err
	}
	loads := make([]model.SupportAgentLoad, 0, len(counts))
	for _, uid := range agentUIDs {
		loads = append(loads, model.SupportAgentLoad{
			AgentUID:        uid,
			ActiveCustomers: counts[uid],
		})
	}
	return loads, nil
}

func (s *SupportService) GetAssignment(ctx context.Context, customerUID string) (*model.SupportAssignmentDetail, error) {
	customer, err := s.userRepo.GetByUID(ctx, customerUID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrSupportAssignmentNotFound
		}
		return nil, err
	}
	if customer.IsSupportAgent {
		return nil, ErrSupportAgentViewer
	}

	item, err := s.repo.GetActiveByCustomer(ctx, customerUID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrSupportAssignmentNotFound
		}
		return nil, err
	}
	return s.buildDetail(ctx, item)
}

func (s *SupportService) EnsureAssignment(ctx context.Context, customerUID string) (*model.SupportAssignmentDetail, error) {
	detail, err := s.GetAssignment(ctx, customerUID)
	if err == nil && detail != nil && detail.Agent != nil && detail.Agent.IsSupportAgent && detail.Agent.Status == "active" {
		return detail, nil
	}
	if errors.Is(err, ErrSupportAgentViewer) {
		return nil, ErrSupportAgentViewer
	}
	if err != nil && !errors.Is(err, ErrSupportAssignmentNotFound) {
		return nil, err
	}

	agents, err := s.ListAgents(ctx)
	if err != nil {
		return nil, err
	}
	if len(agents) == 0 {
		return nil, ErrSupportAgentUnavailable
	}
	selectedAgentUID := ""
	for _, agent := range agents {
		if agent.UID != customerUID {
			selectedAgentUID = agent.UID
			break
		}
	}
	if selectedAgentUID == "" {
		selectedAgentUID = agents[0].UID
	}

	return s.AssignAgent(ctx, nil, customerUID, selectedAgentUID)
}

func (s *SupportService) AssignAgent(ctx context.Context, assignedBy *string, customerUID, agentUID string) (*model.SupportAssignmentDetail, error) {
	if customerUID == "" || agentUID == "" {
		return nil, ErrSupportAgentNotFound
	}

	customer, err := s.userRepo.GetByUID(ctx, customerUID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrSupportAssignmentNotFound
		}
		return nil, err
	}
	if customer.Status != "active" {
		return nil, ErrSupportAssignmentNotFound
	}

	agent, err := s.userRepo.GetByUID(ctx, agentUID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrSupportAgentNotFound
		}
		return nil, err
	}
	if !agent.IsSupportAgent || agent.Status != "active" {
		return nil, ErrSupportAgentUnavailable
	}

	conversation, _, err := s.convRepo.CreateDirect(ctx, customerUID, agentUID)
	if err != nil {
		return nil, err
	}

	item, err := s.repo.ReplaceActive(ctx, customerUID, agentUID, assignedBy, conversation.ID)
	if err != nil {
		return nil, err
	}
	return s.buildDetail(ctx, item)
}

func (s *SupportService) buildDetail(ctx context.Context, item *model.SupportAssignment) (*model.SupportAssignmentDetail, error) {
	agent, err := s.userRepo.GetByUID(ctx, item.AgentUID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrSupportAgentNotFound
		}
		return nil, err
	}

	return &model.SupportAssignmentDetail{
		Assignment: item,
		Agent:      agent,
	}, nil
}
