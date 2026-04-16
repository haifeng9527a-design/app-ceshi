package handler

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
	"tongxin-go/internal/service"
)

type SpotHandler struct {
	svc *service.SpotService
}

func NewSpotHandler(svc *service.SpotService) *SpotHandler {
	return &SpotHandler{svc: svc}
}

// GET /api/spot/symbols?category=crypto|stocks
func (h *SpotHandler) ListSymbols(w http.ResponseWriter, r *http.Request) {
	category := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("category")))
	syms, err := h.svc.ListSupportedSymbols(r.Context(), category)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load symbols")
		return
	}
	if syms == nil {
		syms = []model.SpotSupportedSymbol{}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"symbols": syms,
		"count":   len(syms),
	})
}

// GET /api/spot/fee-schedule
func (h *SpotHandler) GetFeeSchedule(w http.ResponseWriter, r *http.Request) {
	tiers, err := h.svc.GetFeeSchedule(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load fee schedule")
		return
	}
	if tiers == nil {
		tiers = []model.SpotFeeTier{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"tiers": tiers})
}

// POST /api/spot/orders
func (h *SpotHandler) PlaceOrder(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.SpotPlaceOrderRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}

	order, err := h.svc.PlaceSpotOrder(r.Context(), uid, &req)
	if err != nil {
		if errors.Is(err, repository.ErrInsufficientBalance) {
			writeError(w, http.StatusBadRequest, "insufficient balance")
			return
		}
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusCreated, order)
}

// DELETE /api/spot/orders/{id}
func (h *SpotHandler) CancelOrder(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	orderID := r.PathValue("id")
	if orderID == "" {
		writeError(w, http.StatusBadRequest, "order id required")
		return
	}

	if err := h.svc.CancelSpotOrder(r.Context(), uid, orderID); err != nil {
		if errors.Is(err, repository.ErrOrderForbidden) {
			writeError(w, http.StatusForbidden, "not your order")
			return
		}
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// GET /api/spot/orders?status=&symbol=&limit=&offset=
func (h *SpotHandler) ListOrders(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	status := r.URL.Query().Get("status")
	symbol := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("symbol")))
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 {
		limit = 50
	}

	orders, total, err := h.svc.ListSpotOrders(r.Context(), uid, status, symbol, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load orders")
		return
	}
	if orders == nil {
		orders = []*model.SpotOrder{}
	}

	writeJSON(w, http.StatusOK, model.SpotOrderListResponse{
		Orders: orders,
		Total:  total,
		Limit:  limit,
		Offset: offset,
	})
}

// GET /api/spot/orders/history?symbol=&limit=&offset= — 已成交 + 已取消
func (h *SpotHandler) OrderHistory(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	symbol := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("symbol")))
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 {
		limit = 50
	}

	// service 不支持 OR-status 查询，复用两次：暂时只返回 filled
	// 完整实现会在 SpotRepo 加 ListUserHistory；MVP 简化版只看 filled
	orders, total, err := h.svc.ListSpotOrders(r.Context(), uid, model.SpotOrderStatusFilled, symbol, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load history")
		return
	}
	if orders == nil {
		orders = []*model.SpotOrder{}
	}

	writeJSON(w, http.StatusOK, model.SpotOrderListResponse{
		Orders: orders,
		Total:  total,
		Limit:  limit,
		Offset: offset,
	})
}

// GET /api/spot/account
func (h *SpotHandler) GetAccount(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	info, err := h.svc.GetSpotAccount(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load account")
		return
	}
	writeJSON(w, http.StatusOK, info)
}
