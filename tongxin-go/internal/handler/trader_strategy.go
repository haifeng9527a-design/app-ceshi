package handler

import (
	"net/http"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

type TraderStrategyHandler struct {
	svc *service.TraderStrategyService
}

func NewTraderStrategyHandler(svc *service.TraderStrategyService) *TraderStrategyHandler {
	return &TraderStrategyHandler{svc: svc}
}

// POST /api/trader/strategies
func (h *TraderStrategyHandler) Create(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.CreateTraderStrategyRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	strategy, err := h.svc.Create(r.Context(), uid, &req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusCreated, strategy)
}

// GET /api/trader/strategies/my
func (h *TraderStrategyHandler) ListMy(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	status := r.URL.Query().Get("status")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	items, total, err := h.svc.ListMy(r.Context(), uid, status, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list strategies")
		return
	}
	if items == nil {
		items = []model.TraderStrategy{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"strategies": items, "total": total})
}

// GET /api/trader/strategies/feed
func (h *TraderStrategyHandler) Feed(w http.ResponseWriter, r *http.Request) {
	category := r.URL.Query().Get("category")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	items, total, err := h.svc.ListPublished(r.Context(), category, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list strategies")
		return
	}
	if items == nil {
		items = []model.TraderStrategy{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"strategies": items, "total": total})
}

// GET /api/trader/strategies/{id}
func (h *TraderStrategyHandler) GetByID(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "missing strategy id")
		return
	}

	strategy, err := h.svc.GetByID(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusNotFound, "strategy not found")
		return
	}

	// Check if current user has liked
	uid := middleware.GetUserUID(r.Context())
	liked := false
	if uid != "" {
		liked = h.svc.HasLiked(r.Context(), id, uid)
	}

	writeJSON(w, http.StatusOK, map[string]any{"strategy": strategy, "liked": liked})
}

// GET /api/strategies/author/{uid}
func (h *TraderStrategyHandler) ListByAuthor(w http.ResponseWriter, r *http.Request) {
	uid := r.PathValue("uid")
	if uid == "" {
		writeError(w, http.StatusBadRequest, "missing uid")
		return
	}

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	items, total, err := h.svc.ListByTrader(r.Context(), uid, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list strategies")
		return
	}
	if items == nil {
		items = []model.TraderStrategy{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"strategies": items, "total": total})
}

// PUT /api/trader/strategies/{id}
func (h *TraderStrategyHandler) Update(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "missing strategy id")
		return
	}

	var req model.UpdateTraderStrategyRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	strategy, err := h.svc.Update(r.Context(), id, uid, &req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, strategy)
}

// DELETE /api/trader/strategies/{id}
func (h *TraderStrategyHandler) Delete(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "missing strategy id")
		return
	}

	if err := h.svc.Delete(r.Context(), id, uid); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// POST /api/trader/strategies/{id}/like
func (h *TraderStrategyHandler) Like(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "missing strategy id")
		return
	}

	liked, err := h.svc.Like(r.Context(), id, uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to like")
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"liked": liked})
}
