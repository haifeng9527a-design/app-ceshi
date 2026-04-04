package handler

import (
	"net/http"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
	"tongxin-go/internal/ws"
)

type WalletHandler struct {
	walletRepo *repository.WalletRepo
	tradingHub *ws.TradingHub
}

func NewWalletHandler(wr *repository.WalletRepo, th *ws.TradingHub) *WalletHandler {
	return &WalletHandler{walletRepo: wr, tradingHub: th}
}

// POST /api/wallet/deposit
func (h *WalletHandler) Deposit(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.DepositRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Amount <= 0 {
		writeError(w, http.StatusBadRequest, "amount must be positive")
		return
	}
	if req.Amount > 1000000 {
		writeError(w, http.StatusBadRequest, "amount too large")
		return
	}

	wallet, err := h.walletRepo.Deposit(r.Context(), uid, req.Amount)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "deposit failed")
		return
	}

	// Push balance update via WebSocket
	h.tradingHub.PushToUser(uid, map[string]any{
		"type": "balance_update",
		"data": map[string]any{
			"balance": wallet.Balance,
			"frozen":  wallet.Frozen,
		},
	})

	writeJSON(w, http.StatusOK, wallet)
}

// GET /api/wallet
func (h *WalletHandler) GetBalance(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	wallet, err := h.walletRepo.EnsureWallet(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get wallet")
		return
	}

	writeJSON(w, http.StatusOK, wallet)
}

// GET /api/wallet/transactions
func (h *WalletHandler) GetTransactions(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	limit := 50
	offset := 0
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 {
			limit = n
		}
	}
	if o := r.URL.Query().Get("offset"); o != "" {
		if n, err := strconv.Atoi(o); err == nil && n >= 0 {
			offset = n
		}
	}

	txs, err := h.walletRepo.GetTransactions(r.Context(), uid, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get transactions")
		return
	}
	if txs == nil {
		txs = []model.WalletTransaction{}
	}

	writeJSON(w, http.StatusOK, txs)
}
