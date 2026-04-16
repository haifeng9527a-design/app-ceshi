package model

import (
	"encoding/json"
	"time"
)

// TouchHistory 一键触达历史（migration 037）。
//
// 设计：
//   - invitee_uids / channels 用 text[]，避免 N:M 中间表
//   - channels 每个元素的实际发送结果存 payload.channel_results
//   - status = all(channel success) ? 'success' : any-success ? 'partial' : 'failed'
//   - 'pending' 仅用于异步发送的中间态，本项目同步发送不会落这个状态
type TouchHistory struct {
	ID          string          `json:"id"`
	AgentUID    string          `json:"agent_uid"`
	InviteeUIDs []string        `json:"invitee_uids"`
	Template    string          `json:"template"`
	Channels    []string        `json:"channels"`
	Payload     json.RawMessage `json:"payload,omitempty"`
	Status      string          `json:"status"` // 'pending' | 'success' | 'partial' | 'failed'
	CreatedAt   time.Time       `json:"created_at"`
}

// TouchRequest 前端触达入参（所有 4 个 channel handler 共用同一结构）。
// custom_body 可覆盖模板默认 body；为空则用模板默认。
type TouchRequest struct {
	InviteeUIDs []string `json:"invitee_uids"`
	Template    string   `json:"template"`    // 'reactivate' | 'thank_you' | 'commission_arrived'
	CustomBody  string   `json:"custom_body"` // 可选
}

// TouchChannelResult 单一渠道的发送结果。
type TouchChannelResult struct {
	Channel    string `json:"channel"`              // 'internal' | 'email' | 'sms' | 'wechat'
	Success    bool   `json:"success"`
	Count      int    `json:"count"`                // 成功发送的接收人数
	ErrMessage string `json:"err_message,omitempty"`
}

// TouchResponse handler 层的聚合回执。
type TouchResponse struct {
	HistoryID      string               `json:"history_id"`
	Status         string               `json:"status"` // 同 TouchHistory.Status
	ChannelResults []TouchChannelResult `json:"channel_results"`
}

// TouchTemplate 每个模板的默认文案（服务端维护，前端可 GET /api/agent/touch/templates 获取）。
type TouchTemplate struct {
	Key          string `json:"key"`
	Label        string `json:"label"`
	Title        string `json:"title"`         // 站内通知的 title；email 的 subject
	DefaultBody  string `json:"default_body"`  // 支持 {agent_name} / {invitee_name} 占位符
	TargetSuffix string `json:"target_suffix"` // 触达 CTA 文案，如「去交易」
}

// SupportedTouchTemplates 所有可用模板。与 service.touch.render 里的 switch 必须同步。
var SupportedTouchTemplates = []TouchTemplate{
	{
		Key: "reactivate", Label: "召回未活跃",
		Title:        "好久不见 👋",
		DefaultBody:  "你已经好几天没登录了，错过了近期多轮行情。现在回来还有专属激活奖励。",
		TargetSuffix: "立即登录",
	},
	{
		Key: "thank_you", Label: "感谢活跃",
		Title:        "感谢一直以来的支持 🎉",
		DefaultBody:  "过去一个月你交易非常活跃，是我们最宝贵的伙伴。返佣已按时到账。",
		TargetSuffix: "查看返佣",
	},
	{
		Key: "commission_arrived", Label: "返佣到账提醒",
		Title:        "你的返佣已到账 💰",
		DefaultBody:  "本期返佣已自动结算到你的钱包，可立即查看明细。",
		TargetSuffix: "查看明细",
	},
}
