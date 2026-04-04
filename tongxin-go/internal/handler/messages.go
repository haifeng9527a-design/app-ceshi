package handler

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
	"tongxin-go/internal/ws"
)

type MessagesHandler struct {
	msgSvc  *service.MessageService
	chatHub *ws.ChatHub
}

func NewMessagesHandler(msgSvc *service.MessageService, chatHub *ws.ChatHub) *MessagesHandler {
	return &MessagesHandler{msgSvc: msgSvc, chatHub: chatHub}
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
	metaOK := len(req.Metadata) > 0 && strings.TrimSpace(string(req.Metadata)) != "" &&
		string(req.Metadata) != "null" && string(req.Metadata) != "{}"
	if req.ConversationID == "" || (strings.TrimSpace(req.Content) == "" && !metaOK) {
		writeError(w, http.StatusBadRequest, "conversation_id and content or metadata are required")
		return
	}

	msg, err := h.msgSvc.SendMessage(r.Context(), uid, &req)
	if err != nil {
		if errors.Is(err, service.ErrNotConversationMember) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to send message")
		return
	}

	if h.chatHub != nil {
		h.chatHub.PublishNewMessageREST(r.Context(), req.ConversationID, msg, uid)
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

	msgs, err := h.msgSvc.ListMessages(r.Context(), uid, conversationID, limit, before)
	if err != nil {
		if errors.Is(err, service.ErrNotConversationMember) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to list messages")
		return
	}
	if msgs == nil {
		msgs = []model.Message{}
	}

	writeJSON(w, http.StatusOK, msgs)
}

// GET /api/conversations/{id}/messages/search?q=&limit=
func (h *MessagesHandler) Search(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	conversationID := r.PathValue("id")
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 50
	}

	msgs, err := h.msgSvc.SearchMessages(r.Context(), uid, conversationID, q, limit)
	if err != nil {
		if errors.Is(err, service.ErrNotConversationMember) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusInternalServerError, "search failed")
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
