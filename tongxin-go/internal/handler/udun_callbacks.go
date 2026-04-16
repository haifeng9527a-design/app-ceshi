package handler

import (
	"log"
	"net/http"
	"strings"

	"tongxin-go/internal/integrations/udun"
	"tongxin-go/internal/service"
)

type UdunCallbackHandler struct {
	assetsSvc  *service.AssetsService
	signSecret string
}

func NewUdunCallbackHandler(assetsSvc *service.AssetsService, signSecret string) *UdunCallbackHandler {
	return &UdunCallbackHandler{
		assetsSvc:  assetsSvc,
		signSecret: signSecret,
	}
}

// POST /api/integrations/udun/callback/deposit
func (h *UdunCallbackHandler) Deposit(w http.ResponseWriter, r *http.Request) {
	if h.assetsSvc == nil {
		writeError(w, http.StatusServiceUnavailable, "udun integration unavailable")
		return
	}
	signSecret := strings.TrimSpace(h.signSecret)
	if signSecret == "" {
		writeError(w, http.StatusServiceUnavailable, "udun callback verification not configured")
		return
	}

	values, err := udun.ParseFormCallback(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid callback payload")
		return
	}
	if !udun.VerifyFormCallbackSignature(values, signSecret) {
		writeError(w, http.StatusUnauthorized, "invalid callback signature")
		return
	}

	callback, err := udun.ParseDepositCallback(values)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid deposit callback payload")
		return
	}

	result, err := h.assetsSvc.HandleUdunDepositCallback(r.Context(), callback)
	if err != nil {
		log.Printf("[udun][deposit-callback] process failed: %v", err)
		writeError(w, http.StatusInternalServerError, "failed to process deposit callback")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status": result.Status,
		"ack":    "ok",
		"result": result,
	})
}

// POST /api/integrations/udun/callback/withdraw
func (h *UdunCallbackHandler) Withdraw(w http.ResponseWriter, r *http.Request) {
	if h.assetsSvc == nil {
		writeError(w, http.StatusServiceUnavailable, "udun integration unavailable")
		return
	}
	signSecret := strings.TrimSpace(h.signSecret)
	if signSecret == "" {
		writeError(w, http.StatusServiceUnavailable, "udun callback verification not configured")
		return
	}

	values, err := udun.ParseFormCallback(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid callback payload")
		return
	}
	if !udun.VerifyFormCallbackSignature(values, signSecret) {
		writeError(w, http.StatusUnauthorized, "invalid callback signature")
		return
	}

	callback, err := udun.ParseWithdrawCallback(values)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid withdraw callback payload")
		return
	}

	result, err := h.assetsSvc.HandleUdunWithdrawCallback(r.Context(), callback)
	if err != nil {
		log.Printf("[udun][withdraw-callback] process failed: %v", err)
		writeError(w, http.StatusInternalServerError, "failed to process withdraw callback")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status": result.Status,
		"ack":    "ok",
		"result": result,
	})
}
