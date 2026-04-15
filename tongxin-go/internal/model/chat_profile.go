package model

type ChatRelationshipStatus string

const (
	ChatRelationshipSelf            ChatRelationshipStatus = "self"
	ChatRelationshipFriend          ChatRelationshipStatus = "friend"
	ChatRelationshipPendingOutgoing ChatRelationshipStatus = "pending_outgoing"
	ChatRelationshipPendingIncoming ChatRelationshipStatus = "pending_incoming"
	ChatRelationshipNotFriend       ChatRelationshipStatus = "not_friend"
	ChatRelationshipSupport         ChatRelationshipStatus = "support"
)

type ChatTraderSummary struct {
	IsTrader         bool    `json:"is_trader"`
	AllowCopyTrading bool    `json:"allow_copy_trading"`
	WinRate          float64 `json:"win_rate"`
	CopiersCount     int     `json:"copiers_count"`
	TotalTrades      int     `json:"total_trades"`
	TotalPnl         float64 `json:"total_pnl"`
}

type ChatProfile struct {
	UID                   string                 `json:"uid"`
	DisplayName           string                 `json:"display_name"`
	AvatarURL             string                 `json:"avatar_url,omitempty"`
	Email                 string                 `json:"email,omitempty"`
	ShortID               string                 `json:"short_id,omitempty"`
	Bio                   string                 `json:"bio,omitempty"`
	Role                  string                 `json:"role,omitempty"`
	Status                string                 `json:"status,omitempty"`
	Online                bool                   `json:"online"`
	IsSelf                bool                   `json:"is_self"`
	IsSupportAgent        bool                   `json:"is_support_agent"`
	RelationshipStatus    ChatRelationshipStatus `json:"relationship_status"`
	RelationshipRequestID string                 `json:"relationship_request_id,omitempty"`
	CanAddFriend          bool                   `json:"can_add_friend"`
	CanAcceptFriend       bool                   `json:"can_accept_friend"`
	TraderSummary         *ChatTraderSummary     `json:"trader_summary,omitempty"`
}
