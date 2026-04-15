package handler

import (
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5"
	"tongxin-go/internal/middleware"
	"tongxin-go/internal/service"
	"tongxin-go/internal/ws"
)

type ChatProfileHandler struct {
	svc     *service.ChatProfileService
	chatHub *ws.ChatHub
}

func NewChatProfileHandler(svc *service.ChatProfileService, chatHub *ws.ChatHub) *ChatProfileHandler {
	return &ChatProfileHandler{svc: svc, chatHub: chatHub}
}

func (h *ChatProfileHandler) Get(w http.ResponseWriter, r *http.Request) {
	viewerUID := middleware.GetUserUID(r.Context())
	if viewerUID == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	targetUID := r.PathValue("uid")
	if targetUID == "" {
		writeError(w, http.StatusBadRequest, "user id required")
		return
	}

	profile, err := h.svc.GetChatProfile(r.Context(), viewerUID, targetUID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "user not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to load chat profile")
		return
	}

	if h.chatHub != nil {
		profile.Online = h.chatHub.IsUserOnline(targetUID)
	}

	writeJSON(w, http.StatusOK, profile)
}
