package handler

import (
	"errors"
	"net/http"
	"os"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
	"tongxin-go/internal/service"
)

// ThresholdHandler 代理后台「告警阈值」CRUD（Sprint 2）。
type ThresholdHandler struct {
	svc *service.ThresholdService
}

func NewThresholdHandler(svc *service.ThresholdService) *ThresholdHandler {
	return &ThresholdHandler{svc: svc}
}

// GET /api/agent/thresholds/metrics
//
// 返回全部支持的 metric 元信息（供前端下拉）。公开给已登录代理；无需额外鉴权。
// 不依赖 DB，所以即使 threshold service 为 nil 也能返回。
func (h *ThresholdHandler) ListMetrics(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"metrics": model.SupportedThresholdMetrics})
}

// GET /api/agent/thresholds
func (h *ThresholdHandler) List(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	items, err := h.svc.List(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list thresholds")
		return
	}
	if items == nil {
		items = []*model.AgentThreshold{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"thresholds": items})
}

// POST /api/agent/thresholds
// body: { metric, op, threshold_value, is_enabled }
//
// 注：后端不做 PUT/{id}，而是 (agent_uid, metric) 唯一键的 upsert，
// 简化前端逻辑（不用记 id）。
func (h *ThresholdHandler) Upsert(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req struct {
		Metric         string  `json:"metric"`
		Op             string  `json:"op"`
		ThresholdValue float64 `json:"threshold_value"`
		IsEnabled      bool    `json:"is_enabled"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	t, err := h.svc.Upsert(r.Context(), &model.UpsertThresholdInput{
		AgentUID:       uid,
		Metric:         req.Metric,
		Op:             req.Op,
		ThresholdValue: req.ThresholdValue,
		IsEnabled:      req.IsEnabled,
	})
	if err != nil {
		switch {
		case errors.Is(err, repository.ErrThresholdInvalidMetric):
			writeError(w, http.StatusBadRequest, "invalid metric")
		case errors.Is(err, repository.ErrThresholdInvalidOp):
			writeError(w, http.StatusBadRequest, "invalid op (must be lt or gt)")
		default:
			writeError(w, http.StatusInternalServerError, "failed to upsert threshold")
		}
		return
	}
	writeJSON(w, http.StatusOK, t)
}

// POST /api/agent/thresholds/_dev/scan
//
// Dev-only：立即跑一次 ScanAndFire，返回 {scanned, fired, errors}。
// 用于 Sprint 2 demo / 手动验证；prod 关闭（GO_ENV=production）。
// 与 /api/agent/notifications/_dev/create 采取同样的 gate 策略。
func (h *ThresholdHandler) DevScan(w http.ResponseWriter, r *http.Request) {
	if os.Getenv("GO_ENV") == "production" {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	if middleware.GetUserUID(r.Context()) == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	scanned, fired, errs := h.svc.ScanAndFire(r.Context())
	errStrs := make([]string, 0, len(errs))
	for _, e := range errs {
		errStrs = append(errStrs, e.Error())
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"scanned": scanned,
		"fired":   fired,
		"errors":  errStrs,
	})
}

// DELETE /api/agent/thresholds/{id}
func (h *ThresholdHandler) Delete(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "id required")
		return
	}
	if err := h.svc.Delete(r.Context(), id, uid); err != nil {
		if errors.Is(err, repository.ErrThresholdNotFound) {
			writeError(w, http.StatusNotFound, "threshold not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to delete threshold")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
