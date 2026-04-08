package handler

import (
	"errors"
	"net/http"
	"time"

	"tongxin-go/internal/config"
	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
	"tongxin-go/internal/ws"
)

type CallsHandler struct {
	callSvc *service.CallService
	chatHub *ws.ChatHub
	cfg     *config.Config
}

func NewCallsHandler(callSvc *service.CallService, chatHub *ws.ChatHub, cfg *config.Config) *CallsHandler {
	return &CallsHandler{callSvc: callSvc, chatHub: chatHub, cfg: cfg}
}

func (h *CallsHandler) Start(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var body model.StartCallRequest
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	call, members, err := h.callSvc.Start(r.Context(), uid, &body)
	if err != nil {
		if errors.Is(err, service.ErrNotConversationMember) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	h.broadcastCall("call_invite", call, members, uid)
	writeJSON(w, http.StatusCreated, call)
}

func (h *CallsHandler) Get(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	call, _, err := h.callSvc.Get(r.Context(), uid, r.PathValue("id"))
	if err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusNotFound, "call not found")
		return
	}
	writeJSON(w, http.StatusOK, call)
}

func (h *CallsHandler) Accept(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	call, members, err := h.callSvc.Accept(r.Context(), uid, r.PathValue("id"))
	if err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	h.broadcastCall("call_accepted", call, members, uid)
	writeJSON(w, http.StatusOK, call)
}

func (h *CallsHandler) Reject(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	var body model.EndCallRequest
	_ = decodeJSON(r, &body)
	call, members, err := h.callSvc.Reject(r.Context(), uid, r.PathValue("id"), body.Reason)
	if err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	h.broadcastCall("call_rejected", call, members, uid)
	writeJSON(w, http.StatusOK, call)
}

func (h *CallsHandler) End(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	var body model.EndCallRequest
	_ = decodeJSON(r, &body)
	call, members, err := h.callSvc.End(r.Context(), uid, r.PathValue("id"), body.Reason)
	if err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	h.broadcastCall("call_ended", call, members, uid)
	writeJSON(w, http.StatusOK, call)
}

func (h *CallsHandler) LiveKitToken(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	if h.cfg == nil || h.cfg.LiveKitURL == "" || h.cfg.LiveKitAPIKey == "" || h.cfg.LiveKitAPISecret == "" {
		writeError(w, http.StatusServiceUnavailable, "livekit is not configured")
		return
	}

	call, _, err := h.callSvc.Get(r.Context(), uid, r.PathValue("id"))
	if err != nil {
		if errors.Is(err, service.ErrForbidden) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		writeError(w, http.StatusNotFound, "call not found")
		return
	}

	token, err := middleware.SignJWT(map[string]any{
		"iss":  h.cfg.LiveKitAPIKey,
		"sub":  uid,
		"nbf":  time.Now().Unix(),
		"name": uid,
		"video": map[string]any{
			"room":           call.RoomName,
			"roomJoin":       true,
			"canPublish":     true,
			"canSubscribe":   true,
			"canPublishData": true,
		},
		"metadata": "",
	}, []byte(h.cfg.LiveKitAPISecret), time.Hour)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to sign livekit token")
		return
	}

	writeJSON(w, http.StatusOK, model.LiveKitTokenResponse{
		ServerURL: h.cfg.LiveKitURL,
		RoomName:  call.RoomName,
		Token:     token,
		Identity:  uid,
	})
}

func (h *CallsHandler) broadcastCall(eventType string, call *model.Call, memberIDs []string, actorUID string) {
	if h.chatHub == nil || call == nil {
		return
	}
	frame := map[string]any{
		"type":     eventType,
		"call":     call,
		"actor_id": actorUID,
	}
	for _, memberID := range memberIDs {
		h.chatHub.BroadcastToUser(memberID, frame)
	}
}
