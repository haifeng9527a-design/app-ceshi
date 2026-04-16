package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
	"tongxin-go/internal/service"
)

// NotificationHandler 代理商后台站内通知 REST 入口。
// 前端 notification-bell 组件负责调用 GET + POST read。
type NotificationHandler struct {
	svc *service.NotificationService
}

func NewNotificationHandler(svc *service.NotificationService) *NotificationHandler {
	return &NotificationHandler{svc: svc}
}

// GET /api/agent/notifications?unread=true&limit=50&offset=0
func (h *NotificationHandler) List(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	unreadOnly := r.URL.Query().Get("unread") == "true"
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	resp, err := h.svc.List(r.Context(), uid, unreadOnly, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load notifications")
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// POST /api/agent/notifications/{id}/read
func (h *NotificationHandler) MarkRead(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "notification id is required")
		return
	}

	if err := h.svc.MarkRead(r.Context(), id, uid); err != nil {
		if errors.Is(err, repository.ErrNotificationNotFound) {
			writeError(w, http.StatusNotFound, "notification not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to mark read")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "read"})
}

// POST /api/agent/notifications/read-all
func (h *NotificationHandler) MarkAllRead(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	count, err := h.svc.MarkAllRead(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to mark all read")
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"updated": count})
}

// POST /api/agent/notifications/_dev/create
//
// 仅供 Sprint 1 demo 端到端验证：在 dev 环境下走完整 service.Create 路径
// （DB INSERT + ChatHub 广播），让前端 toast/bell 能在 1s 内更新。
//
// 生产部署时通过 GO_ENV=production 屏蔽。绝不暴露到对外网关。
//
// Body: { "kind": "...", "title": "...", "body": "...", "payload": {...} }
// 写入接收人 = 当前 JWT uid（不允许跨用户写）。
func (h *NotificationHandler) DevCreate(w http.ResponseWriter, r *http.Request) {
	if os.Getenv("GO_ENV") == "production" {
		writeError(w, http.StatusForbidden, "dev endpoint disabled in production")
		return
	}
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var body struct {
		Kind    string          `json:"kind"`
		Title   string          `json:"title"`
		Body    string          `json:"body"`
		Payload json.RawMessage `json:"payload,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json body")
		return
	}
	if body.Kind == "" {
		body.Kind = "risk_alert"
	}
	if body.Title == "" {
		body.Title = "测试通知"
	}
	if body.Body == "" {
		body.Body = "这是一条来自 _dev 端点的测试通知"
	}

	n, err := h.svc.Create(r.Context(), &model.CreateNotificationInput{
		UserUID: uid,
		Kind:    body.Kind,
		Title:   body.Title,
		Body:    body.Body,
		Payload: body.Payload,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create notification")
		return
	}
	writeJSON(w, http.StatusOK, n)
}
