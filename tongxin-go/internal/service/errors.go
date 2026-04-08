package service

import "errors"

var (
	// ErrNotConversationMember caller is not in the conversation
	ErrNotConversationMember = errors.New("not a conversation member")
	ErrForbidden             = errors.New("forbidden")
)
