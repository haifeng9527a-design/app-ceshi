package model

import "time"

// AgentThreshold 代理自定义告警阈值（migration 037）。
//
// 设计：
//   - 一个 (agent_uid, metric) 只能有一条规则（DB UNIQUE）
//   - op + threshold_value 组合成「metric {lt|gt} value」的布尔判定
//   - LastTriggeredAt 用于 24h 防抖，避免 cron 每 10 分钟重复推送
//   - IsEnabled=false 的阈值不会被 cron 扫描，但保留数据便于 toggle 恢复
type AgentThreshold struct {
	ID              string     `json:"id"`
	AgentUID        string     `json:"agent_uid"`
	Metric          string     `json:"metric"`          // 'active_invitees_7d' | 'pending_commission' | 'month_volume_drop_pct' | 'lifetime_commission'
	Op              string     `json:"op"`              // 'lt' | 'gt'
	ThresholdValue  float64    `json:"threshold_value"`
	IsEnabled       bool       `json:"is_enabled"`
	LastTriggeredAt *time.Time `json:"last_triggered_at,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
}

// UpsertThresholdInput 创建/更新阈值时的入参。
// 若 (agent_uid, metric) 已存在则更新 op/threshold_value/is_enabled；否则插入。
type UpsertThresholdInput struct {
	AgentUID       string
	Metric         string
	Op             string
	ThresholdValue float64
	IsEnabled      bool
}

// ThresholdMetric 每个 metric 的元信息，前端 dropdown 时展示中文名与单位。
// 实际计算逻辑在 service 层的 evaluator。
type ThresholdMetric struct {
	Metric    string `json:"metric"`
	Label     string `json:"label"`      // 中文名
	Unit      string `json:"unit"`       // '人' / 'USDT' / '%'
	DefaultOp string `json:"default_op"` // 'lt' / 'gt'
	Hint      string `json:"hint"`       // 提示文案，例如「低于此值时告警」
}

// SupportedThresholdMetrics 供前端 /api/agent/thresholds/metrics 使用。
// 与 service.threshold.evaluate 里的 case 必须同步。
var SupportedThresholdMetrics = []ThresholdMetric{
	{
		Metric: "active_invitees_7d", Label: "7 天活跃下级", Unit: "人",
		DefaultOp: "lt", Hint: "少于此人数时告警",
	},
	{
		Metric: "pending_commission", Label: "待结算返佣", Unit: "USDT",
		DefaultOp: "gt", Hint: "超过此金额时告警（提醒查看）",
	},
	{
		Metric: "month_volume_drop_pct", Label: "本月交易量环比下跌", Unit: "%",
		DefaultOp: "gt", Hint: "下跌幅度超过此值时告警",
	},
	{
		Metric: "lifetime_commission", Label: "累计返佣", Unit: "USDT",
		DefaultOp: "gt", Hint: "达到里程碑时告警（庆祝）",
	},
}
