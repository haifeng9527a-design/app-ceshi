package handler

import (
	"net/http"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

type TraderHandler struct {
	svc *service.TraderService
}

func NewTraderHandler(svc *service.TraderService) *TraderHandler {
	return &TraderHandler{svc: svc}
}

// POST /api/trader/apply
func (h *TraderHandler) Apply(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.SubmitApplicationRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	app, err := h.svc.SubmitApplication(r.Context(), uid, &req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusCreated, app)
}

// GET /api/trader/my-application
func (h *TraderHandler) MyApplication(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	app, err := h.svc.GetMyApplication(r.Context(), uid)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"application": nil})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"application": app})
}

// GET /api/trader/my-stats
func (h *TraderHandler) MyStats(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	stats, err := h.svc.GetTraderStats(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get stats")
		return
	}

	writeJSON(w, http.StatusOK, stats)
}

// PUT /api/trader/copy-trading-toggle
func (h *TraderHandler) ToggleCopyTrading(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.ToggleCopyTradingRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.svc.ToggleCopyTrading(r.Context(), uid, req.Allow); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to toggle")
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"allow_copy_trading": req.Allow})
}

// GET /api/trader/my-followers
func (h *TraderHandler) MyFollowers(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	followers, err := h.svc.GetMyFollowers(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get followers")
		return
	}
	if followers == nil {
		followers = []model.CopyTrading{}
	}

	writeJSON(w, http.StatusOK, followers)
}

// GET /api/trader/my-following
func (h *TraderHandler) MyFollowing(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	following, err := h.svc.GetMyFollowing(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get following")
		return
	}
	if following == nil {
		following = []model.CopyTrading{}
	}

	writeJSON(w, http.StatusOK, following)
}

// GET /api/trader/rankings
func (h *TraderHandler) Rankings(w http.ResponseWriter, r *http.Request) {
	sortBy := r.URL.Query().Get("sort")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 {
		limit = 20
	}

	items, total, err := h.svc.GetTraderRankings(r.Context(), sortBy, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get rankings")
		return
	}
	if items == nil {
		items = []model.TraderRankingItem{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"traders": items, "total": total})
}

// GET /api/trader/{uid}/profile
func (h *TraderHandler) TraderProfile(w http.ResponseWriter, r *http.Request) {
	traderUID := r.PathValue("uid")
	if traderUID == "" {
		writeError(w, http.StatusBadRequest, "missing trader uid")
		return
	}

	profile, err := h.svc.GetTraderProfile(r.Context(), traderUID)
	if err != nil {
		writeError(w, http.StatusNotFound, "trader not found")
		return
	}

	writeJSON(w, http.StatusOK, profile)
}

// POST /api/trader/{uid}/follow
func (h *TraderHandler) FollowTrader(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	traderUID := r.PathValue("uid")
	if traderUID == "" {
		writeError(w, http.StatusBadRequest, "missing trader uid")
		return
	}

	var req model.FollowTraderRequest
	if err := decodeJSON(r, &req); err != nil {
		// Default values
		req.CopyRatio = 1.0
	}

	ct, err := h.svc.FollowTrader(r.Context(), uid, traderUID, &req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusCreated, ct)
}

// DELETE /api/trader/{uid}/follow
func (h *TraderHandler) UnfollowTrader(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	traderUID := r.PathValue("uid")
	if traderUID == "" {
		writeError(w, http.StatusBadRequest, "missing trader uid")
		return
	}

	if err := h.svc.UnfollowTrader(r.Context(), uid, traderUID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to unfollow")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "unfollowed"})
}

// ── Admin Handlers ──

// GET /api/admin/trader-applications
func (h *TraderHandler) AdminListApplications(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 {
		limit = 20
	}

	apps, total, err := h.svc.ListApplications(r.Context(), status, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list applications")
		return
	}
	if apps == nil {
		apps = []model.TraderApplication{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"applications": apps, "total": total})
}

// POST /api/admin/trader-applications/{id}/approve
func (h *TraderHandler) AdminApprove(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	appID := r.PathValue("id")

	if err := h.svc.ApproveApplication(r.Context(), appID, uid); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "approved"})
}

// POST /api/admin/trader-applications/{id}/reject
func (h *TraderHandler) AdminReject(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	appID := r.PathValue("id")

	var req model.RejectApplicationRequest
	if err := decodeJSON(r, &req); err != nil {
		req.Reason = ""
	}

	if err := h.svc.RejectApplication(r.Context(), appID, uid, req.Reason); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "rejected"})
}
