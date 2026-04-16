package model

// Sprint 3 / M4：多指标时间序列。用于代理后台「数据中心」页面的叠加折线图。
//
// 设计：一次请求可同时拉多个 metric，每个 metric 一条 series。
// 单位：所有金额统一 USDT（下级 wallet_transactions 原值），未做币种换算（平台主流 stable）。
// 粒度：day / week / month；service 层把用户时间范围按粒度 date_trunc。
//
// 范围口径（和 GetAgentBusinessStats 对齐）：
//   - deposit / withdraw / volume  → 直接下级（users.inviter_uid = agent）聚合
//   - commission                    → 本 agent 自身 commission_records（全 kind）
//
// 返回包含 total 方便前端直接在图上标注「区间总计」。

type TimeSeriesPoint struct {
	Date  string  `json:"date"`  // ISO date at granularity bucket start，"2026-04-16"
	Value float64 `json:"value"` // 聚合值，单位见 TimeSeriesSeries.Unit
}

type TimeSeriesSeries struct {
	Metric string            `json:"metric"` // 'deposit' | 'withdraw' | 'commission' | 'volume'
	Label  string            `json:"label"`  // 中文标签，前端 legend 直接用
	Unit   string            `json:"unit"`   // 'USDT' 统一
	Total  float64           `json:"total"`  // 区间总和
	Points []TimeSeriesPoint `json:"points"` // 已按 date 升序
}

type TimeSeriesResponse struct {
	From        string             `json:"from"`        // "2026-01-01"
	To          string             `json:"to"`          // "2026-04-16"
	Granularity string             `json:"granularity"` // "day" | "week" | "month"
	Series      []TimeSeriesSeries `json:"series"`
}

// SupportedTimeSeriesMetrics 前端下拉的元信息；与 repository 中 CASE 分支必须同步。
type TimeSeriesMetricMeta struct {
	Metric string `json:"metric"`
	Label  string `json:"label"`
	Unit   string `json:"unit"`
	Hint   string `json:"hint"`
}

var SupportedTimeSeriesMetrics = []TimeSeriesMetricMeta{
	{Metric: "deposit", Label: "下级充值", Unit: "USDT", Hint: "直接下级的 deposit 总额"},
	{Metric: "withdraw", Label: "下级提现", Unit: "USDT", Hint: "直接下级的 withdraw 总额"},
	{Metric: "volume", Label: "下级交易量", Unit: "USDT", Hint: "合约 filled + 现货 quote_qty"},
	{Metric: "commission", Label: "我的返佣", Unit: "USDT", Hint: "commission_records 已结算总额"},
}
