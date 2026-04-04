package handler

import (
	"net/http"
	"strconv"
	"time"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

type MessagesHandler struct {
	msgSvc *service.MessageService
}

func NewMessagesHandler(msgSvc *service.MessageService) *MessagesHandler {
	return &MessagesHandler{msgSvc: msgSvc}
}

// POST /api/messages
func (h *MessagesHandler) Send(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.SendMessageRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.ConversationID == "" || req.Content == "" {
		writeError(w, http.StatusBadRequest, "conversation_id and content are required")
		return
	}

	msg, err := h.msgSvc.SendMessage(r.Context(), uid, &req)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to send message")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"id":         msg.ID,
		"created_at": msg.CreatedAt,
	})
}

// GET /api/conversations/{id}/messages?limit=50&before=timestamp
func (h *MessagesHandler) ListByConversation(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	conversationID := r.PathValue("id")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 50
	}

	var before *time.Time
	if beforeStr := r.URL.Query().Get("before"); beforeStr != "" {
		t, err := time.Parse(time.RFC3339, beforeStr)
		if err == nil {
			before = &t
		}
	}

	msgs, err := h.msgSvc.ListMessages(r.Context(), conversationID, limit, before)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list messages")
		return
	}
	if msgs == nil {
		msgs = []model.Message{}
	}

	writeJSON(w, http.StatusOK, msgs)
}

// DELETE /api/messages/{id}
func (h *MessagesHandler) Delete(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	if err := h.msgSvc.DeleteMessage(r.Context(), id, uid); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to delete message")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
