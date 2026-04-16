package model

// TeamTreeNode 是团队层级 Treemap 节点。
//
// 为什么只到 3 层：
//   - 业务上 L1/L2/L3 已覆盖 override 返佣的所有层级
//   - Treemap 再深视觉上无法辨识
//   - 3 层递归 CTE 不会爆
//
// Contribution 的定义：
//   - 本月该 invitee 给平台贡献的 fee_base（commission_events.fee_base sum）
//   - 用作 Treemap 的 value，决定矩形面积
type TeamTreeNode struct {
	UID          string         `json:"uid"`
	DisplayName  string         `json:"display_name"`
	Email        string         `json:"email"`
	Depth        int            `json:"depth"` // 1=direct, 2=L2, 3=L3
	IsAgent      bool           `json:"is_agent"`
	MyRebateRate float64        `json:"my_rebate_rate"`
	Contribution float64        `json:"contribution"`       // 本月 fee_base sum
	Commission   float64        `json:"commission"`         // 本月该节点给 root 贡献的返佣
	Children     []TeamTreeNode `json:"children,omitempty"` // 嵌套结构
}

// TeamTreeResponse 返回根节点（= 调用者自己）+ 嵌套下级。
type TeamTreeResponse struct {
	RootUID     string         `json:"root_uid"`
	GeneratedAt string         `json:"generated_at"` // ISO timestamp
	Nodes       []TeamTreeNode `json:"nodes"`        // 直接下级（children 递归嵌套）
	TotalNodes  int            `json:"total_nodes"`  // 扁平计数
	TotalVolume float64        `json:"total_volume"` // 全团队本月 fee_base sum
}

// DashboardPrefs 是代理商自定义看板偏好。
//
// 结构约定（前端演进不破坏）：只有 modules 一个 key，未来加 theme/grid 另加 key 即可。
type DashboardPrefs struct {
	Modules []DashboardModulePref `json:"modules,omitempty"`
}

type DashboardModulePref struct {
	ID     string `json:"id"`     // 前端内置模块 id，如 'risk-radar'
	Hidden bool   `json:"hidden"` // 是否隐藏
}
