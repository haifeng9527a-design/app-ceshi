package handler

import (
	"net/http"
	"strconv"
	"strings"

	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

type AdminSpotHandler struct {
	spotRepo *repository.SpotRepo
}

func NewAdminSpotHandler(spotRepo *repository.SpotRepo) *AdminSpotHandler {
	return &AdminSpotHandler{spotRepo: spotRepo}
}

// GET /api/admin/spot-orders?status=&symbol=&user_id=&limit=&offset=
func (h *AdminSpotHandler) ListAllOrders(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	offset, _ := strconv.Atoi(q.Get("offset"))
	if limit <= 0 {
		limit = 50
	}
	status := q.Get("status")
	symbol := strings.ToUpper(strings.TrimSpace(q.Get("symbol")))
	userID := strings.TrimSpace(q.Get("user_id"))

	orders, total, err := h.spotRepo.ListAllOrdersFiltered(r.Context(), status, symbol, userID, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list spot orders")
		return
	}
	if orders == nil {
		orders = []*model.SpotOrder{}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"orders": orders,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

// GET /api/admin/spot-fee-tiers
func (h *AdminSpotHandler) ListFeeTiers(w http.ResponseWriter, r *http.Request) {
	tiers, err := h.spotRepo.ListFeeSchedule(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list spot fee tiers")
		return
	}
	if tiers == nil {
		tiers = []model.SpotFeeTier{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"tiers": tiers})
}

// PUT /api/admin/spot-fee-tiers/{vipLevel}
//
//	body: { "maker_fee": 0.001, "taker_fee": 0.001 }
func (h *AdminSpotHandler) UpdateFeeTier(w http.ResponseWriter, r *http.Request) {
	vipStr := r.PathValue("vipLevel")
	vipLevel, err := strconv.Atoi(vipStr)
	if err != nil || vipLevel < 0 {
		writeError(w, http.StatusBadRequest, "invalid vip level")
		return
	}

	var body struct {
		MakerFee float64 `json:"maker_fee"`
		TakerFee float64 `json:"taker_fee"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if body.MakerFee < 0 || body.MakerFee > 0.05 || body.TakerFee < 0 || body.TakerFee > 0.05 {
		writeError(w, http.StatusBadRequest, "fee out of range (0..0.05)")
		return
	}

	if err := h.spotRepo.UpdateFeeTier(r.Context(), vipLevel, body.MakerFee, body.TakerFee); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update spot fee tier")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}
