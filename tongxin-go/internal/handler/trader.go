package handler

import (
	"net/http"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

type TraderHandler struct {
	svc        *service.TraderService
	tradingSvc *service.TradingService
}

func NewTraderHandler(svc *service.TraderService, tradingSvc *service.TradingService) *TraderHandler {
	return &TraderHandler{svc: svc, tradingSvc: tradingSvc}
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

	// Optional: extract viewer UID from auth token (may be empty for unauthenticated)
	viewerUID := middleware.GetUserUID(r.Context())

	profile, err := h.svc.GetTraderProfile(r.Context(), traderUID, viewerUID)
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
		// 暴露原始错误（前端用 "has open positions" 来弹「请先平仓」提示）
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "unfollowed"})
}

// PATCH /api/trader/{uid}/follow/capital — 追加 / 赎回跟单池子本金
// body: { "delta": 5000 }  正数为追加，负数为赎回
func (h *TraderHandler) AdjustAllocatedCapital(w http.ResponseWriter, r *http.Request) {
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

	var req model.AdjustAllocatedCapitalRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	if req.Delta == 0 {
		writeError(w, http.StatusBadRequest, "delta must be non-zero")
		return
	}

	ct, err := h.svc.AdjustAllocatedCapital(r.Context(), uid, traderUID, req.Delta)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, ct)
}

// GET /api/trader/{uid}/positions — public: open positions of a trader
func (h *TraderHandler) TraderPositions(w http.ResponseWriter, r *http.Request) {
	traderUID := r.PathValue("uid")
	if traderUID == "" {
		writeError(w, http.StatusBadRequest, "missing trader uid")
		return
	}

	if h.tradingSvc == nil {
		writeJSON(w, http.StatusOK, []model.Position{})
		return
	}

	positions, err := h.tradingSvc.ListPositionsWithPnL(r.Context(), traderUID)
	if err != nil {
		writeJSON(w, http.StatusOK, []model.Position{})
		return
	}
	if positions == nil {
		positions = []model.Position{}
	}

	writeJSON(w, http.StatusOK, positions)
}

// GET /api/trader/{uid}/trades — public: recent closed positions of a trader
func (h *TraderHandler) TraderTrades(w http.ResponseWriter, r *http.Request) {
	traderUID := r.PathValue("uid")
	if traderUID == "" {
		writeError(w, http.StatusBadRequest, "missing trader uid")
		return
	}

	limit := 10
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 {
			limit = n
		}
	}

	if h.tradingSvc == nil {
		writeJSON(w, http.StatusOK, []model.Position{})
		return
	}

	trades, err := h.tradingSvc.ListPositionHistory(r.Context(), traderUID, limit)
	if err != nil {
		writeJSON(w, http.StatusOK, []model.Position{})
		return
	}
	if trades == nil {
		trades = []model.Position{}
	}

	writeJSON(w, http.StatusOK, trades)
}

// GET /api/trader/{uid}/equity — public: equity curve data
func (h *TraderHandler) TraderEquity(w http.ResponseWriter, r *http.Request) {
	traderUID := r.PathValue("uid")
	if traderUID == "" {
		writeError(w, http.StatusBadRequest, "missing trader uid")
		return
	}

	period := r.URL.Query().Get("period")
	if period == "" {
		period = "30d"
	}

	points, err := h.svc.GetEquityHistory(r.Context(), traderUID, period)
	if err != nil {
		writeJSON(w, http.StatusOK, []model.EquityPoint{})
		return
	}
	if points == nil {
		points = []model.EquityPoint{}
	}
	writeJSON(w, http.StatusOK, points)
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

// ── Copy Trading Settings ──

// PUT /api/trader/{uid}/follow/settings
func (h *TraderHandler) UpdateCopySettings(w http.ResponseWriter, r *http.Request) {
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
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	ct, err := h.svc.UpdateCopySettings(r.Context(), uid, traderUID, &req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, ct)
}

// POST /api/trader/{uid}/follow/pause
func (h *TraderHandler) PauseCopyTrading(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	traderUID := r.PathValue("uid")
	if err := h.svc.PauseCopyTrading(r.Context(), uid, traderUID); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "paused"})
}

// POST /api/trader/{uid}/follow/resume
func (h *TraderHandler) ResumeCopyTrading(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	traderUID := r.PathValue("uid")
	if err := h.svc.ResumeCopyTrading(r.Context(), uid, traderUID); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "resumed"})
}

// ── User Follow (Watch) ──

// POST /api/trader/{uid}/watch
func (h *TraderHandler) WatchTrader(w http.ResponseWriter, r *http.Request) {
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
	if err := h.svc.WatchTrader(r.Context(), uid, traderUID); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "followed"})
}

// DELETE /api/trader/{uid}/watch
func (h *TraderHandler) UnwatchTrader(w http.ResponseWriter, r *http.Request) {
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
	if err := h.svc.UnwatchTrader(r.Context(), uid, traderUID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to unfollow")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "unfollowed"})
}

// GET /api/trader/my-watched
func (h *TraderHandler) MyWatchedTraders(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	traders, err := h.svc.GetFollowedTraders(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get watched traders")
		return
	}
	if traders == nil {
		traders = []model.FollowedTrader{}
	}
	writeJSON(w, http.StatusOK, traders)
}

// GET /api/trader/copy-trade-logs
func (h *TraderHandler) CopyTradeLogs(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 {
		limit = 50
	}
	logs, total, err := h.svc.GetCopyTradeLogs(r.Context(), uid, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"logs": logs, "total": total})
}
