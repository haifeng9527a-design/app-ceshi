package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

// AgentDashboardHandler 把 dashboard 页面所需、但跨服务聚合的 3 个端点收敛到一处：
//   - GET /api/agent/risk-radar    风险雷达（基于 RiskMetrics 聚合 + 规则转 signal）
//   - GET /api/agent/team-tree     3 层团队树（用于 Treemap）
//   - GET /api/agent/dashboard-prefs   看板自定义偏好
//   - PUT /api/agent/dashboard-prefs   保存看板自定义偏好
//
// 这些逻辑都只依赖 ReferralRepo，没有独立 service 层（规则简单 + 一次查询）。
// 如果后面要加"风险信号静默"之类状态化逻辑，再抽 service。
type AgentDashboardHandler struct {
	repo *repository.ReferralRepo
}

func NewAgentDashboardHandler(repo *repository.ReferralRepo) *AgentDashboardHandler {
	return &AgentDashboardHandler{repo: repo}
}

// GET /api/agent/risk-radar
// 基于 repo.GetRiskMetrics() 返回的原始指标，按 3 条规则转成 []RiskSignal。
// 前端 risk-radar-card 直接按 Kind 渲染不同图标/操作按钮。
func (h *AgentDashboardHandler) RiskRadar(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	m, err := h.repo.GetRiskMetrics(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load risk metrics")
		return
	}

	signals := make([]model.RiskSignal, 0, 3)

	// 规则 1：自返佣 pending。只要金额 > 0 就出信号（方便 arron 的 2 笔 pending 作 demo）。
	if m.PendingSelfRebateAmount > 0 {
		signals = append(signals, model.RiskSignal{
			Kind:      "self_rebate_pending",
			Severity:  "warning",
			Title:     "自返佣待结算",
			Detail:    fmt.Sprintf("当前有 %.2f USDT 自返佣处于 pending 状态，等待日结。", m.PendingSelfRebateAmount),
			Amount:    m.PendingSelfRebateAmount,
			ActionURL: "/commission-records?status=pending",
		})
	}

	// 规则 2：7 天未活跃下级。
	if m.InactiveInviteeCount > 0 {
		signals = append(signals, model.RiskSignal{
			Kind:      "inactive_invitee_7d",
			Severity:  "critical",
			Title:     "活跃下级告警",
			Detail:    fmt.Sprintf("7 天未登录的直接下级 %d 人（共 %d 人），建议一键触达激活。", m.InactiveInviteeCount, m.TotalInviteeCount),
			Count:     m.InactiveInviteeCount,
			ActionURL: "/touch?filter=inactive_7d",
		})
	}

	// 规则 3：月返佣环比下跌 > 20%。上月 0 则跳过（无从比较）。
	if m.LastMonthCommission > 0 {
		drop := (m.LastMonthCommission - m.ThisMonthCommission) / m.LastMonthCommission
		if drop > 0.20 {
			signals = append(signals, model.RiskSignal{
				Kind:      "monthly_drop",
				Severity:  "warning",
				Title:     "月返佣环比下跌",
				Detail:    fmt.Sprintf("本月返佣 %.2f USDT 较上月 %.2f USDT 下跌 %.1f%%。", m.ThisMonthCommission, m.LastMonthCommission, drop*100),
				DropPct:   drop * 100,
				ActionURL: "/data-center",
			})
		}
	}

	writeJSON(w, http.StatusOK, &model.RiskRadarResponse{Signals: signals})
}

// GET /api/agent/team-tree
// 团队 3 层树：直推=L1，直推的下级=L2，L2 的下级=L3。
// root 不在 Nodes 里——前端 Treemap 的 root 就是代理自己（已登录）。
func (h *AgentDashboardHandler) TeamTree(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	tree, err := h.repo.GetTeamTree(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load team tree")
		return
	}
	// 保持 json 数组非 nil，方便前端 .map 不炸。
	if tree.Nodes == nil {
		tree.Nodes = []model.TeamTreeNode{}
	}
	writeJSON(w, http.StatusOK, tree)
}

// GET /api/agent/dashboard-prefs
func (h *AgentDashboardHandler) GetDashboardPrefs(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	prefs, err := h.repo.GetDashboardPrefs(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load dashboard prefs")
		return
	}
	writeJSON(w, http.StatusOK, prefs)
}

// GET /api/agent/commission-events?kind=&status=&limit=&offset=
// 给前端 CommissionSettlementBanner + 实时事件流复用。
// 默认按 created_at DESC 排序；status=pending 可以抓所有未结算的。
func (h *AgentDashboardHandler) ListCommissionEvents(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	q := r.URL.Query()
	kind := q.Get("kind")
	status := q.Get("status")
	limit, _ := strconv.Atoi(q.Get("limit"))
	offset, _ := strconv.Atoi(q.Get("offset"))

	events, total, err := h.repo.ListCommissionEventsForAgent(r.Context(), uid, kind, status, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list commission events")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"events": events,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

// PUT /api/agent/dashboard-prefs
// 完整覆盖存储；前端 dnd-kit 排序完发整个 modules 数组过来。
func (h *AgentDashboardHandler) PutDashboardPrefs(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	var body model.DashboardPrefs
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if err := h.repo.PutDashboardPrefs(r.Context(), uid, &body); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to save dashboard prefs")
		return
	}
	// 回读一次，保证前端 state 和 DB 完全一致（容错字段归一化）。
	prefs, err := h.repo.GetDashboardPrefs(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "saved but failed to reload")
		return
	}
	writeJSON(w, http.StatusOK, prefs)
}
