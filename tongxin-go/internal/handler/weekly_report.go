package handler

import (
	"net/http"
	"os"
	"time"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/service"
)

// WeeklyReportHandler Sprint 5：周报前端渲染 + dev 手动触发。
//
// 三个端点：
//  1. GET  /weekly-report/render-data?token=...   —— chromedp 内部前端页面用
//     返回 JSON WeeklyReportData。token 必须是 service.Generate 签发的 60s 内有效的。
//     故意不走 Authenticate 中间件（chromedp 没有 session），鉴权完全依赖 token cache。
//
//  2. POST /api/agent/_dev/run-weekly-report  —— dev-only 手动触发
//     body: { "agent_uid"?: "xxx", "week_offset"?: -1 }（week_offset 默认 -1 = 上周）
//     若 agent_uid 缺省则跑调用者本人。
//
//  3. POST /api/agent/_dev/run-weekly-report-all —— dev-only 全量生成
//     只在 GO_ENV != production 下启用。
type WeeklyReportHandler struct {
	svc *service.WeeklyReportService
}

func NewWeeklyReportHandler(svc *service.WeeklyReportService) *WeeklyReportHandler {
	return &WeeklyReportHandler{svc: svc}
}

// GET /weekly-report/render-data?token=xxx
// 不走 auth middleware —— 前端 chromedp 环境没法附 Bearer 头，所以用 query token 做一次性鉴权。
func (h *WeeklyReportHandler) RenderData(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		writeError(w, http.StatusUnauthorized, "token required")
		return
	}
	// token 解码（校验签名 + 过期）
	if _, err := middleware.VerifyJWT(token, middleware.JWTSecret); err != nil {
		writeError(w, http.StatusUnauthorized, "invalid or expired token")
		return
	}
	// 从 cache 取已经算好的 report
	data := h.svc.ConsumeRenderToken(token)
	if data == nil {
		writeError(w, http.StatusNotFound, "render data expired or unknown token")
		return
	}
	writeJSON(w, http.StatusOK, data)
}

// POST /api/agent/_dev/run-weekly-report
//
// Body:
//
//	{ "agent_uid"?: "xxx", "week_offset"?: -1 }
func (h *WeeklyReportHandler) DevRunOne(w http.ResponseWriter, r *http.Request) {
	if os.Getenv("GO_ENV") == "production" {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	callerUID, err := requireAgent(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err.Error())
		return
	}

	var body struct {
		AgentUID   string `json:"agent_uid"`
		WeekOffset int    `json:"week_offset"`
	}
	_ = decodeJSON(r, &body) // body 可以为空

	target := body.AgentUID
	if target == "" {
		target = callerUID
	}
	offset := body.WeekOffset
	if offset == 0 {
		offset = -1 // 默认上周
	}
	weekRef := time.Now().AddDate(0, 0, offset*7)

	report, pngURL, err := h.svc.Generate(r.Context(), target, weekRef)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"png_url": pngURL,
		"report":  report,
	})
}

// POST /api/agent/_dev/run-weekly-report-all
func (h *WeeklyReportHandler) DevRunAll(w http.ResponseWriter, r *http.Request) {
	if os.Getenv("GO_ENV") == "production" {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	if _, err := requireAgent(r); err != nil {
		writeError(w, http.StatusUnauthorized, err.Error())
		return
	}
	weekRef := time.Now().AddDate(0, 0, -7)
	ok, fail, errs := h.svc.GenerateAll(r.Context(), weekRef)

	errStrs := make([]string, 0, len(errs))
	for _, e := range errs {
		errStrs = append(errStrs, e.Error())
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":     ok,
		"fail":   fail,
		"errors": errStrs,
	})
}
