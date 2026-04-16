package model

// RiskSignal 一条风险雷达信号。前端 risk-radar-card 一卡显示一条。
//
// 三种 Kind：
//   - "self_rebate_pending" : 自己产生的自返佣 commission_events 仍处 pending（未结算）
//   - "inactive_invitee_7d" : 7 天没有登录过的直接下级数量
//   - "monthly_drop"        : 本月返佣总额相比上月下跌超过 20%
//
// Severity 用于前端徽章颜色：critical (红) / warning (黄) / info (蓝)。
type RiskSignal struct {
	Kind      string  `json:"kind"`
	Severity  string  `json:"severity"`
	Title     string  `json:"title"`
	Detail    string  `json:"detail"`
	Count     int     `json:"count,omitempty"`
	Amount    float64 `json:"amount,omitempty"`
	DropPct   float64 `json:"drop_pct,omitempty"`
	ActionURL string  `json:"action_url,omitempty"`
}

// RiskRadarResponse 是 GET /api/agent/risk-radar 的返回结构。
// signals 可能为空数组（无风险），前端要 graceful degrade 显示「一切正常」。
type RiskRadarResponse struct {
	Signals []RiskSignal `json:"signals"`
}
