package model

import "time"

type SupportAssignment struct {
	ID             string    `json:"id"`
	CustomerUID    string    `json:"customer_uid"`
	AgentUID       string    `json:"agent_uid"`
	AssignedBy     *string   `json:"assigned_by,omitempty"`
	Status         string    `json:"status"`
	ConversationID string    `json:"conversation_id"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

type SupportAssignmentDetail struct {
	Assignment  *SupportAssignment `json:"assignment,omitempty"`
	Agent       *User              `json:"agent,omitempty"`
	AgentOnline bool               `json:"agent_online"`
}

type AssignSupportAgentRequest struct {
	AgentUID string `json:"agent_uid"`
}

type SupportAgentLoad struct {
	AgentUID        string `json:"agent_uid"`
	ActiveCustomers int    `json:"active_customers"`
}
