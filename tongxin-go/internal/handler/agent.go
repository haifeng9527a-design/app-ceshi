package handler

import (
	"errors"
	"net/http"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
	"tongxin-go/internal/service"
)

// AgentHandler exposes agent-side endpoints for the referral/agent program.
type AgentHandler struct {
	svc *service.ReferralService
}

func NewAgentHandler(svc *service.ReferralService) *AgentHandler {
	return &AgentHandler{svc: svc}
}

// requireAgent extracts the caller UID from the request context.
// The actual is_agent authorization check is performed in the service layer.
func requireAgent(r *http.Request) (string, error) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		return "", errors.New("authentication required")
	}
	return uid, nil
}

// handleServiceError maps known sentinel errors to appropriate HTTP status codes.
func handleServiceError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, repository.ErrNotDirectChild):
		writeError(w, http.StatusBadRequest, "target is not your direct invitee")
	case errors.Is(err, repository.ErrRateExceedsParent):
		writeError(w, http.StatusBadRequest, "rate exceeds your own rate")
	case errors.Is(err, repository.ErrRateOutOfBounds):
		writeError(w, http.StatusBadRequest, "rate out of bounds")
	case errors.Is(err, repository.ErrApplicationExists):
		writeError(w, http.StatusConflict, "application already pending")
	default:
		writeError(w, http.StatusInternalServerError, "internal server error")
	}
}

// POST /api/agent/apply
func (h *AgentHandler) Apply(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.ApplyAgentRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	app, err := h.svc.ApplyForAgent(r.Context(), uid, &req)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, app)
}

// GET /api/agent/application-status
func (h *AgentHandler) ApplicationStatus(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	app, err := h.svc.GetMyApplicationStatus(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load application status")
		return
	}
	if app == nil {
		writeError(w, http.StatusNotFound, "no application found")
		return
	}

	writeJSON(w, http.StatusOK, app)
}

// GET /api/agent/dashboard-summary
func (h *AgentHandler) DashboardSummary(w http.ResponseWriter, r *http.Request) {
	uid, err := requireAgent(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err.Error())
		return
	}

	summary, err := h.svc.GetAgentDashboard(r.Context(), uid)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, summary)
}

// GET /api/agent/invite-links
func (h *AgentHandler) ListInviteLinks(w http.ResponseWriter, r *http.Request) {
	uid, err := requireAgent(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err.Error())
		return
	}

	links, err := h.svc.ListMyInviteLinks(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load invite links")
		return
	}

	writeJSON(w, http.StatusOK, links)
}

// POST /api/agent/invite-links
func (h *AgentHandler) CreateInviteLink(w http.ResponseWriter, r *http.Request) {
	uid, err := requireAgent(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err.Error())
		return
	}

	var req model.CreateInviteLinkRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	link, err := h.svc.CreateMyInviteLink(r.Context(), uid, &req)
	if err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, link)
}

// DELETE /api/agent/invite-links/{id}
func (h *AgentHandler) DisableInviteLink(w http.ResponseWriter, r *http.Request) {
	uid, err := requireAgent(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err.Error())
		return
	}

	linkID := r.PathValue("id")
	if linkID == "" {
		writeError(w, http.StatusBadRequest, "link id is required")
		return
	}

	if err := h.svc.DisableMyInviteLink(r.Context(), uid, linkID); err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "disabled"})
}

// GET /api/agent/sub-agents
func (h *AgentHandler) ListSubAgents(w http.ResponseWriter, r *http.Request) {
	uid, err := requireAgent(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err.Error())
		return
	}

	subs, err := h.svc.ListSubAgents(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load sub-agents")
		return
	}

	writeJSON(w, http.StatusOK, subs)
}

// POST /api/agent/sub-agents/{uid}/promote
func (h *AgentHandler) PromoteSubAgent(w http.ResponseWriter, r *http.Request) {
	callerUID, err := requireAgent(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err.Error())
		return
	}

	targetUID := r.PathValue("uid")
	if targetUID == "" {
		writeError(w, http.StatusBadRequest, "target uid is required")
		return
	}

	var req model.SetRateRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.svc.AgentPromoteSub(r.Context(), callerUID, targetUID, req.Rate); err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "promoted"})
}

// PUT /api/agent/sub-agents/{uid}/rate
func (h *AgentHandler) SetSubAgentRate(w http.ResponseWriter, r *http.Request) {
	callerUID, err := requireAgent(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err.Error())
		return
	}

	targetUID := r.PathValue("uid")
	if targetUID == "" {
		writeError(w, http.StatusBadRequest, "target uid is required")
		return
	}

	var req model.SetRateRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.svc.AgentSetSubRate(r.Context(), callerUID, targetUID, req.Rate); err != nil {
		handleServiceError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}
