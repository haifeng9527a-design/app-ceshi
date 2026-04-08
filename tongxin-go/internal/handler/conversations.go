package handler

import (
	"errors"
	"net/http"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

type ConversationsHandler struct {
	msgSvc *service.MessageService
}

func NewConversationsHandler(msgSvc *service.MessageService) *ConversationsHandler {
	return &ConversationsHandler{msgSvc: msgSvc}
}

// GET /api/conversations
func (h *ConversationsHandler) List(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	convos, err := h.msgSvc.ListConversations(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list conversations")
		return
	}
	if convos == nil {
		convos = []model.Conversation{}
	}

	writeJSON(w, http.StatusOK, convos)
}

// GET /api/conversations/{id}
func (h *ConversationsHandler) GetByID(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	c, err := h.msgSvc.GetConversation(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusNotFound, "conversation not found")
		return
	}
	writeJSON(w, http.StatusOK, c)
}

// POST /api/conversations/direct
func (h *ConversationsHandler) CreateDirect(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var body model.CreateDirectRequest
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	c, created, err := h.msgSvc.CreateDirect(r.Context(), uid, body.PeerID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create conversation")
		return
	}

	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}

	writeJSON(w, status, map[string]any{
		"id":      c.ID,
		"created": created,
	})
}

// POST /api/conversations/group
func (h *ConversationsHandler) CreateGroup(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var body model.CreateGroupRequest
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	c, err := h.msgSvc.CreateGroup(r.Context(), uid, &body)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create group")
		return
	}

	writeJSON(w, http.StatusCreated, c)
}

// PATCH /api/conversations/{id}/read
func (h *ConversationsHandler) MarkAsRead(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	if err := h.msgSvc.MarkAsRead(r.Context(), uid, id); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to mark as read")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// GET /api/conversations/unread-count
func (h *ConversationsHandler) UnreadCount(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	count, err := h.msgSvc.GetUnreadCount(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get unread count")
		return
	}

	writeJSON(w, http.StatusOK, map[string]int{"count": count})
}

// GET /api/conversations/{id}/group-info
func (h *ConversationsHandler) GroupInfo(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	c, members, err := h.msgSvc.GetGroupInfo(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusNotFound, "conversation not found")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"conversation": c,
		"members":      members,
	})
}

// PUT /api/conversations/{id}/group-info
func (h *ConversationsHandler) UpdateGroupInfo(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	var body model.UpdateGroupRequest
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if err := h.msgSvc.UpdateGroupInfo(r.Context(), uid, id, &body); err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to update group info")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// POST /api/conversations/{id}/members
func (h *ConversationsHandler) AddMembers(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	id := r.PathValue("id")
	var body model.AddGroupMembersRequest
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if err := h.msgSvc.AddGroupMembers(r.Context(), uid, id, body.MemberIDs); err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to add members")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// DELETE /api/conversations/{id}/members/{userId}
func (h *ConversationsHandler) RemoveMember(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	id := r.PathValue("id")
	memberUID := r.PathValue("userId")
	if err := h.msgSvc.RemoveGroupMember(r.Context(), uid, id, memberUID); err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// PATCH /api/conversations/{id}/members/{userId}/role
func (h *ConversationsHandler) UpdateMemberRole(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	memberUID := r.PathValue("userId")
	var body model.UpdateGroupMemberRoleRequest
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.msgSvc.UpdateGroupMemberRole(r.Context(), uid, id, memberUID, body.Role); err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// DELETE /api/conversations/{id}
func (h *ConversationsHandler) Dissolve(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	id := r.PathValue("id")
	if err := h.msgSvc.DissolveGroup(r.Context(), uid, id); err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to dissolve group")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "dissolved"})
}
