package handler

import (
	"errors"
	"net/http"
	"strings"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
	"tongxin-go/internal/ws"
)

type SupportHandler struct {
	svc     *service.SupportService
	chatHub *ws.ChatHub
}

func NewSupportHandler(svc *service.SupportService, chatHub *ws.ChatHub) *SupportHandler {
	return &SupportHandler{svc: svc, chatHub: chatHub}
}

func (h *SupportHandler) enrich(detail *model.SupportAssignmentDetail) *model.SupportAssignmentDetail {
	if detail == nil {
		return nil
	}
	if detail.Agent != nil {
		detail.AgentOnline = h.chatHub != nil && h.chatHub.IsUserConnected(detail.Agent.UID)
	}
	return detail
}

// GET /api/admin/support/agents
func (h *SupportHandler) ListAgents(w http.ResponseWriter, r *http.Request) {
	agents, err := h.svc.ListAgents(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list support agents")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"agents": agents})
}

// GET /api/admin/support/agent-loads?uids=a,b,c
func (h *SupportHandler) AgentLoads(w http.ResponseWriter, r *http.Request) {
	rawUIDs := strings.Split(strings.TrimSpace(r.URL.Query().Get("uids")), ",")
	agentUIDs := make([]string, 0, len(rawUIDs))
	seen := make(map[string]struct{})
	for _, uid := range rawUIDs {
		uid = strings.TrimSpace(uid)
		if uid == "" {
			continue
		}
		if _, ok := seen[uid]; ok {
			continue
		}
		seen[uid] = struct{}{}
		agentUIDs = append(agentUIDs, uid)
	}

	loads, err := h.svc.GetAgentLoads(r.Context(), agentUIDs)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get support agent loads")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"loads": loads})
}

// GET /api/admin/users/{uid}/support-assignment
func (h *SupportHandler) AdminGetAssignment(w http.ResponseWriter, r *http.Request) {
	customerUID := r.PathValue("uid")
	detail, err := h.svc.GetAssignment(r.Context(), customerUID)
	if err != nil {
		if errors.Is(err, service.ErrSupportAssignmentNotFound) {
			writeJSON(w, http.StatusOK, map[string]any{"assignment": nil})
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to get support assignment")
		return
	}
	writeJSON(w, http.StatusOK, h.enrich(detail))
}

// POST /api/admin/users/{uid}/support-assignment
func (h *SupportHandler) AdminAssign(w http.ResponseWriter, r *http.Request) {
	customerUID := r.PathValue("uid")
	var body model.AssignSupportAgentRequest
	if err := decodeJSON(r, &body); err != nil || body.AgentUID == "" {
		writeError(w, http.StatusBadRequest, "agent_uid is required")
		return
	}

	adminUID := middleware.GetUserUID(r.Context())
	assignedBy := &adminUID
	detail, err := h.svc.AssignAgent(r.Context(), assignedBy, customerUID, body.AgentUID)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrSupportAgentNotFound):
			writeError(w, http.StatusNotFound, "support agent not found")
		case errors.Is(err, service.ErrSupportAgentUnavailable):
			writeError(w, http.StatusBadRequest, "support agent is unavailable")
		case errors.Is(err, service.ErrSupportAssignmentNotFound):
			writeError(w, http.StatusNotFound, "customer not found")
		default:
			writeError(w, http.StatusInternalServerError, "failed to assign support agent")
		}
		return
	}
	writeJSON(w, http.StatusOK, h.enrich(detail))
}

// GET /api/support/me
func (h *SupportHandler) GetMyAssignment(w http.ResponseWriter, r *http.Request) {
	customerUID := middleware.GetUserUID(r.Context())
	if customerUID == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	detail, err := h.svc.GetAssignment(r.Context(), customerUID)
	if err != nil {
		if errors.Is(err, service.ErrSupportAssignmentNotFound) || errors.Is(err, service.ErrSupportAgentViewer) {
			writeJSON(w, http.StatusOK, map[string]any{"assignment": nil})
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to get support assignment")
		return
	}
	writeJSON(w, http.StatusOK, h.enrich(detail))
}

// POST /api/support/me/ensure
func (h *SupportHandler) EnsureMyAssignment(w http.ResponseWriter, r *http.Request) {
	customerUID := middleware.GetUserUID(r.Context())
	if customerUID == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	detail, err := h.svc.EnsureAssignment(r.Context(), customerUID)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrSupportAgentViewer):
			writeJSON(w, http.StatusOK, map[string]any{"assignment": nil})
			return
		case errors.Is(err, service.ErrSupportAgentUnavailable):
			writeError(w, http.StatusNotFound, "no support agent available")
		case errors.Is(err, service.ErrSupportAssignmentNotFound):
			writeError(w, http.StatusNotFound, "customer not found")
		default:
			writeError(w, http.StatusInternalServerError, "failed to ensure support assignment")
		}
		return
	}
	writeJSON(w, http.StatusOK, h.enrich(detail))
}
