package handler

import (
	"net/http"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
	"tongxin-go/internal/service"
)

// ReferralHandler exposes user-facing referral endpoints.
// All users (including non-agents) can see their invite overview and share codes.
type ReferralHandler struct {
	svc *service.ReferralService
}

func NewReferralHandler(svc *service.ReferralService) *ReferralHandler {
	return &ReferralHandler{svc: svc}
}

// GET /api/referral/me — overview (my rate, lifetime, this month, invite count, is_agent)
func (h *ReferralHandler) GetOverview(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	overview, err := h.svc.GetOverview(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load referral overview")
		return
	}

	writeJSON(w, http.StatusOK, overview)
}

// GET /api/referral/commission-records?kind=&limit=&offset=
func (h *ReferralHandler) ListCommissionRecords(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	kind := r.URL.Query().Get("kind")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	if offset < 0 {
		offset = 0
	}

	records, total, err := h.svc.ListMyCommissionRecords(r.Context(), uid, kind, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load commission records")
		return
	}

	// Ensure records is never null in JSON (frontend expects array)
	if records == nil {
		records = []*model.CommissionRecord{}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"records": records,
		"total":   total,
		"limit":   limit,
		"offset":  offset,
	})
}

// GET /api/referral/invitees?limit=&offset=
func (h *ReferralHandler) ListInvitees(w http.ResponseWriter, r *http.Request) {
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

	invitees, total, err := h.svc.ListMyInvitees(r.Context(), uid, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load invitees")
		return
	}

	if invitees == nil {
		invitees = []repository.InviteeRow{}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"invitees": invitees,
		"total":    total,
		"limit":    limit,
		"offset":   offset,
	})
}

// POST /api/referral/validate-code?code=XXX (public — no auth needed, used before register)
func (h *ReferralHandler) ValidateCode(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("code")
	if code == "" {
		writeError(w, http.StatusBadRequest, "code is required")
		return
	}

	valid, ownerName, err := h.svc.ValidateInviteCodeFull(r.Context(), code)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "validation failed")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"valid":      valid,
		"owner_name": ownerName,
	})
}
