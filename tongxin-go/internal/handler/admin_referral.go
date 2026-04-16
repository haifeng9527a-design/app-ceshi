package handler

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
	"tongxin-go/internal/service"
)

// AdminReferralHandler exposes admin-side endpoints for the referral/agent program.
// All endpoints assume admin auth middleware is already applied by the router.
type AdminReferralHandler struct {
	svc *service.ReferralService
}

func NewAdminReferralHandler(svc *service.ReferralService) *AdminReferralHandler {
	return &AdminReferralHandler{svc: svc}
}

// GET /api/admin/agent-applications?status=&limit=&offset=
func (h *AdminReferralHandler) ListApplications(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	status := r.URL.Query().Get("status")
	if status == "" {
		status = "pending"
	}

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	if offset < 0 {
		offset = 0
	}

	applications, total, err := h.svc.AdminListApplications(r.Context(), status, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list applications")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"applications": applications,
		"total":        total,
		"limit":        limit,
		"offset":       offset,
	})
}

// POST /api/admin/agent-applications/{id}/approve
func (h *AdminReferralHandler) ApproveApplication(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	applicationID := r.PathValue("id")
	if applicationID == "" {
		writeError(w, http.StatusBadRequest, "application id is required")
		return
	}

	var req model.ApproveAgentRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	app, err := h.svc.ApproveAgent(r.Context(), applicationID, uid, req.ProposedRate, req.Note)
	if err != nil {
		if errors.Is(err, repository.ErrApplicationNotFound) {
			writeError(w, http.StatusNotFound, "application not found")
			return
		}
		if errors.Is(err, repository.ErrRateOutOfBounds) {
			writeError(w, http.StatusBadRequest, "rate out of allowed bounds")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to approve application")
		return
	}

	writeJSON(w, http.StatusOK, app)
}

// POST /api/admin/agent-applications/{id}/reject
func (h *AdminReferralHandler) RejectApplication(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	applicationID := r.PathValue("id")
	if applicationID == "" {
		writeError(w, http.StatusBadRequest, "application id is required")
		return
	}

	err := h.svc.RejectApplication(r.Context(), applicationID, uid, "")
	if err != nil {
		if errors.Is(err, repository.ErrApplicationNotFound) {
			writeError(w, http.StatusNotFound, "application not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to reject application")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "rejected"})
}

// GET /api/admin/agents?limit=&offset=
func (h *AdminReferralHandler) ListAgents(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	if offset < 0 {
		offset = 0
	}

	agents, total, err := h.svc.AdminListAgents(r.Context(), limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list agents")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"agents": agents,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

// PUT /api/admin/agents/{uid}/set-rate
func (h *AdminReferralHandler) SetAgentRate(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
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

	err := h.svc.AdminSetUserRate(r.Context(), targetUID, req.Rate)
	if err != nil {
		if errors.Is(err, repository.ErrRateOutOfBounds) {
			writeError(w, http.StatusBadRequest, "rate out of allowed bounds")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to set rate")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// POST /api/admin/agents/{uid}/freeze
func (h *AdminReferralHandler) FreezeAgent(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	targetUID := r.PathValue("uid")
	if targetUID == "" {
		writeError(w, http.StatusBadRequest, "target uid is required")
		return
	}

	err := h.svc.AdminSetFrozen(r.Context(), targetUID, true)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to freeze agent")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "frozen"})
}

// POST /api/admin/agents/{uid}/unfreeze
func (h *AdminReferralHandler) UnfreezeAgent(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	targetUID := r.PathValue("uid")
	if targetUID == "" {
		writeError(w, http.StatusBadRequest, "target uid is required")
		return
	}

	err := h.svc.AdminSetFrozen(r.Context(), targetUID, false)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to unfreeze agent")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "unfrozen"})
}

// GET /api/admin/commission/daily-report?date=
func (h *AdminReferralHandler) DailyReport(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	dateStr := r.URL.Query().Get("date")
	var date time.Time
	if dateStr != "" {
		date, _ = time.Parse("2006-01-02", dateStr)
	}
	if date.IsZero() {
		date = time.Now().UTC().AddDate(0, 0, -1)
	}

	report, err := h.svc.AdminDailyReport(r.Context(), date)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to generate daily report")
		return
	}

	writeJSON(w, http.StatusOK, report)
}

// GET /api/admin/platform-config
func (h *AdminReferralHandler) GetPlatformConfig(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	cfg := h.svc.GetPlatformConfig()

	writeJSON(w, http.StatusOK, cfg)
}

// PATCH /api/admin/platform-config
// MVP: returns current config; runtime config changes deferred to a future release.
func (h *AdminReferralHandler) UpdatePlatformConfig(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	cfg := h.svc.GetPlatformConfig()

	writeJSON(w, http.StatusOK, cfg)
}
