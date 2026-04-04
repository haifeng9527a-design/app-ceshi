package handler

import (
	"log"
	"net/http"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
	"tongxin-go/internal/ws"
)

type FriendsHandler struct {
	friendSvc *service.FriendService
	userSvc   *service.UserService
	chatHub   *ws.ChatHub // optional: real-time friend notifications
}

func NewFriendsHandler(friendSvc *service.FriendService, userSvc *service.UserService, chatHub *ws.ChatHub) *FriendsHandler {
	return &FriendsHandler{friendSvc: friendSvc, userSvc: userSvc, chatHub: chatHub}
}

// GET /api/friends
func (h *FriendsHandler) ListFriends(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	friends, err := h.friendSvc.ListFriends(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list friends")
		return
	}
	if friends == nil {
		friends = []model.FriendProfile{}
	}

	writeJSON(w, http.StatusOK, friends)
}

// POST /api/friends/request
func (h *FriendsHandler) SendRequest(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var body model.FriendRequestBody
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	toID := body.ToUserID
	if toID == "" {
		toID = body.TargetUserID
	}
	if toID == "" {
		writeError(w, http.StatusBadRequest, "to_user_id is required")
		return
	}
	if toID == uid {
		writeError(w, http.StatusBadRequest, "cannot send request to yourself")
		return
	}

	req, err := h.friendSvc.SendRequest(r.Context(), uid, toID, body.Message)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to send request")
		return
	}

	if h.chatHub != nil && h.userSvc != nil {
		fromName := ""
		if u, err := h.userSvc.GetProfile(r.Context(), uid); err == nil {
			fromName = u.DisplayName
		}
		h.chatHub.BroadcastToUser(toID, map[string]any{
			"type":              "friend_request",
			"request_id":        req.ID,
			"from_user_id":      uid,
			"from_display_name": fromName,
		})
	} else if h.chatHub == nil {
		log.Printf("[friends] chat hub unavailable (messages/WS not initialized): realtime friend_request push skipped, to_user=%s", toID)
	}

	writeJSON(w, http.StatusCreated, req)
}

// POST /api/friends/accept
func (h *FriendsHandler) AcceptRequest(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var body model.AcceptRejectBody
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	fromUID, err := h.friendSvc.AcceptRequest(r.Context(), body.RequestID, uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to accept request")
		return
	}

	if h.chatHub != nil && h.userSvc != nil && fromUID != "" {
		name := ""
		if u, err := h.userSvc.GetProfile(r.Context(), uid); err == nil {
			name = u.DisplayName
		}
		h.chatHub.BroadcastToUser(fromUID, map[string]any{
			"type":                   "friend_accepted",
			"accepter_user_id":       uid,
			"accepter_display_name":  name,
		})
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "accepted"})
}

// POST /api/friends/reject
func (h *FriendsHandler) RejectRequest(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var body model.AcceptRejectBody
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.friendSvc.RejectRequest(r.Context(), body.RequestID, uid); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to reject request")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "rejected"})
}

// GET /api/friends/incoming
func (h *FriendsHandler) GetIncoming(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	reqs, err := h.friendSvc.GetIncoming(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get requests")
		return
	}
	if reqs == nil {
		reqs = []model.FriendRequest{}
	}

	writeJSON(w, http.StatusOK, reqs)
}

// GET /api/friends/outgoing
func (h *FriendsHandler) GetOutgoing(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	reqs, err := h.friendSvc.GetOutgoing(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get requests")
		return
	}
	if reqs == nil {
		reqs = []model.FriendRequest{}
	}

	writeJSON(w, http.StatusOK, reqs)
}

// DELETE /api/friends/{id}
func (h *FriendsHandler) DeleteFriend(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	friendID := r.PathValue("id")
	if friendID == "" {
		writeError(w, http.StatusBadRequest, "friend id required")
		return
	}

	if err := h.friendSvc.DeleteFriend(r.Context(), uid, friendID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to delete friend")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// POST /api/friends/block
func (h *FriendsHandler) BlockUser(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var body struct {
		TargetID string `json:"target_id"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.friendSvc.BlockUser(r.Context(), uid, body.TargetID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to block user")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "blocked"})
}
