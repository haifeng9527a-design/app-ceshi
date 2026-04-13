package handler

import (
	"net/http"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/repository"
	"tongxin-go/internal/service"
)

type AdminTradingHandler struct {
	tradingSvc  *service.TradingService
	feeRepo     *repository.FeeRepo
	walletRepo  *repository.WalletRepo
	posRepo     *repository.PositionRepo
	orderRepo   *repository.OrderRepo
	userRepo    *repository.UserRepo
	revenueRepo *repository.RevenueRepo
	tpaRepo     *repository.ThirdPartyApiRepo
}

func NewAdminTradingHandler(
	tradingSvc *service.TradingService,
	feeRepo *repository.FeeRepo,
	walletRepo *repository.WalletRepo,
	posRepo *repository.PositionRepo,
	orderRepo *repository.OrderRepo,
	userRepo *repository.UserRepo,
	revenueRepo *repository.RevenueRepo,
	tpaRepo *repository.ThirdPartyApiRepo,
) *AdminTradingHandler {
	return &AdminTradingHandler{
		tradingSvc:  tradingSvc,
		feeRepo:     feeRepo,
		walletRepo:  walletRepo,
		posRepo:     posRepo,
		orderRepo:   orderRepo,
		userRepo:    userRepo,
		revenueRepo: revenueRepo,
		tpaRepo:     tpaRepo,
	}
}

// ═══════════════════════════════════════════════════════════════════
// Phase 1: Fee Management
// ═══════════════════════════════════════════════════════════════════

// GET /api/admin/fee-tiers
func (h *AdminTradingHandler) ListFeeTiers(w http.ResponseWriter, r *http.Request) {
	tiers, err := h.feeRepo.ListAll(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list fee tiers")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tiers": tiers})
}

// PUT /api/admin/fee-tiers/{level}
func (h *AdminTradingHandler) UpdateFeeTier(w http.ResponseWriter, r *http.Request) {
	level, err := strconv.Atoi(r.PathValue("level"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid level")
		return
	}
	var req struct {
		MakerFee  float64 `json:"maker_fee"`
		TakerFee  float64 `json:"taker_fee"`
		MinVolume float64 `json:"min_volume"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	uid := middleware.GetUserUID(r.Context())

	existing, err := h.feeRepo.GetByLevel(r.Context(), level)
	if err != nil {
		writeError(w, http.StatusNotFound, "fee tier not found")
		return
	}
	existing.MakerFee = req.MakerFee
	existing.TakerFee = req.TakerFee
	existing.MinVolume = req.MinVolume
	existing.UpdatedBy = uid

	if err := h.feeRepo.Upsert(r.Context(), *existing); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update fee tier")
		return
	}

	h.tradingSvc.ReloadFeeSchedule(r.Context())
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// POST /api/admin/fee-tiers
func (h *AdminTradingHandler) CreateFeeTier(w http.ResponseWriter, r *http.Request) {
	var req struct {
		VipLevel  int     `json:"vip_level"`
		MakerFee  float64 `json:"maker_fee"`
		TakerFee  float64 `json:"taker_fee"`
		MinVolume float64 `json:"min_volume"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	uid := middleware.GetUserUID(r.Context())

	tier := repository.FeeTierFromModel(req.VipLevel, req.MakerFee, req.TakerFee, req.MinVolume, uid)
	if err := h.feeRepo.Upsert(r.Context(), tier); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create fee tier")
		return
	}

	h.tradingSvc.ReloadFeeSchedule(r.Context())
	writeJSON(w, http.StatusOK, map[string]string{"status": "created"})
}

// DELETE /api/admin/fee-tiers/{level}
func (h *AdminTradingHandler) DeleteFeeTier(w http.ResponseWriter, r *http.Request) {
	level, err := strconv.Atoi(r.PathValue("level"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid level")
		return
	}
	if err := h.feeRepo.Delete(r.Context(), level); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to delete fee tier")
		return
	}
	h.tradingSvc.ReloadFeeSchedule(r.Context())
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// POST /api/admin/users/{uid}/vip-level
func (h *AdminTradingHandler) SetUserVipLevel(w http.ResponseWriter, r *http.Request) {
	targetUID := r.PathValue("uid")
	var req struct {
		VipLevel int `json:"vip_level"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if err := h.userRepo.UpdateVipLevel(r.Context(), targetUID, req.VipLevel); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to set VIP level")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// GET /api/admin/fee-stats
func (h *AdminTradingHandler) GetFeeStats(w http.ResponseWriter, r *http.Request) {
	stats, err := h.walletRepo.GetPlatformFeeStats(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get fee stats")
		return
	}
	writeJSON(w, http.StatusOK, stats)
}

// ═══════════════════════════════════════════════════════════════════
// Phase 2: Position Monitoring
// ═══════════════════════════════════════════════════════════════════

// GET /api/admin/positions
func (h *AdminTradingHandler) ListAllPositions(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	offset, _ := strconv.Atoi(q.Get("offset"))
	if limit <= 0 {
		limit = 50
	}

	filters := repository.PositionFilters{
		Status:      q.Get("status"),
		Symbol:      q.Get("symbol"),
		UserID:      q.Get("user_id"),
		Side:        q.Get("side"),
		IsCopyTrade: q.Get("is_copy_trade"),
		Limit:       limit,
		Offset:      offset,
	}

	positions, total, err := h.posRepo.ListAllFiltered(r.Context(), filters)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list positions")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"positions": positions, "total": total})
}

// GET /api/admin/positions/summary
func (h *AdminTradingHandler) PositionsSummary(w http.ResponseWriter, r *http.Request) {
	summary, err := h.posRepo.GetOpenSummary(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get position summary")
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

// ═══════════════════════════════════════════════════════════════════
// Phase 3: Liquidation Data
// ═══════════════════════════════════════════════════════════════════

// GET /api/admin/liquidations
func (h *AdminTradingHandler) ListLiquidations(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	offset, _ := strconv.Atoi(q.Get("offset"))
	if limit <= 0 {
		limit = 50
	}

	filters := repository.LiquidationFilters{
		Symbol:   q.Get("symbol"),
		UserID:   q.Get("user_id"),
		DateFrom: q.Get("date_from"),
		DateTo:   q.Get("date_to"),
		Limit:    limit,
		Offset:   offset,
	}

	positions, total, err := h.posRepo.ListLiquidated(r.Context(), filters)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list liquidations")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"liquidations": positions, "total": total})
}

// GET /api/admin/liquidations/stats
func (h *AdminTradingHandler) LiquidationStats(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	stats, err := h.posRepo.GetLiquidationStats(r.Context(), q.Get("date_from"), q.Get("date_to"))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get liquidation stats")
		return
	}
	writeJSON(w, http.StatusOK, stats)
}

// ═══════════════════════════════════════════════════════════════════
// Phase 4: Financial Management
// ═══════════════════════════════════════════════════════════════════

// GET /api/admin/revenue/daily
func (h *AdminTradingHandler) DailyRevenue(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	rows, err := h.revenueRepo.ListDaily(r.Context(), q.Get("date_from"), q.Get("date_to"))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get daily revenue")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"rows": rows})
}

// GET /api/admin/revenue/summary
func (h *AdminTradingHandler) RevenueSummary(w http.ResponseWriter, r *http.Request) {
	summary, err := h.revenueRepo.GetSummary(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get revenue summary")
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

// POST /api/admin/revenue/snapshot
func (h *AdminTradingHandler) TriggerSnapshot(w http.ResponseWriter, r *http.Request) {
	if err := h.revenueRepo.CalcAndUpsertToday(r.Context()); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to trigger snapshot")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// ═══════════════════════════════════════════════════════════════════
// Phase 5: Third-Party API Management
// ═══════════════════════════════════════════════════════════════════

// GET /api/admin/third-party-apis
func (h *AdminTradingHandler) ListThirdPartyApis(w http.ResponseWriter, r *http.Request) {
	apis, err := h.tpaRepo.ListAll(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list third-party APIs")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"apis": apis})
}

// GET /api/admin/third-party-apis/{name}
func (h *AdminTradingHandler) GetThirdPartyApi(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	api, err := h.tpaRepo.GetByName(r.Context(), name)
	if err != nil {
		writeError(w, http.StatusNotFound, "API service not found")
		return
	}
	writeJSON(w, http.StatusOK, api)
}

// PUT /api/admin/third-party-apis/{name}
func (h *AdminTradingHandler) UpdateThirdPartyApi(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	uid := middleware.GetUserUID(r.Context())

	var req struct {
		ApiKey      *string `json:"api_key,omitempty"`
		ApiSecret   *string `json:"api_secret,omitempty"`
		BaseURL     *string `json:"base_url,omitempty"`
		WsURL       *string `json:"ws_url,omitempty"`
		Description *string `json:"description,omitempty"`
		Reason      string  `json:"reason"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.tpaRepo.Update(r.Context(), name, repository.TpaUpdateFields{
		ApiKey:      req.ApiKey,
		ApiSecret:   req.ApiSecret,
		BaseURL:     req.BaseURL,
		WsURL:       req.WsURL,
		Description: req.Description,
		UpdatedBy:   uid,
		Reason:      req.Reason,
	}); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update API config")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// POST /api/admin/third-party-apis/{name}/toggle
func (h *AdminTradingHandler) ToggleThirdPartyApi(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if err := h.tpaRepo.ToggleActive(r.Context(), name); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to toggle API status")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "toggled"})
}

// POST /api/admin/third-party-apis/{name}/verify
func (h *AdminTradingHandler) VerifyThirdPartyApi(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	result, err := h.tpaRepo.Verify(r.Context(), name)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "verification failed")
		return
	}
	writeJSON(w, http.StatusOK, result)
}

// GET /api/admin/third-party-apis/{name}/history
func (h *AdminTradingHandler) ApiKeyHistory(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 20
	}
	history, err := h.tpaRepo.ListHistory(r.Context(), name, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list key history")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"history": history})
}

// ═══════════════════════════════════════════════════════════════════
// Phase 6: Trading & Wallet Overview
// ═══════════════════════════════════════════════════════════════════

// GET /api/admin/trading-stats
func (h *AdminTradingHandler) TradingStats(w http.ResponseWriter, r *http.Request) {
	stats, err := h.posRepo.GetTradingOverview(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get trading stats")
		return
	}
	writeJSON(w, http.StatusOK, stats)
}

// GET /api/admin/orders
func (h *AdminTradingHandler) ListAllOrders(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	offset, _ := strconv.Atoi(q.Get("offset"))
	if limit <= 0 {
		limit = 50
	}
	filters := repository.OrderFilters{
		Status: q.Get("status"),
		Symbol: q.Get("symbol"),
		UserID: q.Get("user_id"),
		Limit:  limit,
		Offset: offset,
	}
	orders, total, err := h.orderRepo.ListAllFiltered(r.Context(), filters)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list orders")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"orders": orders, "total": total})
}

// GET /api/admin/wallets
func (h *AdminTradingHandler) ListWallets(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	offset, _ := strconv.Atoi(q.Get("offset"))
	if limit <= 0 {
		limit = 50
	}
	wallets, total, err := h.walletRepo.ListAll(r.Context(), limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list wallets")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"wallets": wallets, "total": total})
}

// GET /api/admin/wallet-transactions
func (h *AdminTradingHandler) ListAllTransactions(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	offset, _ := strconv.Atoi(q.Get("offset"))
	if limit <= 0 {
		limit = 50
	}
	filters := repository.TransactionFilters{
		UserID: q.Get("user_id"),
		Type:   q.Get("type"),
		Limit:  limit,
		Offset: offset,
	}
	txs, total, err := h.walletRepo.ListAllTransactions(r.Context(), filters)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list transactions")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"transactions": txs, "total": total})
}
