package handler

import (
	"net/http"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

type TradingHandler struct {
	tradingSvc *service.TradingService
}

func NewTradingHandler(svc *service.TradingService) *TradingHandler {
	return &TradingHandler{tradingSvc: svc}
}

// POST /api/trading/orders
func (h *TradingHandler) CreateOrder(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.PlaceOrderRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	order, err := h.tradingSvc.PlaceOrder(r.Context(), uid, &req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusCreated, order)
}

// GET /api/trading/orders?status=pending|filled|cancelled|all
func (h *TradingHandler) ListOrders(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	status := r.URL.Query().Get("status")
	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 {
			limit = n
		}
	}

	orders, err := h.tradingSvc.ListOrders(r.Context(), uid, status, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list orders")
		return
	}
	writeJSON(w, http.StatusOK, orders)
}

// DELETE /api/trading/orders/{id}
func (h *TradingHandler) CancelOrder(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "order id required")
		return
	}

	order, err := h.tradingSvc.CancelOrder(r.Context(), uid, id)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, order)
}

// GET /api/trading/positions
func (h *TradingHandler) ListPositions(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	positions, err := h.tradingSvc.ListPositionsWithPnL(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list positions")
		return
	}
	if positions == nil {
		positions = []model.Position{}
	}
	writeJSON(w, http.StatusOK, positions)
}

// DELETE /api/trading/positions/{id}
func (h *TradingHandler) ClosePosition(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "position id required")
		return
	}

	pos, err := h.tradingSvc.ClosePosition(r.Context(), uid, id)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, pos)
}

// GET /api/trading/account
func (h *TradingHandler) GetAccount(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	info, err := h.tradingSvc.GetAccountInfo(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get account info")
		return
	}

	writeJSON(w, http.StatusOK, info)
}

// GET /api/trading/positions/history
func (h *TradingHandler) ListPositionHistory(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 {
			limit = n
		}
	}

	positions, err := h.tradingSvc.ListPositionHistory(r.Context(), uid, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list position history")
		return
	}
	writeJSON(w, http.StatusOK, positions)
}

// PUT /api/trading/positions/{id}/tp-sl
func (h *TradingHandler) UpdateTPSL(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "position id required")
		return
	}

	var req struct {
		TpPrice *float64 `json:"tp_price"`
		SlPrice *float64 `json:"sl_price"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	pos, err := h.tradingSvc.UpdateTPSL(r.Context(), uid, id, req.TpPrice, req.SlPrice)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, pos)
}

// POST /api/trading/positions/{id}/partial-close
func (h *TradingHandler) PartialClosePosition(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "position id required")
		return
	}

	var req struct {
		Qty float64 `json:"qty"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Qty <= 0 {
		writeError(w, http.StatusBadRequest, "qty must be positive")
		return
	}

	pos, err := h.tradingSvc.PartialClosePosition(r.Context(), uid, id, req.Qty)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, pos)
}

// GET /api/trading/history
func (h *TradingHandler) GetHistory(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 {
			limit = n
		}
	}

	orders, err := h.tradingSvc.ListHistory(r.Context(), uid, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get history")
		return
	}
	writeJSON(w, http.StatusOK, orders)
}

// GET /api/trading/fee-schedule — public, returns VIP fee tiers
func (h *TradingHandler) GetFeeSchedule(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, h.tradingSvc.GetFeeSchedule())
}

// GET /api/trading/vip-info — authenticated, returns user's VIP level and fee rates
func (h *TradingHandler) GetVipInfo(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	info, err := h.tradingSvc.GetVipInfo(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get VIP info")
		return
	}
	writeJSON(w, http.StatusOK, info)
}
