package handler

import (
	"net/http"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

// TouchHandler 代理后台「一键触达」（Sprint 2）。
//
// 路由设计取舍：PRD 原定 4 个按渠道拆分的端点
//   POST /touch/notify-internal / /touch/email / /touch/sms / /touch/wechat
//
// 实际写下来这四个 handler 只差 channel 字段，前端 & 后端重复。改为：
//
//   POST /api/agent/touch/send   — body 里传 channels 数组，一次请求走全部勾选渠道
//
// 保留以下两个查询端点：
//   GET  /api/agent/touch/templates  — 返回模板元信息
//   GET  /api/agent/touch/history    — 触达历史（倒序）
type TouchHandler struct {
	svc *service.TouchService
}

func NewTouchHandler(svc *service.TouchService) *TouchHandler {
	return &TouchHandler{svc: svc}
}

// GET /api/agent/touch/templates
func (h *TouchHandler) ListTemplates(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"templates": model.SupportedTouchTemplates})
}

// POST /api/agent/touch/send
// body:
//   {
//     invitee_uids: [...],
//     template:     "reactivate" | "thank_you" | "commission_arrived",
//     channels:     ["internal","email","sms","wechat"],
//     custom_body:  "可选文案覆盖"
//   }
func (h *TouchHandler) Send(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req struct {
		InviteeUIDs []string `json:"invitee_uids"`
		Template    string   `json:"template"`
		Channels    []string `json:"channels"`
		CustomBody  string   `json:"custom_body"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	resp, err := h.svc.Send(r.Context(), uid, &model.TouchRequest{
		InviteeUIDs: req.InviteeUIDs,
		Template:    req.Template,
		CustomBody:  req.CustomBody,
	}, req.Channels)
	if err != nil {
		// service 层直接返回 error 的都是可展示的前端错误
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// GET /api/agent/touch/history?limit=50
func (h *TouchHandler) History(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := h.svc.List(r.Context(), uid, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list touch history")
		return
	}
	if items == nil {
		items = []*model.TouchHistory{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"history": items})
}
