package handler

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
	"tongxin-go/internal/service"
)

// TimeSeriesHandler Sprint 3 / M4：代理后台「数据中心」多指标叠加图数据源。
//
// 路由（注册于 main.go）：
//   GET /api/agent/time-series/metrics            返回可用 metric 元信息
//   GET /api/agent/time-series?metrics=...&from=...&to=...&granularity=...
//
// 入参规范：
//   - metrics  逗号分隔；缺省则返回全部 4 条
//   - from/to  ISO 日期 "YYYY-MM-DD"，UTC 零点解析；缺省回退近 30 天
//   - granularity day|week|month，缺省 day
//
// 所有输入都是 query string，不需要 body。
type TimeSeriesHandler struct {
	svc *service.TimeSeriesService
}

func NewTimeSeriesHandler(svc *service.TimeSeriesService) *TimeSeriesHandler {
	return &TimeSeriesHandler{svc: svc}
}

// GET /api/agent/time-series/metrics
func (h *TimeSeriesHandler) ListMetrics(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"metrics": model.SupportedTimeSeriesMetrics})
}

// GET /api/agent/time-series
func (h *TimeSeriesHandler) Query(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	q := r.URL.Query()

	// metrics
	var metrics []string
	if raw := q.Get("metrics"); raw != "" {
		for _, m := range strings.Split(raw, ",") {
			m = strings.TrimSpace(m)
			if m != "" {
				metrics = append(metrics, m)
			}
		}
	}

	// granularity
	granularity := strings.TrimSpace(q.Get("granularity"))
	if granularity == "" {
		granularity = "day"
	}

	// from/to
	nowUTC := time.Now().UTC()
	// 默认：近 30 天，from = now - 30d 起点 (UTC 零点), to = 明天起点（exclusive 右开）
	defaultTo := time.Date(nowUTC.Year(), nowUTC.Month(), nowUTC.Day(), 0, 0, 0, 0, time.UTC).
		AddDate(0, 0, 1)
	defaultFrom := defaultTo.AddDate(0, 0, -31)

	from, err := parseDateParam(q.Get("from"), defaultFrom)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid from")
		return
	}
	to, err := parseDateParam(q.Get("to"), defaultTo)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid to")
		return
	}
	// to 习惯上是「包含当天」，内部以右开处理 → 推到次日零点
	if to.Equal(time.Date(to.Year(), to.Month(), to.Day(), 0, 0, 0, 0, time.UTC)) {
		to = to.AddDate(0, 0, 1)
	}

	resp, err := h.svc.Query(r.Context(), &service.TimeSeriesInput{
		AgentUID:    uid,
		Metrics:     metrics,
		From:        from,
		To:          to,
		Granularity: granularity,
	})
	if err != nil {
		switch {
		case errors.Is(err, repository.ErrTimeSeriesBadGranularity):
			writeError(w, http.StatusBadRequest, "granularity must be day|week|month")
		case errors.Is(err, repository.ErrTimeSeriesBadRange):
			writeError(w, http.StatusBadRequest, "from must be <= to")
		default:
			writeError(w, http.StatusInternalServerError, "failed to query time-series: "+err.Error())
		}
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

func parseDateParam(raw string, defaultVal time.Time) (time.Time, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return defaultVal, nil
	}
	// 支持 "2026-04-16" 和 "2026-04-16T00:00:00Z" 两种
	if t, err := time.Parse("2006-01-02", raw); err == nil {
		return t, nil
	}
	t, err := time.Parse(time.RFC3339, raw)
	return t, err
}
