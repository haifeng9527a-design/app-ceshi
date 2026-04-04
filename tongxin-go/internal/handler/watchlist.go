package handler

import (
	"net/http"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/repository"
)

type WatchlistHandler struct {
	repo *repository.WatchlistRepo
}

func NewWatchlistHandler(repo *repository.WatchlistRepo) *WatchlistHandler {
	return &WatchlistHandler{repo: repo}
}

// GET /api/watchlist
func (h *WatchlistHandler) List(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	items, err := h.repo.List(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list watchlist")
		return
	}
	if items == nil {
		items = []repository.WatchlistItem{}
	}

	writeJSON(w, http.StatusOK, items)
}

// POST /api/watchlist
func (h *WatchlistHandler) Add(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var body struct {
		Symbol     string `json:"symbol"`
		SymbolType string `json:"symbol_type"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if body.Symbol == "" {
		writeError(w, http.StatusBadRequest, "symbol is required")
		return
	}

	if err := h.repo.Add(r.Context(), uid, body.Symbol, body.SymbolType); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to add to watchlist")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{"status": "added"})
}

// DELETE /api/watchlist/{symbol}
func (h *WatchlistHandler) Remove(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	symbol := r.PathValue("symbol")
	if symbol == "" {
		writeError(w, http.StatusBadRequest, "symbol required")
		return
	}

	if err := h.repo.Remove(r.Context(), uid, symbol); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to remove from watchlist")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "removed"})
}

// GET /api/watchlist/check?symbol=AAPL
func (h *WatchlistHandler) Check(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	symbol := r.URL.Query().Get("symbol")
	exists, err := h.repo.Check(r.Context(), uid, symbol)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "check failed")
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"exists": exists})
}
