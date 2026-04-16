package model

// WeeklyReportData Sprint 5：周报数据结构。
//
// 生成链路：
//   - cron (周一 UTC 01:00) 遍历全部 is_agent=true 用户
//   - 逐个调 service.WeeklyReportService.Generate（查 7d 数据 + chromedp 截图）
//   - PNG 上传到 /uploads/weekly-reports/{uid}/{yyyymmdd}.png
//   - notification.Create({kind:'weekly_report', payload:{png_url, ...}})
//
// 前端 /weekly-report-render?token=... 页面消费本结构渲染 1080×1920 海报。
type WeeklyReportData struct {
	AgentUID      string `json:"agent_uid"`
	AgentName     string `json:"agent_name"`
	AgentEmail    string `json:"agent_email"`
	WeekStartISO  string `json:"week_start_iso"` // YYYY-MM-DD，UTC 周一
	WeekEndISO    string `json:"week_end_iso"`   // YYYY-MM-DD，UTC 周日
	WeekLabel     string `json:"week_label"`     // 'Week 16, 2026'
	GeneratedAtMS int64  `json:"generated_at_ms"`

	// 4 个关键指标（本周合计）
	Indicators WeeklyReportIndicators `json:"indicators"`

	// 趋势：本周 7 个日度 bucket
	TrendDaily []WeeklyReportDailyPoint `json:"trend_daily"`

	// Top 5 本周贡献最高的直接下级
	TopInvitees []WeeklyReportTopInvitee `json:"top_invitees"`
}

// WeeklyReportIndicators 4 个核心指标卡。
type WeeklyReportIndicators struct {
	CommissionUSDT    float64 `json:"commission_usdt"`     // 本周我入账返佣合计
	InviteeVolumeUSDT float64 `json:"invitee_volume_usdt"` // 本周所有下级交易 fee_base 合计
	NewInvitees       int     `json:"new_invitees"`        // 本周新增直接下级数
	ActiveInvitees    int     `json:"active_invitees"`     // 本周至少一次活跃（下单 / 入金）的下级数
}

// WeeklyReportDailyPoint 单日趋势点。
type WeeklyReportDailyPoint struct {
	Date            string  `json:"date"`             // YYYY-MM-DD
	CommissionUSDT  float64 `json:"commission_usdt"`  // 当日入账返佣
	VolumeUSDT      float64 `json:"volume_usdt"`      // 当日下级交易 fee_base 合计
	ActiveInvitees  int     `json:"active_invitees"`  // 当日活跃下级数（去重）
}

// WeeklyReportTopInvitee 本周 Top 5 贡献下级。
type WeeklyReportTopInvitee struct {
	UID            string  `json:"uid"`
	DisplayName    string  `json:"display_name"`
	Email          string  `json:"email"`
	VolumeUSDT     float64 `json:"volume_usdt"`     // 本周贡献 fee_base
	CommissionUSDT float64 `json:"commission_usdt"` // 我从 TA 获得的返佣
	RatePercent    float64 `json:"rate_percent"`    // my_rebate_rate * 100
}
